import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

class WinInfo {
  const WinInfo(this.pid, this.exe, this.title);
  final int pid;
  final String exe, title;
}

typedef _EnumNative = ffi.Int32 Function(ffi.IntPtr hwnd, ffi.IntPtr lParam);

/// Lists visible top-level windows with their title and owning .exe name.
class WindowScan {
  WindowScan._();

  static bool _ready = false;
  static late int Function(ffi.Pointer<ffi.NativeFunction<_EnumNative>>, int) _enum;
  static late int Function(int) _visible;
  static late int Function(int) _textLen;
  static late int Function(int, ffi.Pointer<Utf16>, int) _text;
  static late int Function(int, ffi.Pointer<ffi.Uint32>) _pidOf;
  static late int Function(int, int, int) _open;
  static late int Function(int, int, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>) _query;
  static late int Function(int) _close;
  static final List<int> _found = [];

  static int _collect(int hwnd, int lParam) {
    _found.add(hwnd);
    return 1;
  }

  static void _init() {
    if (_ready) return;
    final user = ffi.DynamicLibrary.open('user32.dll');
    final kernel = ffi.DynamicLibrary.open('kernel32.dll');
    _enum = user.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.NativeFunction<_EnumNative>>, ffi.IntPtr),
        int Function(ffi.Pointer<ffi.NativeFunction<_EnumNative>>, int)>('EnumWindows');
    _visible = user.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('IsWindowVisible');
    _textLen = user.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('GetWindowTextLengthW');
    _text = user.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<Utf16>, ffi.Int32),
        int Function(int, ffi.Pointer<Utf16>, int)>('GetWindowTextW');
    _pidOf = user.lookupFunction<ffi.Uint32 Function(ffi.IntPtr, ffi.Pointer<ffi.Uint32>),
        int Function(int, ffi.Pointer<ffi.Uint32>)>('GetWindowThreadProcessId');
    _open = kernel.lookupFunction<ffi.IntPtr Function(ffi.Uint32, ffi.Int32, ffi.Uint32),
        int Function(int, int, int)>('OpenProcess');
    _query = kernel.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>),
        int Function(int, int, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>)>('QueryFullProcessImageNameW');
    _close = kernel.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('CloseHandle');
    _ready = true;
  }

  static String _exeOf(int pid) {
    final h = _open(0x1000, 0, pid); // PROCESS_QUERY_LIMITED_INFORMATION
    if (h == 0) return '';
    final buf = calloc<ffi.Uint16>(520).cast<Utf16>();
    final len = calloc<ffi.Uint32>()..value = 520;
    var name = '';
    if (_query(h, 0, buf, len) != 0) {
      name = buf.toDartString(length: len.value).split('\\').last.toLowerCase();
    }
    calloc.free(buf);
    calloc.free(len);
    _close(h);
    return name;
  }

  static List<WinInfo> list() {
    if (!Platform.isWindows) return const [];
    try {
      _init();
      _found.clear();
      _enum(ffi.Pointer.fromFunction<_EnumNative>(_collect, 1), 0);
      final names = <int, String>{};
      final out = <WinInfo>[];
      for (final h in _found) {
        if (_visible(h) == 0) continue;
        final len = _textLen(h);
        if (len <= 0) continue;
        final buf = calloc<ffi.Uint16>(len + 2).cast<Utf16>();
        _text(h, buf, len + 1);
        final title = buf.toDartString();
        calloc.free(buf);
        final pp = calloc<ffi.Uint32>();
        _pidOf(h, pp);
        final p = pp.value;
        calloc.free(pp);
        if (p == 0) continue;
        out.add(WinInfo(p, names.putIfAbsent(p, () => _exeOf(p)), title));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
