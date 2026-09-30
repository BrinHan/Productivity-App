// Turns the vector continent outlines into a uniform grid of land dots.
// Runs once at startup; afterwards the painter only touches flat typed arrays.
import 'dart:math' as math;
import 'dart:typed_data';

import 'land_polygons.dart';

class _Poly {
  _Poly(this.pts) {
    var x0 = double.infinity, x1 = -double.infinity;
    var y0 = double.infinity, y1 = -double.infinity;
    for (var i = 0; i < pts.length; i += 2) {
      x0 = math.min(x0, pts[i]);
      x1 = math.max(x1, pts[i]);
      y0 = math.min(y0, pts[i + 1]);
      y1 = math.max(y1, pts[i + 1]);
    }
    minX = x0;
    maxX = x1;
    minY = y0;
    maxY = y1;
  }

  final List<double> pts; // flat: lon, lat, lon, lat, ...
  late final double minX, maxX, minY, maxY;

  /// Even-odd ray casting with a bounding-box early-out.
  bool contains(double x, double y) {
    if (x < minX || x > maxX || y < minY || y > maxY) return false;
    var inside = false;
    final n = pts.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = pts[2 * i], yi = pts[2 * i + 1];
      final xj = pts[2 * j], yj = pts[2 * j + 1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// Equirectangular grid of land dots. Only land cells are stored, together
/// with the trig of their coordinates, so day/night tests need no trig.
class DotGrid {
  DotGrid._({
    required this.columns,
    required this.rows,
    required this.cellDegrees,
    required this.latTop,
    required this.dotX,
    required this.dotY,
    required this.sinLat,
    required this.cosLat,
    required this.sinLon,
    required this.cosLon,
  });

  /// [columns] sets the resolution: 96 columns = 3.75° per dot.
  factory DotGrid.fromPolygons({
    int columns = 96,
    double latTop = 84,
    double latBottom = -60,
    List<List<double>> land = const [...kLandPolygons],
    List<List<double>> water = kWaterPolygons,
  }) {
    final cell = 360.0 / columns;
    final rows = ((latTop - latBottom) / cell).round();
    final landPolys = land.map(_Poly.new).toList(growable: false);
    final waterPolys = water.map(_Poly.new).toList(growable: false);

    final xs = <double>[], ys = <double>[];
    final sLat = <double>[], cLat = <double>[], sLon = <double>[], cLon = <double>[];

    for (var r = 0; r < rows; r++) {
      final lat = latTop - (r + 0.5) * cell;
      for (var c = 0; c < columns; c++) {
        final lon = -180.0 + (c + 0.5) * cell;
        if (!landPolys.any((p) => p.contains(lon, lat))) continue;
        if (waterPolys.any((p) => p.contains(lon, lat))) continue;
        final la = lat * math.pi / 180, lo = lon * math.pi / 180;
        xs.add((c + 0.5) / columns);
        ys.add((r + 0.5) / rows);
        sLat.add(math.sin(la));
        cLat.add(math.cos(la));
        sLon.add(math.sin(lo));
        cLon.add(math.cos(lo));
      }
    }
    return DotGrid._(
      columns: columns,
      rows: rows,
      cellDegrees: cell,
      latTop: latTop,
      dotX: Float32List.fromList(xs),
      dotY: Float32List.fromList(ys),
      sinLat: Float64List.fromList(sLat),
      cosLat: Float64List.fromList(cLat),
      sinLon: Float64List.fromList(sLon),
      cosLon: Float64List.fromList(cLon),
    );
  }

  final int columns, rows;
  final double cellDegrees, latTop;

  /// Dot centres normalised to 0..1 inside the map rectangle.
  final Float32List dotX, dotY;
  final Float64List sinLat, cosLat, sinLon, cosLon;

  int get count => dotX.length;

  /// width / height of the map (cells are square in degrees).
  double get aspectRatio => columns / rows;

  double get latSpan => rows * cellDegrees;

  /// Normalised (0..1) map coordinates for a lat/lon in degrees.
  double xOf(double lonDeg) => (lonDeg + 180.0) / 360.0;
  double yOf(double latDeg) => (latTop - latDeg) / latSpan;
}