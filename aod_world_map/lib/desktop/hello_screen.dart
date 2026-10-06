import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'cs_helper.dart';
import 'unlock_watch.dart';

/// Windows Hello for the Hello screen: the world map that comes up when you
/// step away, and asks Windows Hello who you are when you come back.
///
/// It is a welcome screen, not a lock. Windows' own lock is still what keeps
/// the PC safe; this only makes coming back feel like a phone.
class HelloService {
  HelloService._();

  /// Whether Windows Hello is set up here (face, fingerprint or PIN).
  static Future<bool> available() async {
    final out = await _run(['check']);
    return out == 'avail Available';
  }

  /// Shows Windows Hello's prompt in front of [hwnd]. True once it has
  /// verified you; false if you cancel or it can't.
  static Future<bool> verify(int hwnd, String message) async {
    final out = await _run(['verify', '$hwnd', message]);
    return out == 'result Verified';
  }

  /// The glyph to scan with while Windows Hello decides: however you last
  /// signed in with a face or a finger, or the padlock if never.
  static Future<UnlockMethod> likelyMethod() => UnlockWatch.lastMethod(within: const Duration(days: 90));

  /// This process's app window, to own the prompt.
  static int ownWindow() {
    try {
      final find = ffi.DynamicLibrary.open('user32.dll').lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>),
          int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>)>('FindWindowW');
      final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16(), title = 'Meridian'.toNativeUtf16();
      try {
        return find(cls, title);
      } finally {
        calloc.free(cls);
        calloc.free(title);
      }
    } catch (_) {
      return 0;
    }
  }

  static Future<String> _run(List<String> args) async {
    try {
      final exe = await buildCsHelper('aod_hello_v1', _cs, refs: const [
        r'{fw}\System.Runtime.dll',
        r'{fw}\System.Runtime.WindowsRuntime.dll',
        r'{fw}\System.Runtime.InteropServices.WindowsRuntime.dll',
        r'{md}\Windows.Foundation.winmd',
        r'{md}\Windows.Security.winmd',
      ]);
      if (exe == null) return '';
      final r = await Process.run(exe, args);
      return (r.stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  /// Asks Windows Hello (UserConsentVerifier) through its desktop-app
  /// interop, so the prompt opens in front of the given window.
  static const _cs = r'''
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading;
using Windows.Foundation;
using Windows.Security.Credentials.UI;

static class HelloHelper
{
    [ComImport, Guid("39E050C3-4E74-441A-8DC0-B81104DF949C"), InterfaceType(ComInterfaceType.InterfaceIsIInspectable)]
    interface IUserConsentVerifierInterop
    {
        [return: MarshalAs(UnmanagedType.IInspectable)]
        object RequestVerificationForWindowAsync(IntPtr appWindow, [MarshalAs(UnmanagedType.HString)] string message, [In] ref Guid riid);
    }

    static T Await<T>(IAsyncOperation<T> op)
    {
        while (op.Status == AsyncStatus.Started) Thread.Sleep(10);
        if (op.Status != AsyncStatus.Completed) throw new Exception("async " + op.Status);
        return op.GetResults();
    }

    // check               -> "avail <Available|DeviceNotPresent|...>"
    // verify <hwnd> <msg> -> "result <Verified|Canceled|...>"
    static int Main(string[] args)
    {
        try
        {
            if (args.Length > 0 && args[0] == "check")
            {
                Console.WriteLine("avail " + Await(UserConsentVerifier.CheckAvailabilityAsync()));
                return 0;
            }
            if (args.Length > 2 && args[0] == "verify")
            {
                var hwnd = new IntPtr(long.Parse(args[1]));
                var interop = (IUserConsentVerifierInterop)WindowsRuntimeMarshal.GetActivationFactory(typeof(UserConsentVerifier));
                var iid = typeof(IAsyncOperation<UserConsentVerificationResult>).GUID;
                var op = (IAsyncOperation<UserConsentVerificationResult>)interop.RequestVerificationForWindowAsync(hwnd, args[2], ref iid);
                Console.WriteLine("result " + Await(op));
                return 0;
            }
            return 2;
        }
        catch (Exception e)
        {
            Console.WriteLine("error " + e.Message.Replace('\n', ' '));
            return 1;
        }
    }
}
''';
}

/// Watches for you stepping away: no keyboard or mouse for [after], and
/// nothing (a video, a call) asking Windows to keep the display on. Then
/// [onAway] fires, once, until you are back.
class AwayWatch {
  AwayWatch({required this.after, required this.onAway, required this.skip});

  /// How long idle counts as away; zero turns it off. Read on every check,
  /// so a settings change applies at once.
  final Duration Function() after;
  final void Function() onAway;

  /// True when it should not fire now (Windows is locked, say).
  final bool Function() skip;

  Timer? _timer;
  bool _fired = false;

  void start() {
    if (!Platform.isWindows || !_init()) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void stop() => _timer?.cancel();

  void _check() {
    final idle = _idleFor();
    if (idle < const Duration(seconds: 5)) _fired = false; // you're back
    final limit = after();
    if (_fired || limit == Duration.zero || idle < limit || skip() || _displayRequired()) return;
    _fired = true;
    onAway();
  }

  static bool _ready = false;
  static late int Function(ffi.Pointer<ffi.Uint32>) _lastInput;
  static late int Function() _ticks;
  static int Function(int, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)? _power;

  static bool _init() {
    if (_ready) return true;
    try {
      _lastInput = ffi.DynamicLibrary.open('user32.dll')
          .lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Uint32>), int Function(ffi.Pointer<ffi.Uint32>)>('GetLastInputInfo');
      _ticks = ffi.DynamicLibrary.open('kernel32.dll').lookupFunction<ffi.Uint32 Function(), int Function()>('GetTickCount');
      try {
        _power = ffi.DynamicLibrary.open('powrprof.dll').lookupFunction<
            ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Uint32),
            int Function(int, ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>, int)>('CallNtPowerInformation');
      } catch (_) {}
      _ready = true;
    } catch (_) {}
    return _ready;
  }

  /// Time since the last key press or mouse move, anywhere.
  static Duration _idleFor() {
    final info = calloc<ffi.Uint32>(2)..[0] = 8; // LASTINPUTINFO: cbSize, dwTime
    try {
      if (_lastInput(info) == 0) return Duration.zero;
      final ms = (_ticks() - info[1]) & 0xFFFFFFFF;
      return Duration(milliseconds: ms);
    } finally {
      calloc.free(info);
    }
  }

  /// A video or call is keeping the display on (ES_DISPLAY_REQUIRED).
  static bool _displayRequired() {
    final f = _power;
    if (f == null) return false;
    final state = calloc<ffi.Uint32>();
    try {
      const systemExecutionState = 16, displayRequired = 0x2;
      if (f(systemExecutionState, ffi.nullptr, 0, state.cast(), 4) != 0) return false;
      return state.value & displayRequired != 0;
    } finally {
      calloc.free(state);
    }
  }
}
