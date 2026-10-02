import 'dart:async';

import 'package:flutter/material.dart';

import 'aod/aod_face.dart';
import 'aod/aod_palette.dart';
import 'aod/liquid_wave_loader.dart';
import 'aod/map_model.dart';
import 'aod/settings_menu.dart';
import 'desktop/dynamic_island.dart';
import 'desktop/home_page.dart';
import 'desktop/planner_model.dart';
import 'desktop/app_mode.dart';
import 'desktop/window_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = ShellController();
  final planner = PlannerModel();
  final map = MapModel();
  await Future.wait([shell.init(), planner.load()]);
  map.start();
  runApp(AodApp(shell: shell, planner: planner, map: map));
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
            // Only the active screen exists. The other two are disposed, so
            // island mode holds none of the map or planner UI in memory.
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
              case AppMode.island:
                return IslandScreen(
                  island: widget.shell.island,
                  onShortcut: widget.shell.runShortcut,
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
                    onMinimize: () => widget.shell.enterIsland(),
                    onQuit: () => widget.shell.quit(),
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
