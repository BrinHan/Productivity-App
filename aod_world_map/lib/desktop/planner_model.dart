import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_files.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag': tag,
        'day': day.toIso8601String(),
        'minutes': minutes,
        'done': done,
        if (slipped > 0) 'slipped': slipped,
        if (at != null) 'at': at!.toIso8601String(),
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
        subs: [
          for (final s in ((j['subs'] as List?) ?? const []))
            if (s is Map) Sub((s['t'] as String?) ?? '', (s['d'] as bool?) ?? false),
        ],
      );
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
    if (!t.done && t.day.isBefore(t0) && !t.day.isBefore(oldest)) {
      t.day = t0;
      t.at = null;
      t.slipped++;
      n++;
    }
  }
  return n;
}

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
      if (await f.exists()) {
        _apply(await f.readAsString());
      } else {
        isNew = true;
      }
    } catch (_) {}
    _rollOver();
    // Left open past midnight: carry yesterday's leftovers over then too.
    _dayTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (dayOf(DateTime.now()) != _today) _rollOver();
    });
  }

  void _rollOver() {
    _today = dayOf(DateTime.now());
    if (rollOver(tasks, _today) > 0) _changed();
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
    } catch (_) {}
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
      final f = _file;
      await f.parent.create(recursive: true);
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
      await f.writeAsString(raw);
    } catch (_) {}
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
    _changed();
  }

  void toggleSub(Task t, Sub s) {
    s.done = !s.done;
    _setDone(t, t.subs.isNotEmpty && t.subs.every((x) => x.done));
    _changed();
  }

  /// Pins [t] to start at [at] on the calendar; null lets it fit itself in again.
  void pin(Task t, DateTime? at) {
    t.at = at;
    _changed();
  }

  void remove(Task t) {
    tasks.remove(t);
    if (_focusId == t.id) _focusId = null;
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

  void pickFocusTask(Task? t) {
    _focusId = t?.id;
    _changed();
  }

  void setFocusMinutes(int m) {
    focusTotal = m * 60;
    _focusEnds = null;
    _focusLeft = focusTotal;
    _focusOn = false;
    _syncTick();
    _changed();
  }

  void startFocus() {
    if (focusRunning) return;
    var left = focusSeconds;
    if (left <= 0) left = focusTotal;
    _focusEnds = DateTime.now().add(Duration(seconds: left));
    _focusOn = true;
    _syncTick();
    _changed();
  }

  void pauseFocus() {
    if (!focusRunning) return;
    _focusLeft = focusSeconds;
    _focusEnds = null;
    _syncTick();
    _changed();
  }

  void resetFocus() {
    _focusEnds = null;
    _focusLeft = focusTotal;
    _focusOn = false;
    _syncTick();
    _changed();
  }

  /// Marks the focus task done and ends the session.
  void completeFocus() {
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
