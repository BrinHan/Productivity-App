import 'package:aod_world_map/desktop/day_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 7);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 7, h, m);
  ({DateTime start, DateTime end}) ev(DateTime s, DateTime e) => (start: s, end: e);

  test('an empty day is the whole workday', () {
    final f = dayFit(now: at(7), day: day, startHour: 9, endHour: 17, busy: const [], planned: 120);
    expect(f.free, 8 * 60);
    expect(f.meetings, 0);
    expect(f.over, isFalse);
    expect(f.gaps, hasLength(1));
  });

  test('meetings come out of the free time, overlaps counted once', () {
    final f = dayFit(
      now: at(7),
      day: day,
      startHour: 9,
      endHour: 17,
      busy: [ev(at(10), at(11)), ev(at(10, 30), at(11, 30)), ev(at(14), at(15))],
      planned: 0,
    );
    expect(f.meetings, 90 + 60);
    expect(f.free, 8 * 60 - 150);
    expect(f.gaps.map((g) => g.start), [at(9), at(11, 30), at(15)]);
  });

  test('events outside the workday are clipped away', () {
    final f = dayFit(
      now: at(7),
      day: day,
      startHour: 9,
      endHour: 17,
      busy: [ev(at(8), at(9, 30)), ev(at(16, 30), at(18)), ev(at(19), at(20))],
      planned: 0,
    );
    expect(f.meetings, 60);
    expect(f.free, 7 * 60);
  });

  test('today only counts what is left from now', () {
    final f = dayFit(now: at(15), day: day, startHour: 9, endHour: 17, busy: [ev(at(13), at(16))], planned: 90);
    expect(f.meetings, 60);
    expect(f.free, 60);
    expect(f.over, isTrue);
    expect(f.overBy, 30);
  });

  test('after the workday nothing is free', () {
    final f = dayFit(now: at(18), day: day, startHour: 9, endHour: 17, busy: const [], planned: 30);
    expect(f.free, 0);
    expect(f.over, isTrue);
  });

  test('slivers between back-to-back meetings are not free time', () {
    final f = dayFit(
      now: at(7),
      day: day,
      startHour: 9,
      endHour: 11,
      busy: [ev(at(9), at(9, 55)), ev(at(10), at(11))],
      planned: 0,
    );
    expect(f.free, 0);
    expect(f.gaps, isEmpty);
  });

  group('placeTasks', () {
    ({String id, int minutes, DateTime? at}) task(String id, int minutes, [DateTime? pin]) =>
        (id: id, minutes: minutes, at: pin);

    test('fills the free time after now, not the start of the workday', () {
      final p = placeTasks(
        now: at(21, 55),
        day: day,
        startHour: 9,
        endHour: 23,
        busy: [ev(at(8, 30), at(15)), ev(at(18), at(19))],
        tasks: [task('a', 35)],
      );
      expect(p['a'], [ev(at(21, 55), at(22, 30))]);
    });

    test('goes around meetings and splits across gaps', () {
      final p = placeTasks(
        now: at(7),
        day: day,
        startHour: 9,
        endHour: 17,
        busy: [ev(at(10), at(16))],
        tasks: [task('a', 30), task('b', 60)],
      );
      expect(p['a'], [ev(at(9), at(9, 30))]);
      expect(p['b'], [ev(at(9, 30), at(10)), ev(at(16), at(16, 30))]);
    });

    test('pinned tasks stay put and the rest work around them', () {
      final p = placeTasks(
        now: at(7),
        day: day,
        startHour: 9,
        endHour: 17,
        busy: const [],
        tasks: [task('a', 60), task('b', 30, at(9))],
      );
      expect(p['b'], [ev(at(9), at(9, 30))]);
      expect(p['a'], [ev(at(9, 30), at(10, 30))]);
    });

    test('what does not fit is left short', () {
      final p = placeTasks(
        now: at(16, 35),
        day: day,
        startHour: 9,
        endHour: 17,
        busy: const [],
        tasks: [task('a', 20), task('b', 60)],
      );
      expect(p['a'], [ev(at(16, 35), at(16, 55))]);
      expect(p['b'], isEmpty); // 5 minutes left is too little to start in
    });
  });
}
