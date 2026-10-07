import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Process, ProcessStartMode;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../aod/sky_toggle.dart';
import 'action_items.dart';
import 'agenda_service.dart' show AgendaService, CalendarFeed, isCalendarLink;
import 'app_files.dart';
import 'browser.dart';
import 'date_names.dart';
import 'day_fit.dart';
import 'google_service.dart';
import 'notes_model.dart';
import 'notes_service.dart';
import 'planner_model.dart';
import 'window_shell.dart';

part 'home_theme.dart';
part 'home_widgets.dart';
part 'home_chrome.dart';
part 'home_sidebar.dart';
part 'home_tasks.dart';
part 'home_board.dart';
part 'home_focus.dart';
part 'home_planning.dart';
part 'home_shutdown.dart';
part 'home_week.dart';
part 'home_schedule.dart';
part 'home_account.dart';
part 'home_settings.dart';
part 'home_notes.dart';
part 'home_calendar.dart';
part 'home_welcome.dart';

enum _View { home, focus, planning, tasks, shutdown, week, review, account, settings, notes, calendar }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.shell,
    required this.planner,
    required this.isDark,
    required this.onDarkChanged,
  });
  final ShellController shell;
  final PlannerModel planner;
  final bool isDark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _View _view = _View.home;
  int _startOffset = 0;
  bool _board = true;
  String _tag = 'all';
  bool _hideDone = false;
  Timer? _clockTimer;

  PlannerModel get p => widget.planner;
  GoogleService get g => widget.shell.island.google;
  NotesService get notes => widget.shell.island.notes;
  AgendaService get agenda => widget.shell.island.agenda;

  @override
  void initState() {
    super.initState();
    _Prefs.i.load();
    g.refresh();
    agenda.refresh(widget.shell.island.calendarFeeds);
    widget.shell.view.addListener(_onViewAsked);
    _onViewAsked();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      g.refresh(); // throttled to once per 10 minutes inside the service
      agenda.refresh(widget.shell.island.calendarFeeds); // likewise
    });
  }

  @override
  void dispose() {
    widget.shell.view.removeListener(_onViewAsked);
    _clockTimer?.cancel();
    super.dispose();
  }

  /// The island asked for a page (after a call: the note's to-dos).
  void _onViewAsked() {
    final v = widget.shell.view.value;
    if (v == null) return;
    widget.shell.view.value = null;
    if (v == 'notes') setState(() => _view = _View.notes);
  }

  /// Today's timed events from Google and the iCal feeds, for planning.
  List<({DateTime start, DateTime end})> _busyToday() {
    final today = dayOf(DateTime.now());
    final next = today.add(const Duration(days: 1));
    return [
      for (final e in [...g.events, ...agenda.events])
        if (!e.allDay && e.start.isBefore(next) && e.end.isAfter(today)) (start: e.start, end: e.end),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final t = _T(base.brightness == Brightness.dark);
    final prefs = _Prefs.i;
    final family = prefs.font;
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: family, fontFamilyFallback: _fontFallback),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              prefs.setSidebar(!prefs.sidebarOpen),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: t.bg,
            body: DefaultTextStyle.merge(
              style: TextStyle(fontFamily: family, fontFamilyFallback: _fontFallback),
              child: ListenableBuilder(
                listenable: Listenable.merge([p, g, prefs, notes, agenda]),
                builder: (context, _) => Column(children: [
                  _TitleBar(
                    t: t,
                    shell: widget.shell,
                    sidebarOpen: prefs.sidebarOpen,
                    onToggleSidebar: () => prefs.setSidebar(!prefs.sidebarOpen),
                    notes: notes,
                    onOpenNotes: () => setState(() => _view = _View.notes),
                  ),
                  if (p.isNew) Expanded(child: _welcome(t)) else Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final showPanel = prefs.showSchedule &&
                          c.maxWidth > 1080 &&
                          _view != _View.account &&
                          _view != _View.settings &&
                          _view != _View.notes &&
                          _view != _View.calendar;
                      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          width: prefs.sidebarOpen ? 232 : 0,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: 232,
                              maxWidth: 232,
                              child: _Sidebar(
                                t: t,
                                view: _view,
                                shutdown: p.shutdownToday,
                                onView: (v) => setState(() => _view = v),
                                onMap: widget.shell.showMap,
                                isDark: widget.isDark,
                                onDark: widget.onDarkChanged,
                                g: g,
                                notes: notes,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: _content(t)),
                        if (showPanel) _SchedulePanel(t: t, p: p, g: g),
                      ]);
                    }),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(_T t) {
    final island = widget.shell.island;
    return ListenableBuilder(
      listenable: island,
      builder: (context, _) => _WelcomeView(
        t: t,
        p: p,
        g: g,
        feeds: [for (final f in island.calendarFeeds) f.label],
        onAddFeed: (label, url) => island.addFeed(CalendarFeed(label, url)),
        onDone: () => setState(() {
          _view = _View.home;
          p.finishWelcome();
        }),
      ),
    );
  }

  Widget _content(_T t) {
    switch (_view) {
      case _View.home:
        return _boardView(t);
      case _View.focus:
        return _FocusView(t: t, p: p);
      case _View.planning:
        return _PlanningView(t: t, p: p, busy: _busyToday(), prefs: _Prefs.i);
      case _View.tasks:
        return _TaskListView(t: t, p: p);
      case _View.shutdown:
        return _ShutdownView(t: t, p: p, onMap: widget.shell.showMap);
      case _View.week:
        return _WeekView(
          t: t,
          p: p,
          onOpenDay: (offset) => setState(() {
            _startOffset = offset;
            _view = _View.home;
          }),
        );
      case _View.review:
        return _ReviewView(t: t, p: p);
      case _View.account:
        return _AccountView(t: t, g: g);
      case _View.notes:
        return _NotesView(t: t, notes: notes, p: p);
      case _View.calendar:
        return _CalendarView(t: t, g: g, p: p, onAccount: () => setState(() => _view = _View.account));
      case _View.settings:
        return _SettingsView(
          t: t,
          prefs: _Prefs.i,
          isDark: widget.isDark,
          onDark: widget.onDarkChanged,
          g: g,
          onAccount: () => setState(() => _view = _View.account),
        );
    }
  }

  /// The board fills whatever width it gets: as many day columns as fit
  /// comfortably (up to three), sharing the space evenly, so no day is ever
  /// cut off by the window edge or the schedule panel.
  Widget _boardView(_T t) {
    final today = dayOf(DateTime.now());
    final first = today.add(Duration(days: _startOffset));
    final title = _startOffset == 0 ? 'Today' : '${monthNames[first.month - 1]} ${first.day}';
    final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: _ts(t.text, 30, w: FontWeight.w700, ls: -0.8, h: 1.1)),
      const SizedBox(height: 4),
      Text('${dayNames[first.weekday - 1]}, ${monthNames[first.month - 1]} ${first.day}', style: _ts(t.sub, 14)),
    ]);
    final controls = Row(mainAxisSize: MainAxisSize.min, children: [
      _IconBtn(t, Icons.chevron_left_rounded, 'Previous day', () => setState(() => _startOffset--), size: 22),
      _IconBtn(t, Icons.chevron_right_rounded, 'Next day', () => setState(() => _startOffset++), size: 22),
      const SizedBox(width: 8),
      _Btn(t, 'Today', _startOffset == 0 ? null : () => setState(() => _startOffset = 0),
          compact: true, icon: Icons.today_outlined),
      const SizedBox(width: 8),
      _FilterButton(
        t: t,
        tag: _tag,
        hideDone: _hideDone,
        onTag: (v) => setState(() => _tag = v),
        onHide: () => setState(() => _hideDone = !_hideDone),
      ),
      const SizedBox(width: 8),
      _Seg(t, const ['Board', 'List'], _board ? 0 : 1, (i) => setState(() => _board = i == 0)),
    ]);

    return LayoutBuilder(builder: (context, c) {
      // Tighter margins on small windows.
      final pad = c.maxWidth < 700 ? 20.0 : 32.0;
      const gap = 24.0, minCol = 260.0;
      final avail = math.max(0.0, c.maxWidth - 2 * pad);
      final count = _board ? ((avail + gap) / (minCol + gap)).floor().clamp(1, 3) : 1;
      final days = [for (var i = 0; i < count; i++) first.add(Duration(days: i))];

      Widget column(DateTime d) {
        var tasks = p.forDay(d);
        if (_tag != 'all') tasks = tasks.where((x) => x.tag == _tag).toList();
        if (_hideDone) tasks = tasks.where((x) => !x.done).toList();
        return _DayColumn(t: t, p: p, g: g, date: d, tasks: tasks, isToday: d == today);
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 30, pad, 0),
          // Controls sit beside the title when there is room, under it when not.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [heading, controls],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 26, pad, 24),
            child: _board
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Expanded(child: column(days[i])),
                    ],
                  ])
                : Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: math.min(avail, 720), child: column(days.first)),
                  ),
          ),
        ),
      ]);
    });
  }
}
