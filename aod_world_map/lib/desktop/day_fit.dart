/// How a day's open tasks fit around its meetings: the free time left in
/// the workday, the gaps that make it up, and whether the plan fits.
class DayFit {
  const DayFit({required this.free, required this.meetings, required this.planned, required this.gaps});

  /// Free minutes left in the workday once meetings are taken out.
  final int free;

  /// Minutes of meetings still ahead in the workday.
  final int meetings;

  /// Minutes of open tasks planned for the day.
  final int planned;

  /// The free stretches, in order.
  final List<({DateTime start, DateTime end})> gaps;

  bool get over => planned > free;
  int get overBy => planned - free;
}

/// Gaps shorter than this are not worth planning work into.
const kMinGap = Duration(minutes: 10);

/// [busy] is every timed event on [day]; all-day events don't take time.
/// For today, the workday starts no earlier than [now].
DayFit dayFit({
  required DateTime now,
  required DateTime day,
  required int startHour,
  required int endHour,
  required List<({DateTime start, DateTime end})> busy,
  required int planned,
}) {
  var from = DateTime(day.year, day.month, day.day, startHour);
  final to = DateTime(day.year, day.month, day.day, endHour);
  if (now.isAfter(from)) from = now;
  if (!from.isBefore(to)) return DayFit(free: 0, meetings: 0, planned: planned, gaps: const []);

  // Clip each event to the window, then walk them in order, merging overlaps.
  final clipped = [
    for (final b in busy)
      if (b.end.isAfter(from) && b.start.isBefore(to))
        (start: b.start.isBefore(from) ? from : b.start, end: b.end.isAfter(to) ? to : b.end),
  ]..sort((a, b) => a.start.compareTo(b.start));

  final gaps = <({DateTime start, DateTime end})>[];
  var cursor = from;
  var meetings = Duration.zero;
  for (final b in clipped) {
    if (b.start.isAfter(cursor)) {
      if (b.start.difference(cursor) >= kMinGap) gaps.add((start: cursor, end: b.start));
      meetings += b.end.difference(b.start);
      cursor = b.end;
    } else if (b.end.isAfter(cursor)) {
      meetings += b.end.difference(cursor);
      cursor = b.end;
    }
  }
  if (to.difference(cursor) >= kMinGap) gaps.add((start: cursor, end: to));

  final free = gaps.fold<int>(0, (s, g) => s + g.end.difference(g.start).inMinutes);
  return DayFit(free: free, meetings: meetings.inMinutes, planned: planned, gaps: gaps);
}

/// Where each task lands on [day]'s calendar, by task id. A task pinned to
/// a time on [day] ([at]) stays there; the rest fill the free gaps of the
/// workday in order, split across gaps when one isn't long enough. A task
/// whose spans add up to less than its minutes ran out of room.
Map<String, List<({DateTime start, DateTime end})>> placeTasks({
  required DateTime now,
  required DateTime day,
  required int startHour,
  required int endHour,
  required List<({DateTime start, DateTime end})> busy,
  required List<({String id, int minutes, DateTime? at})> tasks,
}) {
  final d = DateTime(day.year, day.month, day.day);
  final placed = <String, List<({DateTime start, DateTime end})>>{};
  final pinned = <({DateTime start, DateTime end})>[];
  for (final t in tasks) {
    final at = t.at;
    if (at == null || DateTime(at.year, at.month, at.day) != d) continue;
    final span = (start: at, end: at.add(Duration(minutes: t.minutes)));
    placed[t.id] = [span];
    pinned.add(span);
  }

  final gaps = dayFit(
    now: now,
    day: day,
    startHour: startHour,
    endHour: endHour,
    busy: [...busy, ...pinned],
    planned: 0,
  ).gaps;

  var gi = 0;
  var cursor = gaps.isEmpty ? null : gaps.first.start;
  for (final t in tasks) {
    if (placed.containsKey(t.id)) continue;
    final spans = placed[t.id] = [];
    var left = Duration(minutes: t.minutes);
    while (left > Duration.zero && gi < gaps.length) {
      final room = gaps[gi].end.difference(cursor!);
      // Don't start a piece in a sliver the task won't finish in.
      if (room < left && room < kMinGap) {
        if (++gi < gaps.length) cursor = gaps[gi].start;
        continue;
      }
      final take = room < left ? room : left;
      spans.add((start: cursor, end: cursor.add(take)));
      left -= take;
      cursor = cursor.add(take);
      if (!cursor.isBefore(gaps[gi].end) && ++gi < gaps.length) cursor = gaps[gi].start;
    }
  }
  return placed;
}
