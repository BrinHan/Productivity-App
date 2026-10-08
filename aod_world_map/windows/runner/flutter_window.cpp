#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

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

void FlutterWindow::OnDestroy() {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
