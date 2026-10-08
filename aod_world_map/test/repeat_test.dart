import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian/desktop/planner_model.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('repeat_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File file() => File('${dir.path}${Platform.pathSeparator}planner.json');
  final today = dayOf(DateTime.now());
  DateTime d(int y, int m, int day) => DateTime(y, m, day);
  var n = 0;
  String id() => 'n${n++}';

  group('Repeat.next', () {
    // 2026-10-08 is a Thursday.
    test('daily is the day itself', () => expect(Repeat.next(Repeat.daily, d(2026, 10, 8)), d(2026, 10, 8)));

    test('weekdays skips the weekend', () {
      expect(Repeat.next(Repeat.weekdays, d(2026, 10, 10)), d(2026, 10, 12));
      expect(Repeat.next(Repeat.weekdays, d(2026, 10, 9)), d(2026, 10, 9));
    });

    test('weekly lands on its weekday', () {
      expect(Repeat.next('weekly:1', d(2026, 10, 8)), d(2026, 10, 12));
      expect(Repeat.next('weekly:4', d(2026, 10, 8)), d(2026, 10, 8));
    });

    test('monthly on the 31st uses the last day of a short month, then comes back', () {
      expect(Repeat.next('monthly:31', d(2026, 11, 1)), d(2026, 11, 30));
      expect(Repeat.next('monthly:31', d(2026, 12, 1)), d(2026, 12, 31));
      expect(Repeat.next('monthly:31', d(2027, 2, 1)), d(2027, 2, 28));
    });

    test('labels read naturally', () {
      expect(Repeat.label('monthly:1'), 'Monthly on the 1st');
      expect(Repeat.label('monthly:22'), 'Monthly on the 22nd');
      expect(Repeat.label('monthly:12'), 'Monthly on the 12th');
      expect(Repeat.label(Repeat.weekly(d(2026, 10, 8))), 'Every Thursday');
    });

    test('junk rules are dropped on load', () {
      expect(Repeat.valid('weekly:9'), isNull);
      expect(Repeat.valid('hourly'), isNull);
      expect(Repeat.valid('monthly:15'), 'monthly:15');
    });
  });

  group('spawnRepeats', () {
    test('a missed occurrence stays put and the next one lands today', () {
      final old = Task(id: 'a', title: 'inbox', day: today.subtract(const Duration(days: 3)), repeat: Repeat.daily);
      final tasks = [old];
      final added = spawnRepeats(tasks, today, id);
      expect(added.single.day, today);
      expect(added.single.series, 'a');
      expect(old.day, today.subtract(const Duration(days: 3)));
      expect(spawnRepeats(tasks, today, id), isEmpty, reason: 'one open occurrence is enough');
    });

    test("rollover leaves repeating tasks alone", () {
      final r = Task(id: 'r', title: 'r', day: today.subtract(const Duration(days: 1)), repeat: Repeat.daily);
      final plain = Task(id: 'p', title: 'p', day: today.subtract(const Duration(days: 1)));
      expect(rollOver([r, plain], today), 1);
      expect(r.slipped, 0);
    });
  });

  test('ticking one off brings the next, unticking takes it back', () async {
    final p = PlannerModel(file: file());
    await p.load();
    final t = p.add(today, 'standup');
    p.setRepeat(t, Repeat.daily);
    expect(p.tasks, hasLength(1));
    p.toggle(t);
    final next = p.tasks.where((x) => x != t).single;
    expect(next.day, today.add(const Duration(days: 1)));
    expect(next.repeat, Repeat.daily);
    p.toggle(t);
    expect(p.tasks, [t]);
    p.dispose();
  });

  test('stopping or deleting ends the series; undo brings it back', () async {
    final p = PlannerModel(file: file());
    await p.load();
    final t = p.add(today, 'water plants');
    p.setRepeat(t, Repeat.daily);
    p.toggle(t);
    final next = p.tasks.firstWhere((x) => x != t);

    final removed = p.remove(next);
    expect(t.repeat, isNull, reason: 'deleting stops it repeating');
    p.undoRemove(removed);
    expect(p.tasks, contains(next));
    expect(t.repeat, Repeat.daily);

    p.setRepeat(next, null);
    expect(p.tasks.every((x) => x.repeat == null), isTrue);
    p.dispose();
  });

  test('a repeating task survives a save and load', () async {
    final a = PlannerModel(file: file());
    await a.load();
    a.setRepeat(a.add(today, 'review'), 'weekly:${today.weekday}');
    await a.flush();
    final b = PlannerModel(file: file());
    await b.load();
    expect(b.tasks.single.repeat, 'weekly:${today.weekday}');
    a.dispose();
    b.dispose();
  });

  test('focus time goes to the task it was spent on', () async {
    final p = PlannerModel(file: file());
    await p.load();
    final t = p.add(today, 'essay');
    p.pickFocusTask(t);
    p.startFocus();
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    p.pauseFocus();
    expect(t.focused, inInclusiveRange(1, 3));
    final before = t.focused;
    p.resetFocus();
    expect(t.focused, before, reason: 'a paused session is not counted twice');
    p.dispose();
  });
}
