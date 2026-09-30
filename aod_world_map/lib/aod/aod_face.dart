
import 'package:flutter/material.dart';

import 'aod_palette.dart';
import 'dot_grid.dart';
import 'solar_math.dart';
import 'world_map_painter.dart';

/// Full-bleed watch face: dot map, optional alarm, location label, big clock.
/// Fills whatever space its parent gives it.
class AodWorldMapFace extends StatelessWidget {
  const AodWorldMapFace({
    super.key,
    required this.grid,
    required this.utcTime,
    required this.user,
    required this.locationLabel,
    this.localUtcOffset = Duration.zero,
    this.alarmLabel,
    this.cities = const [],
    this.alwaysOn = false,
  });

  final DotGrid grid;
  final DateTime utcTime;
  final GeoPoint user;
  final String locationLabel;
  final Duration localUtcOffset;
  final String? alarmLabel;
  final List<CityMarker> cities;
  final bool alwaysOn;

  @override
  Widget build(BuildContext context) {
    final palette = AodPalette.resolve(Theme.of(context).brightness, alwaysOn: alwaysOn);
    final solar = SolarPosition.fromUtc(utcTime);
    final safe = MediaQuery.paddingOf(context);

    final local = utcTime.toUtc().add(localUtcOffset);
    final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final clock = '$h12:${local.minute.toString().padLeft(2, '0')}';

    return ColoredBox(
      color: palette.background,
      child: LayoutBuilder(builder: (context, c) {
        // Text scales with the window.
        final clockSize = (c.maxWidth * 0.16).clamp(56.0, 180.0);
        final labelSize = (clockSize * 0.22).clamp(13.0, 30.0);
        final pad = clockSize * 0.25;
        final small = TextStyle(color: palette.text, fontSize: labelSize, fontWeight: FontWeight.w600);

        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: WorldMapPainter(
                  grid: grid,
                  solar: solar,
                  palette: palette,
                  user: user,
                  cities: cities,
                ),
              ),
            ),
            if (alarmLabel != null)
              Positioned(
                top: safe.top + pad,
                left: safe.left + pad,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.alarm, size: labelSize, color: palette.text),
                  const SizedBox(width: 6),
                  Text(alarmLabel!, style: small),
                ]),
              ),
            Positioned(
              left: safe.left + pad,
              bottom: safe.bottom + pad * 0.6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.near_me, size: labelSize, color: palette.text),
                    const SizedBox(width: 6),
                    Text(locationLabel, style: small),
                  ]),
                  Text(
                    clock,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: clockSize,
                      height: 1.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -clockSize * 0.03,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
