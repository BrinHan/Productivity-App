// Small astronomy helpers with no Flutter dependencies.
import 'dart:math' as math;

/// A location in degrees.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude; // -90..90
  final double longitude; // -180..180
}

/// The sun's position at one moment.
class SolarPosition {
  SolarPosition._(this.declination, this.subsolarLongitude)
      : sinDec = math.sin(declination),
        cosDec = math.cos(declination),
        sinSubLon = math.sin(subsolarLongitude),
        cosSubLon = math.cos(subsolarLongitude);

  /// Sun declination in radians.
  final double declination;

  /// Subsolar longitude in radians.
  final double subsolarLongitude;

  final double sinDec, cosDec, sinSubLon, cosSubLon;

  /// Creates the sun position for a specific UTC time.
  factory SolarPosition.fromUtc(DateTime time) {
    final utc = time.toUtc();
    final start = DateTime.utc(utc.year);
    final leap = (utc.year % 4 == 0 && utc.year % 100 != 0) || utc.year % 400 == 0;
    final daysInYear = leap ? 366 : 365;

    // Days since the start of the year in UTC.
    final t = utc.difference(start).inMicroseconds / Duration.microsecondsPerDay;
    final utcHours = (t - t.floorToDouble()) * 24.0;

    // Year angle in radians.
    final g = 2 * math.pi / daysInYear * (t - 0.5);

    final decl = 0.006918 -
        0.399912 * math.cos(g) +
        0.070257 * math.sin(g) -
        0.006758 * math.cos(2 * g) +
        0.000907 * math.sin(2 * g) -
        0.002697 * math.cos(3 * g) +
        0.00148 * math.sin(3 * g);

    // Small correction to match clock time with solar time.
    final eot = 229.18 *
        (0.000075 +
            0.001868 * math.cos(g) -
            0.032077 * math.sin(g) -
            0.014615 * math.cos(2 * g) -
            0.040849 * math.sin(2 * g));

    // The sun moves westward by about 15° per hour.
    final lonDeg = -15.0 * (utcHours - 12.0 + eot / 60.0);
    final wrapped = ((lonDeg + 540.0) % 360.0) - 180.0;
    return SolarPosition._(decl, wrapped * math.pi / 180.0);
  }

  /// Solar altitude at a point using cached trig values.
  /// Positive means daylight, negative means night.
  double sinAltitude(double sinLat, double cosLat, double sinLon, double cosLon) =>
      sinLat * sinDec + cosLat * cosDec * (cosLon * cosSubLon + sinLon * sinSubLon);

  bool isDaylight(GeoPoint p) {
    final lat = p.latitude * math.pi / 180.0;
    final lon = p.longitude * math.pi / 180.0;
    return sinAltitude(math.sin(lat), math.cos(lat), math.sin(lon), math.cos(lon)) > 0;
  }

  /// Latitude of the terminator at a given longitude.
  double terminatorLatitude(double lonRad) {
    var tanDec = math.tan(declination);
    if (tanDec.abs() < 1e-6) tanDec = tanDec.isNegative ? -1e-6 : 1e-6; // equinox
    return math.atan(-math.cos(lonRad - subsolarLongitude) / tanDec);
  }
}
