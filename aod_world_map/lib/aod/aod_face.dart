import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'aod_palette.dart';
import 'cursor_field.dart';
import 'dot_grid.dart';
import 'solar_math.dart';
import 'world_map_painter.dart';

/// Full-bleed watch face: dot map, optional alarm, location label, big clock.
/// Hides the system cursor over the map and draws a circle that pushes the
/// dots away.
class AodWorldMapFace extends StatefulWidget {
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
  State<AodWorldMapFace> createState() => _AodWorldMapFaceState();
}

class _AodWorldMapFaceState extends State<AodWorldMapFace> with SingleTickerProviderStateMixin {
  final CursorField _cursor = CursorField();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _cursor.dispose();
    super.dispose();
  }

  // The ticker only runs while the cursor is moving or fading.
  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;
    if (!_cursor.step(dt)) _ticker.stop();
  }

  void _move(Offset p) {
    _cursor.move(p);
    _wake();
  }

  void _leave() {
    _cursor.leave();
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AodPalette.resolve(Theme.of(context).brightness, alwaysOn: widget.alwaysOn);
    final solar = SolarPosition.fromUtc(widget.utcTime);
    final safe = MediaQuery.paddingOf(context);

    final local = widget.utcTime.toUtc().add(widget.localUtcOffset);
    final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final clock = '$h12:${local.minute.toString().padLeft(2, '0')}';

    return MouseRegion(
      cursor: SystemMouseCursors.none,
      onHover: (e) => _move(e.localPosition),
      onExit: (_) => _leave(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _move(e.localPosition),
        onPointerMove: (e) => _move(e.localPosition),
        onPointerUp: (e) {
          if (e.kind == PointerDeviceKind.touch) _leave();
        },
        onPointerCancel: (_) => _leave(),
        child: ColoredBox(
          color: palette.background,
          child: LayoutBuilder(builder: (context, c) {
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
                      grid: widget.grid,
                      solar: solar,
                      palette: palette,
                      user: widget.user,
                      cities: widget.cities,
                      cursor: _cursor,
                    ),
                  ),
                ),
                if (widget.alarmLabel != null)
                  Positioned(
                    top: safe.top + pad,
                    left: safe.left + pad,
                    child: IgnorePointer(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.alarm, size: labelSize, color: palette.text),
                        const SizedBox(width: 6),
                        Text(widget.alarmLabel!, style: small),
                      ]),
                    ),
                  ),
                Positioned(
                  left: safe.left + pad,
                  bottom: safe.bottom + pad * 0.6,
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.near_me, size: labelSize, color: palette.text),
                          const SizedBox(width: 6),
                          Text(widget.locationLabel, style: small),
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
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
