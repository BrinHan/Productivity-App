import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'agenda_service.dart' show AgendaEvent;

class GoogleTask {
  const GoogleTask(this.id, this.listId, this.title, this.due);
  final String id, listId, title;
  final DateTime? due;
}

/// Google account link: Calendar (read), Tasks (read + complete) and Drive
/// backup of the app's own data (hidden app folder, not your normal files).
/// OAuth "installed app" flow with PKCE on a loopback port. The client ID and
/// secret come from the user's own Google Cloud project and live in
/// %APPDATA%\AodWorldMap\google.json together with the refresh token.
class GoogleService extends ChangeNotifier {
  static const _scopes = [
    'https://www.googleapis.com/auth/calendar.readonly',
    'https://www.googleapis.com/auth/tasks',
    'https://www.googleapis.com/auth/drive.appdata',
    'https://www.googleapis.com/auth/userinfo.email',
  ];
  static const _backupFiles = ['island.json', 'planner.json'];

  String clientId = '', clientSecret = '';
  String? email, status, error;
  bool autoBackup = false, busy = false, loading = false;
  List<AgendaEvent> events = const [];
  List<GoogleTask> todos = const [];
  DateTime? updated;

  String? _refresh, _access;
  DateTime? _exp;
  final Map<String, String> _lastUp = {};

  bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get signedIn => _refresh != null;

  static Directory get _dir {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    return Directory('$base${Platform.pathSeparator}AodWorldMap');
  }

  File _f(String name) => File('${_dir.path}${Platform.pathSeparator}$name');

  // ------------------------------------------------------------ storage

  Future<void> load() async {
    try {
      final f = _f('google.json');
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      clientId = (j['clientId'] as String?) ?? '';
      clientSecret = (j['clientSecret'] as String?) ?? '';
      _refresh = j['refresh'] as String?;
      email = j['email'] as String?;
      autoBackup = (j['autoBackup'] as bool?) ?? false;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await _dir.create(recursive: true);
      await _f('google.json').writeAsString(jsonEncode({
        'clientId': clientId,
        'clientSecret': clientSecret,
        'refresh': _refresh,
        'email': email,
        'autoBackup': autoBackup,
      }));
    } catch (_) {}
  }

  void setClient(String id, String secret) {
    clientId = id.trim();
    clientSecret = secret.trim();
    error = null;
    _save();
    notifyListeners();
  }

  void clearClient() {
    clientId = '';
    clientSecret = '';
    _save();
    notifyListeners();
  }

  void setAutoBackup(bool v) {
    autoBackup = v;
    _save();
    notifyListeners();
  }

  // --------------------------------------------------------------- auth

  static String _rand(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = math.Random.secure();
    return String.fromCharCodes(List.generate(n, (_) => chars.codeUnitAt(r.nextInt(chars.length))));
  }

  Future<void> signIn() async {
    if (!configured || busy) return;
    busy = true;
    error = null;
    status = 'Waiting for your browser...';
    notifyListeners();
    HttpServer? server;
    try {
      final verifier = _rand(64);
      final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
      final state = _rand(16);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirect = 'http://127.0.0.1:${server.port}';
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': _scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url.toString()],
          mode: ProcessStartMode.detached);

      String? code;
      String? denied;
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final q = req.uri.queryParameters;
        if (!q.containsKey('code') && !q.containsKey('error')) {
          req.response.statusCode = 404;
          await req.response.close();
          continue;
        }
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body style="font-family:sans-serif;background:#111;color:#fff;'
            'text-align:center;padding-top:80px"><h2>Signed in</h2><p>You can close this tab.</p></body></html>');
        await req.response.close();
        if (q['state'] == state && q['code'] != null) {
          code = q['code'];
        } else {
          denied = q['error'] ?? 'Sign-in was rejected';
        }
        break;
      }
      if (code == null) throw Exception(denied ?? 'Sign-in cancelled');

      final res = await http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }).timeout(const Duration(seconds: 20));
      final j = jsonDecode(res.body) as Map;
      if (res.statusCode != 200) throw Exception(j['error_description'] ?? j['error'] ?? 'Token error');
      _refresh = j['refresh_token'] as String?;
      _access = j['access_token'] as String?;
      _exp = DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
      if (_refresh == null) throw Exception('Google sent no refresh token. Remove the app at myaccount.google.com/permissions and retry.');
      try {
        final me = await _json('GET', Uri.https('www.googleapis.com', '/oauth2/v2/userinfo'));
        email = me['email'] as String?;
      } catch (_) {}
      await _save();
      status = 'Signed in';
      busy = false;
      notifyListeners();
      await refresh(force: true);
    } catch (e) {
      error = _msg(e);
      status = null;
    } finally {
      await server?.close(force: true);
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final r = _refresh;
    _refresh = null;
    _access = null;
    _exp = null;
    email = null;
    events = const [];
    todos = const [];
    status = null;
    error = null;
    await _save();
    notifyListeners();
    if (r != null) {
      try {
        await http.post(Uri.https('oauth2.googleapis.com', '/revoke'), body: {'token': r});
      } catch (_) {}
    }
  }

  Future<String> _token() async {
    final a = _access, e = _exp;
    if (a != null && e != null && DateTime.now().isBefore(e.subtract(const Duration(minutes: 1)))) return a;
    final r = _refresh;
    if (r == null) throw Exception('Not signed in');
    final res = await http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': r,
      'grant_type': 'refresh_token',
    }).timeout(const Duration(seconds: 20));
    final j = jsonDecode(res.body) as Map;
    if (res.statusCode != 200) {
      if (j['error'] == 'invalid_grant') await signOut();
      throw Exception(j['error_description'] ?? 'Google sign-in expired');
    }
    _access = j['access_token'] as String;
    _exp = DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
    return _access!;
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<http.Response> _send(String method, Uri uri,
      {Object? body, Map<String, String>? headers}) async {
    final req = http.Request(method, uri)..headers['Authorization'] = 'Bearer ${await _token()}';
    if (headers != null) req.headers.addAll(headers);
    if (body is List<int>) {
      req.bodyBytes = body;
    } else if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 25)));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var m = 'Google said ${res.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        final em = (j['error'] is Map) ? j['error']['message'] : null;
        if (em is String) m = em;
      } catch (_) {}
      throw Exception(m);
    }
    return res;
  }

  Future<dynamic> _json(String method, Uri uri, {Object? body}) async {
    final res = await _send(method, uri, body: body);
    return res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  // ----------------------------------------------------- calendar + tasks

  Future<void> refresh({bool force = false}) async {
    if (!signedIn || loading) return;
    final u = updated;
    if (!force && u != null && DateTime.now().difference(u).inMinutes < 10) return;
    loading = true;
    error = null;
    notifyListeners();
    final errs = <String>[];
    await Future.wait([
      _loadEvents().catchError((Object e) => errs.add('Calendar: ${_msg(e)}')),
      _loadTasks().catchError((Object e) => errs.add('Tasks: ${_msg(e)}')),
    ]);
    error = errs.isEmpty ? null : errs.join('\n');
    updated = DateTime.now();
    loading = false;
    notifyListeners();
  }

  static DateTime? _time(Object? m) {
    if (m is! Map) return null;
    final dt = m['dateTime'];
    if (dt is String) return DateTime.parse(dt).toLocal();
    final d = m['date'];
    if (d is String) {
      final p = DateTime.parse(d);
      return DateTime(p.year, p.month, p.day);
    }
    return null;
  }

  Future<void> _loadEvents() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day + 2);
    final cals = await _json('GET',
        Uri.https('www.googleapis.com', '/calendar/v3/users/me/calendarList', {'minAccessRole': 'reader'}));
    final items = [
      for (final c in ((cals['items'] as List?) ?? const []))
        if (c is Map && c['selected'] != false && c['id'] is String) c,
    ];
    final out = <AgendaEvent>[];
    await Future.wait([
      for (var i = 0; i < items.length; i++)
        () async {
          final id = Uri.encodeComponent(items[i]['id'] as String);
          final uri = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/$id/events')
              .replace(queryParameters: {
            'timeMin': from.toUtc().toIso8601String(),
            'timeMax': to.toUtc().toIso8601String(),
            'singleEvents': 'true',
            'orderBy': 'startTime',
            'maxResults': '60',
          });
          final r = await _json('GET', uri);
          for (final e in ((r['items'] as List?) ?? const [])) {
            if (e is! Map || e['status'] == 'cancelled') continue;
            final att = e['attendees'];
            if (att is List &&
                att.any((a) => a is Map && a['self'] == true && a['responseStatus'] == 'declined')) {
              continue;
            }
            final s = _time(e['start']), en = _time(e['end']);
            if (s == null) continue;
            final allDay = (e['start'] as Map)['date'] != null;
            out.add(AgendaEvent(
              ((e['summary'] as String?) ?? '').trim().isEmpty ? '(No title)' : (e['summary'] as String).trim(),
              s,
              en ?? s,
              allDay,
              (e['location'] as String?) ?? '',
              100 + i,
            ));
          }
        }(),
    ]);
    out.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    events = out;
  }

  Future<void> _loadTasks() async {
    final now = DateTime.now();
    final limit = DateTime(now.year, now.month, now.day + 2);
    final lists = await _json('GET', Uri.https('tasks.googleapis.com', '/tasks/v1/users/@me/lists'));
    final out = <GoogleTask>[];
    await Future.wait([
      for (final l in ((lists['items'] as List?) ?? const []))
        if (l is Map && l['id'] is String)
          () async {
            final lid = l['id'] as String;
            final r = await _json(
                'GET',
                Uri.https('tasks.googleapis.com', '/tasks/v1/lists/$lid/tasks',
                    {'showCompleted': 'false', 'showHidden': 'false', 'maxResults': '100'}));
            for (final t in ((r['items'] as List?) ?? const [])) {
              if (t is! Map || t['status'] == 'completed') continue;
              final title = ((t['title'] as String?) ?? '').trim();
              if (title.isEmpty || t['id'] is! String) continue;
              DateTime? due;
              final ds = t['due'];
              if (ds is String) {
                final p = DateTime.tryParse(ds);
                if (p != null) due = DateTime(p.year, p.month, p.day);
              }
              if (due != null && !due.isBefore(limit)) continue;
              out.add(GoogleTask(t['id'] as String, lid, title, due));
            }
          }(),
    ]);
    out.sort((a, b) {
      if (a.due == null || b.due == null) return a.due == null ? (b.due == null ? 0 : 1) : -1;
      return a.due!.compareTo(b.due!);
    });
    todos = out;
  }

  Future<void> completeTask(GoogleTask t) async {
    todos = [for (final x in todos) if (x.id != t.id) x];
    notifyListeners();
    try {
      await _json('PATCH',
          Uri.https('tasks.googleapis.com', '/tasks/v1/lists/${t.listId}/tasks/${t.id}'),
          body: {'status': 'completed'});
    } catch (e) {
      error = 'Tasks: ${_msg(e)}';
      notifyListeners();
      await refresh(force: true);
    }
  }

  // ------------------------------------------------------------- Drive

  Future<String?> _driveId(String name) async {
    final r = await _json(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'spaces': 'appDataFolder',
          'q': "name='$name' and trashed=false",
          'fields': 'files(id)',
        }));
    final l = r['files'] as List?;
    return (l == null || l.isEmpty) ? null : (l.first as Map)['id'] as String?;
  }

  Future<void> _upload(String name, String content) async {
    final id = await _driveId(name);
    if (id != null) {
      await _send('PATCH',
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media'),
          body: utf8.encode(content), headers: {'Content-Type': 'application/json'});
    } else {
      const b = 'aodboundary7MA4YWxkTrZu0gW';
      final meta = jsonEncode({'name': name, 'parents': ['appDataFolder']});
      final body = '--$b\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
          '--$b\r\nContent-Type: application/json\r\n\r\n$content\r\n--$b--';
      await _send('POST',
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
          body: utf8.encode(body), headers: {'Content-Type': 'multipart/related; boundary=$b'});
    }
  }

  /// Uploads the planner and island settings. Skips files that did not change.
  Future<void> backupNow({bool silent = false}) async {
    if (!signedIn || busy) return;
    busy = true;
    if (!silent) {
      error = null;
      status = 'Backing up...';
      notifyListeners();
    }
    try {
      var sent = 0;
      for (final name in _backupFiles) {
        final f = _f(name);
        if (!await f.exists()) continue;
        final content = await f.readAsString();
        if (_lastUp[name] == content) continue;
        await _upload(name, content);
        _lastUp[name] = content;
        sent++;
      }
      final n = DateTime.now();
      status = 'Backed up ${n.hour % 12 == 0 ? 12 : n.hour % 12}:${n.minute.toString().padLeft(2, '0')}'
          '${sent == 0 ? ' (no changes)' : ''}';
    } catch (e) {
      if (!silent) error = 'Drive: ${_msg(e)}';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Replaces local planner + settings with the Drive copy. Needs a restart.
  Future<void> restore() async {
    if (!signedIn || busy) return;
    busy = true;
    error = null;
    status = 'Restoring...';
    notifyListeners();
    try {
      var n = 0;
      await _dir.create(recursive: true);
      for (final name in _backupFiles) {
        final id = await _driveId(name);
        if (id == null) continue;
        final res = await _send('GET',
            Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'));
        await _f(name).writeAsBytes(res.bodyBytes);
        _lastUp[name] = utf8.decode(res.bodyBytes, allowMalformed: true);
        n++;
      }
      status = n == 0 ? 'No backup found on Drive' : 'Restored. Quit and reopen the app now.';
    } catch (e) {
      error = 'Drive: ${_msg(e)}';
      status = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void autoBackupTick() {
    if (autoBackup && signedIn) backupNow(silent: true);
  }
}
