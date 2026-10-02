import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'app_mode.dart';
import 'island_controller.dart';

/// Web shell: desktop window, tray, FFI, and native media controls are unavailable.
class ShellController extends ChangeNotifier {
  AppMode mode = AppMode.map;
  final IslandController island = IslandController();

  static bool get supported => false;

  Future<void> init() async {
    await island.load();
  }

  void showHome() {
    if (mode == AppMode.island) return;
    mode = AppMode.home;
    notifyListeners();
  }

  void showMap() {
    if (mode == AppMode.island) return;
    mode = AppMode.map;
    notifyListeners();
  }

  Future<void> toggleMaximize() async {}

  Future<void> quit() async {}

  Future<void> runShortcut(IslandShortcut shortcut) async {
    switch (shortcut.kind) {
      case ShortcutKind.screensaver:
        showMap();
      case ShortcutKind.planner:
        showHome();
      case ShortcutKind.web:
      case ShortcutKind.app:
        island.close();
    }
  }

  Future<void> enterIsland() async {
    if (mode == AppMode.island) return;
    mode = AppMode.island;
    island.reset();
    notifyListeners();
  }

  Future<void> leaveIsland() async {
    if (mode != AppMode.island) return;
    mode = AppMode.map;
    island.reset();
    notifyListeners();
  }
}
