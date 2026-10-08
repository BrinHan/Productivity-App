import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'log.dart';

import 'package:http/http.dart' as http;

// ------------------------------------------------------------------- timer

/// One countdown timer, like the iPhone's. It lives in the island process
/// and rings there; while it runs the resting pill shows it.
class TimerModel extends ChangeNotifier {
  /// The length picked on the dial, kept between runs.
  Duration pick = const Duration(minutes: 15);

  /// The running timer's full length; null when no timer is set.
  Duration? total;
  DateTime? _ends; // null while paused
  Duration _left = Duration.zero;
  Timer? _tick;

  /// The timer reached zero (it has already been cleared).
  void Function()? onDone;

  bool get running => total != null;
  bool get paused => running && _ends == null;

  Duration get remaining {
    final e = _ends;
    if (e == null) return _left;
    final d = e.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void setPick(Duration d) {
    if (d == pick) return;
    pick = d;
    notifyListeners();
  }

  void start() {
    if (pick <= Duration.zero) return;
    total = pick;
    _ends = DateTime.now().add(pick);
    _ticking(true);
    notifyListeners();
  }

  void togglePause() {
    if (!running) return;
    if (paused) {
      _ends = DateTime.now().add(_left);
    } else {
      _left = remaining;
      _ends = null;
    }
    _ticking(!paused);
    notifyListeners();
  }

  void cancel() {
    total = null;
    _ends = null;
    _ticking(false);
    notifyListeners();
  }

  void _ticking(bool on) {
    _tick?.cancel();
    _tick = on
        ? Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (remaining > Duration.zero) return notifyListeners();
            cancel();
            onDone?.call();
          })
        : null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

// ------------------------------------------------------------------ weather

class Weather {
  const Weather({
    required this.place,
    required this.temp,
    required this.feels,
    required this.code,
    required this.day,
    required this.hi,
    required this.lo,
    required this.sunrise,
    required this.sunset,
    required this.at,
  });
  final String place;
  final double temp, feels, hi, lo; // Celsius
  final int code; // WMO weather code
  final bool day;
  final DateTime? sunrise, sunset;
  final DateTime at;
}

/// What a WMO weather code means, in a word or two.
String weatherLabel(int code) => switch (code) {
      0 => 'Clear',
      1 => 'Mostly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Fog',
      51 || 53 || 55 || 56 || 57 => 'Drizzle',
      61 || 63 || 66 => 'Rain',
      65 || 67 => 'Heavy rain',
      71 || 73 || 75 || 77 => 'Snow',
      80 || 81 || 82 => 'Showers',
      85 || 86 => 'Snow showers',
      95 || 96 || 99 => 'Thunderstorm',
      _ => '—',
    };

IconData weatherIcon(int code, {bool day = true}) {
  if (code == 0 || code == 1) return day ? Icons.wb_sunny_rounded : Icons.nightlight_round;
  if (code == 2) return day ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined;
  if (code == 3 || code == 45 || code == 48) return Icons.cloud_rounded;
  if (code >= 71 && code <= 77 || code == 85 || code == 86) return Icons.ac_unit_rounded;
  if (code >= 95) return Icons.thunderstorm_rounded;
  return Icons.water_drop_rounded;
}

/// What the sky is doing, as far as Pip's outfit cares.
enum PipSky { none, clear, cloudy, rain, snow, storm }

/// How Pip dresses for the weather and the hour: sunglasses in the sun, an
/// umbrella in the rain, a scarf in the cold, a nightcap after dark.
class PipLook {
  const PipLook({this.sky = PipSky.none, this.night = false, this.cold = false, this.hot = false});
  final PipSky sky;
  final bool night, cold, hot;

  @override
  bool operator ==(Object other) =>
      other is PipLook && other.sky == sky && other.night == night && other.cold == cold && other.hot == hot;

  @override
  int get hashCode => Object.hash(sky, night, cold, hot);
}

PipSky skyOf(int code) {
  if (code <= 1) return PipSky.clear;
  if (code <= 48) return PipSky.cloudy;
  if (code >= 95) return PipSky.storm;
  if (code >= 71 && code <= 77 || code == 85 || code == 86) return PipSky.snow;
  return PipSky.rain;
}

/// Pip's look for weather [w] at [now]. Night runs from sunset to sunrise
/// when the weather knows them, else 9 PM to 6 AM.
PipLook lookFor(Weather? w, DateTime now) {
  final rise = w?.sunrise, set = w?.sunset;
  final night = rise != null && set != null && rise.day == now.day
      ? now.isBefore(rise) || now.isAfter(set)
      : now.hour >= 21 || now.hour < 6;
  if (w == null) return PipLook(night: night);
  return PipLook(sky: skyOf(w.code), night: night, cold: w.feels <= 5, hot: w.feels >= 30);
}

/// Today's weather where you are, from Open-Meteo (no key needed). The
/// place comes from Windows location when it is allowed, else from the IP.
class WeatherService extends ChangeNotifier {
  Weather? now;
  bool loading = false;
  String? error;

  Future<void> refresh({bool force = false}) async {
    final w = now;
    if (loading || (!force && w != null && DateTime.now().difference(w.at) < const Duration(minutes: 30))) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final where = await _where();
      if (where == null) throw 'Could not tell where you are.';
      final (lat, lon, place) = where;
      final res = await http
          .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': lat.toStringAsFixed(3),
            'longitude': lon.toStringAsFixed(3),
            'current': 'temperature_2m,apparent_temperature,weather_code,is_day',
            'daily': 'temperature_2m_max,temperature_2m_min,sunrise,sunset',
            'timezone': 'auto',
            'forecast_days': '1',
          }))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw 'The weather service did not answer.';
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final c = j['current'] as Map<String, dynamic>;
      final d = j['daily'] as Map<String, dynamic>;
      double first(String k) => ((d[k] as List).first as num).toDouble();
      DateTime? time(String k) => DateTime.tryParse('${(d[k] as List).first}');
      now = Weather(
        place: place,
        temp: (c['temperature_2m'] as num).toDouble(),
        feels: (c['apparent_temperature'] as num).toDouble(),
        code: (c['weather_code'] as num).toInt(),
        day: c['is_day'] == 1,
        hi: first('temperature_2m_max'),
        lo: first('temperature_2m_min'),
        sunrise: time('sunrise'),
        sunset: time('sunset'),
        at: DateTime.now(),
      );
    } catch (e) {
      error = e is String ? e : 'Could not load the weather. Check your connection.';
    }
    loading = false;
    notifyListeners();
  }

  Future<(double, double, String)?> _where() async {
    double? lat, lon;
    try {
      // Only if already allowed: the island never pops a permission prompt.
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
        );
        lat = p.latitude;
        lon = p.longitude;
      }
    } catch (e, st) {
      logError(e, st);
    }
    try {
      // With no coordinates this looks the place up from the IP address.
      final res = await http
          .get(Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
            if (lat != null && lon != null) ...{'latitude': '$lat', 'longitude': '$lon'},
            'localityLanguage': 'en',
          }))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final place = [j['city'], j['locality'], j['principalSubdivision']]
            .whereType<String>()
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        lat ??= (j['latitude'] as num?)?.toDouble();
        lon ??= (j['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) return (lat, lon, place);
      }
    } catch (e, st) {
      logError(e, st);
    }
    return lat != null && lon != null ? (lat, lon, '') : null;
  }
}

// ---------------------------------------------------------------- clipboard

/// The last [kMax] bits of text you copied, newest first. Kept in memory
/// only, never written to disk, and copies a password manager marks as
/// private are skipped.
class ClipboardHistory extends ChangeNotifier {
  static const kMax = 20;
  final List<String> items = [];
  Timer? _poll;
  int _seq = -1;
  int Function()? _sequence;
  int Function(int)? _available;
  final List<int> _privateFormats = [];

  void start() {
    if (_poll != null || !Platform.isWindows) return;
    try {
      final u = DynamicLibrary.open('user32.dll');
      _sequence = u.lookupFunction<Uint32 Function(), int Function()>('GetClipboardSequenceNumber');
      _available = u.lookupFunction<Int32 Function(Uint32), int Function(int)>('IsClipboardFormatAvailable');
      final register = u.lookupFunction<Uint32 Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>(
          'RegisterClipboardFormatW');
      for (final name in ['ExcludeClipboardContentFromMonitorProcessing', 'Clipboard Viewer Ignore']) {
        final p = name.toNativeUtf16();
        _privateFormats.add(register(p));
        calloc.free(p);
      }
      _seq = _sequence!();
    } catch (_) {
      return;
    }
    _poll = Timer.periodic(const Duration(milliseconds: 800), (_) => _check());
  }

  Future<void> _check() async {
    final seq = _sequence!();
    if (seq == _seq) return;
    _seq = seq;
    if (_privateFormats.any((f) => f != 0 && _available!(f) != 0)) return;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text == null || text.trim().isEmpty) return;
      items.remove(text);
      items.insert(0, text.length > 20000 ? text.substring(0, 20000) : text);
      if (items.length > kMax) items.removeRange(kMax, items.length);
      notifyListeners();
    } catch (e, st) {
      logError(e, st);
    }
  }

  /// Puts [text] back on the clipboard; it moves to the top.
  Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));

  void remove(String text) {
    items.remove(text);
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
