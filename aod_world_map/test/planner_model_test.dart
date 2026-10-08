import 'dart:convert';
import 'dart:io';

import 'package:meridian/desktop/planner_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('planner_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File file() => File('${dir.path}${Platform.pathSeparator}planner.json');
  final today = dayOf(DateTime.now());
  Task task(String id, DateTime day, {bool done = false}) => Task(id: id, title: id, day: day, done: done);

  group('rollover', () {
    test('unfinished tasks from earlier days move to today and count the slip', () {
      final tasks = [
        task('yesterday', today.subtract(const Duration(days: 1))),
        task('last week', today.subtract(const Duration(days: 6))),
        task('done', today.subtract(const Duration(days: 1)), done: true),
        task('today', today),
        task('tomorrow', today.add(const Duration(days: 1))),
        task('ancient', today.subtract(const Duration(days: 40))),
      ];
      expect(rollOver(tasks, today), 2);
      expect([for (final t in tasks) if (t.day == today) t.id], ['yesterday', 'last week', 'today']);
      expect([for (final t in tasks) t.slipped], [1, 1, 0, 0, 0, 0]);
    });

    test('happens when the planner loads, and is saved', () async {
      file().writeAsStringSync(jsonEncode({
        'tasks': [task('old', today.subtract(const Duration(days: 2))).toJson()],
      }));
      final p = PlannerModel(file: file());
      await p.load();
      await p.flush();
      expect(p.forDay(today).single.slipped, 1);
      final saved = jsonDecode(file().readAsStringSync()) as Map<String, dynamic>;
      expect((saved['tasks'] as List).single['slipped'], 1);
      p.dispose();
    });
  });

  test('slip and the shutdown bulk move both count', () async {
    final p = PlannerModel(file: file());
    await p.load();
    final a = p.add(today, 'a'), b = p.add(today, 'b');
    p.slip(a);
    expect(p.moveUnfinishedToTomorrow(), 1);
    final tomorrow = today.add(const Duration(days: 1));
    expect(a.day, tomorrow);
    expect(b.day, tomorrow);
    expect([a.slipped, b.slipped], [1, 1]);
    p.dispose();
  });

  group('focus', () {
    test('a running session is shared through the file', () async {
      final a = PlannerModel(file: file());
      await a.load();
      final t = a.add(today, 'write report');
      a.pickFocusTask(t);
      a.startFocus();
      expect(a.focusRunning, isTrue);
      expect(a.focusActive, isTrue);
      await a.flush();

      final b = PlannerModel(file: file());
      await b.load();
      expect(b.focusTask?.title, 'write report');
      expect(b.focusRunning, isTrue);
      expect(b.focusSeconds, closeTo(25 * 60, 2));

      b.pauseFocus();
      await b.flush();
      await a.reload();
      expect(a.focusRunning, isFalse);
      expect(a.focusActive, isTrue, reason: 'paused part way is still a session');
      a.dispose();
      b.dispose();
    });

    test('complete marks the task done and ends the session', () async {
      final p = PlannerModel(file: file());
      await p.load();
      final t = p.add(today, 'x');
      p.pickFocusTask(t);
      p.startFocus();
      p.completeFocus();
      expect(t.done, isTrue);
      expect(p.focusTask, isNull);
      expect(p.focusActive, isFalse);
      expect(p.focusSeconds, p.focusTotal);
      p.dispose();
    });

    test('a session that ran out is finished until reset', () async {
      file().writeAsStringSync(jsonEncode({
        'tasks': const [],
        'focus': {
          'total': 1500,
          'ends': DateTime.now().subtract(const Duration(seconds: 5)).toIso8601String(),
          'left': 1500,
        },
      }));
      final p = PlannerModel(file: file());
      await p.load();
      expect(p.focusFinished, isTrue);
      expect(p.focusSeconds, 0);
      p.startFocus(); // starting again begins a fresh session
      expect(p.focusSeconds, closeTo(1500, 2));
      p.resetFocus();
      expect(p.focusActive, isFalse);
      p.dispose();
    });
  });
}
