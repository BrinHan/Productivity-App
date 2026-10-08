import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Whether Windows is set to cut down on motion (Settings > Accessibility >
/// Visual effects > Animation effects off). Flutter doesn't pass this on for
/// Windows, so it is read straight from Windows, and looked at again at most
/// every few seconds so turning it off takes effect without a restart.
class Motion {
  Motion._();

  /// For tests, and to try the reduced version without changing Windows.
  static bool? override;

  static bool _reduced = false;
  static DateTime _readAt = DateTime(0);
  static int Function(int, int, ffi.Pointer<ffi.Int32>, int)? _spi;

  static bool get reduced {
    final o = override;
    if (o != null) return o;
    final now = DateTime.now();
    if (now.difference(_readAt) > const Duration(seconds: 5)) {
      _readAt = now;
      _reduced = _read();
    }
    return _reduced;
  }

  static bool _read() {
    if (!Platform.isWindows) return false;
    try {
      _spi ??= ffi.DynamicLibrary.open('user32.dll')
          .lookupFunction<
            ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Int32>, ffi.Uint32),
            int Function(int, int, ffi.Pointer<ffi.Int32>, int)
          >('SystemParametersInfoW');
      final on = calloc<ffi.Int32>();
      try {
        const spiGetClientAreaAnimation = 0x1042;
        if (_spi!(spiGetClientAreaAnimation, 0, on, 0) == 0) return false;
        return on.value == 0;
      } finally {
        calloc.free(on);
      }
    } catch (_) {
      return false; // can't tell: keep the animations
    }
  }
}
