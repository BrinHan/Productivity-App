import 'dart:async';

import 'package:flutter/material.dart';

import 'agenda_service.dart';
import 'island_controller.dart';
import 'island_widgets.dart';

const _card = Color(0xFF1C1C1E);
const _dim = TextStyle(fontSize: 11, color: Color(0x99FFFFFF));
const _feedColors = <Color>[
  Color(0xFF0A84FF),
  Color(0xFF30D158),
  Color(0xFFFF9F0A),
  Color(0xFFBF5AF2),
  Color(0xFFFF375F),
  Color(0xFF64D2FF),
];
Color _feedColor(int i) => _feedColors[i % _feedColors.length];

const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '$h$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Today: schedule from subscribed calendars + the planner's to-do list.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.c});
  final IslandController c;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Timer? _tick, _refresh;
  bool _manage = false;
  String? _feedError;
  final _task = TextEditingController();
  final _taskFocus = FocusNode();
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync();
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) => _sync());
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refresh?.cancel();
    _task.dispose();
    _taskFocus.dispose();
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _sync({bool force = false}) => widget.c.agenda.refresh(widget.c.calendarFeeds, force: force);

  void _addTask(String v) {
    final s = v.trim();
    final p = widget.c.planner;
    if (s.isEmpty || p == null) return;
    p.add(DateTime.now(), s);
    _task.clear();
    _taskFocus.requestFocus();
  }

  void _connect() {
    final url = _url.text.trim();
    final ok = url.startsWith('http://') || url.startsWith('https://') || url.startsWith('webcal');
    if (!ok) {
      setState(() => _feedError = 'Paste the iCal link (starts with https:// or webcal://)');
      return;
    }
    final name = _name.text.trim();
    widget.c.addFeed(CalendarFeed(name.isEmpty ? 'Calendar ${widget.c.calendarFeeds.length + 1}' : name, url));
    _name.clear();
    _url.clear();
    setState(() {
      _feedError = null;
      _manage = false;
    });
    _sync(force: true);
  }

  // ------------------------------------------------------------ widgets

  Widget _icon(IconData i, VoidCallback onTap, {bool on = false, String? tip}) => IslandPressable(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          decoration: BoxDecoration(
            color: on ? const Color(0x2EFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(i, size: 17, color: on ? Colors.white : const Color(0xB3FFFFFF)),
        ),
      );

  Widget _header() {
    final n = DateTime.now();
    final loading = widget.c.agenda.loading;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      const Text('Today', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text('${_dayShort[n.weekday - 1]}, ${_monthShort[n.month - 1]} ${n.day}', style: _dim),
      ),
      const Spacer(),
      if (loading)
        const Padding(
          padding: EdgeInsets.only(right: 10, bottom: 6),
          child: SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
        )
      else if (widget.c.calendarFeeds.isNotEmpty)
        _icon(Icons.refresh_rounded, () => _sync(force: true)),
      const SizedBox(width: 4),
      _icon(_manage ? Icons.close_rounded : Icons.calendar_month_rounded, () => setState(() => _manage = !_manage), on: _manage),
    ]);
  }

  Widget _section(String title, {String? trailing, required Widget child, Widget? footer}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
            const Spacer(),
            if (trailing != null) Text(trailing, style: _dim),
          ]),
          const SizedBox(height: 6),
          Expanded(child: child),
          if (footer != null) footer,
        ]),
      );

  // ----------------------------------------------------------- schedule

  Widget _schedule() {
    final c = widget.c;
    final a = c.agenda;
    final now = DateTime.now();
    final today = _day(now), tomorrow = DateTime(now.year, now.month, now.day + 1);

    if (c.calendarFeeds.isEmpty) {
      return _section(
        'Schedule',
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_month_rounded, size: 26, color: Color(0x80FFFFFF)),
            const SizedBox(height: 8),
            const Text('Connect a calendar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            const Text('Google, iCloud or Outlook,\nread-only', textAlign: TextAlign.center, style: _dim),
            const SizedBox(height: 10),
            IslandPressable(
              onTap: () => setState(() => _manage = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Text('Add calendar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ]),
        ),
      );
    }

    bool onDay(AgendaEvent e, DateTime d) {
      final next = DateTime(d.year, d.month, d.day + 1);
      return e.start.isBefore(next) && (e.end.isAfter(d) || e.start == d);
    }

    final todayEv = [for (final e in a.events) if (onDay(e, today)) e];
    final tomEv = [for (final e in a.events) if (!onDay(e, today) && onDay(e, tomorrow)) e];

    Widget group(String? label, List<AgendaEvent> list) {
      final allDay = [for (final e in list) if (e.allDay) e];
      final timed = [for (final e in list) if (!e.allDay) e];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Color(0x80FFFFFF))),
          ),
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in allDay)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _feedColor(e.feed).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        for (final e in timed) _EventRow(e: e, now: now),
      ]);
    }

    final empty = todayEv.isEmpty && tomEv.isEmpty;
    return _section(
      'Schedule',
      trailing: todayEv.isEmpty ? null : '${todayEv.length} today',
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          for (final e in a.errors.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text("Couldn't load ${e.key}: ${e.value}",
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFFFF8A80))),
            ),
          if (empty && !a.loading)
            const Padding(padding: EdgeInsets.only(top: 18), child: Center(child: Text('Nothing scheduled', style: _dim))),
          if (todayEv.isNotEmpty) group(null, todayEv),
          if (tomEv.isNotEmpty) group('Tomorrow', tomEv),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- to do

  Widget _todo() {
    final p = widget.c.planner;
    if (p == null) {
      return _section('To do', child: const Center(child: Text('Planner unavailable', style: _dim)));
    }
    final all = p.forDay(DateTime.now());
    final tasks = [...all.where((t) => !t.done), ...all.where((t) => t.done)];
    final left = all.where((t) => !t.done).length;
    final reminders = widget.c.agenda.todos;

    return _section(
      'To do',
      trailing: all.isEmpty ? null : (left == 0 ? 'All done' : '$left left'),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          if (tasks.isEmpty && reminders.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 18), child: Center(child: Text('Nothing to do. Enjoy it.', style: _dim))),
          for (final t in tasks)
            IslandPressable(
              onTap: () => p.toggle(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.done ? const Color(0xFF30D158) : Colors.transparent,
                      border: Border.all(color: t.done ? const Color(0xFF30D158) : const Color(0x66FFFFFF), width: 1.6),
                    ),
                    child: t.done ? const Icon(Icons.check_rounded, size: 14, color: Colors.black) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.done ? const Color(0x73FFFFFF) : Colors.white,
                          decoration: t.done ? TextDecoration.lineThrough : null,
                          decorationColor: const Color(0x73FFFFFF),
                        )),
                  ),
                  const SizedBox(width: 6),
                  Text('${t.minutes}m', style: _dim),
                ]),
              ),
            ),
          if (reminders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text('REMINDERS',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Color(0x80FFFFFF))),
            ),
            for (final r in reminders)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(Icons.notifications_none_rounded, size: 18, color: _feedColor(r.feed)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                  if (r.due != null) Text(_clock(r.due!), style: _dim),
                ]),
              ),
          ],
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SizedBox(
          height: 32,
          child: TextField(
            controller: _task,
            focusNode: _taskFocus,
            onSubmitted: _addTask,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0x14FFFFFF),
              hintText: 'Add a task',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
              prefixIcon: const Icon(Icons.add_rounded, size: 16, color: Color(0x99FFFFFF)),
              prefixIconConstraints: const BoxConstraints(minWidth: 30),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ manager

  Widget _field(TextEditingController ctl, String hint, {bool grow = false}) => SizedBox(
        height: 32,
        child: TextField(
          controller: ctl,
          onChanged: (_) {
            if (_feedError != null) setState(() => _feedError = null);
          },
          style: const TextStyle(fontSize: 12, color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0x14FFFFFF),
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _manager() {
    final c = widget.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18)),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          const Text('Calendars', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (c.calendarFeeds.isEmpty) const Text('None connected yet', style: _dim),
          for (var i = 0; i < c.calendarFeeds.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _feedColor(i), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Text(c.calendarFeeds[i].label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                IslandPressable(
                  onTap: () {
                    c.removeFeed(c.calendarFeeds[i]);
                    _sync(force: true);
                  },
                  child: const SizedBox(width: 28, height: 24, child: Icon(Icons.close_rounded, size: 15, color: Color(0x99FFFFFF))),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 110, child: _field(_name, 'Name')),
            const SizedBox(width: 8),
            Expanded(child: _field(_url, 'iCal link (https:// or webcal://)')),
            const SizedBox(width: 8),
            IslandPressable(
              onTap: _connect,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ]),
          if (_feedError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_feedError!, style: const TextStyle(fontSize: 11, color: Color(0xFFFF8A80))),
            ),
          const SizedBox(height: 12),
          const Text(
            'Google: Calendar settings, your calendar, "Secret address in iCal format".\n'
            'iCloud: Calendar app, Share, Public Calendar, copy the link.\n'
            'Outlook: Settings, Shared calendars, Publish a calendar, ICS link.\n'
            'The link is stored on this PC only and is read-only.',
            style: TextStyle(fontSize: 10.5, height: 1.4, color: Color(0x80FFFFFF)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.c.planner;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.c.agenda, if (p != null) p]),
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        child: Column(children: [
          _header(),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: _manage
                  ? KeyedSubtree(key: const ValueKey('m'), child: _manager())
                  : KeyedSubtree(
                      key: const ValueKey('t'),
                      child: Row(children: [
                        Expanded(flex: 11, child: _schedule()),
                        const SizedBox(width: 10),
                        Expanded(flex: 10, child: _todo()),
                      ]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.e, required this.now});
  final AgendaEvent e;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final live = !now.isBefore(e.start) && now.isBefore(e.end);
    final past = !now.isBefore(e.end);
    return Opacity(
      opacity: past ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 58,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_clock(e.start),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: live ? const Color(0xFFFF9F0A) : Colors.white)),
                if (e.end != e.start) Text(_clock(e.end), style: const TextStyle(fontSize: 10.5, color: Color(0x80FFFFFF))),
              ]),
            ),
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: _feedColor(e.feed), borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
                if (e.location.isNotEmpty) Text(e.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0x80FFFFFF))),
              ]),
            ),
            if (live)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('Now', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFFF9F0A))),
              ),
          ]),
        ),
      ),
    );
  }
}
