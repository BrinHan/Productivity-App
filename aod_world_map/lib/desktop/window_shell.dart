import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'island_controller.dart';
import 'now_playing.dart';

/// Order matters: it is the index of the screen shown by the app.
enum AppMode { map, home, island }

const Size kIslandWindowSize = Size(560, 132);
const Size _kAppMin = Size(720, 480);

/// Owns the native window. Switches between the normal app window and the
/// tiny transparent always-on-top island window, and runs the tray icon.
class ShellController extends ChangeNotifier with WindowListener, tray.TrayListener {
  AppMode mode = AppMode.map;
  final IslandController island = IslandController();

  AppMode _returnMode = AppMode.map;
  Rect? _savedBounds;
  bool _wasMaximized = false;
  bool _busy = false, _ticking = false, _captured = false;
  Timer? _poll;
  NowPlayingService? _music;

  // Hover zone, computed from the primary display (logical pixels).
  double _zoneCx = 0, _zoneTop = 0;

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Some window calls are not implemented on every OS; ignore those.
  Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  Future<void> init() async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'AOD World Map',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await _try(() => windowManager.setMinimumSize(_kAppMin));
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
    await _initTray();
    _music = NowPlayingService(island.setNowPlaying);
    await _try(() => _music!.start());
  }

  Future<void> _initTray() async {
    await _try(() async {
      await tray.trayManager.setIcon('assets/tray_icon.ico');
      await tray.trayManager.setToolTip('AOD World Map');
      await tray.trayManager.setContextMenu(tray.Menu(items: [
        tray.MenuItem(key: 'open', label: 'Open app'),
        tray.MenuItem.separator(),
        tray.MenuItem(key: 'idle', label: 'Island: idle'),
        tray.MenuItem(key: 'call', label: 'Island: incoming call'),
        tray.MenuItem(key: 'music', label: 'Island: music'),
        tray.MenuItem(key: 'success', label: 'Island: Face ID success'),
        tray.MenuItem.separator(),
        tray.MenuItem(key: 'quit', label: 'Quit'),
      ]));
      tray.trayManager.addListener(this);
    });
  }

  // ---- screens -----------------------------------------------------------

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

  Future<void> toggleMaximize() async {
    if (!supported) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> quit() async {
    if (!supported) return;
    _music?.dispose();
    await _try(() => tray.trayManager.destroy());
    await windowManager.destroy();
  }

  // ---- island mode -------------------------------------------------------

  /// Puts the island window at the top-centre of the PRIMARY display.
  /// Windows converts window coordinates using the DPI of the monitor the
  /// window is currently on, so we first hop onto the primary display, then
  /// size + position, and verify where it actually landed.
  Future<void> _placeIsland() async {
    final d = await screenRetriever.getPrimaryDisplay();
    final origin = d.visiblePosition ?? Offset.zero;
    final area = d.visibleSize ?? d.size;
    final target = Offset(
      origin.dx + (area.width - kIslandWindowSize.width) / 2,
      origin.dy,
    );
    _zoneCx = origin.dx + area.width / 2;
    _zoneTop = origin.dy;

    await windowManager.setPosition(origin + const Offset(80, 80));
    await Future.delayed(const Duration(milliseconds: 150));
    for (var i = 0; i < 3; i++) {
      await windowManager.setSize(kIslandWindowSize);
      await windowManager.setPosition(target);
      await Future.delayed(const Duration(milliseconds: 100));
      final b = await windowManager.getBounds();
      final ok = (b.left - target.dx).abs() < 3 &&
          (b.top - target.dy).abs() < 3 &&
          (b.width - kIslandWindowSize.width).abs() < 3;
      if (ok) break;
    }
  }

  Future<void> enterIsland() async {
    if (!supported || mode == AppMode.island || _busy) return;
    _busy = true;
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      _wasMaximized = await windowManager.isMaximized();
      if (_wasMaximized) await windowManager.unmaximize();
      _savedBounds = await windowManager.getBounds();
      _returnMode = mode;
      island.reset();
      mode = AppMode.island;
      notifyListeners();

      await _try(() => windowManager.setMinimumSize(const Size(1, 1)));
      await _try(() => windowManager.setHasShadow(false));
      await _placeIsland();
      await _try(() => windowManager.setResizable(false));
      await windowManager.setSkipTaskbar(true); // gone from the taskbar
      await windowManager.setAlwaysOnTop(true);
      await _try(() => windowManager.setIgnoreMouseEvents(true, forward: true));
      _captured = false;
      await windowManager.show();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    } finally {
      _busy = false;
    }
  }

  Future<void> leaveIsland() async {
    if (!supported || mode != AppMode.island || _busy) return;
    _busy = true;
    try {
      _poll?.cancel();
      island.reset();
      await _try(() => windowManager.setIgnoreMouseEvents(false));
      await windowManager.setAlwaysOnTop(false);
      await _try(() => windowManager.setResizable(true));
      await _try(() => windowManager.setHasShadow(true));
      await _try(() => windowManager.setMinimumSize(_kAppMin));
      final b = _savedBounds;
      if (b != null) {
        // Same DPI trick as above: move first, then size, then move again.
        await windowManager.setPosition(b.topLeft);
        await Future.delayed(const Duration(milliseconds: 120));
        await windowManager.setSize(b.size);
        await windowManager.setPosition(b.topLeft);
      }
      await windowManager.setSkipTaskbar(false);
      mode = _returnMode;
      notifyListeners();
      await windowManager.show();
      await windowManager.focus();
      if (_wasMaximized) await windowManager.maximize();
    } finally {
      _busy = false;
    }
  }

  Future<void> _openApp() async {
    if (mode == AppMode.island) {
      await leaveIsland();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  /// Polls the global cursor. Near the top-centre of the primary display ->
  /// island pops out. The window ignores the mouse except while the island
  /// is usable, so it never blocks clicks on whatever is underneath.
  Future<void> _tick() async {
    if (mode != AppMode.island || _ticking) return;
    _ticking = true;
    try {
      final p = await screenRetriever.getCursorScreenPoint();
      final cx = _zoneCx, top = _zoneTop;
      final zone = island.visible
          ? Rect.fromLTRB(cx - 260, top - 4, cx + 260, top + 100)
          : Rect.fromLTRB(cx - 170, top - 4, cx + 170, top + 8);
      island.setNear(zone.contains(p));

      if (island.visible) {
        final pillY = top + 6 + island.idleSize.height / 2;
        final target = Offset(
          ((p.dx - cx) / 240).clamp(-1.0, 1.0).toDouble(),
          ((p.dy - pillY) / 120).clamp(-1.0, 1.0).toDouble(),
        );
        island.gaze.value = Offset.lerp(island.gaze.value, target, 0.4)!;
      }

      final capture =
          island.visible && (island.near || island.state == IslandState.call);
      if (capture != _captured) {
        _captured = capture;
        await _try(() => windowManager.setIgnoreMouseEvents(!capture, forward: true));
      }
    } catch (_) {
    } finally {
      _ticking = false;
    }
  }

  // ---- native callbacks --------------------------------------------------

  @override
  void onWindowMinimize() {
    if (mode != AppMode.island) enterIsland();
  }

  @override
  void onTrayIconMouseDown() => _openApp();

  @override
  void onTrayIconRightMouseDown() => tray.trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(tray.MenuItem item) {
    switch (item.key) {
      case 'open':
        _openApp();
      case 'idle':
        island.preview(IslandState.idle);
      case 'call':
        island.preview(IslandState.call);
      case 'music':
        island.preview(IslandState.music);
      case 'success':
        island.preview(IslandState.success);
      case 'quit':
        quit();
    }
  }
}
