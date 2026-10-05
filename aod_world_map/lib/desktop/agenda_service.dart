import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A calendar the user subscribed to by its iCal link (Google "secret
/// address in iCal format", iCloud public calendar, Outlook, ...).
class CalendarFeed {
  CalendarFeed(this.label, this.url);
  String label, url;

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
  static CalendarFeed fromJson(Map<String, dynamic> j) =>
      CalendarFeed((j['label'] as String?) ?? 'Calendar', (j['url'] as String?) ?? '');
}

class AgendaEvent {
  const AgendaEvent(this.title, this.start, this.end, this.allDay, this.location, this.feed);
  final String title, location;
  final DateTime start, end;
  final bool allDay;
  final int feed; // index into the feed list (for colour)
}

class AgendaTodo {
  const AgendaTodo(this.title, this.due, this.feed);
  final String title;
  final DateTime? due;
  final int feed;
}

class _Prop {
  _Prop(this.name, this.params, this.value);
  final String name, value;
  final Map<String, String> params;
}

class _Raw {
  String title = '', location = '', uid = '', status = '';
  DateTime? start, end, recurrenceId;
  bool allDay = false;
  Map<String, String>? rule;
  final Set<int> exdates = {};
  Duration? duration;
}

/// Reads iCal feeds (read-only) and keeps today + tomorrow in memory.
/// Nothing is stored on disk except the feed links themselves.
class AgendaService extends ChangeNotifier {
  List<AgendaEvent> events = const [];
  List<AgendaTodo> todos = const [];
  final Map<String, String> errors = {}; // feed label -> message
  bool loading = false;
  DateTime? updated;
  String _sig = '';

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AodWorldMap';

  Future<void> refresh(List<CalendarFeed> feeds, {bool force = false}) async {
    final sig = feeds.map((f) => f.url).join('|');
    final fresh = updated != null && DateTime.now().difference(updated!).inMinutes < 10;
    if (!force && sig == _sig && fresh) return;
    if (loading) return;
    _sig = sig;
    if (feeds.isEmpty) {
      events = const [];
      todos = const [];
      errors.clear();
      updated = DateTime.now();
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();

    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day + 2);
    final ev = <AgendaEvent>[];
    final td = <AgendaTodo>[];
    final err = <String, String>{};

    await Future.wait([
      for (var i = 0; i < feeds.length; i++)
        () async {
          try {
            final body = await _download(feeds[i].url);
            _parse(body, i, from, to, ev, td);
          } catch (e) {
            err[feeds[i].label] = e.toString().replaceFirst('Exception: ', '');
          }
        }(),
    ]);

    ev.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    events = ev;
    todos = td;
    errors
      ..clear()
      ..addAll(err);
    updated = DateTime.now();
    loading = false;
    notifyListeners();
  }

  Future<String> _download(String raw) async {
    var u = raw.trim();
    if (u.startsWith('webcal://')) u = 'https://${u.substring(9)}';
    if (u.startsWith('webcals://')) u = 'https://${u.substring(10)}';
    final uri = Uri.tryParse(u);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      throw Exception('Not a valid link');
    }
    final res = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Server said ${res.statusCode}');
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (!body.contains('BEGIN:VCALENDAR')) throw Exception('That link is not a calendar');
    return body;
  }

  // ------------------------------------------------------------- parsing

  static List<String> _unfold(String body) {
    final out = <String>[];
    for (final raw in const LineSplitter().convert(body)) {
      if (raw.isNotEmpty && (raw[0] == ' ' || raw[0] == '\t') && out.isNotEmpty) {
        out[out.length - 1] += raw.substring(1);
      } else {
        out.add(raw);
      }
    }
    return out;
  }

  static _Prop? _prop(String line) {
    var q = false, idx = -1;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        q = !q;
      } else if (ch == ':' && !q) {
        idx = i;
        break;
      }
    }
    if (idx <= 0) return null;
    final parts = line.substring(0, idx).split(';');
    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
    }
    return _Prop(parts.first.toUpperCase(), params, line.substring(idx + 1));
  }

  static String _text(String v) => v
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\N', ' ')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\')
      .trim();

  static final _dtRe = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$');

  /// TZID times are read as local time (no tz database on board).
  static ({DateTime t, bool dateOnly})? _dt(String value) {
    final m = _dtRe.firstMatch(value.trim());
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i) ?? '0');
    if (m.group(4) == null) return (t: DateTime(g(1), g(2), g(3)), dateOnly: true);
    if (m.group(7) == 'Z') {
      return (t: DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).toLocal(), dateOnly: false);
    }
    return (t: DateTime(g(1), g(2), g(3), g(4), g(5), g(6)), dateOnly: false);
  }

  static Duration? _dur(String v) {
    final m = RegExp(r'^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return Duration(days: g(1) * 7 + g(2), hours: g(3), minutes: g(4), seconds: g(5));
  }

  void _parse(String body, int feed, DateTime from, DateTime to, List<AgendaEvent> ev, List<AgendaTodo> td) {
    final raws = <_Raw>[];
    final todoRaws = <_Raw>[];
    final lines = _unfold(body);
    String? cur;
    var props = <_Prop>[];
    var skip = 0;

    for (final line in lines) {
      if (line.startsWith('BEGIN:')) {
        final n = line.substring(6).trim();
        if (cur == null) {
          if (n == 'VEVENT' || n == 'VTODO') {
            cur = n;
            props = [];
          }
        } else {
          skip++;
        }
        continue;
      }
      if (line.startsWith('END:')) {
        if (cur != null) {
          if (skip > 0) {
            skip--;
          } else {
            final r = _raw(props);
            (cur == 'VEVENT' ? raws : todoRaws).add(r);
            cur = null;
          }
        }
        continue;
      }
      if (cur != null && skip == 0) {
        final p = _prop(line);
        if (p != null) props.add(p);
      }
    }

    // instances that were moved / edited replace the generated one
    final overridden = <String>{
      for (final r in raws)
        if (r.recurrenceId != null) '${r.uid}|${r.recurrenceId!.millisecondsSinceEpoch}',
    };

    for (final r in raws) {
      final s = r.start;
      if (s == null || r.status == 'CANCELLED') continue;
      final span = r.end != null
          ? r.end!.difference(s)
          : (r.duration ?? (r.allDay ? const Duration(days: 1) : Duration.zero));
      Iterable<DateTime> starts;
      if (r.rule == null) {
        starts = [s];
      } else {
        starts = _expand(s, r.rule!, from, to);
      }
      for (final st in starts) {
        if (r.rule != null) {
          final ms = st.millisecondsSinceEpoch;
          if (r.exdates.contains(ms) || overridden.contains('${r.uid}|$ms')) continue;
        }
        final en = st.add(span);
        final overlaps = st.isBefore(to) && (en.isAfter(from) || (span == Duration.zero && !st.isBefore(from)));
        if (!overlaps) continue;
        ev.add(AgendaEvent(r.title.isEmpty ? '(No title)' : r.title, st, en, r.allDay, r.location, feed));
      }
    }

    for (final r in todoRaws) {
      if (r.status == 'COMPLETED' || r.status == 'CANCELLED') continue;
      if (r.title.isEmpty) continue;
      final due = r.start; // DUE is stored in start for todos
      if (due != null && !due.isBefore(to)) continue;
      td.add(AgendaTodo(r.title, due, feed));
    }
  }

  _Raw _raw(List<_Prop> props) {
    final r = _Raw();
    for (final p in props) {
      switch (p.name) {
        case 'SUMMARY':
          r.title = _text(p.value);
        case 'LOCATION':
          r.location = _text(p.value);
        case 'UID':
          r.uid = p.value.trim();
        case 'STATUS':
          r.status = p.value.trim().toUpperCase();
        case 'DTSTART':
        case 'DUE':
          final d = _dt(p.value);
          if (d != null && (p.name == 'DTSTART' || r.start == null)) {
            r.start = d.t;
            r.allDay = d.dateOnly;
          }
        case 'DTEND':
          r.end = _dt(p.value)?.t;
        case 'DURATION':
          r.duration = _dur(p.value);
        case 'RECURRENCE-ID':
          r.recurrenceId = _dt(p.value)?.t;
        case 'EXDATE':
          for (final part in p.value.split(',')) {
            final d = _dt(part);
            if (d != null) r.exdates.add(d.t.millisecondsSinceEpoch);
          }
        case 'RRULE':
          final m = <String, String>{};
          for (final kv in p.value.split(';')) {
            final eq = kv.indexOf('=');
            if (eq > 0) m[kv.substring(0, eq).toUpperCase()] = kv.substring(eq + 1);
          }
          r.rule = m;
      }
    }
    return r;
  }

  // ----------------------------------------------------------- recurrence

  static int? _weekday(String code) {
    const map = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};
    if (code.length < 2) return null;
    return map[code.substring(code.length - 2).toUpperCase()];
  }

  /// DAILY / WEEKLY(+BYDAY) / MONTHLY / YEARLY with INTERVAL, COUNT, UNTIL.
  /// Wall-clock times stay put across DST.
  static Iterable<DateTime> _expand(DateTime s, Map<String, String> rule, DateTime from, DateTime to) sync* {
    final freq = rule['FREQ'] ?? '';
    final interval = math.max(1, int.tryParse(rule['INTERVAL'] ?? '') ?? 1);
    final count = int.tryParse(rule['COUNT'] ?? '');
    final until = rule['UNTIL'] == null ? null : _dt(rule['UNTIL']!)?.t;
    final byDay = [
      for (final d in (rule['BYDAY'] ?? '').split(','))
        if (_weekday(d) != null) _weekday(d)!,
    ]..sort();
    final byMonthDay = int.tryParse(rule['BYMONTHDAY'] ?? '');

    // skip ahead (only safe without COUNT)
    var k0 = 0;
    if (count == null && from.isAfter(s)) {
      final days = from.difference(s).inDays;
      switch (freq) {
        case 'DAILY':
          k0 = days ~/ interval - 1;
        case 'WEEKLY':
          k0 = days ~/ 7 ~/ interval - 1;
        case 'MONTHLY':
          k0 = ((from.year - s.year) * 12 + from.month - s.month) ~/ interval - 1;
        case 'YEARLY':
          k0 = (from.year - s.year) ~/ interval - 1;
      }
      if (k0 < 0) k0 = 0;
    }

    var n = 0;
    final limit = count == null ? k0 + 400 : 5000;
    for (var k = k0; k < limit; k++) {
      List<DateTime> cands;
      switch (freq) {
        case 'DAILY':
          cands = [DateTime(s.year, s.month, s.day + k * interval, s.hour, s.minute, s.second)];
        case 'WEEKLY':
          final days = byDay.isEmpty ? [s.weekday] : byDay;
          final ws = DateTime(s.year, s.month, s.day - (s.weekday - 1) + 7 * k * interval);
          cands = [
            for (final wd in days) DateTime(ws.year, ws.month, ws.day + wd - 1, s.hour, s.minute, s.second),
          ];
        case 'MONTHLY':
          final m0 = s.month - 1 + k * interval;
          final mo = m0 % 12 + 1;
          final dt = DateTime(s.year + m0 ~/ 12, mo, byMonthDay ?? s.day, s.hour, s.minute, s.second);
          cands = dt.month == mo ? [dt] : [];
        case 'YEARLY':
          final dt = DateTime(s.year + k * interval, s.month, s.day, s.hour, s.minute, s.second);
          cands = dt.month == s.month ? [dt] : [];
        default:
          return;
      }
      for (final t in cands) {
        if (t.isBefore(s)) continue;
        if ((until != null && t.isAfter(until)) || !t.isBefore(to)) return;
        n++;
        if (count != null && n > count) return;
        yield t;
      }
    }
  }
}
