import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'log.dart';

/// How Windows was unlocked, as far as Windows Hello's log can tell.
enum UnlockMethod { face, fingerprint, pin }

/// Notices when Windows is locked and unlocked, and how it was unlocked.
///
/// The lock screen runs on Winlogon's secure desktop, which no app can draw
/// on or even open; the island can only react once you are back. While it
/// is up, [onLock] fires; when your desktop returns, [onUnlock] fires with
/// the method Windows Hello logged in the moments before.
class UnlockWatch {
  UnlockWatch({required this.onLock, required this.onUnlock});
  final void Function() onLock;
  final void Function(UnlockMethod method) onUnlock;

  Timer? _timer;
  bool _locked = false;

  /// Windows is on its lock screen right now.
  bool get locked => _locked;

  void start() {
    if (!Platform.isWindows || !_init()) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  void stop() => _timer?.cancel();

  void _check() {
    final now = _secureDesktopUp();
    if (now == _locked) return;
    _locked = now;
    if (now) {
      onLock();
    } else {
      unawaited(lastMethod().then(onUnlock));
    }
  }

  // ------------------------------------------------------------ the desktop

  static bool _ready = false;
  static late int Function(int, int, int) _openInput;
  static late int Function(int) _closeDesktop;
  static late int Function(int, int, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Uint32>) _objectInfo;

  static bool _init() {
    if (_ready) return true;
    try {
      final u = ffi.DynamicLibrary.open('user32.dll');
      _openInput = u.lookupFunction<ffi.IntPtr Function(ffi.Uint32, ffi.Int32, ffi.Uint32), int Function(int, int, int)>(
          'OpenInputDesktop');
      _closeDesktop = u.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>('CloseDesktop');
      _objectInfo = u.lookupFunction<
          ffi.Int32 Function(ffi.IntPtr, ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Pointer<ffi.Uint32>),
          int Function(int, int, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Uint32>)>('GetUserObjectInformationW');
      _ready = true;
    } catch (e, st) {
      logError(e, st);
    }
    return _ready;
  }

  /// True while the input desktop is not ours ('Default'): the lock screen,
  /// or a sign-in prompt on the secure desktop. Opening it is refused then.
  static bool _secureDesktopUp() {
    const readObjects = 0x0001, uoiName = 2;
    final h = _openInput(0, 0, readObjects);
    if (h == 0) return true;
    final buf = calloc<ffi.Uint16>(64), need = calloc<ffi.Uint32>();
    try {
      if (_objectInfo(h, uoiName, buf.cast(), 128, need) == 0) return false;
      return buf.cast<Utf16>().toDartString().toLowerCase() != 'default';
    } finally {
      calloc.free(buf);
      calloc.free(need);
      _closeDesktop(h);
    }
  }

  // ------------------------------------------------------------ the method

  /// Face or fingerprint if Windows Hello recognised you in the last
  /// [within]; otherwise a PIN or password was used. Event 1004 in the
  /// Biometrics log names the sensor ("Windows Hello Face ...",
  /// "... Fingerprint Sensor"), and the log is readable without admin.
  static Future<UnlockMethod> lastMethod({Duration within = const Duration(seconds: 20)}) async {
    try {
      final r = await Process.run('wevtutil.exe', [
        'qe',
        'Microsoft-Windows-Biometrics/Operational',
        '/q:*[System[(EventID=1004) and TimeCreated[timediff(@SystemTime) <= ${within.inMilliseconds}]]]',
        '/f:text',
        '/c:1',
        '/rd:true',
      ]);
      final text = (r.stdout as String).toLowerCase();
      if (r.exitCode != 0 || !text.contains('event id: 1004')) return UnlockMethod.pin;
      // Only the sensor's name: "face" could hide in other words ("interface").
      final at = text.indexOf('using sensor:');
      final sensor = at < 0 ? '' : text.substring(at);
      return sensor.contains('face') && !sensor.contains('finger') ? UnlockMethod.face : UnlockMethod.fingerprint;
    } catch (_) {
      return UnlockMethod.pin;
    }
  }
}
