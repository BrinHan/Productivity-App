import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'log.dart';

/// System-wide hotkeys, registered by the Windows runner (flutter_window.cpp).
/// Unlike watching the keyboard, a registered hotkey is taken away from the
/// app in front, and its press brings this window to the front so it can be
/// typed into.
class GlobalHotkey {
  GlobalHotkey._();

  static const _channel = MethodChannel('meridian/hotkey');
  static final _handlers = <int, void Function()>{};

  // Win32 modifier flags.
  static const alt = 0x1, ctrl = 0x2, shift = 0x4, win = 0x8;

  /// Registers [mods] + [vk] as hotkey [id]. False if another app has it.
  static Future<bool> register(int id, int mods, int vk, void Function() onPressed) async {
    if (!Platform.isWindows) return false;
    _channel.setMethodCallHandler(_onCall);
    _handlers[id] = onPressed;
    try {
      return await _channel.invokeMethod<bool>('register', {'id': id, 'mods': mods, 'vk': vk}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The key the runner adds when it replays a modifier chord: F24, which no
  /// keyboard has, so the registered combination is free.
  static const _chordVk = 0x87;

  /// Registers pressing Ctrl+Shift+Alt together and letting go, with no
  /// other key, as hotkey [id]. Windows can't register modifiers alone, so
  /// the runner watches for the chord and replays it as Ctrl+Shift+Alt+F24.
  static Future<bool> registerChord(int id, void Function() onPressed) async {
    if (!await register(id, ctrl | shift | alt, _chordVk, onPressed)) return false;
    try {
      if (await _channel.invokeMethod<bool>('chord', {'vk': _chordVk}) ?? false) return true;
    } on PlatformException catch (e, st) {
      logError(e, st);
    } on MissingPluginException catch (e, st) {
      logError(e, st);
    }
    await unregister(id);
    return false;
  }

  static Future<void> unregisterChord(int id) async {
    try {
      await _channel.invokeMethod('unchord');
    } catch (e, st) {
      logError(e, st);
    }
    await unregister(id);
  }

  static Future<void> unregister(int id) async {
    _handlers.remove(id);
    try {
      await _channel.invokeMethod('unregister', {'id': id});
    } catch (e, st) {
      logError(e, st);
    }
  }

  /// Puts back the window that was in front before the last hotkey press.
  static Future<void> giveBackFocus() async {
    try {
      await _channel.invokeMethod('giveBack');
    } catch (e, st) {
      logError(e, st);
    }
  }

  static Future<void> _onCall(MethodCall call) async {
    if (call.method == 'pressed') _handlers[call.arguments]?.call();
  }
}
