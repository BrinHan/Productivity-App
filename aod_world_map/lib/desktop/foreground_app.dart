import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Name of the .exe that owns the foreground window, lower-case ('chrome.exe').
class ForegroundApp {
  ForegroundApp._();

  static final String own =
      Platform.resolvedExecutable.split(Platform.pathSeparator).last.toLowerCase();

  static bool _ready = false;
  static late int Function() _getFg;
  static late int Function(int, ffi.Pointer<ffi.Uint32>) _getPid;
  static late int Function(int, int, int) _open;
  static late int Function(int, int, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>) _query;
  static late int Function(int) _close;

  static void _init() {
    if (_ready) return;
    final user = ffi.DynamicLibrary.open('user32.dll');
    final kernel = ffi.DynamicLibrary.open('kernel32.dll');
    _getFg = user.lookupFunction<ffi.IntPtr Function(), int Function()>('GetForegroundWindow');
    _getPid = user.lookupFunction<
        ffi.Uint32 Function(ffi.IntPtr, ffi.Pointer<ffi.Uint32>),
        int Function(int, ffi.Pointer<ffi.Uint32>)>('GetWindowThreadProcessId');
    _open = kernel.lookupFunction<ffi.IntPtr Function(ffi.Uint32, ffi.Int32, ffi.Uint32),
        int Function(int, int, int)>('OpenProcess');
    _query = kernel.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>),
        int Function(int, int, ffi.Pointer<Utf16>,
            ffi.Pointer<ffi.Uint32>)>('QueryFullProcessImageNameW');
    _close = kernel.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('CloseHandle');
    _ready = true;
  }

  static String? current() {
    if (!Platform.isWindows) return null;
    try {
      _init();
      final hwnd = _getFg();
      if (hwnd == 0) return null;
      final pidPtr = calloc<ffi.Uint32>();
      _getPid(hwnd, pidPtr);
      final pid = pidPtr.value;
      calloc.free(pidPtr);
      if (pid == 0) return null;
      final h = _open(0x1000, 0, pid); // PROCESS_QUERY_LIMITED_INFORMATION
      if (h == 0) return null;
      final buf = calloc<ffi.Uint16>(520).cast<Utf16>();
      final len = calloc<ffi.Uint32>()..value = 520;
      String? name;
      if (_query(h, 0, buf, len) != 0) {
        name = buf.toDartString(length: len.value).split('\\').last.toLowerCase();
      }
      calloc.free(buf);
      calloc.free(len);
      _close(h);
      return name;
    } catch (_) {
      return null;
    }
  }
}
