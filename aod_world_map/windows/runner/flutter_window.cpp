#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Posted by the keyboard hook to the window that installed it.
constexpr UINT kChordArmed = WM_APP + 0x51;  // all three modifiers are down
constexpr UINT kChordFired = WM_APP + 0x52;  // ...and were let go cleanly

// An unassigned key, pressed while the chord is held so that letting go of
// Alt doesn't open the menu bar of the app in front, and Shift+Alt doesn't
// switch the keyboard language. AutoHotkey masks Alt the same way.
constexpr WORD kMaskVk = 0xE8;

// A chord held this long is someone resting on the keys, not a shortcut.
constexpr ULONGLONG kChordMaxMs = 1500;

HWND g_chord_window = nullptr;
int g_held = 0;           // 1 Ctrl, 2 Shift, 4 Alt
bool g_armed = false;     // all three have been down together
bool g_spoiled = false;   // another key went down in the middle
ULONGLONG g_armed_at = 0;

int ModifierBit(DWORD vk) {
  switch (vk) {
    case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL: return 1;
    case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT: return 2;
    case VK_MENU: case VK_LMENU: case VK_RMENU: return 4;
    default: return 0;
  }
}

int HeldModifiers() {
  int held = 0;
  if (GetAsyncKeyState(VK_CONTROL) < 0) held |= 1;
  if (GetAsyncKeyState(VK_SHIFT) < 0) held |= 2;
  if (GetAsyncKeyState(VK_MENU) < 0) held |= 4;
  return held;
}

// Runs on every key press system-wide, so it only does bookkeeping and
// leaves the rest to the window's message loop. It never swallows a key.
LRESULT CALLBACK ChordHook(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION) {
    const auto* k = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    if (!(k->flags & LLKHF_INJECTED)) {
      const bool down = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
      const int bit = ModifierBit(k->vkCode);
      if (bit) {
        if (down) {
          // Start from what Windows says is held, in case a key-up was
          // never seen (Ctrl+Alt+Del lets go on the secure desktop).
          const int others = HeldModifiers() & ~bit;
          if (!others) g_armed = g_spoiled = false;
          g_held = others | bit;
          if (g_held == 7 && !g_armed && !g_spoiled) {
            g_armed = true;
            g_armed_at = GetTickCount64();
            PostMessage(g_chord_window, kChordArmed, 0, 0);
          }
        } else {
          g_held &= ~bit;
          if (g_held == 0) {
            if (g_armed && !g_spoiled && GetTickCount64() - g_armed_at <= kChordMaxMs) {
              PostMessage(g_chord_window, kChordFired, 0, 0);
            }
            g_armed = false;
            g_spoiled = false;
          }
        }
      } else if (down && g_held) {
        // A real shortcut (Ctrl+Shift+Alt+N, or Win for the Office key).
        g_spoiled = true;
      }
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

INPUT KeyInput(WORD vk, bool up) {
  INPUT in = {};
  in.type = INPUT_KEYBOARD;
  in.ki.wVk = vk;
  in.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
  return in;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  hotkeys_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "meridian/hotkey",
      &flutter::StandardMethodCodec::GetInstance());
  hotkeys_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    auto arg = [args](const char* key) {
      if (!args) return 0;
      auto it = args->find(flutter::EncodableValue(key));
      const int* v = it == args->end() ? nullptr : std::get_if<int>(&it->second);
      return v ? *v : 0;
    };
    const auto& method = call.method_name();
    if (method == "register") {
      UnregisterHotKey(GetHandle(), arg("id"));
      const bool ok = RegisterHotKey(GetHandle(), arg("id"), arg("mods") | MOD_NOREPEAT, arg("vk"));
      result->Success(flutter::EncodableValue(ok));
    } else if (method == "unregister") {
      UnregisterHotKey(GetHandle(), arg("id"));
      result->Success();
    } else if (method == "chord") {
      StartChord(static_cast<UINT>(arg("vk")));
      result->Success(flutter::EncodableValue(chord_hook_ != nullptr));
    } else if (method == "unchord") {
      StopChord();
      result->Success();
    } else if (method == "giveBack") {
      if (before_hotkey_ && IsWindow(before_hotkey_)) SetForegroundWindow(before_hotkey_);
      before_hotkey_ = nullptr;
      result->Success();
    } else {
      result->NotImplemented();
    }
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::StartChord(UINT vk) {
  StopChord();
  chord_vk_ = vk;
  g_chord_window = GetHandle();
  chord_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, ChordHook, GetModuleHandle(nullptr), 0);
}

void FlutterWindow::StopChord() {
  if (chord_hook_) UnhookWindowsHookEx(chord_hook_);
  chord_hook_ = nullptr;
  g_held = 0;
  g_armed = g_spoiled = false;
}

// Replays the chord as Ctrl+Shift+Alt+[chord_vk_], which is registered with
// RegisterHotKey, so it arrives as WM_HOTKEY and may take the foreground.
void FlutterWindow::SendChordHotkey() {
  const WORD vk = static_cast<WORD>(chord_vk_);
  INPUT keys[] = {
      KeyInput(VK_CONTROL, false), KeyInput(VK_SHIFT, false), KeyInput(VK_MENU, false),
      KeyInput(vk, false),         KeyInput(vk, true),
      KeyInput(VK_MENU, true),     KeyInput(VK_SHIFT, true),  KeyInput(VK_CONTROL, true),
  };
  SendInput(ARRAYSIZE(keys), keys, sizeof(INPUT));
}

void FlutterWindow::OnDestroy() {
  StopChord();
  hotkeys_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_HOTKEY:
      if (hotkeys_) {
        HWND front = GetForegroundWindow();
        if (front != hwnd) before_hotkey_ = front;
        SetForegroundWindow(hwnd);
        hotkeys_->InvokeMethod("pressed", std::make_unique<flutter::EncodableValue>(static_cast<int>(wparam)));
      }
      return 0;
    case kChordArmed: {
      INPUT mask[] = {KeyInput(kMaskVk, false), KeyInput(kMaskVk, true)};
      SendInput(ARRAYSIZE(mask), mask, sizeof(INPUT));
      return 0;
    }
    case kChordFired:
      if (chord_hook_ && chord_vk_) SendChordHotkey();
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
