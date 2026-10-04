import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'agenda_service.dart';

/// The OAuth client that ships inside the app. Put the values in
/// google_client.json (gitignored) and run or build with
///   --dart-define-from-file=google_client.json
/// Builds without it show a short note instead of a sign-in button.
const String kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const String kGoogleClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

/// Gmail "read" is a restricted scope for public release. Set to false to
/// drop it from the consent screen (the inbox card then disappears).
const bool kGoogleReadMail = true;

class GoogleTask {
  const GoogleTask(this.id, this.listId, this.title, this.due);
  final String id, listId, title;
  final DateTime? due;
}

class GoogleMail {
  const GoogleMail(this.id, this.threadId, this.from, this.subject);
  final String id, threadId, from, subject;
}

class GoogleBirthday {
  const GoogleBirthday(this.name, this.date, this.age);
  final String name;
  final DateTime date;
  final int? age; // turning, when the contact has a birth year
}

class _ApiError implements Exception {
  _ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google sign-in (OAuth 2.0 for desktop apps: system browser, loopback
/// redirect, PKCE) plus Calendar, Tasks, Gmail, Contacts and a private
/// Drive backup. One client for every user, so nobody visits Google Cloud.
class GoogleService extends ChangeNotifier {
  static const _scCalList = 'https://www.googleapis.com/auth/calendar.calendarlist.readonly';
  static const _scCalEv = 'https://www.googleapis.com/auth/calendar.events.readonly';
  static const _scTasks = 'https://www.googleapis.com/auth/tasks';
  static const _scDrive = 'https://www.googleapis.com/auth/drive.appdata';
  static const _scMail = 'https://www.googleapis.com/auth/gmail.readonly';
  static const _scContacts = 'https://www.googleapis.com/auth/contacts.readonly';

  static const _backupName = 'orbit-backup.json';
  static const _backupFiles = ['planner.json', 'island.json', 'ui.json'];

  // ---- live data (read by the planner and the island) ----
  List<AgendaEvent> events = const []; // same type as iCal events, so the island can merge them
  List<GoogleTask> todos = const [];
  List<GoogleMail> mail = const [];
  List<GoogleBirthday> birthdays = const [];
  int unread = 0;

  bool busy = false, loading = false;
  String? status;
  String? _actionError, _syncError;
  String? get error => _actionError ?? _syncError;

  bool autoBackup = false;
  DateTime? lastSync;
  String? email;

  // ---- saved ----
  String? _userId, _userSecret; // "use my own client" (advanced)
  String? _access, _refreshTok;
  DateTime? _expiry, _updated;
  Set<String> _granted = {};
  bool _loaded = false;
  Timer? _autoTimer;
  String? _lastBundle;
  bool _uploading = false;

  // ------------------------------------------------------------ config

  String get _clientId => kGoogleClientId.isNotEmpty ? kGoogleClientId : (_userId ?? '');
  String get _clientSecret => kGoogleClientSecret.isNotEmpty ? kGoogleClientSecret : (_userSecret ?? '');
  bool get bundled => kGoogleClientId.isNotEmpty && kGoogleClientSecret.isNotEmpty;
  bool get configured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;
  bool get signedIn => _refreshTok != null;

  bool _has(String scope) => _granted.contains(scope);
  bool get canCalendar => _has(_scCalList) && _has(_scCalEv);
  bool get canTasks => _has(_scTasks);
  bool get canMail => _has(_scMail);
  bool get canContacts => _has(_scContacts);
  bool get canDrive => _has(_scDrive);

  List<String> get _scopes => [
        'openid',
        'email',
        _scCalList,
        _scCalEv,
        _scTasks,
        _scDrive,
        if (kGoogleReadMail) _scMail,
        _scContacts,
      ];

  // ------------------------------------------------------- persistence

  Directory get _dir {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    return Directory('$base${Platform.pathSeparator}AodWorldMap');
  }

  File get _file => File('${_dir.path}${Platform.pathSeparator}google.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _file.exists()) {
        final j = jsonDecode(await _file.readAsString());
        if (j is Map) {
          _userId = j['userClientId'] as String?;
          _userSecret = j['userClientSecret'] as String?;
          _refreshTok = j['refresh'] as String?;
          _access = j['access'] as String?;
          final exp = j['expiry'] as String?;
          _expiry = exp == null ? null : DateTime.tryParse(exp);
          email = j['email'] as String?;
          _granted = {for (final s in (j['scopes'] as List? ?? const [])) '$s'};
          autoBackup = (j['autoBackup'] as bool?) ?? false;
          final ls = j['lastSync'] as String?;
          lastSync = ls == null ? null : DateTime.tryParse(ls);
        }
      }
    } catch (_) {}
    if (autoBackup && signedIn) _startAuto();
    notifyListeners();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> _save() async {
    try {
      await _dir.create(recursive: true);
      await _file.writeAsString(jsonEncode({
        'userClientId': _userId,
        'userClientSecret': _userSecret,
        'refresh': _refreshTok,
        'access': _access,
        'expiry': _expiry?.toIso8601String(),
        'email': email,
        'scopes': _granted.toList(),
        'autoBackup': autoBackup,
        'lastSync': lastSync?.toIso8601String(),
      }));
    } catch (_) {}
  }

  // ---- "use my own client" (only shown under Advanced) ----

  void setClient(String id, String secret) {
    _userId = id.trim();
    _userSecret = secret.trim();
    _actionError = null;
    _save();
    notifyListeners();
  }

  void clearClient() {
    _userId = null;
    _userSecret = null;
    _save();
    notifyListeners();
  }

  // ----------------------------------------------------------- sign in

  static final _rng = math.Random.secure();

  static String _rand(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return String.fromCharCodes([for (var i = 0; i < n; i++) chars.codeUnitAt(_rng.nextInt(chars.length))]);
  }

  Future<void> _openBrowser(String url) async {
    if (!Platform.isWindows) return;
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
  }

  static String _doneHtml(bool ok, String text) => '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Orbit</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0f0f11;color:#ededef;
font:16px/1.5 "Segoe UI",system-ui,sans-serif}main{max-width:380px;padding:32px;text-align:center}
h1{font-size:20px;margin:0 0 8px;letter-spacing:-.01em}p{margin:0;color:#a1a1aa}</style></head>
<body><main><h1>${ok ? 'You are signed in' : 'Sign-in did not finish'}</h1><p>$text</p></main></body></html>''';

  Future<Map<String, String>> _waitForCode(HttpServer server, String state) async {
    await for (final req in server.timeout(const Duration(minutes: 4))) {
      final q = req.uri.queryParameters;
      if (!q.containsKey('code') && !q.containsKey('error')) {
        req.response.statusCode = 404;
        await req.response.close();
        continue;
      }
      final good = q['state'] == state && q.containsKey('code');
      req.response.headers.contentType = ContentType.html;
      req.response.write(good
          ? _doneHtml(true, 'You can close this tab and go back to Orbit.')
          : _doneHtml(false, 'You can close this tab and try again from Orbit.'));
      await req.response.close();
      if (q['state'] != state) throw _ApiError('The sign-in response did not match. Try again.');
      if (q.containsKey('error')) {
        throw _ApiError(q['error'] == 'access_denied' ? 'Sign-in was cancelled.' : 'Google said: ${q['error']}');
      }
      return q;
    }
    throw _ApiError('Sign-in timed out. Try again.');
  }

  Future<void> signIn() async {
    await _ensureLoaded();
    if (!configured || busy) return;
    busy = true;
    _actionError = null;
    status = 'Finish signing in in your browser.';
    notifyListeners();
    HttpServer? server;
    try {
      final verifier = _rand(64);
      final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
      final state = _rand(24);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirect = 'http://127.0.0.1:${server.port}';
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': _scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
        'include_granted_scopes': 'true',
      });
      await _openBrowser(url.toString());
      final q = await _waitForCode(server, state);

      final res = await http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': q['code']!,
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }).timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode != 200 || data is! Map) {
        final why = data is Map ? (data['error_description'] ?? data['error'] ?? res.statusCode) : res.statusCode;
        throw _ApiError('Google would not finish sign-in ($why).');
      }
      final refresh = data['refresh_token'] as String?;
      if (refresh == null) {
        throw _ApiError('Google did not return a refresh token. Remove Orbit at myaccount.google.com/permissions and try again.');
      }
      _refreshTok = refresh;
      _access = data['access_token'] as String?;
      _expiry = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3600));
      _granted = {for (final s in ('${data['scope'] ?? ''}').split(' ')) if (s.isNotEmpty) s};

      email = await _fetchEmail();
      await _save();
      status = 'Connected';
      busy = false;
      notifyListeners();
      unawaited(refreshAll(force: true));
    } catch (e) {
      _actionError = e is _ApiError
          ? e.message
          : (e is TimeoutException ? 'Sign-in timed out. Try again.' : 'Sign-in failed. Check your connection and try again.');
      status = null;
      busy = false;
      notifyListeners();
    } finally {
      await server?.close(force: true);
    }
  }

  Future<String?> _fetchEmail() async {
    try {
      final r = await _call('GET', Uri.https('openidconnect.googleapis.com', '/v1/userinfo'));
      if (r.statusCode == 200) return (jsonDecode(r.body) as Map)['email'] as String?;
    } catch (_) {}
    return null;
  }

  Future<void> signOut() async {
    await _ensureLoaded();
    final tok = _refreshTok;
    busy = true;
    notifyListeners();
    if (tok != null) {
      try {
        await http
            .post(Uri.https('oauth2.googleapis.com', '/revoke'), body: {'token': tok})
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    await _clearSession(null);
    busy = false;
    notifyListeners();
  }

  Future<void> _clearSession(String? why) async {
    _autoTimer?.cancel();
    _refreshTok = null;
    _access = null;
    _expiry = null;
    _granted = {};
    email = null;
    autoBackup = false;
    events = const [];
    todos = const [];
    mail = const [];
    birthdays = const [];
    unread = 0;
    status = null;
    _syncError = null;
    _actionError = why;
    await _save();
    notifyListeners();
  }

  // ------------------------------------------------------------- tokens

  Future<String?> _token() async {
    final exp = _expiry;
    if (_access != null && exp != null && DateTime.now().isBefore(exp.subtract(const Duration(minutes: 1)))) {
      return _access;
    }
    return _renew();
  }

  Future<String?> _renew() async {
    final r = _refreshTok;
    if (r == null) return null;
    try {
      final res = await http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'refresh_token': r,
        'grant_type': 'refresh_token',
      }).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map) {
        _access = data['access_token'] as String?;
        _expiry = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3600));
        await _save();
        return _access;
      }
      if (data is Map && data['error'] == 'invalid_grant') {
        await _clearSession('Your Google session ended. Sign in again.');
      }
    } catch (_) {}
    return null;
  }

  Future<http.Response> _call(String method, Uri uri, {Object? body, Map<String, String>? headers}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final tok = await _token();
      if (tok == null) throw _ApiError('Not signed in to Google.');
      final req = http.Request(method, uri)..headers['Authorization'] = 'Bearer $tok';
      if (headers != null) req.headers.addAll(headers);
      if (body is String) req.body = body;
      if (body is List<int>) req.bodyBytes = body;
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 25)));
      if (res.statusCode == 401 && attempt == 0) {
        _access = null;
        _expiry = null;
        continue;
      }
      return res;
    }
    throw _ApiError('Google rejected the request.');
  }

  void _ok(http.Response r, String name) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    if (r.statusCode == 403) {
      final b = r.body;
      if (b.contains('SERVICE_DISABLED') || b.contains('accessNotConfigured')) {
        throw _ApiError('$name API is switched off in the Google Cloud project.');
      }
      throw _ApiError('$name was not allowed.');
    }
    throw _ApiError('$name returned ${r.statusCode}.');
  }

  // ------------------------------------------------------------- reading

  Future<void> refresh({bool force = false}) => refreshAll(force: force);

  Future<void> refreshAll({bool force = false}) async {
    await _ensureLoaded();
    if (!signedIn || !configured) return;
    final fresh = _updated != null && DateTime.now().difference(_updated!).inMinutes < 10;
    if (!force && fresh) return;
    if (loading) return;
    loading = true;
    notifyListeners();
    final problems = <String>[];
    Future<void> guard(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        problems.add(e is _ApiError ? e.message : 'A Google request failed.');
      }
    }

    await Future.wait([guard(_loadCalendar), guard(_loadTasks), guard(_loadMail), guard(_loadBirthdays)]);
    _updated = DateTime.now();
    _syncError = problems.isEmpty ? null : problems.toSet().join(' ');
    loading = false;
    notifyListeners();
  }

  DateTime? _when(Map? m) {
    if (m == null) return null;
    final dt = m['dateTime'] as String?;
    if (dt != null) return DateTime.tryParse(dt)?.toLocal();
    final d = m['date'] as String?;
    return d == null ? null : DateTime.tryParse('${d}T00:00:00');
  }

  Future<void> _loadCalendar() async {
    if (!canCalendar) {
      events = const [];
      return;
    }
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day + 2);
    final lr = await _call(
      'GET',
      Uri.https('www.googleapis.com', '/calendar/v3/users/me/calendarList', {
        'minAccessRole': 'reader',
        'fields': 'items(id,summary,selected,primary)',
      }),
    );
    _ok(lr, 'Calendar');
    final items = ((jsonDecode(lr.body) as Map)['items'] as List?) ?? const [];
    final cals = [
      for (final c in items)
        if (c is Map && (c['selected'] == true || c['primary'] == true)) c,
    ].take(12).toList();

    final out = <AgendaEvent>[];
    await Future.wait([
      for (var ci = 0; ci < cals.length; ci++)
        () async {
          final c = cals[ci];
          final r = await _call(
            'GET',
            Uri.https('www.googleapis.com', '/calendar/v3/calendars/${c['id']}/events', {
              'timeMin': from.toUtc().toIso8601String(),
              'timeMax': to.toUtc().toIso8601String(),
              'singleEvents': 'true',
              'orderBy': 'startTime',
              'maxResults': '50',
              'fields': 'items(summary,location,status,start,end)',
            }),
          );
          if (r.statusCode != 200) return;
          for (final e in ((jsonDecode(r.body) as Map)['items'] as List?) ?? const []) {
            if (e is! Map || e['status'] == 'cancelled') continue;
            final s = _when(e['start'] as Map?), en = _when(e['end'] as Map?);
            if (s == null) continue;
            final allDay = (e['start'] as Map)['date'] != null;
            out.add(AgendaEvent(
              '${e['summary'] ?? '(No title)'}',
              s,
              en ?? s,
              allDay,
              '${e['location'] ?? ''}',
              1000 + ci, // colour slot, apart from the iCal feeds
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
    if (!canTasks) {
      todos = const [];
      return;
    }
    final lr = await _call('GET', Uri.https('tasks.googleapis.com', '/tasks/v1/users/@me/lists', {'maxResults': '20'}));
    _ok(lr, 'Tasks');
    final lists = ((jsonDecode(lr.body) as Map)['items'] as List?) ?? const [];
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final out = <GoogleTask>[];
    await Future.wait([
      for (final l in lists)
        if (l is Map)
          () async {
            final r = await _call(
              'GET',
              Uri.https('tasks.googleapis.com', '/tasks/v1/lists/${l['id']}/tasks', {
                'showCompleted': 'false',
                'showHidden': 'false',
                'maxResults': '50',
                'fields': 'items(id,title,due,status)',
              }),
            );
            if (r.statusCode != 200) return;
            for (final t in ((jsonDecode(r.body) as Map)['items'] as List?) ?? const []) {
              if (t is! Map) continue;
              final title = '${t['title'] ?? ''}'.trim();
              if (title.isEmpty || t['status'] == 'completed') continue;
              DateTime? due;
              final raw = t['due'] as String?;
              if (raw != null) {
                final u = DateTime.tryParse(raw);
                if (u != null) due = DateTime(u.year, u.month, u.day); // a date, not an instant
              }
              if (due != null && !due.isBefore(tomorrow)) continue;
              out.add(GoogleTask('${t['id']}', '${l['id']}', title, due));
            }
          }(),
    ]);
    out.sort((a, b) {
      if (a.due == null) return b.due == null ? 0 : 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    });
    todos = out.take(30).toList();
  }

  Future<void> completeTask(GoogleTask t) async {
    final before = todos;
    todos = [for (final x in todos) if (x.id != t.id) x];
    notifyListeners();
    try {
      final r = await _call(
        'PATCH',
        Uri.https('tasks.googleapis.com', '/tasks/v1/lists/${t.listId}/tasks/${t.id}'),
        body: jsonEncode({'status': 'completed'}),
        headers: {'Content-Type': 'application/json'},
      );
      _ok(r, 'Tasks');
    } catch (e) {
      todos = before;
      _actionError = 'Could not complete that task in Google.';
      notifyListeners();
    }
  }

  String _senderName(String from) {
    final m = RegExp(r'^\s*"?([^"<]+?)"?\s*<').firstMatch(from);
    final n = (m?.group(1) ?? from).trim();
    return n.isEmpty ? from : n;
  }

  Future<void> _loadMail() async {
    if (!canMail) {
      mail = const [];
      unread = 0;
      return;
    }
    final lr = await _call(
      'GET',
      Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/labels/INBOX', {'fields': 'messagesUnread'}),
    );
    _ok(lr, 'Gmail');
    unread = ((jsonDecode(lr.body) as Map)['messagesUnread'] as num?)?.toInt() ?? 0;

    final r = await _call(
      'GET',
      Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages', {
        'labelIds': 'INBOX',
        'q': 'is:unread',
        'maxResults': '5',
        'fields': 'messages(id,threadId)',
      }),
    );
    _ok(r, 'Gmail');
    final ids = ((jsonDecode(r.body) as Map)['messages'] as List?) ?? const [];
    final out = <GoogleMail>[];
    await Future.wait([
      for (final m in ids)
        if (m is Map)
          () async {
            final mr = await _call(
              'GET',
              Uri(
                scheme: 'https',
                host: 'gmail.googleapis.com',
                path: '/gmail/v1/users/me/messages/${m['id']}',
                queryParameters: {
                  'format': 'metadata',
                  'metadataHeaders': ['From', 'Subject'],
                  'fields': 'id,threadId,payload/headers',
                },
              ),
            );
            if (mr.statusCode != 200) return;
            final j = jsonDecode(mr.body) as Map;
            String h(String n) {
              for (final x in (((j['payload'] as Map?)?['headers']) as List?) ?? const []) {
                if (x is Map && '${x['name']}'.toLowerCase() == n.toLowerCase()) return '${x['value']}';
              }
              return '';
            }

            final subject = h('Subject').trim();
            out.add(GoogleMail('${j['id']}', '${j['threadId']}', _senderName(h('From')),
                subject.isEmpty ? '(No subject)' : subject));
          }(),
    ]);
    // keep Google's newest-first order
    final order = {for (var i = 0; i < ids.length; i++) '${(ids[i] as Map)['id']}': i};
    out.sort((a, b) => (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));
    mail = out;
  }

  Future<void> _loadBirthdays() async {
    if (!canContacts) {
      birthdays = const [];
      return;
    }
    final r = await _call(
      'GET',
      Uri.https('people.googleapis.com', '/v1/people/me/connections', {
        'personFields': 'names,birthdays',
        'pageSize': '1000',
        'fields': 'connections(names(displayName),birthdays(date))',
      }),
    );
    _ok(r, 'Contacts');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final horizon = today.add(const Duration(days: 30));
    final out = <GoogleBirthday>[];
    for (final c in ((jsonDecode(r.body) as Map)['connections'] as List?) ?? const []) {
      if (c is! Map) continue;
      final names = c['names'] as List?;
      final name = names != null && names.isNotEmpty ? '${(names.first as Map)['displayName'] ?? ''}' : '';
      if (name.isEmpty) continue;
      for (final b in (c['birthdays'] as List?) ?? const []) {
        final d = b is Map ? b['date'] as Map? : null;
        final mo = (d?['month'] as num?)?.toInt(), da = (d?['day'] as num?)?.toInt();
        if (mo == null || da == null) continue;
        var next = DateTime(today.year, mo, da);
        if (next.isBefore(today)) next = DateTime(today.year + 1, mo, da);
        if (next.isAfter(horizon)) continue;
        final y = (d?['year'] as num?)?.toInt();
        out.add(GoogleBirthday(name, next, y == null ? null : next.year - y));
        break;
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    birthdays = out.take(8).toList();
  }

  // -------------------------------------------------------- Drive backup

  Future<String> _bundle() async {
    final files = <String, String>{};
    for (final n in _backupFiles) {
      final f = File('${_dir.path}${Platform.pathSeparator}$n');
      if (await f.exists()) files[n] = await f.readAsString();
    }
    return jsonEncode({'v': 1, 'files': files});
  }

  Future<String?> _findBackup() async {
    final r = await _call(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '$_backupName'",
        'fields': 'files(id)',
      }),
    );
    _ok(r, 'Drive');
    final files = ((jsonDecode(r.body) as Map)['files'] as List?) ?? const [];
    return files.isEmpty ? null : '${(files.first as Map)['id']}';
  }

  Future<void> _upload(String data) async {
    final id = await _findBackup();
    if (id != null) {
      final r = await _call(
        'PATCH',
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/$id', {'uploadType': 'media'}),
        body: data,
        headers: {'Content-Type': 'application/json'},
      );
      _ok(r, 'Drive');
    } else {
      final boundary = 'orbit${_rand(14)}';
      final meta = jsonEncode({'name': _backupName, 'parents': ['appDataFolder']});
      final body = '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
          '--$boundary\r\nContent-Type: application/json\r\n\r\n$data\r\n--$boundary--';
      final r = await _call(
        'POST',
        Uri.https('www.googleapis.com', '/upload/drive/v3/files', {'uploadType': 'multipart', 'fields': 'id'}),
        body: utf8.encode(body),
        headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
      );
      _ok(r, 'Drive');
    }
    _lastBundle = data;
    lastSync = DateTime.now();
    await _save();
  }

  Future<void> backupNow() async {
    await _ensureLoaded();
    if (!signedIn || busy) return;
    if (!canDrive) {
      _actionError = 'Drive backup was not allowed on the Google consent screen.';
      notifyListeners();
      return;
    }
    busy = true;
    _actionError = null;
    status = 'Backing up to Drive.';
    notifyListeners();
    try {
      await _upload(await _bundle());
      status = 'Backed up just now.';
    } catch (e) {
      _actionError = e is _ApiError ? e.message : 'Backup failed. Check your connection.';
      status = null;
    }
    busy = false;
    notifyListeners();
  }

  /// Replaces local planner and island data. Quit and reopen afterwards.
  Future<void> restore() async {
    await _ensureLoaded();
    if (!signedIn || busy) return;
    if (!canDrive) {
      _actionError = 'Drive backup was not allowed on the Google consent screen.';
      notifyListeners();
      return;
    }
    busy = true;
    _actionError = null;
    status = 'Restoring from Drive.';
    notifyListeners();
    try {
      final id = await _findBackup();
      if (id == null) throw _ApiError('No backup found in your Drive yet.');
      final r = await _call('GET', Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}));
      _ok(r, 'Drive');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final files = (j is Map ? j['files'] : null) as Map?;
      if (files == null || files.isEmpty) throw _ApiError('That backup is empty.');
      await _dir.create(recursive: true);
      for (final e in files.entries) {
        final name = '${e.key}';
        if (!_backupFiles.contains(name)) continue;
        await File('${_dir.path}${Platform.pathSeparator}$name').writeAsString('${e.value}');
      }
      lastSync = DateTime.now();
      await _save();
      status = 'Restored. Quit and reopen Orbit to load it.';
    } catch (e) {
      _actionError = e is _ApiError ? e.message : 'Restore failed. Check your connection.';
      status = null;
    }
    busy = false;
    notifyListeners();
  }

  void setAutoBackup(bool v) {
    if (v && lastSync == null) {
      _actionError = 'Do one manual backup or restore first, so an empty install cannot overwrite your cloud copy.';
      notifyListeners();
      return;
    }
    autoBackup = v;
    _actionError = null;
    v ? _startAuto() : _autoTimer?.cancel();
    _save();
    notifyListeners();
  }

  void _startAuto() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(minutes: 2), (_) => autoBackupTick());
  }

  /// Uploads only when something changed. Safe to call from anywhere.
  Future<void> autoBackupTick() async {
    await _ensureLoaded();
    if (!autoBackup || !signedIn || !canDrive || busy || _uploading) return;
    _uploading = true;
    try {
      final b = await _bundle();
      if (b == _lastBundle) return;
      await _upload(b);
      notifyListeners();
    } catch (_) {
    } finally {
      _uploading = false;
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }
}
