import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
  }) : subs = subs ?? [];
  final String id;
  String title, tag;
  DateTime day;
  int minutes;
  bool done;
  final List<Sub> subs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag': tag,
        'day': day.toIso8601String(),
        'minutes': minutes,
        'done': done,
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
        subs: [
          for (final s in ((j['subs'] as List?) ?? const []))
            if (s is Map) Sub((s['t'] as String?) ?? '', (s['d'] as bool?) ?? false),
        ],
      );
}

class PlannerModel extends ChangeNotifier {
  /// A brand new install: there was no planner file to load. The planner
  /// starts empty and the app window shows its welcome until [finishWelcome].
  bool isNew = false;

  final List<Task> tasks = [];
  String? _shutdownDay;
  int _seq = 0;
  Timer? _saveTimer;

  File get _file {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final s = Platform.pathSeparator;
    return File('$base${s}AodWorldMap${s}planner.json');
  }

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
    _lastJson = raw;
    // Keep the Focus pick pointing at the fresh copy of the same task.
    final f = focusTask;
    if (f != null) focusTask = tasks.where((x) => x.id == f.id).firstOrNull;
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

  Future<void> _write() async {
    try {
      final f = _file;
      await f.parent.create(recursive: true);
      final raw = jsonEncode({
        'tasks': [for (final t in tasks) t.toJson()],
        'shutdownDay': _shutdownDay,
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

  void toggle(Task t) {
    t.done = !t.done;
    for (final s in t.subs) {
      s.done = t.done;
    }
    _changed();
  }

  void toggleSub(Task t, Sub s) {
    s.done = !s.done;
    t.done = t.subs.isNotEmpty && t.subs.every((x) => x.done);
    _changed();
  }

  void remove(Task t) {
    tasks.remove(t);
    if (focusTask == t) focusTask = null;
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

  // ---- focus timer (only ticks while running) ----
  Task? focusTask;
  int focusTotal = 25 * 60, focusSeconds = 25 * 60;
  bool focusRunning = false;
  Timer? _tick;

  void pickFocusTask(Task? t) {
    focusTask = t;
    notifyListeners();
  }

  void setFocusMinutes(int m) {
    focusTotal = m * 60;
    focusSeconds = focusTotal;
    notifyListeners();
  }

  void startFocus() {
    if (focusRunning) return;
    if (focusSeconds <= 0) focusSeconds = focusTotal;
    focusRunning = true;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      focusSeconds--;
      if (focusSeconds <= 0) {
        focusSeconds = 0;
        pauseFocus();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pauseFocus() {
    _tick?.cancel();
    focusRunning = false;
    notifyListeners();
  }

  void resetFocus() {
    pauseFocus();
    focusSeconds = focusTotal;
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}
