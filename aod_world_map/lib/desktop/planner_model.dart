import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_files.dart';
import 'log.dart';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

class Sub {
  Sub(this.title, [this.done = false]);
  String title;
  bool done;
}

class Task {
  Task({
    required this.id,
    required this.title,
    required this.day,
    this.minutes = 30,
    this.tag = 'work',
    List<Sub>? subs,
    this.done = false,
    this.slipped = 0,
    this.at,
    this.repeat,
    this.series,
    this.focused = 0,
  }) : subs = subs ?? [];
  final String id;
  String title, tag;
  DateTime day;
  int minutes;
  bool done;
  final List<Sub> subs;

  /// How many times the task was left unfinished and carried to a later day.
  int slipped;

  /// Pinned start time on the calendar. Without one, the task fills the
  /// next free gap in its day.
  DateTime? at;

  /// How the task repeats ('daily', 'weekdays', 'weekly:3', 'monthly:15';
  /// see [Repeat]), or null. Every occurrence carries it, and they share a
  /// [series] id, the first occurrence's id.
  String? repeat;
  String? series;

  /// Seconds spent on it in focus sessions, for the weekly review to set
  /// against [minutes].
  int focused;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag': tag,
        'day': day.toIso8601String(),
        'minutes': minutes,
        'done': done,
        if (slipped > 0) 'slipped': slipped,
        if (at != null) 'at': at!.toIso8601String(),
        if (repeat != null) 'repeat': repeat,
        if (series != null) 'series': series,
        if (focused > 0) 'focused': focused,
        'subs': [
          for (final s in subs) {'t': s.title, 'd': s.done},
        ],
      };

  static Task fromJson(Map<String, dynamic> j) => Task(
        id: (j['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: (j['title'] as String?) ?? '',
        tag: (j['tag'] as String?) ?? 'work',
        day: dayOf(DateTime.tryParse((j['day'] as String?) ?? '') ?? DateTime.now()),
        minutes: (j['minutes'] as num?)?.toInt() ?? 30,
        done: (j['done'] as bool?) ?? false,
        slipped: (j['slipped'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse((j['at'] as String?) ?? ''),
        repeat: Repeat.valid(j['repeat'] as String?),
        series: j['series'] as String?,
        focused: (j['focused'] as num?)?.toInt() ?? 0,
        subs: [
          for (final s in ((j['subs'] as List?) ?? const []))
            if (s is Map) Sub((s['t'] as String?) ?? '', (s['d'] as bool?) ?? false),
        ],
      );
}

/// Repeat rules. Weekly and monthly ones carry the day they land on, so a
/// monthly task on the 31st comes back to the 31st after a short month.
class Repeat {
  Repeat._();

  static const daily = 'daily', weekdays = 'weekdays';
  static String weekly(DateTime d) => 'weekly:${d.weekday}';
  static String monthly(DateTime d) => 'monthly:${d.day}';

  /// [rule] if it is one, else null.
  static String? valid(String? rule) {
    if (rule == daily || rule == weekdays) return rule;
    final m = RegExp(r'^(weekly|monthly):(\d+)$').firstMatch(rule ?? '');
    if (m == null) return null;
    final n = int.parse(m.group(2)!);
    return (m.group(1) == 'weekly' ? n >= 1 && n <= 7 : n >= 1 && n <= 31) ? rule : null;
  }

  /// The first day on or after [from] that [rule] lands on.
  static DateTime next(String rule, DateTime from) {
    var d = dayOf(from);
    if (rule == daily) return d;
    if (rule == weekdays) {
      while (d.weekday > DateTime.friday) {
        d = DateTime(d.year, d.month, d.day + 1);
      }
      return d;
    }
    final n = int.parse(rule.split(':').last);
    if (rule.startsWith('weekly')) return DateTime(d.year, d.month, d.day + (n - d.weekday) % 7);
    // Monthly: day n, or the month's last day when it is shorter.
    for (var i = 0;; i++) {
      final last = DateTime(d.year, d.month + i + 1, 0).day;
      final c = DateTime(d.year, d.month + i, n > last ? last : n);
      if (!c.isBefore(d)) return c;
    }
  }

  /// How the rule reads in a menu or a chip.
  static String label(String rule) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (rule == daily) return 'Every day';
    if (rule == weekdays) return 'Every weekday';
    final n = int.parse(rule.split(':').last);
    if (rule.startsWith('weekly')) return 'Every ${days[n - 1]}';
    final th = (n % 100 >= 11 && n % 100 <= 13) ? 'th' : const {1: 'st', 2: 'nd', 3: 'rd'}[n % 10] ?? 'th';
    return 'Monthly on the $n$th';
  }
}

/// Keeps one open occurrence of every repeating series on or after
/// [today]. When the latest occurrence is done, or its day has passed, the
/// next one is added. Missed occurrences stay where they were rather than
/// piling up on today. Returns the tasks added.
List<Task> spawnRepeats(List<Task> tasks, DateTime today, String Function() newId) {
  final t0 = dayOf(today);
  final latest = <String, Task>{};
  for (final t in tasks) {
    if (t.repeat == null) continue;
    final key = t.series ?? t.id;
    final cur = latest[key];
    if (cur == null || t.day.isAfter(cur.day) || (t.day == cur.day && !t.done)) latest[key] = t;
  }
  final added = <Task>[];
  for (final e in latest.entries) {
    final t = e.value;
    if (!t.done && !t.day.isBefore(t0)) continue; // still to do
    final after = t.day.isBefore(t0) ? t0 : DateTime(t.day.year, t.day.month, t.day.day + 1);
    added.add(Task(
      id: newId(),
      title: t.title,
      day: Repeat.next(t.repeat!, after),
      minutes: t.minutes,
      tag: t.tag,
      subs: [for (final s in t.subs) Sub(s.title)],
      repeat: t.repeat,
      series: e.key,
    ));
  }
  tasks.addAll(added);
  return added;
}

/// Unfinished tasks from the last this-many days roll over to today.
/// Older ones were left behind before rollover existed and stay put.
const kRolloverDays = 14;

/// Moves unfinished tasks from earlier days to [today] and counts the slip.
/// Returns how many moved.
int rollOver(List<Task> tasks, DateTime today) {
  final t0 = dayOf(today);
  final oldest = t0.subtract(const Duration(days: kRolloverDays));
  var n = 0;
  for (final t in tasks) {
    // A repeating task doesn't roll over: its next occurrence is coming.
    if (!t.done && t.repeat == null && t.day.isBefore(t0) && !t.day.isBefore(oldest)) {
      t.day = t0;
      t.at = null;
      t.slipped++;
      n++;
    }
  }
  return n;
}

typedef RemovedTask = ({Task task, int index, List<Task> stopped});

class PlannerModel extends ChangeNotifier {
  /// [file] is for tests; the app keeps the planner in its data folder.
  PlannerModel({File? file}) : _fileOverride = file;
  final File? _fileOverride;

  /// A brand new install: there was no planner file to load. The planner
  /// starts empty and the app window shows its welcome until [finishWelcome].
  bool isNew = false;

  final List<Task> tasks = [];
  String? _shutdownDay;
  int _seq = 0;
  Timer? _saveTimer, _dayTimer;
  DateTime _today = dayOf(DateTime.now());

  File get _file => _fileOverride ?? appDataFile('planner.json');

  String? _lastJson; // what this process last read or wrote

  Future<void> load() async {
    try {
      final f = _file;
      if (await f.exists() || await backupOf(f).exists()) {
        // A planner that won't parse falls back to the last backup rather
        // than starting empty and saving over it.
        final raw = await readWithBackup(f, (raw) => jsonDecode(raw) is Map<String, dynamic>);
        if (raw != null) _apply(raw);
      } else {
        isNew = true;
      }
    } catch (e, st) {
      logError(e, st);
    }
    _rollOver();
    // Left open past midnight: carry yesterday's leftovers over then too.
    _dayTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (dayOf(DateTime.now()) != _today) _rollOver();
    });
  }

  void _rollOver() {
    _today = dayOf(DateTime.now());
    final moved = rollOver(tasks, _today);
    if (spawnRepeats(tasks, _today, _id).isNotEmpty || moved > 0) _changed();
  }

  /// The welcome is done (or skipped). Saving creates the planner file, so
  /// it will not show again.
  void finishWelcome() {
    isNew = false;
    _changed();
  }

  bool _apply(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic>) return false;
    tasks
      ..clear()
      ..addAll([
        for (final t in ((j['tasks'] as List?) ?? const []))
          if (t is Map<String, dynamic>) Task.fromJson(t),
      ]);
    _shutdownDay = j['shutdownDay'] as String?;
    final f = j['focus'];
    if (f is Map) {
      _focusId = f['task'] as String?;
      focusTotal = (f['total'] as num?)?.toInt() ?? 25 * 60;
      _focusEnds = DateTime.tryParse((f['ends'] as String?) ?? '');
      _focusLeft = (f['left'] as num?)?.toInt() ?? focusTotal;
      _focusOn = (f['on'] as bool?) ?? false;
    }
    _lastJson = raw;
    _syncTick();
    return true;
  }

  /// The other process (island or app window) saved the planner.
  Future<void> reload() async {
    try {
      final raw = await _file.readAsString();
      if (raw == _lastJson || _saveTimer?.isActive == true) return;
      if (_apply(raw)) notifyListeners();
    } catch (e, st) {
      logError(e, st);
    }
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _write);
  }

  /// Writes now instead of after the usual pause.
  Future<void> flush() async {
    if (_saveTimer?.isActive != true) return;
    _saveTimer!.cancel();
    await _write();
  }

  Future<void> _write() async {
    try {
      final raw = jsonEncode({
        'tasks': [for (final t in tasks) t.toJson()],
        'shutdownDay': _shutdownDay,
        'focus': {
          'task': _focusId,
          'total': focusTotal,
          'ends': _focusEnds?.toIso8601String(),
          'left': _focusLeft,
          'on': _focusOn,
        },
      });
      _lastJson = raw;
      await writeFileSafely(_file, raw, backup: true);
    } catch (e, st) {
      logError(e, st);
    }
  }

  List<Task> forDay(DateTime d) {
    final k = dayOf(d);
    return tasks.where((t) => t.day == k).toList();
  }

  Task add(DateTime day, String title, {int minutes = 30, String tag = 'work'}) {
    final t = Task(id: _id(), title: title, day: dayOf(day), minutes: minutes, tag: tag);
    tasks.add(t);
    _changed();
    return t;
  }

  /// Where today's calendar has a task, set by the app window. A task
  /// checked off is pinned there, so the rest of the plan doesn't shift.
  DateTime? Function(Task)? placeOf;

  void _setDone(Task t, bool done) {
    if (done && !t.done) t.at ??= placeOf?.call(t);
    if (!done && t.done) t.at = null;
    t.done = done;
  }

  void toggle(Task t) {
    _setDone(t, !t.done);
    for (final s in t.subs) {
      s.done = t.done;
    }
    _repeatChanged(t);
    _changed();
  }

  void toggleSub(Task t, Sub s) {
    s.done = !s.done;
    _setDone(t, t.subs.isNotEmpty && t.subs.every((x) => x.done));
    _repeatChanged(t);
    _changed();
  }

  /// Ticking off a repeating task brings in its next occurrence; unticking
  /// it takes that back out again while it is still untouched.
  void _repeatChanged(Task t) {
    if (t.repeat == null) return;
    final key = t.series ?? t.id;
    if (!t.done) {
      tasks.removeWhere(
        (x) => x != t && (x.series ?? x.id) == key && x.day.isAfter(t.day) && !x.done && x.subs.every((s) => !s.done),
      );
    }
    spawnRepeats(tasks, _today, _id);
  }

  /// Makes [t] repeat by [rule] (see [Repeat]), or stop with null. Either
  /// way the series' occurrences still to come after [t] go; a new rule
  /// starts a new series from [t].
  void setRepeat(Task t, String? rule) {
    final key = t.series ?? t.id;
    final family = tasks.where((x) => x.repeat != null && (x.series ?? x.id) == key).toList();
    tasks.removeWhere((x) => x != t && family.contains(x) && !x.done && x.day.isAfter(t.day));
    for (final x in family) {
      x.repeat = null;
    }
    t
      ..repeat = rule
      ..series = rule == null ? null : t.id;
    if (rule != null) spawnRepeats(tasks, _today, _id);
    _changed();
  }

  /// Pins [t] to start at [at] on the calendar; null lets it fit itself in again.
  void pin(Task t, DateTime? at) {
    t.at = at;
    _changed();
  }

  /// Deletes [t]. Deleting a repeating task stops the series, so it does
  /// not just come back tomorrow. Pass the result to [undoRemove] to undo.
  RemovedTask remove(Task t) {
    final index = tasks.indexOf(t);
    tasks.remove(t);
    final stopped = <Task>[];
    if (t.repeat != null) {
      final key = t.series ?? t.id;
      for (final x in tasks) {
        if (x.repeat != null && (x.series ?? x.id) == key) {
          x.repeat = null;
          stopped.add(x);
        }
      }
    }
    if (_focusId == t.id) _focusId = null;
    _changed();
    return (task: t, index: index, stopped: stopped);
  }

  void undoRemove(RemovedTask r) {
    if (tasks.contains(r.task)) return;
    tasks.insert(r.index.clamp(0, tasks.length).toInt(), r.task);
    for (final x in r.stopped) {
      x.repeat = r.task.repeat;
    }
    _changed();
  }

  void rename(Task t, String title) {
    t.title = title;
    _changed();
  }

  void addMinutes(Task t, int delta) {
    t.minutes = (t.minutes + delta).clamp(5, 600).toInt();
    _changed();
  }

  void moveDay(Task t, int days) {
    t.day = dayOf(t.day.add(Duration(days: days)));
    t.at = null;
    _changed();
  }

  /// Not getting to it today: carry it to tomorrow and count the slip.
  void slip(Task t) {
    t.day = dayOf(DateTime.now()).add(const Duration(days: 1));
    t.at = null;
    t.slipped++;
    _changed();
  }

  void cycleTag(Task t) {
    const tags = ['work', 'personal', 'health'];
    t.tag = tags[(tags.indexOf(t.tag) + 1) % tags.length];
    _changed();
  }

  int moveUnfinishedToTomorrow() {
    final today = dayOf(DateTime.now());
    var n = 0;
    for (final t in tasks) {
      if (t.day == today && !t.done) {
        t.day = today.add(const Duration(days: 1));
        t.at = null;
        t.slipped++;
        n++;
      }
    }
    if (n > 0) _changed();
    return n;
  }

  void clearCompleted(DateTime day) {
    final k = dayOf(day);
    tasks.removeWhere((t) => t.day == k && t.done);
    _changed();
  }

  bool get shutdownToday => _shutdownDay == _dayKey(DateTime.now());

  void setShutdown(bool v) {
    _shutdownDay = v ? _dayKey(DateTime.now()) : null;
    _changed();
  }

  // ---- focus timer ----
  // Saved with the planner, so the island shows the same session the
  // planner runs. A running session is stored as when it ends, so each
  // process works out what is left on its own clock.

  String? _focusId;
  int focusTotal = 25 * 60;
  DateTime? _focusEnds; // set while running (and once it has run out)
  int _focusLeft = 25 * 60; // seconds left while paused or not started
  bool _focusOn = false; // started, and not yet reset or completed
  Timer? _tick;

  Task? get focusTask => _focusId == null ? null : tasks.where((x) => x.id == _focusId).firstOrNull;

  bool get focusRunning => _focusEnds != null && DateTime.now().isBefore(_focusEnds!);

  /// The timer ran out and nobody has finished or reset the session yet.
  bool get focusFinished => _focusEnds != null && !focusRunning;

  /// Running, paused part way, or run out: the island shows it.
  bool get focusActive => _focusOn;

  int get focusSeconds {
    final e = _focusEnds;
    if (e == null) return _focusLeft;
    final ms = e.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// Credits the focus task with the time run since the session last
  /// started (or was banked), and starts counting afresh from now. While a
  /// session runs, [_focusLeft] holds what was left when it started.
  void _bank() {
    if (_focusEnds == null) return;
    final now = focusSeconds;
    final spent = _focusLeft - now;
    if (spent > 0) focusTask?.focused += spent;
    _focusLeft = now;
  }

  void pickFocusTask(Task? t) {
    _bank(); // time so far goes to the task it was spent on
    _focusId = t?.id;
    _changed();
  }

  void setFocusMinutes(int m) {
    _bank();
    focusTotal = m * 60;
    _focusEnds = null;
    _focusLeft = focusTotal;
    _focusOn = false;
    _syncTick();
    _changed();
  }

  void startFocus() {
    if (focusRunning) return;
    _bank(); // a session that ran out
    var left = focusSeconds;
    if (left <= 0) left = focusTotal;
    _focusLeft = left;
    _focusEnds = DateTime.now().add(Duration(seconds: left));
    _focusOn = true;
    _syncTick();
    _changed();
  }

  void pauseFocus() {
    if (!focusRunning) return;
    _bank();
    _focusEnds = null;
    _syncTick();
    _changed();
  }

  void resetFocus() {
    _bank();
    _focusEnds = null;
    _focusLeft = focusTotal;
    _focusOn = false;
    _syncTick();
    _changed();
  }

  /// Marks the focus task done and ends the session.
  void completeFocus() {
    _bank();
    _focusEnds = null;
    final t = focusTask;
    if (t != null && !t.done) toggle(t);
    _focusId = null;
    resetFocus();
  }

  /// Ticks once a second while a session runs, and once more when it runs out.
  void _syncTick() {
    if (!focusRunning) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!focusRunning) {
        _tick?.cancel();
        _tick = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _saveTimer?.cancel();
    _dayTimer?.cancel();
    super.dispose();
  }
}
