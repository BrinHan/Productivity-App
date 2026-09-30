import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'aod/aod_face.dart';
import 'aod/aod_palette.dart';
import 'aod/dot_grid.dart';
import 'aod/liquid_wave_loader.dart';
import 'aod/solar_math.dart';

void main() => runApp(const AodApp());

class AodApp extends StatelessWidget {
  const AodApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AOD World Map',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: const AodScreen(),
      );
}

class AodScreen extends StatefulWidget {
  const AodScreen({super.key});

  @override
  State<AodScreen> createState() => _AodScreenState();
}

class _AodScreenState extends State<AodScreen> {
  final DotGrid _grid = DotGrid.fromPolygons();
  DateTime _now = DateTime.now();
  Timer? _timer;

  late GeoPoint _user = GeoPoint(35, _now.timeZoneOffset.inMinutes / 60 * 15);
  String _label = 'Locating…';
  bool _loading = true;
  bool _precise = false; // true once a real GPS fix has arrived

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => setState(() => _now = DateTime.now()),
    );
    _locate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Two lookups race in parallel:
  ///  - IP lookup: ~city-level, answers in a fraction of a second, no prompt.
  ///  - GPS/browser fix: precise but slow; overrides the IP guess when it lands.
  /// The loader hides as soon as either one answers (or after 4 s).
  void _locate() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
    _ipLookup();
    _preciseLookup();
  }

  Future<void> _ipLookup() async {
    final data = await _geocode();
    if (!mounted || data == null || _precise) return;
    final lat = _num(data['latitude']), lon = _num(data['longitude']);
    setState(() {
      if (lat != null && lon != null) _user = GeoPoint(lat, lon);
      _label = _nameFrom(data) ?? _label;
      _loading = false;
    });
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
      if (!mounted) return;
      _precise = true;
      setState(() {
        _user = GeoPoint(pos.latitude, pos.longitude);
        _loading = false;
      });
      final data = await _geocode(pos.latitude, pos.longitude);
      if (mounted && data != null) setState(() => _label = _nameFrom(data) ?? _label);
    } catch (_) {
      // Keep whatever the IP lookup found.
    }
  }

  /// BigDataCloud free client endpoint. With coordinates it names the place;
  /// without, it locates the caller by IP address.
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

  @override
  Widget build(BuildContext context) {
    final palette = AodPalette.resolve(Theme.of(context).brightness);
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AodWorldMapFace(
            grid: _grid,
            utcTime: _now.toUtc(),
            user: _user,
            locationLabel: _label,
            localUtcOffset: _now.timeZoneOffset,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _loading
                ? ColoredBox(
                    key: const ValueKey('loader'),
                    color: palette.background,
                    child: SizedBox.expand(child: LiquidWaveLoader(palette: palette)),
                  )
                : const SizedBox.shrink(key: ValueKey('done')),
          ),
        ],
      ),
    );
  }
}
