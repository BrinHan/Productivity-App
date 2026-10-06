import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'foreground_app.dart';
import 'island_controller.dart';
import 'island_pages.dart';
import 'now_playing.dart';
import 'planner_model.dart';
import 'process_link.dart';
import 'window_shell.dart' show launchApp, openWeb;

const Size kIslandWindowSize = Size(640, 480);

/// The dynamic island as its own small, always-on-top process. It starts
/// with the app and stays when the app window closes, so it works over
/// Chrome or anything else. It owns the background work: meeting notes,
/// the media helper, the tray icon and Drive backup.
///
/// The window is a transparent 640x480 strip at the top of the primary
/// display that lets clicks through except over the pill itself.
class IslandShell extends ChangeNotifier with tray.TrayListener {
  IslandShell(this.planner);
  final PlannerModel planner;
  final IslandController island = IslandController();

  LinkServer? _server;
  DataWatch? _watch;
  NowPlayingService? _music;
  Timer? _poll, _notesPush, _trim;
  bool _ticking = false, _captured = false, _pushQueued = false;
  int _n = 0;

  double _winLeft = 0, _winTop = 0, _zoneCx = 0, _zoneTop = 0;
  int Function(int)? _asyncKey;
  bool _lWas = false, _escWas = false, _annotateWas = false, _askWas = false;

  Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// Takes the island's single-instance lock. False if one already runs.
  Future<bool> claim() async {
    _server = await LinkServer.bind(kIslandPort, _onMessage);
    return _server != null;
  }

  Future<void> init() async {
    island.planner = planner;
    await island.load();

    // Notes: the app window mirrors recording state and sends the buttons.
    _server!.onConnect = (peer) => peer.send(island.notes.snapshot());
    island.notes.addListener(_queueNotesPush);
    island.notes.tick.addListener(_queueNotesPush);
    _watch = DataWatch(appDataDir, _onFile)..start();

    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: kIslandWindowSize,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      title: 'Meridian Island',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await _try(() => windowManager.setMinimumSize(const Size(1, 1)));
      await _try(() => windowManager.setHasShadow(false));
      await _try(() => windowManager.setResizable(false));
      await _placeIsland();
      await _try(() => windowManager.setIgnoreMouseEvents(true, forward: true));
      await windowManager.show(inactive: true); // never steal focus from what you are doing
    });

    _initKeys();
    await _initTray();
    island.sendMusic = (cmd) => _music?.send(cmd);
    island.openUrl = (u) => _try(() => openWeb(u));
    island.startAnnotate = () {
      island.close();
      openOverlay();
    };
    island.addListener(_onIslandChanged);
    _onIslandChanged();
    _poll = Timer.periodic(const Duration(milliseconds: 60), (_) => _tick());
    // Have an overlay waiting so annotating opens instantly. Started a moment
    // after the island so the two don't compete at login.
    Timer(const Duration(seconds: 4), _warmOverlay);
  }

  /// Starts a hidden overlay unless one is already running.
  Future<void> _warmOverlay() async {
    if (!await LinkServer.isUp(kOverlayPort)) await spawnSelf(['--overlay', '--standby']);
  }

  // ---- messages and shared files ----------------------------------------

  void _onMessage(Map<String, dynamic> m, LinkPeer from) {
    final t = '${m['t']}';
    if (t.startsWith('notes.')) {
      island.notes.handleCommand(m);
    } else if (t == 'quit') {
      quit();
    } else if (t == 'preview') {
      // Same as the tray's "Island: ..." items; handy from a script too.
      final s = IslandState.values.where((x) => x.name == m['state']).firstOrNull;
      if (s != null) island.preview(s);
    }
  }

  void _onFile(String name) {
    if (name == 'planner.json') {
      planner.reload();
    } else if (name == 'island.json') {
      island.reloadSettings();
    } else if (name == 'google.json') {
      island.google.reloadFromDisk();
    }
  }

  /// At most ten notes updates a second, which is what the level line needs.
  void _queueNotesPush() {
    if (_server == null || _server!.peers.isEmpty) return;
    if (_notesPush?.isActive == true) {
      _pushQueued = true;
      return;
    }
    _server!.broadcast(island.notes.snapshot());
    _notesPush = Timer(const Duration(milliseconds: 100), () {
      if (_pushQueued) {
        _pushQueued = false;
        _queueNotesPush();
      }
    });
  }

  IslandState? _lastState;

  void _onIslandChanged() {
    _syncMusic();
    if (island.state == _lastState) return;
    _lastState = island.state;
    // Once the island settles into a new shape, hand back what the change
    // used (decoded art, text layout, shader setup) and keep doing so while
    // it sits there. Whatever the next frames need comes back by itself.
    _trim?.cancel();
    _trim = Timer(const Duration(seconds: 3), () {
      trimMemory();
      _trim = Timer.periodic(const Duration(seconds: 30), (_) => trimMemory());
    });
  }

  /// The media helper runs unless it was turned off in settings.
  void _syncMusic() {
    final want = Platform.isWindows && island.musicHelper;
    if (want && _music == null) {
      _music = NowPlayingService(island.setNowPlaying, onBands: island.bands.set);
      unawaited(_music!.start());
    } else if (!want && _music != null) {
      _music!.dispose();
      _music = null;
      island.setNowPlaying(null);
    }
  }

  // ---- the app window ---------------------------------------------------

  /// Brings the app window forward, starting it if it is closed.
  Future<void> openApp([String? mode]) async {
    island.close();
    final sent = await LinkServer.sendOnce(kAppPort, {'t': 'open', 'mode': mode});
    if (!sent) await spawnSelf([if (mode != null) '--$mode']);
  }

  /// Shows the annotation overlay, starting it if it is not running.
  /// [toggle] hides it instead when it is showing; [ask] opens the AI panel.
  Future<void> openOverlay({bool toggle = false, bool ask = false}) async {
    final t = ask ? 'ask' : (toggle ? 'toggle' : 'show');
    final sent = await LinkServer.sendOnce(kOverlayPort, {'t': t});
    if (!sent) await spawnSelf(['--overlay', if (ask) '--ask']); // none waiting (it crashed or was ended)
  }

  Future<void> runShortcut(IslandShortcut s) async {
    switch (s.kind) {
      case ShortcutKind.screensaver:
        await openApp('map');
      case ShortcutKind.planner:
        await openApp('home');
      case ShortcutKind.web:
        await _try(() => openWeb(s.target));
        island.close();
      case ShortcutKind.app:
        await _try(() => launchApp(s.target));
        island.close();
    }
  }

  /// Quits everything: the app window too.
  Future<void> quit() async {
    _poll?.cancel();
    _trim?.cancel();
    await LinkServer.sendOnce(kAppPort, const {'t': 'quit'});
    await LinkServer.sendOnce(kOverlayPort, const {'t': 'quit'});
    _music?.dispose();
    _watch?.stop();
    await _try(() => tray.trayManager.destroy());
    await _server?.close();
    await shutdownWindow();
  }

  // ---- window -----------------------------------------------------------

  /// Flush with the very top of the PRIMARY display, centred. Windows uses
  /// the DPI of the monitor the window is on, so hop onto the primary
  /// display first, then size + position, and verify where it landed.
  Future<void> _placeIsland() async {
    final d = await screenRetriever.getPrimaryDisplay();
    final target = Offset((d.size.width - kIslandWindowSize.width) / 2, 0);
    _winLeft = target.dx;
    _winTop = target.dy;
    _zoneCx = d.size.width / 2;
    _zoneTop = 0;

    await windowManager.setPosition(const Offset(80, 80));
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

  void _initKeys() {
    if (!Platform.isWindows) return;
    try {
      final lib = ffi.DynamicLibrary.open('user32.dll');
      _asyncKey = lib.lookupFunction<ffi.Int16 Function(ffi.Int32), int Function(int)>('GetAsyncKeyState');
    } catch (_) {}
  }

  bool _down(int vk) {
    final f = _asyncKey;
    return f != null && (f(vk) & 0x8000) != 0;
  }

  Future<void> _initTray() async {
    await _try(() async {
      await tray.trayManager.setIcon('assets/tray_icon.ico');
      await tray.trayManager.setToolTip('Meridian');
      await tray.trayManager.setContextMenu(tray.Menu(items: [
        tray.MenuItem(key: 'open', label: 'Open app'),
        tray.MenuItem(key: 'planner', label: 'Open planner'),
        tray.MenuItem(key: 'annotate', label: 'Annotate screen  (Ctrl+Shift+A)'),
        tray.MenuItem.separator(),
        tray.MenuItem(key: 'island', label: 'Island: open'),
        tray.MenuItem(key: 'notch', label: 'Island: Chrome notch'),
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

  Rect _pillRect() {
    final w = island.pillSize.width, h = island.pillSize.height;
    return Rect.fromLTWH(_winLeft + (kIslandWindowSize.width - w) / 2, _winTop + island.pillDy, w, h);
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      _n++;
      // Ctrl+Shift+A: annotate (again to hide). Ctrl+Shift+Space: ask the AI.
      final chord = _down(0x11) && _down(0x10);
      final annotate = chord && _down(0x41), ask = chord && _down(0x20);
      if (annotate && !_annotateWas) unawaited(openOverlay(toggle: true));
      if (ask && !_askWas) unawaited(openOverlay(ask: true));
      _annotateWas = annotate;
      _askWas = ask;
      if (_n % 5 == 0) {
        // Chrome in front? (our own windows being clicked don't count)
        final fg = ForegroundApp.current();
        if (fg != null && fg != ForegroundApp.own) island.setChromeMode(fg == 'chrome.exe');
      }

      final p = await screenRetriever.getCursorScreenPoint();
      final pill = _pillRect();
      final visible = island.visible;
      final isOpen = island.state == IslandState.open;
      final over = visible && pill.inflate(6).contains(p);
      final notch = island.state == IslandState.notch;
      final hiddenHalf = island.quiet ? 80.0 : 170.0;
      final inZone = isOpen
          ? pill.inflate(40).contains(p)
          : (visible
              ? (notch
                      ? Rect.fromLTRB(_zoneCx - 90, _zoneTop - 4, _zoneCx + 90, _zoneTop + 34)
                      : Rect.fromLTRB(_zoneCx - 260, _zoneTop - 4, _zoneCx + 260, _zoneTop + 100))
                  .contains(p)
              : Rect.fromLTRB(_zoneCx - hiddenHalf, _zoneTop - 4, _zoneCx + hiddenHalf, _zoneTop + 8).contains(p));
      island.setNear(inZone);
      island.setOverPill(over);

      // Esc closes; a click outside the open island closes (click mode).
      final lDown = _down(0x01), escDown = _down(0x1B);
      final clicked = lDown && !_lWas, esc = escDown && !_escWas;
      _lWas = lDown;
      _escWas = escDown;
      if (isOpen && (esc || (clicked && !island.openOnHover && !pill.inflate(2).contains(p)))) {
        island.close();
      }

      if (visible) {
        final seated = isOpen && island.page == IslandPage.home;
        final eye = seated
            ? Offset(pill.left + (pill.width - kOpenHome.width) / 2 + homeSeatCenter(kOpenHome).dx,
                pill.top + homeSeatCenter(kOpenHome).dy)
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

  // ---- tray -------------------------------------------------------------

  @override
  void onTrayIconMouseDown() => openApp();

  @override
  void onTrayIconRightMouseDown() => tray.trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        openApp();
      case 'planner':
        openApp('home');
      case 'annotate':
        openOverlay();
      case 'island':
        island.preview(IslandState.open);
      case 'notch':
        island.preview(IslandState.notch);
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
