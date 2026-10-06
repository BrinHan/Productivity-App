import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

/// The few Win32 calls the overlay needs: its own window rect, the cursor,
/// key state, and a GDI grab of the screen under the overlay.
class OverlayWin32 {
  OverlayWin32._();

  static bool _ready = false;
  static late int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>) _findWindow;
  static late int Function(int, ffi.Pointer<ffi.Int32>) _getWindowRect;
  static late int Function(ffi.Pointer<ffi.Int32>) _getCursorPos;
  static late int Function(int) _asyncKey;
  static late int Function(int, int) _setAffinity;
  static late int Function(int) _getDC;
  static late int Function(int, int) _releaseDC;
  static late int Function(int) _createCompatibleDC;
  static late int Function(int, int, int) _createCompatibleBitmap;
  static late int Function(int, int) _selectObject;
  static late int Function(int, int, int, int, int, int, int, int, int) _bitBlt;
  static late int Function(int, int, int, int, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int) _getDIBits;
  static late int Function(int) _deleteObject;
  static late int Function(int) _deleteDC;
  static late int Function(int, int) _monitorFromPoint;
  static late int Function(int, ffi.Pointer<ffi.Int32>) _getMonitorInfo;
  static late int Function(int, int, int, int, int, int, int) _setWindowPos;
  static late int Function(int, int, int, int) _setLayeredAttrs;

  static void _init() {
    if (_ready) return;
    final u = ffi.DynamicLibrary.open('user32.dll');
    final g = ffi.DynamicLibrary.open('gdi32.dll');
    _findWindow = u.lookupFunction<ffi.IntPtr Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>),
        int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>)>('FindWindowW');
    _getWindowRect = u.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<ffi.Int32>),
        int Function(int, ffi.Pointer<ffi.Int32>)>('GetWindowRect');
    _getCursorPos =
        u.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Int32>), int Function(ffi.Pointer<ffi.Int32>)>('GetCursorPos');
    _asyncKey = u.lookupFunction<ffi.Int16 Function(ffi.Int32), int Function(int)>('GetAsyncKeyState');
    _setAffinity = u.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.Uint32), int Function(int, int)>(
        'SetWindowDisplayAffinity');
    _getDC = u.lookupFunction<ffi.IntPtr Function(ffi.IntPtr), int Function(int)>('GetDC');
    _releaseDC = u.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.IntPtr), int Function(int, int)>('ReleaseDC');
    _createCompatibleDC = g.lookupFunction<ffi.IntPtr Function(ffi.IntPtr), int Function(int)>('CreateCompatibleDC');
    _createCompatibleBitmap = g.lookupFunction<ffi.IntPtr Function(ffi.IntPtr, ffi.Int32, ffi.Int32),
        int Function(int, int, int)>('CreateCompatibleBitmap');
    _selectObject =
        g.lookupFunction<ffi.IntPtr Function(ffi.IntPtr, ffi.IntPtr), int Function(int, int)>('SelectObject');
    _bitBlt = g.lookupFunction<
        ffi.Int32 Function(
            ffi.IntPtr, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.IntPtr, ffi.Int32, ffi.Int32, ffi.Uint32),
        int Function(int, int, int, int, int, int, int, int, int)>('BitBlt');
    _getDIBits = g.lookupFunction<
        ffi.Int32 Function(
            ffi.IntPtr, ffi.IntPtr, ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Uint32),
        int Function(int, int, int, int, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int)>('GetDIBits');
    _deleteObject = g.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('DeleteObject');
    _deleteDC = g.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('DeleteDC');
    // POINT is passed by value; on x64 that is one 64-bit register.
    _monitorFromPoint =
        u.lookupFunction<ffi.IntPtr Function(ffi.Int64, ffi.Uint32), int Function(int, int)>('MonitorFromPoint');
    _getMonitorInfo = u.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.Pointer<ffi.Int32>),
        int Function(int, ffi.Pointer<ffi.Int32>)>('GetMonitorInfoW');
    _setWindowPos = u.lookupFunction<
        ffi.Int32 Function(ffi.IntPtr, ffi.IntPtr, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Uint32),
        int Function(int, int, int, int, int, int, int)>('SetWindowPos');
    _setLayeredAttrs = u.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.Uint8, ffi.Uint32),
        int Function(int, int, int, int)>('SetLayeredWindowAttributes');
    _ready = true;
  }

  static int _hwnd = 0;

  /// The overlay's top-level window (main.cpp titles it 'Meridian Overlay').
  static int get hwnd {
    if (_hwnd != 0) return _hwnd;
    _init();
    final title = 'Meridian Overlay'.toNativeUtf16();
    _hwnd = _findWindow(ffi.nullptr, title);
    calloc.free(title);
    return _hwnd;
  }

  /// Window rect in physical screen pixels.
  static ui.Rect? windowRect() {
    _init();
    final h = hwnd;
    if (h == 0) return null;
    final r = calloc<ffi.Int32>(4);
    try {
      if (_getWindowRect(h, r) == 0) return null;
      return ui.Rect.fromLTRB(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble());
    } finally {
      calloc.free(r);
    }
  }

  /// Cursor in physical screen pixels.
  static ui.Offset cursor() {
    _init();
    final p = calloc<ffi.Int32>(2);
    try {
      _getCursorPos(p);
      return ui.Offset(p[0].toDouble(), p[1].toDouble());
    } finally {
      calloc.free(p);
    }
  }

  /// Moves the overlay over the whole monitor the cursor is on, if it is not
  /// there already (a standby overlay waits wherever it was started). Like
  /// main.cpp: hop onto the monitor first so its DPI applies, then size.
  static void coverCursorMonitor() {
    _init();
    final h = hwnd;
    if (h == 0) return;
    final c = cursor();
    final pt = (c.dy.toInt() << 32) | (c.dx.toInt() & 0xFFFFFFFF);
    final mon = _monitorFromPoint(pt, 2); // MONITOR_DEFAULTTONEAREST
    if (mon == 0) return;
    final mi = calloc<ffi.Int32>(10); // MONITORINFO
    try {
      mi[0] = 40; // cbSize
      if (_getMonitorInfo(mon, mi) == 0) return;
      final r = ui.Rect.fromLTRB(mi[1].toDouble(), mi[2].toDouble(), mi[3].toDouble(), mi[4].toDouble());
      if (windowRect() == r) return;
      const topmost = -1, flags = 0x0010; // HWND_TOPMOST, SWP_NOACTIVATE
      final x = r.left.toInt(), y = r.top.toInt();
      _setWindowPos(h, topmost, x, y, 200, 200, flags);
      _setWindowPos(h, topmost, x, y, r.width.toInt(), r.height.toInt(), flags);
    } finally {
      calloc.free(mi);
    }
  }

  static bool keyDown(int vk) {
    _init();
    return (_asyncKey(vk) & 0x8000) != 0;
  }

  /// Click-through makes the window layered, and a layered window given no
  /// attributes keeps showing old frames (the toolbar stays invisible until
  /// a click turns click-through off). Fully opaque attributes fix that.
  static void showLayered() {
    _init();
    final h = hwnd;
    if (h != 0) _setLayeredAttrs(h, 0, 255, 0x2); // LWA_ALPHA
  }

  /// Hides the overlay from screen capture (ours and everyone else's) while
  /// [on]. Only on for the moment we grab the screen, so annotations still
  /// show when you share your screen.
  static void excludeFromCapture(bool on) {
    _init();
    final h = hwnd;
    if (h != 0) _setAffinity(h, on ? 0x11 : 0); // WDA_EXCLUDEFROMCAPTURE : WDA_NONE
  }

  /// Grabs [rect] (physical pixels) of the desktop as an opaque image.
  static Future<ui.Image?> grab(ui.Rect rect) async {
    _init();
    final x = rect.left.round(), y = rect.top.round();
    final w = rect.width.round(), h = rect.height.round();
    if (w <= 0 || h <= 0) return null;
    final screen = _getDC(0);
    final mem = _createCompatibleDC(screen);
    final bmp = _createCompatibleBitmap(screen, w, h);
    final old = _selectObject(mem, bmp);
    Uint8List? bytes;
    try {
      // SRCCOPY | CAPTUREBLT (include layered windows like the island).
      if (_bitBlt(mem, 0, 0, w, h, screen, x, y, 0x00CC0020 | 0x40000000) == 0) return null;
      _selectObject(mem, old); // GetDIBits wants the bitmap deselected
      final info = calloc<ffi.Uint8>(44); // BITMAPINFOHEADER (+ slack)
      final buf = calloc<ffi.Uint8>(w * h * 4);
      try {
        final v = ByteData.sublistView(info.asTypedList(44));
        v.setUint32(0, 40, Endian.little); // biSize
        v.setInt32(4, w, Endian.little); // biWidth
        v.setInt32(8, -h, Endian.little); // biHeight, negative = top-down
        v.setUint16(12, 1, Endian.little); // biPlanes
        v.setUint16(14, 32, Endian.little); // biBitCount
        v.setUint32(16, 0, Endian.little); // BI_RGB
        if (_getDIBits(mem, bmp, 0, h, buf, info, 0) == h) {
          bytes = Uint8List.fromList(buf.asTypedList(w * h * 4));
        }
      } finally {
        calloc.free(buf);
        calloc.free(info);
      }
    } finally {
      _selectObject(mem, old);
      _deleteObject(bmp);
      _deleteDC(mem);
      _releaseDC(0, screen);
    }
    if (bytes == null) return null;
    // GDI leaves alpha at 0; make every pixel opaque.
    final px = bytes.buffer.asUint32List();
    for (var i = 0; i < px.length; i++) {
      px[i] |= 0xFF000000;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.bgra8888, done.complete);
    return done.future;
  }
}
