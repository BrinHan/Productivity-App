import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show File, Platform, Process, ProcessStartMode;

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'island_controller.dart';
import 'now_playing.dart';

/// Order matters: it is the index of the screen shown by the app.
enum AppMode { map, home, island }

const Size kIslandWindowSize = Size(640, 360);
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

  // Island window position on the primary display (logical pixels).
  double _winLeft = 0, _winTop = 0, _zoneCx = 0, _zoneTop = 0;

  // Global mouse / key state (Windows API) for click-away and Esc.
  int Function(int)? _asyncKey;
  bool _lWas = false, _escWas = false;

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  Future<void> init() async {
    await island.load(); // saved shortcuts + settings
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
    _initKeys();
    await _initTray();
    _music = NowPlayingService(island.setNowPlaying);
    island.sendMusic = (cmd) => _music?.send(cmd);
    await _try(() => _music!.start());
  }

  void _initKeys() {
    if (!Platform.isWindows) return;
    try {
      final lib = ffi.DynamicLibrary.open('user32.dll');
      _asyncKey = lib.lookupFunction<ffi.Int16 Function(ffi.Int32), int Function(int)>(
          'GetAsyncKeyState');
    } catch (_) {}
  }

  bool _down(int vk) {
    final f = _asyncKey;
    return f != null && (f(vk) & 0x8000) != 0;
  }

  Future<void> _initTray() async {
    await _try(() async {
      await tray.trayManager.setIcon('assets/tray_icon.ico');
      await tray.trayManager.setToolTip('AOD World Map');
      await tray.trayManager.setContextMenu(tray.Menu(items: [
        tray.MenuItem(key: 'open', label: 'Open app'),
        tray.MenuItem.separator(),
        tray.MenuItem(key: 'island', label: 'Island: open'),
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

  // ---- shortcuts ---------------------------------------------------------

  Future<void> runShortcut(IslandShortcut s) async {
    switch (s.kind) {
      case ShortcutKind.screensaver:
        await _goTo(AppMode.map);
      case ShortcutKind.planner:
        await _goTo(AppMode.home);
      case ShortcutKind.web:
        await _try(() => _openWeb(s.target));
        island.close();
      case ShortcutKind.app:
        await _try(() => _launchApp(s.target));
        island.close();
    }
  }

  Future<void> _goTo(AppMode m) async {
    if (mode == AppMode.island) {
      _returnMode = m;
      await leaveIsland();
    } else if (m == AppMode.map) {
      showMap();
    } else {
      showHome();
    }
  }

  /// Chrome opens a URL as a new tab in its most recently used window.
  Future<void> _openWeb(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.contains('://')) u = 'https://$u';
    if (!Platform.isWindows) return;
    final env = Platform.environment;
    for (final base in [env['ProgramFiles'], env['ProgramFiles(x86)'], env['LOCALAPPDATA']]) {
      if (base == null) continue;
      final f = File('$base\\Google\\Chrome\\Application\\chrome.exe');
      if (f.existsSync()) {
        await Process.start(f.path, [u], mode: ProcessStartMode.detached);
        return;
      }
    }
    await Process.start('explorer.exe', [u], mode: ProcessStartMode.detached); // default browser
  }

  Future<void> _launchApp(String target) async {
    final t = target.trim();
    if (t.isEmpty || !Platform.isWindows) return;
    final env = Platform.environment;
    final candidates = <String>[];
    if (t.toLowerCase() == 'code' || t.toLowerCase() == 'vscode') {
      final local = env['LOCALAPPDATA'], pf = env['ProgramFiles'];
      if (local != null) candidates.add('$local\\Programs\\Microsoft VS Code\\Code.exe');
      if (pf != null) candidates.add('$pf\\Microsoft VS Code\\Code.exe');
    } else {
      candidates.add(t);
    }
    for (final c in candidates) {
      if (File(c).existsSync()) {
        await Process.start(c, [], mode: ProcessStartMode.detached);
        return;
      }
    }
    await Process.start('cmd.exe', ['/c', 'start', '', t], mode: ProcessStartMode.detached);
  }

  // ---- island mode -------------------------------------------------------

  /// Puts the island window at the top-centre of the PRIMARY display.
  /// Windows converts window coordinates with the DPI of the monitor the
  /// window is currently on, so we hop onto the primary display first, then
  /// size + position, and verify where it actually landed.
  Future<void> _placeIsland() async {
    final d = await screenRetriever.getPrimaryDisplay();
    final origin = d.visiblePosition ?? Offset.zero;
    final area = d.visibleSize ?? d.size;
    final target = Offset(
      origin.dx + (area.width - kIslandWindowSize.width) / 2,
      origin.dy,
    );
    _winLeft = target.dx;
    _winTop = target.dy;
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

  Rect _pillRect() {
    final w = island.pillSize.width, h = island.pillSize.height;
    return Rect.fromLTWH(
      _winLeft + (kIslandWindowSize.width - w) / 2,
      _winTop + 6 + island.pillDy,
      w,
      h,
    );
  }

  /// Polls the global cursor (50 ms). The window only captures the mouse
  /// while the cursor is over the pill, so it never blocks clicks on
  /// whatever is underneath the transparent area.
  Future<void> _tick() async {
    if (mode != AppMode.island || _ticking) return;
    _ticking = true;
    try {
      final p = await screenRetriever.getCursorScreenPoint();
      final pill = _pillRect();
      final visible = island.visible;
      final over = visible && pill.inflate(6).contains(p);
      final isOpen = island.state == IslandState.open;
      final inZone = isOpen
          ? pill.inflate(40).contains(p)
          : (visible
              ? Rect.fromLTRB(_zoneCx - 260, _zoneTop - 4, _zoneCx + 260, _zoneTop + 100).contains(p)
              : Rect.fromLTRB(_zoneCx - 170, _zoneTop - 4, _zoneCx + 170, _zoneTop + 8).contains(p));
      island.setNear(inZone);
      island.setOverPill(over);

      // Esc closes; clicking anywhere outside the pill closes (click mode).
      final lDown = _down(0x01), escDown = _down(0x1B);
      final clicked = lDown && !_lWas, esc = escDown && !_escWas;
      _lWas = lDown;
      _escWas = escDown;
      if (isOpen) {
        if (esc || (clicked && !island.openOnHover && !pill.inflate(2).contains(p))) {
          island.close();
        }
      }

      // Pip looks toward the cursor.
      if (visible) {
        final eye = (isOpen && island.page == IslandPage.home)
            ? Offset(pill.left + 54, pill.top + 95)
            : pill.center;
        final target = Offset(
          ((p.dx - eye.dx) / 240).clamp(-1.0, 1.0).toDouble(),
          ((p.dy - eye.dy) / 120).clamp(-1.0, 1.0).toDouble(),
        );
        island.gaze.value = Offset.lerp(island.gaze.value, target, 0.4)!;
      }

      if (over != _captured) {
        _captured = over;
        await _try(() => windowManager.setIgnoreMouseEvents(!over, forward: true));
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
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        _openApp();
      case 'island':
        island.preview(IslandState.open);
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
