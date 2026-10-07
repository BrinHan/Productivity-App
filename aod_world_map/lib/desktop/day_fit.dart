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
