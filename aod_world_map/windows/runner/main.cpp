#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // The island and overlay processes start small and hidden; Dart (or the
  // block below, for the overlay) places them before they are shown. Without this it would size up as a
  // 1280x720 window and take focus from whatever you are using.
  bool island = false, overlay = false;
  for (const auto& a : command_line_arguments) {
    if (a == "--island") island = true;
    if (a == "--overlay") overlay = true;
  }
  const bool quiet = island || overlay;

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin = quiet ? Win32Window::Point(0, 0) : Win32Window::Point(10, 10);
  Win32Window::Size size = quiet ? Win32Window::Size(640, 480) : Win32Window::Size(1280, 720);
  window.SetShowWithoutActivating(quiet);
  const wchar_t* title = island ? L"AOD Island" : overlay ? L"AOD Overlay" : L"aod_world_map";
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  if (overlay) {
    // The annotation overlay covers the whole monitor the cursor is on,
    // taskbar included. Hop onto that monitor first (its DPI may resize us),
    // then take its full rect in physical pixels.
    HWND hwnd = window.GetHandle();
    POINT pt;
    ::GetCursorPos(&pt);
    MONITORINFO mi{sizeof(mi)};
    ::GetMonitorInfo(::MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST), &mi);
    const RECT r = mi.rcMonitor;
    ::SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP);
    ::SetWindowLongPtr(hwnd, GWL_EXSTYLE, ::GetWindowLongPtr(hwnd, GWL_EXSTYLE) | WS_EX_TOOLWINDOW);
    const UINT flags = SWP_NOACTIVATE | SWP_FRAMECHANGED;
    ::SetWindowPos(hwnd, HWND_TOPMOST, r.left, r.top, 200, 200, flags);
    ::SetWindowPos(hwnd, HWND_TOPMOST, r.left, r.top, r.right - r.left, r.bottom - r.top, flags);
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
