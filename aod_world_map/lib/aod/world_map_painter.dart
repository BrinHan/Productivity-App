import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'aod_palette.dart';
import 'cursor_field.dart';
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

  /// Each dot's brightness level for one sun position. The cursor repaints
  /// every frame but the sun moves once a minute, so this is reused until
  /// the grid or the sun changes.
  static Uint8List levels = Uint8List(0);
  static DotGrid? _grid;
  static double _decl = double.nan, _lon = double.nan;

  static bool fresh(DotGrid g, SolarPosition s) =>
      identical(g, _grid) && s.declination == _decl && s.subsolarLongitude == _lon;

  static void keep(DotGrid g, SolarPosition s) {
    _grid = g;
    _decl = s.declination;
    _lon = s.subsolarLongitude;
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
    this.cursor,
  }) : super(repaint: cursor); // repaints on every cursor tick, no widget rebuild

  final DotGrid grid;
  final SolarPosition solar;
  final AodPalette palette;
  final GeoPoint user;
  final List<CityMarker> cities;
  final double dotFill;
  final CursorField? cursor;

  /// Sun-height band for the day/night fade (sin(alt) = 0 is the terminator).
  static const double _nightSin = -0.10;
  static const double _daySin = 0.06;
  static const double _invRange = 1 / (_daySin - _nightSin);

  static const double _maxStretch = 1;
  static const double _mapScale = 0.8;

  /// Cursor repel: radius in grid pitches, and how far the centre dots are
  /// shoved (fraction of the radius). Keep pushFactor <= 0.5.
  static const double _radiusPitches = 5;
  static const double _pushFactor = 0.2;

  double _radius(double pitch) => (pitch * _radiusPitches).clamp(56.0, 140.0).toDouble();

  Offset _displace(Offset p, double pitch) {
    final cur = cursor;
    if (cur == null || cur.strength < 0.001) return p;
    final r = _radius(pitch);
    final dx = p.dx - cur.pos.dx, dy = p.dy - cur.pos.dy;
    final d2 = dx * dx + dy * dy;
    if (d2 >= r * r) return p;
    final d = math.sqrt(d2) + 0.001;
    final f = 1 - d / r;
    final push = f * f * r * _pushFactor * cur.strength;
    return Offset(p.dx + dx / d * push, p.dy + dy / d * push);
  }

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width * _mapScale, h = size.height * _mapScale;
    final natural = w / grid.aspectRatio;
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

    Offset at(GeoPoint p) =>
        _displace(Offset(ox + grid.xOf(p.longitude) * w, oy + grid.yOf(p.latitude) * h), pitch);

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
    canvas.drawCircle(u, pitch * 1.7, Paint()..color = palette.userHalo.withValues(alpha: 0.22));
    canvas.drawCircle(u, pitch * 1, Paint()..color = palette.user);

    _paintCursor(canvas);
  }

  void _paintDots(Canvas canvas, double ox, double oy, double w, double h, double pitch) {
    final n = grid.count;
    _Scratch.ensure(n);
    final bins = _Scratch.bins;
    final counts = _Scratch.counts..fillRange(0, _levels, 0);
    final dotX = grid.dotX, dotY = grid.dotY;
    final sLat = grid.sinLat, cLat = grid.cosLat, sLon = grid.sinLon, cLon = grid.cosLon;

    final cur = cursor;
    final strength = cur?.strength ?? 0.0;
    final pushing = strength > 0.001;
    final cx = cur?.pos.dx ?? 0.0, cy = cur?.pos.dy ?? 0.0;
    final r = _radius(pitch), r2 = r * r;
    final kPush = r * _pushFactor * strength;

    if (!_Scratch.fresh(grid, solar) || _Scratch.levels.length != n) {
      final levels = _Scratch.levels.length == n ? _Scratch.levels : Uint8List(n);
      for (var i = 0; i < n; i++) {
        final sinAlt = solar.sinAltitude(sLat[i], cLat[i], sLon[i], cLon[i]);
        var t = (sinAlt - _nightSin) * _invRange;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        t = t * t * (3 - 2 * t); // smoothstep
        levels[i] = (t * (_levels - 1) + 0.5).toInt();
      }
      _Scratch.levels = levels;
      _Scratch.keep(grid, solar);
    }
    final levels = _Scratch.levels;

    for (var i = 0; i < n; i++) {
      final lvl = levels[i];

      var x = ox + dotX[i] * w, y = oy + dotY[i] * h;
      if (pushing) {
        final dx = x - cx, dy = y - cy;
        final d2 = dx * dx + dy * dy;
        if (d2 < r2) {
          final d = math.sqrt(d2) + 0.001;
          final f = 1 - d / r;
          final push = f * f * kPush;
          x += dx / d * push;
          y += dy / d * push;
        }
      }

      final buf = bins[lvl];
      var k = counts[lvl];
      buf[k++] = x;
      buf[k++] = y;
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

  /// The circle cursor: a ring with a centre dot, fading in/out.
  void _paintCursor(Canvas canvas) {
    final cur = cursor;
    if (cur == null || cur.strength < 0.01) return;
    final a = 0.9 * cur.strength;
    canvas.drawCircle(
      cur.target,
      12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = true
        ..color = palette.text.withValues(alpha: a),
    );
    canvas.drawCircle(cur.target, 2, Paint()..color = palette.text.withValues(alpha: a));
  }

  /// Thin terminator line, no glow. Brightness varies along its length:
  /// dim at both ends and in the middle, brightest a quarter of the way in
  /// from each end. Clipped to the map's top/bottom and faded near those edges.
  void _paintTerminator(Canvas canvas, double ox, double oy, double w, double h, double pitch) {
    const steps = 720;
    final top = oy, bottom = oy + h;
    final maxPiece = math.max(4.0, pitch);

    final segs = <double>[];
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
      final u = (acc + len / 2) / total;
      acc += len;

      final wave = math.sin(2 * math.pi * u);
      final along = 0.10 + 0.90 * wave * wave;

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
      old.cursor != cursor ||
      old.solar.declination != solar.declination ||
      old.solar.subsolarLongitude != solar.subsolarLongitude ||
      old.user.latitude != user.latitude ||
      old.user.longitude != user.longitude ||
      old.cities != cities ||
      old.dotFill != dotFill;
}
