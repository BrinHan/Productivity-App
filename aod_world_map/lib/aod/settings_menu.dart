import 'package:flutter/material.dart';

import '../desktop/dynamic_island.dart';
import '../desktop/island_controller.dart';
import '../desktop/island_widgets.dart';
import 'aod_palette.dart';
import 'sky_toggle.dart';

/// Gear button + panel. Open state is owned by the screen so it can close
/// the panel when you click anywhere outside it.
class SettingsMenu extends StatelessWidget {
  const SettingsMenu({
    super.key,
    required this.palette,
    required this.isDark,
    required this.onDarkChanged,
    required this.island,
    required this.onExit,
    required this.onMinimize,
    required this.onQuit,
    required this.onShortcut,
    required this.open,
    required this.onOpenChanged,
  });

  final AodPalette palette;
  final bool isDark;
  final ValueChanged<bool> onDarkChanged;
  final IslandController island;
  final VoidCallback onExit, onMinimize, onQuit;
  final void Function(IslandShortcut) onShortcut;
  final bool open;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Material(
          color: p.text.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Settings',
            icon: Icon(open ? Icons.close : Icons.settings, color: p.text),
            onPressed: () => onOpenChanged(!open),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topRight,
          child: open
              ? Padding(padding: const EdgeInsets.only(top: 8), child: _panel(context, p))
              : const SizedBox(width: 0, height: 0),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, AodPalette p) {
    final label = TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w600);
    final small = TextStyle(color: p.text.withValues(alpha: 0.7), fontSize: 12);

    return Container(
      width: 380,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 110),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.background.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.text.withValues(alpha: 0.25)),
      ),
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: island,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Theme', style: label),
                const Spacer(),
                SkyToggle(isNight: isDark, onChanged: onDarkChanged, em: 12),
              ]),
              const SizedBox(height: 18),
              Text('Dynamic island', style: label),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip(p, 'Idle', IslandState.idle),
                _chip(p, 'Open', IslandState.open),
                _chip(p, 'Chrome notch', IslandState.notch),
                _chip(p, 'Incoming call', IslandState.call),
                _chip(p, 'Music', IslandState.music),
                _chip(p, 'Face ID', IslandState.success),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MouseRegion(
                  onHover: (e) => island.gaze.value = Offset(
                    ((e.localPosition.dx - 174) / 174).clamp(-1.0, 1.0).toDouble(),
                    ((e.localPosition.dy - 30) / 60).clamp(-1.0, 1.0).toDouble(),
                  ),
                  onExit: (_) => island.gaze.value = Offset.zero,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    color: p.text.withValues(alpha: 0.10),
                    width: double.infinity,
                    height: island.state == IslandState.open ? 250 : 96,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: 0,
                        maxWidth: 560,
                        minHeight: 0,
                        maxHeight: 380,
                        child: Transform.scale(
                          scale: 0.62,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: 560,
                            height: 380,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: DynamicIsland(
                                controller: island,
                                showWhenHidden: true,
                                onShortcut: onShortcut,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Text('Open island on', style: label),
                const Spacer(),
                _seg(p, 'Click', !island.openOnHover, () => island.setOpenOnHover(false)),
                const SizedBox(width: 6),
                _seg(p, 'Hover', island.openOnHover, () => island.setOpenOnHover(true)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text('Quiet notch in Chrome', style: label),
                const Spacer(),
                _seg(p, 'On', island.quietInChrome, () => island.setQuietInChrome(true)),
                const SizedBox(width: 6),
                _seg(p, 'Off', !island.quietInChrome, () => island.setQuietInChrome(false)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Text('Idle size', style: label),
                const Spacer(),
                Text('${island.idleWidth.round()} px', style: small),
              ]),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: p.text,
                  inactiveTrackColor: p.text.withValues(alpha: 0.25),
                  thumbColor: p.text,
                  overlayColor: p.text.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: island.idleWidth,
                  min: 180,
                  max: 360,
                  onChanged: island.setIdleWidth,
                ),
              ),
              Text('Character color', style: label),
              const SizedBox(height: 8),
              Wrap(spacing: 10, children: [
                for (final c in kPipColors) _swatch(p, c),
              ]),
              const SizedBox(height: 4),
              Text('Shortcuts and the stock ticker are edited in the island (gear tab).',
                  style: small),
              const SizedBox(height: 14),
              Divider(color: p.text.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              _action(p, Icons.home_outlined, 'Exit to home page', onExit, filled: true),
              const SizedBox(height: 8),
              _action(p, Icons.picture_in_picture_alt_outlined, 'Minimize to island', onMinimize),
              const SizedBox(height: 8),
              _action(p, Icons.power_settings_new, 'Quit', onQuit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seg(AodPalette p, String text, bool on, VoidCallback onTap) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? p.text : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.text.withValues(alpha: 0.4)),
            ),
            child: Text(text,
                style: TextStyle(
                  color: on ? p.background : p.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      );

  Widget _swatch(AodPalette p, Color c) {
    final selected = island.pipColor.toARGB32() == c.toARGB32();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => island.setPipColor(c),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? p.text : p.text.withValues(alpha: 0.25),
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(AodPalette p, String text, IslandState s) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => island.preview(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.text.withValues(alpha: 0.4)),
            ),
            child: Text(text,
                style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _action(AodPalette p, IconData icon, String text, VoidCallback onTap,
          {bool filled = false}) =>
      Material(
        color: filled ? p.text.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.text.withValues(alpha: 0.25)),
                  ),
            child: Row(children: [
              Icon(icon, size: 18, color: p.text),
              const SizedBox(width: 10),
              Text(text,
                  style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
