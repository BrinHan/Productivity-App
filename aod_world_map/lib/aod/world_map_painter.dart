import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'aod_palette.dart';
import 'dot_grid.dart';
import 'solar_math.dart';

enum MarkerShape { circle, diamond }

/// A small secondary marker (unused by default).
class CityMarker {
  const CityMarker(this.name, this.location, {this.shape = MarkerShape.circle});
  final String name;
  final GeoPoint location;
  final MarkerShape shape;
}

/// Brightness levels between full night and full day.
const int _levels = 16;

/// Reused across frames so painting never allocates.
class _Scratch {
  static List<Float32List> bins = [];
  static final Int32List counts = Int32List(_levels);

  static void ensure(int dots) {
    if (bins.isEmpty || bins.first.length < dots * 2) {
      bins = List.generate(_levels, (_) => Float32List(dots * 2));
    }
  }
}

class WorldMapPainter extends CustomPainter {
  WorldMapPainter({
    required this.grid,
    required this.solar,
    required this.palette,
    required this.user,
    this.cities = const [],
    this.dotFill = 0.62,
  });

  final DotGrid grid;
  final SolarPosition solar;
  final AodPalette palette;
  final GeoPoint user;
  final List<CityMarker> cities;
  final double dotFill;

  /// Sun-height band for the day/night fade (sin(alt) = 0 is the terminator).
  static const double _nightSin = -0.10;
  static const double _daySin = 0.06;
  static const double _invRange = 1 / (_daySin - _nightSin);

  /// How much the map may stretch vertically to fill the window.
  /// 1.0 = never stretched (letterboxed). Lower = more compressed.
  static const double _maxStretch = 1.25;

  /// Fraction of the window the map occupies, leaving a small margin.
  static const double _mapScale = 0.96;

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width * _mapScale, h = size.height * _mapScale;
    final natural = w / grid.aspectRatio; // undistorted height at this width
    final stretch = h / natural;
    if (stretch > _maxStretch) {
      h = natural * _maxStretch;
    } else if (stretch < 1 / _maxStretch) {
      w = h * _maxStretch * grid.aspectRatio;
    }
    final ox = (size.width - w) / 2, oy = (size.height - h) / 2;
    final pitch = math.min(w / grid.columns, h / grid.rows);

    _paintDots(canvas, ox, oy, w, h, pitch);
    _paintTerminator(canvas, ox, oy, w, h, pitch);

    Offset at(GeoPoint p) => Offset(ox + grid.xOf(p.longitude) * w, oy + grid.yOf(p.latitude) * h);

    final cityPaint = Paint()..color = palette.city;
    for (final c in cities) {
      final o = at(c.location);
      if (c.shape == MarkerShape.circle) {
        canvas.drawCircle(o, pitch * 0.6, cityPaint);
      } else {
        final r = pitch * 0.9;
        canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - r)
            ..lineTo(o.dx + r, o.dy)
            ..lineTo(o.dx, o.dy + r)
            ..lineTo(o.dx - r, o.dy)
            ..close(),
          cityPaint,
        );
      }
    }

    final u = at(user);
    canvas.drawCircle(u, pitch * 2.6, Paint()..color = palette.userHalo.withValues(alpha: 0.22));
    canvas.drawCircle(u, pitch * 1.3, Paint()..color = palette.user);
  }

  void _paintDots(Canvas canvas, double ox, double oy, double w, double h, double pitch) {
    final n = grid.count;
    _Scratch.ensure(n);
    final bins = _Scratch.bins;
    final counts = _Scratch.counts..fillRange(0, _levels, 0);
    final dotX = grid.dotX, dotY = grid.dotY;
    final sLat = grid.sinLat, cLat = grid.cosLat, sLon = grid.sinLon, cLon = grid.cosLon;

    for (var i = 0; i < n; i++) {
      final sinAlt = solar.sinAltitude(sLat[i], cLat[i], sLon[i], cLon[i]);
      var t = (sinAlt - _nightSin) * _invRange;
      t = t < 0 ? 0 : (t > 1 ? 1 : t);
      t = t * t * (3 - 2 * t); // smoothstep
      final lvl = (t * (_levels - 1) + 0.5).toInt();
      final buf = bins[lvl];
      var k = counts[lvl];
      buf[k++] = ox + dotX[i] * w;
      buf[k++] = oy + dotY[i] * h;
      counts[lvl] = k;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = pitch * dotFill
      ..isAntiAlias = true;

    for (var l = 0; l < _levels; l++) {
      final used = counts[l];
      if (used == 0) continue;
      paint.color = Color.lerp(palette.night, palette.day, l / (_levels - 1))!;
      canvas.drawRawPoints(ui.PointMode.points, Float32List.view(bins[l].buffer, 0, used), paint);
    }
  }

  /// Thin terminator line, no glow. Its brightness varies along its length:
  /// dim at both ends and in the middle, brightest a quarter of the way in
  /// from each end. It is clipped to the map's top/bottom and faded near
  /// those edges so it never ends in a hard cut.
  void _paintTerminator(Canvas canvas, double ox, double oy, double w, double h, double pitch) {
    const steps = 720;
    final top = oy, bottom = oy + h;
    final maxPiece = math.max(4.0, pitch); // keeps brightness changes smooth

    // 1) Sample the curve, clip it to the map's height, split into short pieces.
    final segs = <double>[]; // x0, y0, x1, y1 per piece
    var total = 0.0;
    double px = 0, py = 0;
    for (var i = 0; i <= steps; i++) {
      final lon = -math.pi + 2 * math.pi * i / steps;
      final latDeg = solar.terminatorLatitude(lon) * 180 / math.pi;
      final x = ox + w * i / steps;
      final y = oy + grid.yOf(latDeg) * h;
      if (i > 0) {
        var t0 = 0.0, t1 = 1.0;
        final dy = y - py;
        var visible = true;
        if (dy.abs() < 1e-9) {
          visible = py >= top && py <= bottom;
        } else {
          var ta = (top - py) / dy, tb = (bottom - py) / dy;
          if (ta > tb) {
            final s = ta;
            ta = tb;
            tb = s;
          }
          t0 = math.max(0.0, ta);
          t1 = math.min(1.0, tb);
          visible = t0 < t1;
        }
        if (visible) {
          final ax = px + (x - px) * t0, ay = py + dy * t0;
          final bx = px + (x - px) * t1, by = py + dy * t1;
          final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
          final pieces = math.max(1, (len / maxPiece).ceil());
          for (var k = 0; k < pieces; k++) {
            final f0 = k / pieces, f1 = (k + 1) / pieces;
            segs
              ..add(ax + (bx - ax) * f0)
              ..add(ay + (by - ay) * f0)
              ..add(ax + (bx - ax) * f1)
              ..add(ay + (by - ay) * f1);
          }
          total += len;
        }
      }
      px = x;
      py = y;
    }
    if (segs.isEmpty || total <= 0) return;

    // 2) Draw each piece with its own brightness.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = math.max(1.0, pitch * 0.22)
      ..isAntiAlias = true;
    final edgeBand = h * 0.10;
    var acc = 0.0;
    for (var s = 0; s < segs.length; s += 4) {
      final x0 = segs[s], y0 = segs[s + 1], x1 = segs[s + 2], y1 = segs[s + 3];
      final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      final u = (acc + len / 2) / total; // 0..1 along the line
      acc += len;

      final wave = math.sin(2 * math.pi * u);
      final along = 0.10 + 0.90 * wave * wave; // 0.10 at ends & centre, 1.0 at 1/4 and 3/4

      final ym = (y0 + y1) / 2;
      var e = math.min(ym - top, bottom - ym) / edgeBand;
      e = e < 0 ? 0 : (e > 1 ? 1 : e);
      e = e * e * (3 - 2 * e);

      paint.color = palette.terminator.withValues(alpha: 0.65 * along * e);
      canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
    }
  }

  @override
  bool shouldRepaint(WorldMapPainter old) =>
      old.grid != grid ||
      old.palette != palette ||
      old.solar.declination != solar.declination ||
      old.solar.subsolarLongitude != solar.subsolarLongitude ||
      old.user.latitude != user.latitude ||
      old.user.longitude != user.longitude ||
      old.cities != cities ||
      old.dotFill != dotFill;
}
