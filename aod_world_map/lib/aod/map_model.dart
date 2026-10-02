import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'dot_grid.dart';
import 'solar_math.dart';

class MapModel extends ChangeNotifier {
  final DotGrid grid = DotGrid.fromPolygons();
  GeoPoint user = GeoPoint(35, DateTime.now().timeZoneOffset.inMinutes / 60 * 15);
  String label = 'Locating…';
  bool loading = true;
  bool _precise = false, _started = false;

  void start() {
    if (_started) return;
    _started = true;
    Future.delayed(const Duration(seconds: 4), () {
      if (loading) {
        loading = false;
        notifyListeners();
      }
    });
    _ipLookup();
    _preciseLookup();
  }

  Future<void> _ipLookup() async {
    final data = await _geocode();
    if (data == null || _precise) return;
    final lat = _num(data['latitude']), lon = _num(data['longitude']);
    if (lat != null && lon != null) user = GeoPoint(lat, lon);
    label = _nameFrom(data) ?? label;
    loading = false;
    notifyListeners();
  }

  Future<void> _preciseLookup() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _precise = true;
      user = GeoPoint(pos.latitude, pos.longitude);
      loading = false;
      notifyListeners();
      final data = await _geocode(pos.latitude, pos.longitude);
      if (data != null) {
        label = _nameFrom(data) ?? label;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _geocode([double? lat, double? lon]) async {
    try {
      final uri = Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
        if (lat != null && lon != null) ...{
          'latitude': lat.toStringAsFixed(2),
          'longitude': lon.toStringAsFixed(2),
        },
        'localityLanguage': 'en',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : null;

  static String? _nameFrom(Map<String, dynamic> json) {
    for (final key in ['city', 'locality', 'principalSubdivision', 'countryName']) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
