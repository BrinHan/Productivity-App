import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_files.dart';
import 'log.dart';

/// This build's version. Kept equal to `version:` in pubspec.yaml by
/// test/updates_test.dart, so bump both together.
const kAppVersion = '1.2.0';

/// Where releases are published.
const kReleasesRepo = 'BrinHan/Productivity-App';

class Release {
  const Release(this.version, this.page, [this.installer]);
  final String version;

  /// The release's GitHub page, with its notes.
  final String page;

  /// The installer download, when the release has one attached.
  final String? installer;

  Map<String, dynamic> toJson() => {'version': version, 'page': page, 'installer': installer};

  static Release? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = j['version'], p = j['page'];
    if (v is! String || p is! String) return null;
    return Release(v, p, j['installer'] as String?);
  }
}

/// Whether version [a] is later than [b]. Versions are dotted numbers, an
/// optional leading v, and anything after `-` or `+` is ignored.
bool isNewerVersion(String a, String b) {
  List<int> parts(String v) {
    final core = v.trim().replaceFirst(RegExp('^[vV]'), '').split(RegExp('[-+]')).first;
    return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p > q;
  }
  return false;
}

/// Asks GitHub for the latest release, at most once a day across all of
/// Meridian's processes (the answer is kept in update.json). The island
/// shows a line when there is a newer one; Settings > About checks on demand.
class UpdateCheck {
  UpdateCheck._();

  static const every = Duration(hours: 20);

  static File get _file => appDataFile('update.json');

  /// The newer release, or null when this is the latest (or no one knows).
  static Future<Release?> newer({bool force = false, http.Client? client}) async {
    final latest = await _latest(force: force, client: client);
    return latest != null && isNewerVersion(latest.version, kAppVersion) ? latest : null;
  }

  static Future<Release?> _latest({required bool force, http.Client? client}) async {
    Map? cached;
    try {
      if (await _file.exists()) cached = jsonDecode(await _file.readAsString()) as Map?;
    } catch (e, st) {
      logError(e, st);
    }
    final checked = DateTime.tryParse('${cached?['checked']}');
    if (!force && checked != null && DateTime.now().difference(checked) < every) {
      return Release.fromJson(cached?['latest']);
    }
    Release? latest;
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(
            Uri.https('api.github.com', '/repos/$kReleasesRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Meridian/$kAppVersion'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        latest = parseRelease(r.body);
      } else if (r.statusCode != 404) {
        // 404 just means nothing is published yet.
        Log.info('Update check: GitHub answered ${r.statusCode}');
        return Release.fromJson(cached?['latest']);
      }
    } catch (e) {
      Log.info('Update check failed: $e');
      return Release.fromJson(cached?['latest']);
    } finally {
      if (client == null) c.close();
    }
    try {
      await writeFileSafely(
        _file,
        jsonEncode({'checked': DateTime.now().toIso8601String(), 'latest': latest?.toJson()}),
      );
    } catch (e, st) {
      logError(e, st);
    }
    return latest;
  }

  /// Reads GitHub's release JSON. Null for drafts, pre-releases and junk.
  static Release? parseRelease(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map || j['draft'] == true || j['prerelease'] == true) return null;
      final tag = j['tag_name'], page = j['html_url'];
      if (tag is! String || page is! String) return null;
      String? installer;
      for (final a in (j['assets'] as List?) ?? const []) {
        final url = a is Map ? a['browser_download_url'] : null;
        if (url is String && url.toLowerCase().endsWith('.exe')) installer = url;
      }
      return Release(tag.replaceFirst(RegExp('^[vV]'), ''), page, installer);
    } on FormatException {
      return null;
    }
  }
}
