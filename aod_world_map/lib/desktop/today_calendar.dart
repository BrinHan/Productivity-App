import 'package:flutter/material.dart';

import 'date_names.dart';
import 'island_controller.dart';
import 'island_widgets.dart';

const _feedColors = <Color>[
  Color(0xFF0A84FF),
  Color(0xFF30D158),
  Color(0xFFFF9F0A),
  Color(0xFFBF5AF2),
  Color(0xFFFF375F),
  Color(0xFF64D2FF),
];

/// The colour of iCal feed (or Google colour slot) [i].
Color feedColor(int i) => _feedColors[i % _feedColors.length];

/// One event for the island's month and week views, whichever calendar it
/// came from (iCal feed or Google), with its colour already worked out.
class DayEvent {
  const DayEvent(this.title, this.start, this.end, this.allDay, this.color);
  final String title;
  final DateTime start, end;
  final bool allDay;
  final Color color;

  bool on(DateTime day) {
    final next = DateTime(day.year, day.month, day.day + 1);
    return start.isBefore(next) && (end.isAfter(day) || start == day);
  }
}

/// Events in this month's six-week grid, from the iCal feeds plus Google's
/// month (today and tomorrow until that has loaded).
List<DayEvent> calendarEvents(IslandController c) {
  final g = c.google;
  final now = DateTime.now();
  final month = g.signedIn ? g.monthEvents(now.year, now.month) : null;
  final calColor = {for (final cal in g.calendars) cal.id: cal.color};
  return [
    for (final e in c.agenda.events) DayEvent(e.title, e.start, e.end, e.allDay, feedColor(e.feed)),
    if (month != null)
      for (final e in month)
        DayEvent(e.title, e.start, e.end, e.allDay, Color(e.color ?? calColor[e.calId] ?? 0xFF4A9EE8))
    else
      for (final e in g.events) DayEvent(e.title, e.start, e.end, e.allDay, feedColor(e.feed)),
  ];
}

const _dim = TextStyle(fontSize: 11, color: Color(0x99FFFFFF));
const _label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Color(0x80FFFFFF));
const _letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Sunday that starts [d]'s week.
DateTime _weekStart(DateTime d) => DateTime(d.year, d.month, d.day - d.weekday % 7);

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '$h$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// "9a", "2:30p": short enough for a week column.
String _short(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '$h$m${d.hour < 12 ? 'a' : 'p'}';
}

List<DayEvent> _onDay(List<DayEvent> es, DateTime d) => [for (final e in es) if (e.on(d)) e]
  ..sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.start.compareTo(b.start);
  });

/// This month as a grid with a dot per event; tap a day for its list below.
class IslandMonthView extends StatefulWidget {
  const IslandMonthView({super.key, required this.events});
  final List<DayEvent> events;

  @override
  State<IslandMonthView> createState() => _IslandMonthViewState();
}

class _IslandMonthViewState extends State<IslandMonthView> {
  DateTime _selected = _day(DateTime.now());

  Widget _cell(DateTime d, DateTime today) {
    final inMonth = d.month == today.month;
    final isToday = d == today, isPicked = d == _selected;
    final dots = [for (final e in widget.events) if (e.on(d)) e.color].take(3);
    return IslandPressable(
      onTap: () => setState(() => _selected = d),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday ? Colors.white : (isPicked ? const Color(0x33FFFFFF) : Colors.transparent),
          ),
          child: Text('${d.day}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isToday || isPicked ? FontWeight.w800 : FontWeight.w600,
                color: isToday ? Colors.black : (inMonth ? Colors.white : const Color(0x40FFFFFF)),
              )),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 4,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final c in dots)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(color: inMonth ? c : c.withValues(alpha: 0.4), shape: BoxShape.circle),
              ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final first = DateTime(today.year, today.month);
    final start = _weekStart(first);
    final daysIn = DateTime(today.year, today.month + 1, 0).day;
    final rows = (first.weekday % 7 + daysIn + 6) ~/ 7;
    final picked = _onDay(widget.events, _selected);
    final s = _selected;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final l in _letters) Expanded(child: Center(child: Text(l, style: _label))),
      ]),
      const SizedBox(height: 2),
      for (var r = 0; r < rows; r++)
        SizedBox(
          height: 31,
          child: Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(child: _cell(DateTime(start.year, start.month, start.day + r * 7 + c), today)),
          ]),
        ),
      const Divider(height: 10, thickness: 1, color: Color(0x14FFFFFF)),
      Text(s == today ? 'TODAY' : '${dayShort[s.weekday - 1]}, ${monthShort[s.month - 1]} ${s.day}'.toUpperCase(),
          style: _label),
      Expanded(
        child: picked.isEmpty
            ? const Padding(padding: EdgeInsets.only(top: 6), child: Text('Nothing scheduled', style: _dim))
            : ListView(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                children: [for (final e in picked) _Line(e: e)],
              ),
      ),
    ]);
  }
}

/// A day's event in the month view's list: time, colour bar, title.
class _Line extends StatelessWidget {
  const _Line({required this.e});
  final DayEvent e;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 56, child: Text(e.allDay ? 'All day' : _clock(e.start), style: _dim)),
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Text(e.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// This week (Sunday to Saturday), one column per day.
class IslandWeekView extends StatelessWidget {
  const IslandWeekView({super.key, required this.events});
  final List<DayEvent> events;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = _day(now);
    final start = _weekStart(today);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: 2),
        Expanded(child: _column(DateTime(start.year, start.month, start.day + i), today, now)),
      ],
    ]);
  }

  Widget _column(DateTime d, DateTime today, DateTime now) {
    final isToday = d == today;
    return Container(
      padding: const EdgeInsets.fromLTRB(1, 4, 1, 1),
      decoration: BoxDecoration(
        color: isToday ? const Color(0x14FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text(_letters[d.weekday % 7], style: _label),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? Colors.white : Colors.transparent),
          child: Text('${d.day}',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: isToday ? Colors.black : Colors.white)),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            children: [for (final e in _onDay(events, d)) _Chip(e: e, past: !e.allDay && e.end.isBefore(now))],
          ),
        ),
      ]),
    );
  }
}

/// An event in a week column: a tinted block with its start time and title.
class _Chip extends StatelessWidget {
  const _Chip({required this.e, required this.past});
  final DayEvent e;
  final bool past;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: past ? 0.45 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: e.color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(5)),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 2, color: e.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!e.allDay)
                      Text(_short(e.start),
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))),
                    Text(e.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.15)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}
