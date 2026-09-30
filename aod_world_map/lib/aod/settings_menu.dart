import 'package:flutter/material.dart';

import 'aod_palette.dart';
import 'sky_toggle.dart';

/// Gear button that opens a small panel containing the theme toggle.
class SettingsMenu extends StatefulWidget {
  const SettingsMenu({
    super.key,
    required this.palette,
    required this.isDark,
    required this.onDarkChanged,
  });

  final AodPalette palette;
  final bool isDark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Material(
          color: p.text.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Settings',
            icon: Icon(_open ? Icons.close : Icons.settings, color: p.text),
            onPressed: () => setState(() => _open = !_open),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topRight,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: p.background.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.text.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Theme',
                          style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 16),
                        SkyToggle(isNight: widget.isDark, onChanged: widget.onDarkChanged, em: 12),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: 0, height: 0),
        ),
      ],
    );
  }
}
