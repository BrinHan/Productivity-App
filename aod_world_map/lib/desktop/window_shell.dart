import 'dart:async';
import 'dart:io' show File, Platform, Process, ProcessStartMode;

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'hello_screen.dart';
import 'island_controller.dart';
import 'planner_model.dart';
import 'process_link.dart';
import 'unlock_watch.dart';

/// The app window shows one of these at a time; the other is disposed.
enum AppMode { map, home }

const Size _kAppMin = Size(720, 480);

/// The app window (screensaver map and planner). The dynamic island is a
/// separate process (see IslandShell), so it keeps working over Chrome or
/// anything else, and closing this window frees all of its memory.
class ShellController extends ChangeNotifier with WindowListener {
  ShellController({this.mode = AppMode.map, this.helloAtStart = false});
  AppMode mode;

  /// Started (with --hello) only to show the Hello screen.
  final bool helloAtStart;

  /// Island settings, Google and notes as seen from the app window.
  final IslandController island = IslandController(inApp: true);
  PlannerModel? planner;

  LinkServer? _lock;
  LinkClient? _link;
  DataWatch? _watch;
  Timer? _trim;

  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// Takes the single-instance lock. False when an app window is already
  /// open; that one has been asked to come forward instead.
  Future<bool> claim() async {
    _lock = await LinkServer.bind(kAppPort, _onMessage);
    if (_lock != null) return true;
    await LinkServer.sendOnce(kAppPort, helloAtStart ? const {'t': 'hello'} : {'t': 'open', 'mode': mode.name});
    return false;
  }

  Future<void> init(PlannerModel p) async {
    planner = p;
    island.planner = p;
    await island.load();
    if (!supported) return;
    // The island lives on after this window closes; start it if needed.
    if (!await LinkServer.isUp(kIslandPort)) await spawnSelf(['--island']);
    _link = LinkClient(kIslandPort, _onIsland)..start();
    island.notes.send = (m) => _link?.send(m) ?? false;
    island.openUrl = (u) => _try(() => openWeb(u));
    _watch = DataWatch(appDataDir, _onFile)..start();

    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Meridian',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await _try(() => windowManager.setMinimumSize(_kAppMin));
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
  }

  void _onIsland(Map<String, dynamic> m) {
    if (m['t'] == 'notes') island.notes.applySnapshot(m);
  }

  /// Something the island process saved.
  void _onFile(String name) {
    if (name == 'planner.json') {
      planner?.reload();
    } else if (name == 'island.json') {
      island.reloadSettings();
    } else if (name == 'google.json') {
      island.google.reloadFromDisk();
    } else if (name.startsWith('notes') && name.endsWith('.json') && !island.notes.recording) {
      island.notes.loadNotes();
    }
  }

  void _onMessage(Map<String, dynamic> m, LinkPeer from) {
    switch (m['t']) {
      case 'open':
        final want = AppMode.values.where((x) => x.name == m['mode']).firstOrNull;
        bringForward(want);
      case 'quit':
        quit();
      case 'hello':
        startHello();
      case 'helloEnd':
        if (hello.value) _endHello();
    }
  }

  /// Another launch, or the island, asked for this window.
  Future<void> bringForward([AppMode? m]) async {
    if (m != null && m != mode) {
      mode = m;
      notifyListeners();
    }
    if (!supported) return;
    await _try(() async {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// The first frame can render into a small surface in the corner when the
  /// window is maximized before Flutter is ready. A real resize event makes
  /// Flutter re-read the size, so after the first frame: resize to the work
  /// area, then maximize.
  Future<void> settleWindow() async {
    if (!supported) return;
    await Future.delayed(const Duration(milliseconds: 250));
    await _try(() async {
      final d = await screenRetriever.getPrimaryDisplay();
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      await windowManager.unmaximize();
      await windowManager.setBounds(Rect.fromLTWH(pos.dx, pos.dy, size.width - 4, size.height - 4));
      await Future.delayed(const Duration(milliseconds: 120));
      await windowManager.maximize();
    });
    if (helloAtStart) await startHello(spawned: true);
  }

  // ---- screens -----------------------------------------------------------

  void showHome() {
    mode = AppMode.home;
    notifyListeners();
  }

  void showMap() {
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

  Future<void> minimize() async {
    if (supported) await windowManager.minimize();
  }

  /// Closes the app window. The island keeps running.
  Future<void> quit() async {
    if (!supported) return;
    _trim?.cancel();
    _watch?.stop();
    _link?.stop();
    await _lock?.close();
    await shutdownWindow();
  }

  /// Quits the island as well.
  Future<void> quitAll() async {
    await LinkServer.sendOnce(kIslandPort, const {'t': 'quit'});
    await quit();
  }

  // ---- Hello screen ------------------------------------------------------

  /// True while the Hello screen is up: the map, full screen and on top,
  /// waiting for you to come back and sign in with Windows Hello.
  final ValueNotifier<bool> hello = ValueNotifier(false);
  bool _helloChecking = false, _helloSpawned = false;
  bool _helloWasVisible = true, _helloWasMinimized = false;
  AppMode _helloWasMode = AppMode.map;
  DateTime _helloQuietUntil = DateTime(2000);

  Future<void> startHello({bool spawned = false}) async {
    if (hello.value || !supported) return;
    _helloSpawned = spawned;
    _helloWasMode = mode;
    _helloWasVisible = !spawned;
    await _try(() async {
      if (!spawned) _helloWasVisible = await windowManager.isVisible();
      _helloWasMinimized = await windowManager.isMinimized();
    });
    mode = AppMode.map;
    hello.value = true;
    notifyListeners();
    await _try(() async {
      if (_helloWasMinimized) await windowManager.restore();
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setFullScreen(true);
      await windowManager.focus();
    });
    // Appearing can jiggle the mouse; only a real return counts.
    _helloQuietUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  /// A key press or mouse move on the Hello screen: ask Windows Hello.
  Future<void> helloInput() async {
    if (!hello.value || _helloChecking || DateTime.now().isBefore(_helloQuietUntil)) return;
    _helloChecking = true;
    try {
      if (!await HelloService.available()) {
        await _endHello(); // no Windows Hello here: nothing to check
        return;
      }
      final likely = await HelloService.likelyMethod();
      _link?.send({'t': 'hello', 'phase': 'scan', 'method': likely.name});
      if (await HelloService.verify(HelloService.ownWindow(), 'Welcome back')) {
        // How you got in: Windows Hello logs a face or finger; a PIN leaves no trace.
        final how = await UnlockWatch.lastMethod(within: const Duration(seconds: 15));
        _link?.send({'t': 'hello', 'phase': 'done', 'method': how.name});
        await _endHello();
      } else {
        _link?.send({'t': 'hello', 'phase': 'fail'});
        _helloQuietUntil = DateTime.now().add(const Duration(milliseconds: 1500));
      }
    } finally {
      _helloChecking = false;
    }
  }

  Future<void> _endHello() async {
    hello.value = false;
    await _try(() async {
      await windowManager.setFullScreen(false);
      await windowManager.setAlwaysOnTop(false);
    });
    if (_helloSpawned) {
      await quit(); // the window was only here for the Hello screen
      return;
    }
    mode = _helloWasMode;
    notifyListeners();
    await _try(() async {
      if (!_helloWasVisible) {
        await windowManager.hide();
      } else if (_helloWasMinimized) {
        await windowManager.minimize();
      }
    });
  }

  // ---- shortcuts ---------------------------------------------------------

  Future<void> runShortcut(IslandShortcut s) async {
    switch (s.kind) {
      case ShortcutKind.screensaver:
        showMap();
      case ShortcutKind.planner:
        showHome();
      case ShortcutKind.web:
        await _try(() => openWeb(s.target));
      case ShortcutKind.app:
        await _try(() => launchApp(s.target));
    }
  }

  // ---- native callbacks --------------------------------------------------

  /// Minimized: hand idle memory back to Windows after the animation.
  @override
  void onWindowMinimize() {
    _trim?.cancel();
    _trim = Timer(const Duration(seconds: 2), trimMemory);
  }

  @override
  void onWindowRestore() => _trim?.cancel();
}

/// Chrome opens a URL as a new tab in its most recently used window.
Future<void> openWeb(String url) async {
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
  await Process.start('explorer.exe', [u], mode: ProcessStartMode.detached);
}

Future<void> launchApp(String target) async {
  final t = target.trim();
  if (t.isEmpty || !Platform.isWindows) return;
  // Start menu apps ('shell:AppsFolder\<id>'), Store apps included.
  if (t.toLowerCase().startsWith('shell:')) {
    await Process.start('explorer.exe', [t], mode: ProcessStartMode.detached);
    return;
  }
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
