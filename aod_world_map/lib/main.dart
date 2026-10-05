import 'dart:async';
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;

import 'aod/aod_face.dart';
import 'aod/aod_palette.dart';
import 'aod/liquid_wave_loader.dart';
import 'aod/map_model.dart';
import 'aod/settings_menu.dart';
import 'desktop/annotate/overlay_screen.dart';
import 'desktop/annotate/overlay_shell.dart';
import 'desktop/dynamic_island.dart';
import 'desktop/home_page.dart';
import 'desktop/island_shell.dart';
import 'desktop/planner_model.dart';
import 'desktop/window_shell.dart';

/// One exe, three processes: `--island` runs the always-on-top island on its
/// own; `--overlay` is the screen annotation layer the island starts on
/// demand; anything else opens the app window (`--home` for the planner),
/// which starts the island if it is not running yet.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--island')) return _runIsland();
  if (args.contains('--overlay')) {
    return _runOverlay(ask: args.contains('--ask'), standby: args.contains('--standby'));
  }

  // Keep decoded images small (album art is the only real image).
  PaintingBinding.instance.imageCache
    ..maximumSize = 20
    ..maximumSizeBytes = 8 << 20;
  final shell = ShellController(mode: args.contains('--home') ? AppMode.home : AppMode.map);
  if (!await shell.claim()) exit(0); // already open; it was brought forward
  final planner = PlannerModel();
  await planner.load();
  await shell.init(planner);
  final map = MapModel()..start();
  runApp(AodApp(shell: shell, planner: planner, map: map));
  WidgetsBinding.instance.addPostFrameCallback((_) => shell.settleWindow());
}

Future<void> _runIsland() async {
  // The island draws album art and little else.
  PaintingBinding.instance.imageCache
    ..maximumSize = 6
    ..maximumSizeBytes = 2 << 20;
  final planner = PlannerModel();
  final shell = IslandShell(planner);
  if (!await shell.claim()) exit(0); // one island at a time
  // A small pill needs a small GPU cache; the default is sized for a
  // full-screen app.
  unawaited(SystemChannels.skia.invokeMethod<void>('Skia.setResourceCacheMaxBytes', 6 << 20).catchError((_) {}));
  await planner.load();
  await shell.init();
  runApp(IslandApp(shell: shell));
}

Future<void> _runOverlay({required bool ask, required bool standby}) async {
  PaintingBinding.instance.imageCache
    ..maximumSize = 4
    ..maximumSizeBytes = 2 << 20;
  final shell = OverlayShell();
  if (!await shell.claim(ask: ask, standby: standby)) exit(0); // one overlay at a time
  await shell.init(ask: ask, standby: standby);
  runApp(OverlayApp(shell: shell));
}

/// The island process: just the island, on a transparent window.
class IslandApp extends StatelessWidget {
  const IslandApp({super.key, required this.shell});
  final IslandShell shell;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AOD Island',
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true, canvasColor: Colors.transparent),
        home: IslandScreen(island: shell.island, onShortcut: shell.runShortcut),
      );
}

class AodApp extends StatefulWidget {
  const AodApp({super.key, required this.shell, required this.planner, required this.map});
  final ShellController shell;
  final PlannerModel planner;
  final MapModel map;

  @override
  State<AodApp> createState() => _AodAppState();
}

class _AodAppState extends State<AodApp> {
  bool _dark =
      WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  void _setDark(bool v) => setState(() => _dark = v);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AOD World Map',
        debugShowCheckedModeBanner: false,
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: ListenableBuilder(
          listenable: widget.shell,
          builder: (context, _) {
            // Only the active screen exists; the other is disposed. The
            // island is its own process, so it is not drawn here.
            switch (widget.shell.mode) {
              case AppMode.map:
                return AodScreen(
                  shell: widget.shell,
                  map: widget.map,
                  isDark: _dark,
                  onDarkChanged: _setDark,
                );
              case AppMode.home:
                return HomePage(
                  shell: widget.shell,
                  planner: widget.planner,
                  isDark: _dark,
                  onDarkChanged: _setDark,
                );
            }
          },
        ),
      );
}

class AodScreen extends StatefulWidget {
  const AodScreen({
    super.key,
    required this.shell,
    required this.map,
    required this.isDark,
    required this.onDarkChanged,
  });
  final ShellController shell;
  final MapModel map;
  final bool isDark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<AodScreen> createState() => _AodScreenState();
}

class _AodScreenState extends State<AodScreen> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AodPalette.resolve(Theme.of(context).brightness);
    final m = widget.map;
    return Scaffold(
      backgroundColor: palette.background,
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            AodWorldMapFace(
              grid: m.grid,
              utcTime: _now.toUtc(),
              user: m.user,
              locationLabel: m.label,
              localUtcOffset: _now.timeZoneOffset,
            ),
            // Clicking anywhere outside the settings panel closes it.
            if (_settingsOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _settingsOpen = false),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SettingsMenu(
                    palette: palette,
                    isDark: widget.isDark,
                    onDarkChanged: widget.onDarkChanged,
                    island: widget.shell.island,
                    onExit: widget.shell.showHome,
                    onMinimize: widget.shell.quit, // the island keeps running
                    onQuit: widget.shell.quitAll,
                    onShortcut: widget.shell.runShortcut,
                    open: _settingsOpen,
                    onOpenChanged: (v) => setState(() => _settingsOpen = v),
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: m.loading
                  ? ColoredBox(
                      key: const ValueKey('loader'),
                      color: palette.background,
                      child: SizedBox.expand(child: LiquidWaveLoader(palette: palette)),
                    )
                  : const SizedBox.shrink(key: ValueKey('done')),
            ),
          ],
        ),
      ),
    );
  }
}
