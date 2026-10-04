import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform, Process, ProcessStartMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../aod/sky_toggle.dart';
import 'google_service.dart';
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

enum _View { home, focus, planning, tasks, shutdown, week, review, account, settings, notes }

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

  @override
  void initState() {
    super.initState();
    _Prefs.i.load();
    g.refresh();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      g.refresh(); // throttled to once per 10 minutes inside the service
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
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
                listenable: Listenable.merge([p, g, prefs, notes]),
                builder: (context, _) => Column(children: [
                  _TitleBar(
                    t: t,
                    shell: widget.shell,
                    sidebarOpen: prefs.sidebarOpen,
                    onToggleSidebar: () => prefs.setSidebar(!prefs.sidebarOpen),
                    notes: notes,
                    onOpenNotes: () => setState(() => _view = _View.notes),
                  ),
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final showPanel = prefs.showSchedule &&
                          c.maxWidth > 1080 &&
                          _view != _View.account &&
                          _view != _View.settings &&
                          _view != _View.notes;
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

  Widget _content(_T t) {
    switch (_view) {
      case _View.home:
        return _boardView(t);
      case _View.focus:
        return _FocusView(t: t, p: p);
      case _View.planning:
        return _PlanningView(t: t, p: p);
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
        return _NotesView(t: t, notes: notes);
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

  Widget _boardView(_T t) {
    final today = dayOf(DateTime.now());
    final count = _board ? 3 : 1;
    final days = [for (var i = 0; i < count; i++) today.add(Duration(days: _startOffset + i))];
    final first = days.first;
    final title = _startOffset == 0 ? 'Today' : '${_monthNames[first.month - 1]} ${first.day}';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _ts(t.text, 30, w: FontWeight.w700, ls: -0.8, h: 1.1)),
            const SizedBox(height: 4),
            Text('${_dayNames[first.weekday - 1]}, ${_monthNames[first.month - 1]} ${first.day}',
                style: _ts(t.sub, 14)),
          ]),
          const Spacer(),
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
        ]),
      ),
      Expanded(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(32, 26, 32, 24),
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 24),
          itemBuilder: (_, i) {
            var tasks = p.forDay(days[i]);
            if (_tag != 'all') tasks = tasks.where((x) => x.tag == _tag).toList();
            if (_hideDone) tasks = tasks.where((x) => !x.done).toList();
            return SizedBox(
              width: _board ? 316 : 640,
              child: _DayColumn(
                t: t,
                p: p,
                g: g,
                date: days[i],
                tasks: tasks,
                isToday: days[i] == today,
              ),
            );
          },
        ),
      ),
    ]);
  }
}
