import 'dart:io' show Platform;

import 'package:flutter/services.dart';

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

  static Future<void> unregister(int id) async {
    _handlers.remove(id);
    try {
      await _channel.invokeMethod('unregister', {'id': id});
    } catch (_) {}
  }

  /// Puts back the window that was in front before the last hotkey press.
  static Future<void> giveBackFocus() async {
    try {
      await _channel.invokeMethod('giveBack');
    } catch (_) {}
  }

  static Future<void> _onCall(MethodCall call) async {
    if (call.method == 'pressed') _handlers[call.arguments]?.call();
  }
}
