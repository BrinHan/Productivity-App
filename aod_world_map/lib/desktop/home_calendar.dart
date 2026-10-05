part of 'home_page.dart';

/// Calendar page modelled on Notion Calendar: a rail with a mini month, the
/// calendar and task lists, a Day / Week / Month grid, and a panel that
/// slides in from the right to read or edit the selected item.
///
/// Editing: click or drag on empty time to create, drag an event to move
/// it, drag its bottom edge to resize, drag all-day items and tasks between
/// days. Shortcuts: D W M switch view, T today, J / K (or arrows) page,
/// C new event, ` hides the rail, Esc closes the panel.

enum _CalMode { day, week, month }

const _calRed = Color(0xFFEB5757);
const _calTaskBlue = Color(0xFF5B8DEF);
const _calShortDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _calMiniDays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const _calPlannerId = '__planner', _calGTasksId = '__gtasks';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime _sunday(DateTime d) => dayOf(d).subtract(Duration(days: d.weekday % 7));

int _daysBetween(DateTime a, DateTime b) => (dayOf(b).difference(dayOf(a)).inHours / 24).round();

/// Calendar arithmetic that survives daylight-saving changes.
DateTime _shift(DateTime x, {int days = 0, int minutes = 0}) =>
    DateTime(x.year, x.month, x.day + days, x.hour, x.minute + minutes);

int _snap(double m, {bool up = false}) => (up ? (m / 15).ceil() : (m / 15).floor()) * 15;

String _dateLabel(DateTime d) => '${_calShortDays[d.weekday % 7]}, ${_monthNames[d.month - 1].substring(0, 3)} ${d.day}';

String _tzLabel() {
  final o = DateTime.now().timeZoneOffset;
  final h = o.inMinutes ~/ 60, m = o.inMinutes.abs() % 60;
  final sign = o.isNegative ? '-' : '+';
  return 'GMT$sign${h.abs()}${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
}

/// A to-do on the calendar: a planner task or a dated Google task.
class _CalTask {
  _CalTask.planner(Task t)
      : key = 'p:${t.id}',
        title = t.title,
        day = dayOf(t.day),
        done = t.done,
        planner = t,
        google = null;
  _CalTask.google(GoogleTask t)
      : key = 'g:${t.id}',
        title = t.title,
        day = t.due!,
        done = false,
        planner = null,
        google = t;
  final String key, title;
  final DateTime day;
  final bool done;
  final Task? planner;
  final GoogleTask? google;

  Color color(_T t) => planner != null ? t.accent : _calTaskBlue;
}

/// What a drag between days carries.
class _CalDrag {
  const _CalDrag({this.e, this.task});
  final CalEvent? e;
  final _CalTask? task;
}

class _CalendarView extends StatefulWidget {
  const _CalendarView({required this.t, required this.g, required this.p, required this.onAccount});
  final _T t;
  final GoogleService g;
  final PlannerModel p;
  final VoidCallback onAccount;

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  _CalMode _mode = _CalMode.week;
  DateTime _anchor = dayOf(DateTime.now());
  int _dir = 0; // -1 back, 1 forward, 0 view change: decides the slide
  bool _rail = true;
  CalEvent? _draft; // a new event that has not been saved
  Object? _sel; // CalEvent, or a task key
  Object? _shown; // what the panel draws, kept while it slides away
  late double _scroll;
  final _focus = FocusNode(debugLabel: 'calendar');

  _T get t => widget.t;
  GoogleService get g => widget.g;
  PlannerModel get p => widget.p;

  @override
  void initState() {
    super.initState();
    _mode = _CalMode.values[_Prefs.i.calMode.clamp(0, 2)];
    final n = DateTime.now();
    _scroll = math.max(0, (n.hour - 2) * _CalTimeGrid.rowH).toDouble();
    // The page root already holds focus, so autofocus alone would not win.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- range

  DateTime get _from => switch (_mode) {
        _CalMode.day => _anchor,
        _CalMode.week => _sunday(_anchor),
        _CalMode.month => _sunday(DateTime(_anchor.year, _anchor.month)),
      };

  int get _span => switch (_mode) { _CalMode.day => 1, _CalMode.week => 7, _CalMode.month => 42 };

  List<DateTime> get _days => [for (var i = 0; i < _span; i++) DateTime(_from.year, _from.month, _from.day + i)];

  String get _title {
    if (_mode == _CalMode.week) {
      final a = _from, b = _days.last;
      if (a.month != b.month) {
        final y = a.year == b.year ? '' : ' ${a.year}';
        return '${_monthNames[a.month - 1].substring(0, 3)}$y – ${_monthNames[b.month - 1].substring(0, 3)} ${b.year}';
      }
    }
    return '${_monthNames[_anchor.month - 1]} ${_anchor.year}';
  }

  /// Visible events (plus the draft), de-duplicated across month caches.
  ({List<CalEvent> items, bool syncing}) _events() {
    final days = _days;
    final end = days.last.add(const Duration(days: 1));
    final seen = <String>{};
    final out = <CalEvent>[];
    var syncing = false;
    var m = DateTime(days.first.year, days.first.month);
    final hidden = _Prefs.i.calHidden;
    while (m.isBefore(end)) {
      final list = g.monthEvents(m.year, m.month);
      if (list == null) syncing = true;
      for (final e in list ?? const <CalEvent>[]) {
        if (hidden.contains(e.calId)) continue;
        if (!e.end.isAfter(days.first) && !(e.start == e.end && !e.start.isBefore(days.first))) continue;
        if (!e.start.isBefore(end)) continue;
        if (seen.add('${e.calId}|${e.id}|${e.start.millisecondsSinceEpoch}')) out.add(e);
      }
      m = DateTime(m.year, m.month + 1);
    }
    if (_draft != null) out.add(_draft!);
    return (items: out, syncing: syncing && g.signedIn && g.canCalendar);
  }

  List<_CalTask> _tasks() {
    final days = _days;
    final first = days.first, end = days.last.add(const Duration(days: 1));
    bool inside(DateTime d) => !d.isBefore(first) && d.isBefore(end);
    final hidden = _Prefs.i.calHidden;
    return [
      if (!hidden.contains(_calPlannerId))
        for (final x in p.tasks)
          if (inside(x.day)) _CalTask.planner(x),
      if (!hidden.contains(_calGTasksId))
        for (final x in g.datedTasks)
          if (inside(x.due!)) _CalTask.google(x),
    ];
  }

  _CalTask? _findTask(String key) {
    if (key.startsWith('p:')) {
      for (final x in p.tasks) {
        if ('p:${x.id}' == key) return _CalTask.planner(x);
      }
    } else {
      for (final x in g.datedTasks) {
        if ('g:${x.id}' == key) return _CalTask.google(x);
      }
    }
    return null;
  }

  /// The current copy of a selected event (it may have been edited since).
  CalEvent? _resolve(CalEvent s, List<CalEvent> visible) {
    if (s.isDraft) return _draft;
    for (final e in visible) {
      if (e.same(s)) return e;
    }
    return s;
  }

  GoogleCalendar? _cal(String id) => g.calendars.where((c) => c.id == id).firstOrNull;

  GoogleCalendar? get _defaultCal =>
      g.calendars.where((c) => c.writable && c.primary).firstOrNull ?? g.calendars.where((c) => c.writable).firstOrNull;

  bool get _canCreate => g.canEditCalendar && _defaultCal != null;

  bool _canEdit(CalEvent e) => e.isDraft || (g.canEditCalendar && (_cal(e.calId)?.writable ?? false));

  Color _color(CalEvent e) {
    if (e.color != null) return Color(e.color!);
    final c = _cal(e.calId) ?? (e.isDraft ? _defaultCal : null);
    return c == null ? const Color(0xFF4A9EE8) : Color(c.color);
  }

  bool _isSel(CalEvent e) {
    final s = _sel;
    return s is CalEvent && (s.isDraft ? e.isDraft : e.same(s));
  }

  String? get _selTask => _sel is String ? _sel as String : null;

  // -------------------------------------------------------- navigation

  void _page(int d) => setState(() {
        _dir = d;
        _anchor = switch (_mode) {
          _CalMode.day => _anchor.add(Duration(days: d)),
          _CalMode.week => _anchor.add(Duration(days: 7 * d)),
          _CalMode.month => DateTime(_anchor.year, _anchor.month + d),
        };
      });

  void _goto(DateTime d, {_CalMode? mode}) => setState(() {
        final day = dayOf(d);
        _dir = day.isAfter(_anchor) ? 1 : (day.isBefore(_anchor) ? -1 : 0);
        if (mode != null && mode != _mode) {
          _dir = 0;
          _mode = mode;
          _Prefs.i.setCalMode(mode.index);
        }
        _anchor = day;
      });

  void _setMode(_CalMode m) {
    if (m == _mode) return;
    setState(() {
      _dir = 0;
      _mode = m;
    });
    _Prefs.i.setCalMode(m.index);
  }

  // ----------------------------------------------------------- editing

  /// Click selects, a second click deselects. Picking anything else drops
  /// an unsaved draft; clicking the draft itself keeps it open.
  void _select(Object? s) => setState(() {
        final isDraft = s is CalEvent && s.isDraft;
        final same = s is CalEvent ? _isSel(s) : (s != null && s == _sel);
        if (!isDraft) _draft = null;
        _sel = same && !isDraft ? null : s;
        if (_sel != null) _shown = _sel;
      });

  void _closePanel() => setState(() {
        _sel = null;
        _draft = null;
      });

  void _newDraft(DateTime start, DateTime end, {bool allDay = false}) {
    if (!_canCreate) {
      _flash(g.signedIn
          ? (g.canEditCalendar ? 'None of your calendars can be edited.' : 'Reconnect Google once to add events.')
          : 'Connect Google to add events.');
      return;
    }
    final d = CalEvent('', _defaultCal!.id, '', start, end, allDay, '', null);
    setState(() {
      _draft = d;
      _sel = d;
      _shown = d;
    });
  }

  void _newAtNextHour() {
    final n = DateTime.now();
    final base = _mode == _CalMode.month || _anchor == dayOf(n) ? dayOf(n) : _anchor;
    final hour = base == dayOf(n) ? math.min(n.hour + 1, 23) : 9;
    final s = DateTime(base.year, base.month, base.day, hour);
    if (_mode == _CalMode.month && base != _anchor) _anchor = base;
    _newDraft(s, s.add(const Duration(hours: 1)));
  }

  void _change(CalEvent old, CalEvent next) {
    if (old.isDraft) {
      setState(() => _draft = next);
      return;
    }
    if (_isSel(old)) setState(() => _sel = next);
    g.updateEvent(old, next);
  }

  void _drop(_CalDrag d, DateTime day) {
    final e = d.e, task = d.task;
    if (e != null) {
      final diff = _daysBetween(e.start, day);
      if (diff == 0 || !_canEdit(e)) return;
      _change(e, e.copyWith(start: _shift(e.start, days: diff), end: _shift(e.end, days: diff)));
    } else if (task != null) {
      final diff = _daysBetween(task.day, day);
      if (diff == 0) return;
      if (task.planner != null) {
        p.moveDay(task.planner!, diff);
      } else {
        g.updateTask(task.google!, due: day);
      }
    }
  }

  void _toggleTask(_CalTask x) {
    if (x.planner != null) {
      p.toggle(x.planner!);
    } else {
      g.completeTask(x.google!);
      if (_sel == x.key) _closePanel();
    }
  }

  Future<void> _save(CalEvent old, CalEvent next) async {
    if (old.isDraft) {
      setState(() {
        _draft = null;
        _sel = null;
      });
      final real = await g.createEvent(next);
      if (real != null && mounted && _sel == null) setState(() => _sel = _shown = real);
    } else {
      if (_isSel(old)) setState(() => _sel = _shown = next);
      await g.updateEvent(old, next);
    }
  }

  void _delete(CalEvent e) {
    _closePanel();
    g.deleteEvent(e);
    _undoBar('Deleted "${e.title.isEmpty ? 'Untitled' : e.title}"', () => g.createEvent(e.copyWith(id: '')));
  }

  void _createTask(String title, DateTime day, bool google) {
    _closePanel();
    if (title.trim().isEmpty) return;
    if (google) {
      g.createTask(title.trim(), day);
    } else {
      p.add(day, title.trim());
    }
  }

  void _deleteTask(_CalTask x) {
    _closePanel();
    if (x.planner != null) {
      _deleteWithUndo(context, t, p, x.planner!);
    } else {
      final gt = x.google!;
      g.deleteTask(gt);
      _undoBar('Deleted "${gt.title}"', () => g.createTask(gt.title, gt.due!));
    }
  }

  void _undoBar(String text, VoidCallback undo) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 360,
      backgroundColor: t.raised,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm), side: BorderSide(color: t.line)),
      content: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13)),
      action: SnackBarAction(label: 'Undo', textColor: t.accent, onPressed: undo),
    ));
  }

  void _flash(String text) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 360,
      backgroundColor: t.raised,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm), side: BorderSide(color: t.line)),
      content: Text(text, style: _ts(t.text, 13)),
    ));
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape && (_sel != null || _draft != null)) {
      _closePanel();
      return KeyEventResult.handled;
    }
    // Letters belong to a text field when one is focused.
    if (!_focus.hasPrimaryFocus) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyD) {
      _setMode(_CalMode.day);
    } else if (k == LogicalKeyboardKey.keyW) {
      _setMode(_CalMode.week);
    } else if (k == LogicalKeyboardKey.keyM) {
      _setMode(_CalMode.month);
    } else if (k == LogicalKeyboardKey.keyT) {
      _goto(DateTime.now());
    } else if (k == LogicalKeyboardKey.keyC) {
      _newAtNextHour();
    } else if (k == LogicalKeyboardKey.keyJ || k == LogicalKeyboardKey.arrowRight) {
      _page(1);
    } else if (k == LogicalKeyboardKey.keyK || k == LogicalKeyboardKey.arrowLeft) {
      _page(-1);
    } else if (k == LogicalKeyboardKey.backquote) {
      setState(() => _rail = !_rail);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final ev = _events();
    final tasks = _tasks();
    final key = '${_mode.name}-${_from.millisecondsSinceEpoch}';
    final reduce = MediaQuery.of(context).disableAnimations;
    final grid = _mode == _CalMode.month
        ? _CalMonthGrid(
            t: t,
            month: _anchor.month,
            days: _days,
            events: ev.items,
            tasks: tasks,
            color: _color,
            canEdit: _canEdit,
            isSel: _isSel,
            selTask: _selTask,
            onSelect: _select,
            onToggleTask: _toggleTask,
            onOpenDay: (d) => _goto(d, mode: _CalMode.day),
            onCreate: (d) => _newDraft(d, d.add(const Duration(days: 1)), allDay: true),
            onDrop: _drop,
          )
        : _CalTimeGrid(
            t: t,
            days: _days,
            events: ev.items,
            tasks: tasks,
            color: _color,
            newColor: _defaultCal == null ? t.accent : Color(_defaultCal!.color),
            canEdit: _canEdit,
            canCreate: _canCreate,
            isSel: _isSel,
            selTask: _selTask,
            onSelect: _select,
            onToggleTask: _toggleTask,
            onOpenDay: (d) => _goto(d, mode: _CalMode.day),
            onCreate: (s, e, allDay) => _newDraft(s, e, allDay: allDay),
            onChange: _change,
            onDrop: _drop,
            scroll: _scroll,
            onScroll: (v) => _scroll = v,
          );

    final banner = _banner();
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _slideOpen(
            open: _rail,
            width: 224,
            alignment: Alignment.centerLeft,
            child: _CalRail(
              t: t,
              g: g,
              anchor: _anchor,
              range: _days,
              mode: _mode,
              onPick: _goto,
              onToggle: (id) => _Prefs.i.toggleCal(id),
              onAccount: widget.onAccount,
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _header(ev.syncing),
              if (banner != null) banner,
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: reduce ? 120 : 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
                    transitionBuilder: (child, a) {
                      if (reduce || _dir == 0) return FadeTransition(opacity: a, child: child);
                      // In from the side you are heading, out the other way.
                      final incoming = child.key == ValueKey(key);
                      final dx = (incoming ? 0.035 : -0.035) * _dir;
                      return FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(key: ValueKey(key), child: grid),
                  ),
                ),
              ),
            ]),
          ),
          _slideOpen(
            open: _sel != null,
            width: 320,
            alignment: Alignment.centerRight,
            child: _panel(ev.items),
          ),
        ]),
      ),
    );
  }

  Widget _panel(List<CalEvent> visible) {
    final s = _shown;
    if (s is CalEvent) {
      final e = _resolve(s, visible);
      if (e == null) return const SizedBox.shrink();
      return _CalEventPanel(
        key: ValueKey(e.isDraft ? 'draft' : '${e.calId}|${e.id}'),
        t: t,
        g: g,
        e: e,
        editable: _canEdit(e),
        color: _color(e),
        onDraftChanged: (n) => setState(() => _draft = n),
        onSave: (n) => _save(e, n),
        onDelete: () => _delete(e),
        onCreateTask: _createTask,
        onClose: _closePanel,
        onReconnect: g.signIn,
      );
    }
    if (s is String) {
      final x = _findTask(s);
      if (x == null) return const SizedBox.shrink();
      return _CalTaskPanel(
        key: ValueKey(s),
        t: t,
        task: x,
        onRename: (v) => x.planner != null ? p.rename(x.planner!, v) : g.updateTask(x.google!, title: v),
        onMove: (d) => _drop(_CalDrag(task: x), d),
        onToggle: () => _toggleTask(x),
        onDelete: () => _deleteTask(x),
        onClose: _closePanel,
      );
    }
    return const SizedBox.shrink();
  }

  /// Width-animated side surface that enters and leaves along the same edge.
  Widget _slideOpen({required bool open, required double width, required Alignment alignment, required Widget child}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: open ? width : 0,
        child: ClipRect(
          child: OverflowBox(alignment: alignment, minWidth: width, maxWidth: width, child: child),
        ),
      );

  Widget _header(bool syncing) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 16, 10),
        child: Row(children: [
          if (!_rail) ...[
            _IconBtn(t, Icons.view_sidebar_outlined, 'Show sidebar  `', () => setState(() => _rail = true), size: 17),
            const SizedBox(width: 6),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(_title, key: ValueKey(_title), style: _ts(t.text, 22, w: FontWeight.w700, ls: -0.5)),
          ),
          const SizedBox(width: 12),
          AnimatedOpacity(
            opacity: syncing || g.loading ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Text('Syncing', style: _ts(t.faint, 12)),
          ),
          const Spacer(),
          _IconBtn(t, Icons.add_rounded, 'New event  C', _newAtNextHour, size: 19),
          const SizedBox(width: 4),
          _CalModeMenu(t: t, mode: _mode, onPick: _setMode),
          const SizedBox(width: 8),
          _Btn(t, 'Today', () => _goto(DateTime.now()), compact: true),
          const SizedBox(width: 6),
          _IconBtn(t, Icons.chevron_left_rounded, 'Previous  K', () => _page(-1), size: 20),
          _IconBtn(t, Icons.chevron_right_rounded, 'Next  J', () => _page(1), size: 20),
          if (_rail)
            _IconBtn(t, Icons.view_sidebar_outlined, 'Hide sidebar  `', () => setState(() => _rail = false), size: 17),
        ]),
      );

  Widget? _banner() {
    Widget bar(String text, String action, VoidCallback? onTap, {bool warn = false}) => Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 16, 10),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: warn ? t.warn.withValues(alpha: 0.08) : t.surface,
            borderRadius: BorderRadius.circular(_rSm),
            border: Border.all(color: warn ? t.warn.withValues(alpha: 0.4) : t.line),
          ),
          child: Row(children: [
            Icon(warn ? Icons.error_outline_rounded : Icons.event_outlined, size: 16, color: warn ? t.warn : t.sub),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: _ts(warn ? t.text : t.sub, 13))),
            _Btn(t, action, onTap, compact: true),
          ]),
        );
    if (!g.signedIn) return bar('Connect Google to see and edit your calendar here.', 'Connect', widget.onAccount);
    if (!g.canEditCalendar) {
      return bar(
        g.canCalendar
            ? 'Orbit can only read your calendar. Reconnect Google once to add and edit events.'
            : 'Calendar access was not granted. Reconnect Google to see your events.',
        g.busy ? 'Waiting for browser' : 'Reconnect',
        g.busy ? null : g.signIn,
      );
    }
    final err = g.actionError ?? g.calendarError;
    if (err != null) {
      return bar(err, 'Retry', () {
        g.clearActionError();
        g.refresh(force: true);
      }, warn: true);
    }
    return null;
  }
}

// ---------------------------------------------------------------- header

class _CalModeMenu extends StatelessWidget {
  const _CalModeMenu({required this.t, required this.mode, required this.onPick});
  final _T t;
  final _CalMode mode;
  final ValueChanged<_CalMode> onPick;

  static const _labels = {_CalMode.day: 'Day', _CalMode.week: 'Week', _CalMode.month: 'Month'};
  static const _keys = {_CalMode.day: 'D', _CalMode.week: 'W', _CalMode.month: 'M'};

  @override
  Widget build(BuildContext context) => PopupMenuButton<_CalMode>(
        tooltip: 'Change view',
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rSm + 2),
          side: BorderSide(color: t.line),
        ),
        onSelected: onPick,
        itemBuilder: (_) => [
          for (final m in _CalMode.values)
            PopupMenuItem(
              value: m,
              height: 36,
              child: SizedBox(
                width: 120,
                child: Row(children: [
                  Text(_labels[m]!, style: _ts(t.text, 13, w: m == mode ? FontWeight.w600 : FontWeight.w500)),
                  const Spacer(),
                  _Kbd(t, _keys[m]!),
                ]),
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_rSm),
            border: Border.all(color: t.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_labels[mode]!, style: _ts(t.text, 13, w: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: t.sub),
          ]),
        ),
      );
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.t, this.label);
  final _T t;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: _ts(t.sub, 11, w: FontWeight.w600)),
      );
}

/// Hover state for the custom calendar surfaces.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder, this.onTap});
  final Widget Function(bool hover) builder;
  final VoidCallback? onTap;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.builder(_h)),
      );
}

/// Drag handle for moving an item to another day. The drag only starts past
/// the touch slop, so a plain click still selects.
Widget _dayDraggable(BuildContext context, _CalDrag data, Widget child, {bool enabled = true, double width = 180}) {
  if (!enabled) return child;
  final style = DefaultTextStyle.of(context).style;
  return Draggable<_CalDrag>(
    data: data,
    feedback: DefaultTextStyle(
      style: style,
      child: Material(
        type: MaterialType.transparency,
        child: Opacity(opacity: 0.92, child: SizedBox(width: width, height: 20, child: child)),
      ),
    ),
    childWhenDragging: Opacity(opacity: 0.35, child: child),
    child: child,
  );
}

// ------------------------------------------------------------ mini month

/// Small month picker used by the rail and the date fields.
class _MiniMonth extends StatefulWidget {
  const _MiniMonth({
    required this.t,
    required this.focus,
    required this.onPick,
    this.range = const {},
    this.band = false,
  });
  final _T t;
  final DateTime focus; // month to show; also the picked day
  final Set<DateTime> range; // days to highlight
  final bool band; // highlight whole weeks instead of single days
  final ValueChanged<DateTime> onPick;

  @override
  State<_MiniMonth> createState() => _MiniMonthState();
}

class _MiniMonthState extends State<_MiniMonth> {
  late DateTime _month = DateTime(widget.focus.year, widget.focus.month);

  @override
  void didUpdateWidget(_MiniMonth old) {
    super.didUpdateWidget(old);
    // Follow the main grid when it pages to another month.
    if (old.focus != widget.focus) _month = DateTime(widget.focus.year, widget.focus.month);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final today = dayOf(DateTime.now());
    final start = _sunday(_month);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        const SizedBox(width: 4),
        Text('${_monthNames[_month.month - 1]} ${_month.year}', style: _ts(t.text, 13, w: FontWeight.w600)),
        const Spacer(),
        _IconBtn(t, Icons.keyboard_arrow_up_rounded, 'Previous month',
            () => setState(() => _month = DateTime(_month.year, _month.month - 1)), size: 16),
        _IconBtn(t, Icons.keyboard_arrow_down_rounded, 'Next month',
            () => setState(() => _month = DateTime(_month.year, _month.month + 1)), size: 16),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (final d in _calMiniDays)
          Expanded(child: Center(child: Text(d, style: _ts(t.faint, 10.5, w: FontWeight.w600)))),
      ]),
      const SizedBox(height: 4),
      for (var w = 0; w < 6; w++)
        Builder(builder: (_) {
          final week = [for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + w * 7 + i)];
          final band = widget.band && week.any(widget.range.contains);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 1),
            decoration: BoxDecoration(
              color: band ? t.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              for (final d in week)
                Expanded(
                  child: _Hover(
                    onTap: () => widget.onPick(d),
                    builder: (h) {
                      final isToday = d == today;
                      final picked = !widget.band && widget.range.contains(d);
                      final other = d.month != _month.month;
                      return Container(
                        height: 24,
                        margin: const EdgeInsets.all(1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isToday ? _calRed : (picked || h ? t.line : Colors.transparent),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('${d.day}',
                            style: _ts(
                              isToday ? Colors.white : (other ? t.faint : t.text),
                              11.5,
                              w: isToday || !other ? FontWeight.w600 : FontWeight.w500,
                              tab: true,
                            )),
                      );
                    },
                  ),
                ),
            ]),
          );
        }),
    ]);
  }
}

Future<DateTime?> _pickDate(BuildContext context, _T t, DateTime initial) => showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => Dialog(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rLg), side: BorderSide(color: t.line)),
        child: SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _MiniMonth(t: t, focus: initial, range: {dayOf(initial)}, onPick: (d) => Navigator.of(ctx).pop(d)),
          ),
        ),
      ),
    );

// ------------------------------------------------------------------ rail

class _CalRail extends StatelessWidget {
  const _CalRail({
    required this.t,
    required this.g,
    required this.anchor,
    required this.range,
    required this.mode,
    required this.onPick,
    required this.onToggle,
    required this.onAccount,
  });
  final _T t;
  final GoogleService g;
  final DateTime anchor;
  final List<DateTime> range;
  final _CalMode mode;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<String> onToggle;
  final VoidCallback onAccount;

  Widget _row(String id, Color col, String name, {String? note}) {
    final off = _Prefs.i.calHidden.contains(id);
    return _Hover(
      onTap: () => onToggle(id),
      builder: (h) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(color: h ? t.raised : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: off ? 0.45 : 1,
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: off ? Colors.transparent : col,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: col, width: 1.5),
              ),
              child: off ? null : const Icon(Icons.check_rounded, size: 10, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Expanded(
              child:
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13, w: FontWeight.w600)),
            ),
            if (off)
              Icon(Icons.visibility_off_outlined, size: 14, color: t.faint)
            else if (note != null)
              Text(note, style: _ts(t.faint, 11.5)),
          ]),
        ),
      ),
    );
  }

  Widget _heading(String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.sub, 12, w: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: t.side, border: Border(right: BorderSide(color: t.line))),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _MiniMonth(
              t: t,
              focus: anchor,
              range: mode == _CalMode.month ? const {} : range.toSet(),
              band: mode == _CalMode.week,
              onPick: onPick,
            ),
            const SizedBox(height: 18),
            _heading(g.email ?? 'Calendars'),
            if (g.calendars.isEmpty)
              _Hover(
                onTap: g.signedIn ? null : onAccount,
                builder: (h) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  decoration:
                      BoxDecoration(color: h ? t.raised : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Icon(g.signedIn ? Icons.sync_rounded : Icons.add_rounded, size: 16, color: t.sub),
                    const SizedBox(width: 8),
                    Text(g.signedIn ? 'Loading calendars' : 'Add calendar account', style: _ts(t.sub, 13)),
                  ]),
                ),
              ),
            for (final c in g.calendars)
              _row(c.id, Color(c.color), c.name, note: c.primary ? 'Default' : (c.writable ? null : 'Read-only')),
            const SizedBox(height: 18),
            _heading('Tasks'),
            _row(_calPlannerId, t.accent, 'Daily planner'),
            if (g.canTasks) _row(_calGTasksId, _calTaskBlue, 'Google Tasks'),
          ]),
        ),
      );
}

// ------------------------------------------------------------- time grid

class _CalSeg {
  _CalSeg(this.e, this.s, this.end);
  final CalEvent e;
  final DateTime s, end;
  int level = 0, slot = 0, slots = 1;
  List<_CalSeg> group = const [];
}

/// Lays out one day's timed events the way Notion does: events that start
/// together share the width, an event that starts inside another one is
/// stacked on top of it with an indent.
List<_CalSeg> _layoutDay(List<CalEvent> events, DateTime day) {
  final next = day.add(const Duration(days: 1));
  final segs = <_CalSeg>[];
  for (final e in events) {
    if (e.allDay) continue;
    final s = e.start.isBefore(day) ? day : e.start;
    var en = e.end.isAfter(next) ? next : e.end;
    if (!s.isBefore(next)) continue;
    if (!en.isAfter(s)) {
      if (e.start.isBefore(day)) continue;
      en = s.add(const Duration(minutes: 30));
    }
    segs.add(_CalSeg(e, s, en));
  }
  segs.sort((a, b) {
    final c = a.s.compareTo(b.s);
    return c != 0 ? c : b.end.compareTo(a.end);
  });
  final placed = <_CalSeg>[];
  for (final g in segs) {
    final over = [
      for (final p in placed)
        if (p.end.isAfter(g.s)) p,
    ];
    final twin = over.where((p) => g.s.difference(p.s).inMinutes < 30).toList();
    if (twin.isNotEmpty) {
      final host = twin.first;
      g
        ..level = host.level
        ..group = host.group;
      host.group.add(g);
    } else {
      g
        ..level = over.isEmpty ? 0 : over.map((p) => p.level).reduce(math.max) + 1
        ..group = [g];
    }
    placed.add(g);
  }
  for (final g in placed) {
    g
      ..slots = g.group.length
      ..slot = g.group.indexOf(g);
  }
  return placed;
}

enum _GridDrag { create, move, resize }

class _CalTimeGrid extends StatefulWidget {
  const _CalTimeGrid({
    required this.t,
    required this.days,
    required this.events,
    required this.tasks,
    required this.color,
    required this.newColor,
    required this.canEdit,
    required this.canCreate,
    required this.isSel,
    required this.selTask,
    required this.onSelect,
    required this.onToggleTask,
    required this.onOpenDay,
    required this.onCreate,
    required this.onChange,
    required this.onDrop,
    required this.scroll,
    required this.onScroll,
  });
  final _T t;
  final List<DateTime> days;
  final List<CalEvent> events;
  final List<_CalTask> tasks;
  final Color Function(CalEvent) color;
  final Color newColor;
  final bool Function(CalEvent) canEdit;
  final bool canCreate;
  final bool Function(CalEvent) isSel;
  final String? selTask;
  final ValueChanged<Object> onSelect;
  final ValueChanged<_CalTask> onToggleTask;
  final ValueChanged<DateTime> onOpenDay;
  final void Function(DateTime start, DateTime end, bool allDay) onCreate;
  final void Function(CalEvent old, CalEvent next) onChange;
  final void Function(_CalDrag, DateTime) onDrop;
  final double scroll;
  final ValueChanged<double> onScroll;

  static const rowH = 44.0, gutter = 56.0;

  @override
  State<_CalTimeGrid> createState() => _CalTimeGridState();
}

class _CalTimeGridState extends State<_CalTimeGrid> {
  late final ScrollController _sc = ScrollController(initialScrollOffset: widget.scroll)
    ..addListener(() => widget.onScroll(_sc.offset));
  final _stackKey = GlobalKey(), _viewKey = GlobalKey();
  Timer? _tick;
  double _colW = 1;

  _GridDrag? _kind;
  CalEvent? _orig;
  int _day0 = 0;
  double _min0 = 0;
  CalEvent? _preview;

  static const rowH = _CalTimeGrid.rowH, gutter = _CalTimeGrid.gutter;

  @override
  void initState() {
    super.initState();
    // Keep the red now-line moving.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sc.dispose();
    super.dispose();
  }

  // ------------------------------------------------- direct manipulation

  ({int day, double min}) _at(Offset global) {
    final box = _stackKey.currentContext!.findRenderObject() as RenderBox;
    final p = box.globalToLocal(global);
    final day = ((p.dx - gutter) / _colW).floor().clamp(0, widget.days.length - 1);
    final min = ((p.dy - 6) / rowH * 60).clamp(0.0, 1440.0).toDouble();
    return (day: day, min: min);
  }

  void _start(_GridDrag k, Offset global, [CalEvent? e]) {
    final a = _at(global);
    _kind = k;
    _orig = e;
    _day0 = a.day;
    _min0 = a.min;
    _update(global);
  }

  void _update(Offset global) {
    if (_kind == null) return;
    final a = _at(global);
    _autoScroll(global);
    final o = _orig;
    setState(() {
      switch (_kind!) {
        case _GridDrag.create:
          final d = widget.days[_day0];
          final lo = _snap(math.min(a.min, _min0));
          var hi = math.min(1440, _snap(math.max(a.min, _min0), up: true));
          if (hi - lo < 15) hi = lo + 15;
          _preview = CalEvent('', '', '', _shift(d, minutes: lo), _shift(d, minutes: hi), false, '', null);
        case _GridDrag.move:
          // Deltas, not absolute positions, so the grab point stays under the pointer.
          final dd = a.day - _day0;
          final dm = ((a.min - _min0) / 15).round() * 15;
          _preview = o!.copyWith(
            start: _shift(o.start, days: dd, minutes: dm),
            end: _shift(o.end, days: dd, minutes: dm),
          );
        case _GridDrag.resize:
          final dm = ((a.min - _min0) / 15).round() * 15;
          var end = _shift(o!.end, minutes: dm);
          if (end.difference(o.start).inMinutes < 15) end = o.start.add(const Duration(minutes: 15));
          _preview = o.copyWith(end: end);
      }
    });
  }

  void _end() {
    final k = _kind, o = _orig, pv = _preview;
    setState(() {
      _kind = null;
      _orig = null;
      _preview = null;
    });
    if (pv == null) return;
    if (k == _GridDrag.create) {
      widget.onCreate(pv.start, pv.end, false);
    } else if (o != null && (pv.start != o.start || pv.end != o.end)) {
      widget.onChange(o, pv);
    }
  }

  void _cancel() => setState(() {
        _kind = null;
        _orig = null;
        _preview = null;
      });

  /// Scrolls when a drag reaches the top or bottom edge of the hours.
  void _autoScroll(Offset global) {
    final vb = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (vb == null || !_sc.hasClients) return;
    final y = vb.globalToLocal(global).dy;
    final d = y < 36 ? -14.0 : (y > vb.size.height - 36 ? 14.0 : 0.0);
    if (d != 0) _sc.jumpTo((_sc.offset + d).clamp(0.0, _sc.position.maxScrollExtent).toDouble());
  }

  void _tapEmpty(Offset global) {
    if (!widget.canCreate) {
      widget.onCreate(DateTime.now(), DateTime.now(), false); // lets the page explain why not
      return;
    }
    final a = _at(global);
    final d = widget.days[a.day];
    final m = math.min(_snap(a.min / 2) * 2, 23 * 60); // half-hour slot
    widget.onCreate(_shift(d, minutes: m), _shift(d, minutes: m + 60), false);
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final t = widget.t, days = widget.days;
    final now = DateTime.now();
    final today = dayOf(now);
    final first = days.first;

    // All-day lanes: events span the days they cover, tasks sit on their day.
    final items = <({CalEvent? e, _CalTask? task, int a, int b, int lane})>[];
    final laneEnds = <int>[];
    void place(CalEvent? e, _CalTask? task, int a, int b) {
      var lane = laneEnds.indexWhere((end) => end < a);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(b);
      } else {
        laneEnds[lane] = b;
      }
      items.add((e: e, task: task, a: a, b: b, lane: lane));
    }

    final ad = widget.events.where((e) => e.allDay).toList()
      ..sort((x, y) {
        final c = x.start.compareTo(y.start);
        return c != 0 ? c : y.end.compareTo(x.end);
      });
    for (final e in ad) {
      final a = math.max(0, _daysBetween(first, e.start));
      final lastDay = e.end.isAfter(e.start) ? e.end.subtract(const Duration(minutes: 1)) : e.start;
      final b = math.min(days.length - 1, _daysBetween(first, lastDay));
      if (b >= a) place(e, null, a, b);
    }
    for (final x in widget.tasks) {
      final i = _daysBetween(first, x.day);
      if (i >= 0 && i < days.length) place(null, x, i, i);
    }
    final allDayH = math.max(1, laneEnds.length) * 22.0 + 6;
    final todayCol = days.indexOf(today);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Day labels.
      SizedBox(
        height: 30,
        child: Row(children: [
          SizedBox(
            width: gutter,
            child: Center(child: Text(_tzLabel(), style: _ts(t.faint, 10, w: FontWeight.w600))),
          ),
          for (final d in days)
            Expanded(
              child: _Hover(
                onTap: days.length > 1 ? () => widget.onOpenDay(d) : null,
                builder: (h) => Center(child: _dayLabel(t, d, d == today, h)),
              ),
            ),
          const SizedBox(width: 8),
        ]),
      ),
      // All-day row.
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: allDayH,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        child: Row(children: [
          SizedBox(
            width: gutter,
            child: Align(
              alignment: const Alignment(0, -0.4),
              child: Text('All-day', style: _ts(t.faint, 10, w: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final colW = c.maxWidth / days.length;
              return Stack(clipBehavior: Clip.none, children: [
                // Drop zones and click-to-create, one per day.
                for (var i = 0; i < days.length; i++)
                  Positioned(
                    left: colW * i,
                    top: 0,
                    bottom: 0,
                    width: colW,
                    child: DragTarget<_CalDrag>(
                      onWillAcceptWithDetails: (d) => d.data.task != null || (d.data.e?.allDay ?? false),
                      onAcceptWithDetails: (d) => widget.onDrop(d.data, days[i]),
                      builder: (context, cand, _) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onCreate(days[i], days[i].add(const Duration(days: 1)), true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            color: cand.isNotEmpty ? t.raised : Colors.transparent,
                            border: Border(left: BorderSide(color: t.line.withValues(alpha: 0.6))),
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final x in items)
                  Positioned(
                    left: colW * x.a + 2,
                    width: colW * (x.b - x.a + 1) - 4,
                    top: 3 + x.lane * 22.0,
                    height: 20,
                    child: x.e != null
                        ? _dayDraggable(
                            context,
                            _CalDrag(e: x.e),
                            _AllDayChip(
                              t: t,
                              e: x.e!,
                              color: widget.color(x.e!),
                              selected: widget.isSel(x.e!),
                              onTap: () => widget.onSelect(x.e!),
                            ),
                            enabled: widget.canEdit(x.e!) && !x.e!.isDraft,
                            width: colW - 4,
                          )
                        : _dayDraggable(
                            context,
                            _CalDrag(task: x.task),
                            _TaskChip(
                              t: t,
                              task: x.task!,
                              selected: widget.selTask == x.task!.key,
                              onTap: () => widget.onSelect(x.task!.key),
                              onToggle: () => widget.onToggleTask(x.task!),
                            ),
                            width: colW - 4,
                          ),
                  ),
              ]);
            }),
          ),
          const SizedBox(width: 8),
        ]),
      ),
      // Hours.
      Expanded(
        child: SingleChildScrollView(
          key: _viewKey,
          controller: _sc,
          child: SizedBox(
            key: _stackKey,
            height: 24 * rowH + 12,
            child: LayoutBuilder(builder: (context, c) {
              final colW = (c.maxWidth - gutter - 8) / days.length;
              _colW = colW;
              final nowY = 6 + (now.hour + now.minute / 60) * rowH;
              final blocks = <Widget>[];
              final o = _orig;
              for (var i = 0; i < days.length; i++) {
                for (final s in _layoutDay(widget.events, days[i])) {
                  final top = 6 + (s.s.hour + s.s.minute / 60) * rowH;
                  final mins = s.end.difference(s.s).inMinutes;
                  final h = math.max(18.0, mins / 60 * rowH);
                  final indent = s.level * 8.0;
                  final w = (colW - 4 - indent) / s.slots;
                  final lifted = o != null && s.e.same(o);
                  final editable = widget.canEdit(s.e);
                  blocks.add(Positioned(
                    left: gutter + colW * i + 2 + indent + w * s.slot,
                    top: top + 1,
                    width: w - (s.slots > 1 ? 2 : 0),
                    height: h - 2,
                    child: Opacity(
                      opacity: lifted ? 0.35 : 1,
                      child: _TimedBlock(
                        t: t,
                        e: s.e,
                        color: widget.color(s.e),
                        stacked: s.level > 0,
                        selected: widget.isSel(s.e),
                        past: s.e.end.isBefore(now),
                        editable: editable,
                        onTap: () => widget.onSelect(s.e),
                        onMove: (g) => _start(_GridDrag.move, g, s.e),
                        onResize: (g) => _start(_GridDrag.resize, g, s.e),
                        onDrag: _update,
                        onEnd: _end,
                        onCancel: _cancel,
                      ),
                    ),
                  ));
                }
              }
              // The thing being dragged, drawn above everything in its new place.
              final pv = _preview;
              if (pv != null) {
                for (var i = 0; i < days.length; i++) {
                  for (final s in _layoutDay([pv], days[i])) {
                    final top = 6 + (s.s.hour + s.s.minute / 60) * rowH;
                    final h = math.max(18.0, s.end.difference(s.s).inMinutes / 60 * rowH);
                    blocks.add(Positioned(
                      left: gutter + colW * i + 2,
                      top: top + 1,
                      width: colW - 4,
                      height: h - 2,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: t.dark ? 0.45 : 0.15), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: _TimedBlock(
                            t: t,
                            e: pv.title.isEmpty && pv.isDraft ? pv.copyWith(title: 'New event') : pv,
                            color: _kind == _GridDrag.create ? widget.newColor : widget.color(pv),
                            stacked: false,
                            selected: true,
                            past: false,
                            editable: false,
                            onTap: () {},
                          ),
                        ),
                      ),
                    ));
                  }
                }
              }
              return Stack(children: [
                // Hour lines and labels.
                for (var hr = 1; hr < 24; hr++) ...[
                  Positioned(
                    left: gutter,
                    right: 8,
                    top: 6 + hr * rowH,
                    height: 1,
                    child: ColoredBox(color: t.line.withValues(alpha: 0.7)),
                  ),
                  Positioned(
                    left: 0,
                    width: gutter - 10,
                    top: 6 + hr * rowH - 7,
                    child: Text('${hr.toString().padLeft(2, '0')}:00',
                        textAlign: TextAlign.right, style: _ts(t.faint, 10, w: FontWeight.w600, tab: true)),
                  ),
                ],
                // Day separators.
                for (var i = 0; i < days.length; i++)
                  Positioned(
                    left: gutter + colW * i,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: ColoredBox(color: t.line.withValues(alpha: 0.7)),
                  ),
                // Empty time: click for a one-hour event, drag to draw one.
                Positioned(
                  left: gutter,
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: widget.canCreate ? SystemMouseCursors.precise : SystemMouseCursors.basic,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _tapEmpty(d.globalPosition),
                      onPanStart: widget.canCreate ? (d) => _start(_GridDrag.create, d.globalPosition) : null,
                      onPanUpdate: widget.canCreate ? (d) => _update(d.globalPosition) : null,
                      onPanEnd: widget.canCreate ? (_) => _end() : null,
                      onPanCancel: widget.canCreate ? _cancel : null,
                    ),
                  ),
                ),
                ...blocks,
                // Now line: strong across today, faint across the rest of the week.
                if (todayCol >= 0) ...[
                  if (days.length > 1)
                    Positioned(
                      left: gutter,
                      right: 8,
                      top: nowY,
                      height: 1,
                      child: IgnorePointer(child: ColoredBox(color: _calRed.withValues(alpha: 0.3))),
                    ),
                  Positioned(
                    left: gutter + colW * todayCol,
                    width: colW,
                    top: nowY - 0.75,
                    height: 1.5,
                    child: const IgnorePointer(child: ColoredBox(color: _calRed)),
                  ),
                  Positioned(
                    left: 6,
                    width: gutter - 12,
                    top: nowY - 8,
                    height: 16,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _calRed, borderRadius: BorderRadius.circular(4)),
                      child: Text(_hm(now), style: _ts(Colors.white, 10, w: FontWeight.w700, tab: true)),
                    ),
                  ),
                ],
              ]);
            }),
          ),
        ),
      ),
    ]);
  }
}

Widget _dayLabel(_T t, DateTime d, bool today, bool hover) {
  final name = _calShortDays[d.weekday % 7];
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Text(name, style: _ts(today || hover ? t.text : t.sub, 12.5, w: today ? FontWeight.w700 : FontWeight.w500)),
    const SizedBox(width: 5),
    if (today)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: _calRed, borderRadius: BorderRadius.circular(4)),
        child: Text('${d.day}', style: _ts(Colors.white, 12, w: FontWeight.w700, tab: true)),
      )
    else
      Text('${d.day}', style: _ts(hover ? t.text : t.sub, 12.5, tab: true)),
  ]);
}

/// Tinted fill behind an event in the event's colour.
Color _tint(_T t, Color c, {bool hover = false, bool selected = false}) {
  final a = (t.dark ? 0.30 : 0.20) + (hover ? 0.06 : 0) + (selected ? 0.14 : 0);
  return Color.alphaBlend(c.withValues(alpha: a), t.bg);
}

Color _timeColor(_T t, Color c) => Color.lerp(c, t.text, t.dark ? 0.35 : 0.55)!;

/// Event block in the hour grid. Drag the body to move it, the bottom edge
/// to change its length.
class _TimedBlock extends StatefulWidget {
  const _TimedBlock({
    required this.t,
    required this.e,
    required this.color,
    required this.stacked,
    required this.selected,
    required this.past,
    required this.editable,
    required this.onTap,
    this.onMove,
    this.onResize,
    this.onDrag,
    this.onEnd,
    this.onCancel,
  });
  final _T t;
  final CalEvent e;
  final Color color;
  final bool stacked, selected, past, editable;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onMove, onResize, onDrag;
  final VoidCallback? onEnd, onCancel;

  @override
  State<_TimedBlock> createState() => _TimedBlockState();
}

class _TimedBlockState extends State<_TimedBlock> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t, e = widget.e, color = widget.color;
    final drag = widget.editable;
    final body = AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: widget.past && !widget.selected ? 0.6 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _tint(t, color, hover: _h, selected: widget.selected),
          borderRadius: BorderRadius.circular(4),
          // A stacked event gets an edge in the page colour, so it reads as on top.
          border: widget.stacked ? Border.all(color: t.bg, width: 1) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3, color: color),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final tight = c.maxHeight < 32;
              final title = e.title.isEmpty ? 'Untitled' : e.title;
              return Padding(
                padding: EdgeInsets.fromLTRB(5, tight ? 1 : 4, 4, 2),
                child: tight
                    ? Text.rich(
                        TextSpan(children: [
                          TextSpan(text: title, style: _ts(t.text, 11, w: FontWeight.w600)),
                          TextSpan(text: '  ${_hm(e.start)}', style: _ts(_timeColor(t, color), 10.5, tab: true)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title,
                            maxLines: math.max(1, ((c.maxHeight - 20) / 14).floor()),
                            overflow: TextOverflow.ellipsis,
                            style: _ts(t.text, 11.5, w: FontWeight.w600, h: 1.2)),
                        Text('${_hm(e.start)}–${_hm(e.end)}',
                            maxLines: 1, style: _ts(_timeColor(t, color), 10.5, tab: true)),
                      ]),
              );
            }),
          ),
        ]),
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: drag ? (d) => widget.onMove?.call(d.globalPosition) : null,
        onPanUpdate: drag ? (d) => widget.onDrag?.call(d.globalPosition) : null,
        onPanEnd: drag ? (_) => widget.onEnd?.call() : null,
        onPanCancel: drag ? widget.onCancel : null,
        child: Stack(fit: StackFit.expand, children: [
          body,
          if (drag)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => widget.onResize?.call(d.globalPosition),
                  onPanUpdate: (d) => widget.onDrag?.call(d.globalPosition),
                  onPanEnd: (_) => widget.onEnd?.call(),
                  onPanCancel: widget.onCancel,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.t, required this.e, required this.color, required this.selected, required this.onTap});
  final _T t;
  final CalEvent e;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Hover(
        onTap: onTap,
        builder: (h) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _tint(t, color, hover: h, selected: selected),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            Container(width: 3, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(e.title.isEmpty ? 'Untitled' : e.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 11, w: FontWeight.w600)),
            ),
          ]),
        ),
      );
}

/// A to-do on the calendar. The box checks off with the same draw-in as the
/// planner; a Google task then fades out after a beat (a second click in
/// that beat takes it back), since Google hides completed tasks.
class _TaskChip extends StatefulWidget {
  const _TaskChip({required this.t, required this.task, required this.selected, required this.onTap, required this.onToggle});
  final _T t;
  final _CalTask task;
  final bool selected;
  final VoidCallback onTap, onToggle;

  @override
  State<_TaskChip> createState() => _TaskChipState();
}

class _TaskChipState extends State<_TaskChip> {
  bool _pending = false;
  Timer? _commit;

  void _toggle() {
    if (widget.task.planner != null) {
      widget.onToggle();
      return;
    }
    _commit?.cancel();
    setState(() => _pending = !_pending);
    if (_pending) _commit = Timer(const Duration(milliseconds: 750), widget.onToggle);
  }

  @override
  void dispose() {
    _commit?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, x = widget.task;
    final done = x.done || _pending;
    final col = x.color(t);
    return _Hover(
      onTap: widget.onTap,
      builder: (h) => AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: done ? 0.55 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.only(left: 3, right: 4),
          decoration: BoxDecoration(
            color: widget.selected ? _tint(t, col, selected: true) : (h ? t.raised : t.surface),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.line),
          ),
          child: Row(children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: done ? col : Colors.transparent,
                    borderRadius: BorderRadius.circular(3.5),
                    border: Border.all(color: done ? col : t.sub.withValues(alpha: 0.6), width: 1.3),
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: done ? 1 : 0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => CustomPaint(painter: _TickPainter(v, Colors.white)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: _ts(done ? t.sub : t.text, 11, w: FontWeight.w600, deco: done ? TextDecoration.lineThrough : null)
                    .copyWith(decorationColor: t.sub),
                child: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ month grid

class _CalMonthGrid extends StatelessWidget {
  const _CalMonthGrid({
    required this.t,
    required this.month,
    required this.days,
    required this.events,
    required this.tasks,
    required this.color,
    required this.canEdit,
    required this.isSel,
    required this.selTask,
    required this.onSelect,
    required this.onToggleTask,
    required this.onOpenDay,
    required this.onCreate,
    required this.onDrop,
  });
  final _T t;
  final int month;
  final List<DateTime> days;
  final List<CalEvent> events;
  final List<_CalTask> tasks;
  final Color Function(CalEvent) color;
  final bool Function(CalEvent) canEdit;
  final bool Function(CalEvent) isSel;
  final String? selTask;
  final ValueChanged<Object> onSelect;
  final ValueChanged<_CalTask> onToggleTask;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<DateTime> onCreate;
  final void Function(_CalDrag, DateTime) onDrop;

  List<CalEvent> _on(DateTime d) {
    final next = d.add(const Duration(days: 1));
    final out = [
      for (final e in events)
        if (e.start.isBefore(next) && (e.end.isAfter(d) || (e.start == e.end && !e.start.isBefore(d)))) e,
    ];
    out.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dayOf(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 26,
          child: Row(children: [
            for (final n in _calShortDays)
              Expanded(child: Center(child: Text(n, style: _ts(t.sub, 12.5, w: FontWeight.w600)))),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line), left: BorderSide(color: t.line))),
            child: Column(children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < 7; i++) Expanded(child: _cell(context, days[w * 7 + i], today, now)),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _cell(BuildContext context, DateTime d, DateTime today, DateTime now) {
    final other = d.month != month;
    final isToday = d == today;
    final evs = _on(d);
    final dayTasks = [
      for (final x in tasks)
        if (x.day == d) x,
    ];
    final label = d.day == 1 ? '${_monthNames[d.month - 1]} 1' : '${d.day}';
    return DragTarget<_CalDrag>(
      onAcceptWithDetails: (det) => onDrop(det.data, d),
      builder: (context, cand, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCreate(d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? t.raised : Colors.transparent,
            border: Border(right: BorderSide(color: t.line), bottom: BorderSide(color: t.line)),
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
          child: LayoutBuilder(builder: (context, c) {
            const lineH = 19.0;
            final total = evs.length + dayTasks.length;
            final room = math.max(0, ((c.maxHeight - 26) / lineH).floor());
            final cap = total <= room ? total : math.max(0, room - 1);
            final rows = <Widget>[];
            var used = 0;
            for (final e in evs) {
              if (used >= cap) break;
              used++;
              final chip = e.allDay
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _AllDayChip(t: t, e: e, color: color(e), selected: isSel(e), onTap: () => onSelect(e)),
                    )
                  : _MonthLine(t: t, e: e, color: color(e), selected: isSel(e), onTap: () => onSelect(e));
              rows.add(SizedBox(
                height: lineH,
                child: Opacity(
                  opacity: other || e.end.isBefore(now) ? 0.6 : 1,
                  child: _dayDraggable(context, _CalDrag(e: e), chip,
                      enabled: canEdit(e) && !e.isDraft, width: c.maxWidth),
                ),
              ));
            }
            for (final x in dayTasks) {
              if (used >= cap) break;
              used++;
              rows.add(SizedBox(
                height: lineH,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _dayDraggable(
                    context,
                    _CalDrag(task: x),
                    _TaskChip(
                      t: t,
                      task: x,
                      selected: selTask == x.key,
                      onTap: () => onSelect(x.key),
                      onToggle: () => onToggleTask(x),
                    ),
                    width: c.maxWidth,
                  ),
                ),
              ));
            }
            final more = total - used;
            return ClipRect(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _Hover(
                    onTap: () => onOpenDay(d),
                    builder: (h) => Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? _calRed : (h ? t.raised : Colors.transparent),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(label,
                          style: _ts(
                            isToday ? Colors.white : (other ? t.faint : t.text),
                            12,
                            w: isToday || d.day == 1 ? FontWeight.w700 : FontWeight.w500,
                            tab: true,
                          )),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                ...rows,
                if (more > 0)
                  _Hover(
                    onTap: () => onOpenDay(d),
                    builder: (h) => Padding(
                      padding: const EdgeInsets.only(left: 6, top: 1),
                      child: Text('$more more', style: _ts(h ? t.text : t.sub, 11, w: FontWeight.w600)),
                    ),
                  ),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

class _MonthLine extends StatelessWidget {
  const _MonthLine({required this.t, required this.e, required this.color, required this.selected, required this.onTap});
  final _T t;
  final CalEvent e;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Hover(
        onTap: onTap,
        builder: (h) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: selected ? _tint(t, color, selected: true) : (h ? t.raised : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Container(
              width: 3,
              height: 13,
              margin: const EdgeInsets.only(left: 2, right: 5),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            Text(_hm(e.start), style: _ts(t.sub, 10.5, tab: true)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(e.title.isEmpty ? 'Untitled' : e.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 11.5, w: FontWeight.w600)),
            ),
          ]),
        ),
      );
}

// --------------------------------------------------------------- panels

/// A labelled property row in the side panel, Notion style.
class _PropRow extends StatelessWidget {
  const _PropRow(this.t, this.icon, this.child);
  final _T t;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 7), child: Icon(icon, size: 16, color: t.sub)),
          const SizedBox(width: 10),
          Expanded(child: child),
        ]),
      );
}

/// Small clickable value, like Notion's property pills.
class _Pill extends StatelessWidget {
  const _Pill(this.t, this.label, this.onTap, {this.leading});
  final _T t;
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => _Hover(
        onTap: onTap,
        builder: (h) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: h && onTap != null ? t.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13, w: FontWeight.w500, tab: true)),
            ),
          ]),
        ),
      );
}

/// Borderless text field for the panel.
Widget _panelField(_T t, TextEditingController c, String hint,
        {double size = 13,
        FontWeight w = FontWeight.w500,
        bool autofocus = false,
        int? maxLines = 1,
        bool readOnly = false,
        ValueChanged<String>? onChanged,
        ValueChanged<String>? onSubmitted}) =>
    TextField(
      controller: c,
      autofocus: autofocus,
      readOnly: readOnly,
      maxLines: maxLines,
      // Titles wrap but Enter still submits; only free text takes new lines.
      textInputAction: onSubmitted != null ? TextInputAction.done : null,
      minLines: 1,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: t.focus,
      style: _ts(t.text, size, w: w),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: _ts(t.faint, size, w: w),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      ),
    );

/// Read or edit an event. Changes stay local until Save (Enter in the title
/// saves too); a draft shows its changes on the grid as you make them.
class _CalEventPanel extends StatefulWidget {
  const _CalEventPanel({
    super.key,
    required this.t,
    required this.g,
    required this.e,
    required this.editable,
    required this.color,
    required this.onDraftChanged,
    required this.onSave,
    required this.onDelete,
    required this.onCreateTask,
    required this.onClose,
    required this.onReconnect,
  });
  final _T t;
  final GoogleService g;
  final CalEvent e;
  final bool editable;
  final Color color;
  final ValueChanged<CalEvent> onDraftChanged;
  final ValueChanged<CalEvent> onSave;
  final VoidCallback onDelete, onClose, onReconnect;
  final void Function(String title, DateTime day, bool google) onCreateTask;

  @override
  State<_CalEventPanel> createState() => _CalEventPanelState();
}

class _CalEventPanelState extends State<_CalEventPanel> {
  late CalEvent _e = widget.e;
  late final _title = TextEditingController(text: widget.e.title);
  late final _place = TextEditingController(text: widget.e.location);
  late final _notes = TextEditingController(text: widget.e.description);
  bool _task = false; // a draft can become a task instead
  bool _googleTask = false;

  _T get t => widget.t;
  bool get _draft => widget.e.isDraft;

  bool get _dirty =>
      _e.title != widget.e.title ||
      _e.start != widget.e.start ||
      _e.end != widget.e.end ||
      _e.allDay != widget.e.allDay ||
      _e.calId != widget.e.calId ||
      _e.location != widget.e.location ||
      _e.description != widget.e.description;

  @override
  void didUpdateWidget(_CalEventPanel old) {
    super.didUpdateWidget(old);
    // Moved or resized on the grid while open: take the new times.
    if (widget.e.start != old.e.start || widget.e.end != old.e.end || widget.e.allDay != old.e.allDay) {
      _e = _e.copyWith(start: widget.e.start, end: widget.e.end, allDay: widget.e.allDay);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _set(CalEvent n) {
    setState(() => _e = n);
    if (_draft) widget.onDraftChanged(n);
  }

  void _save() {
    if (_task) {
      widget.onCreateTask(_title.text, dayOf(_e.start), _googleTask);
      return;
    }
    if (!_draft && !_dirty) return;
    widget.onSave(_e.copyWith(title: _title.text.trim()));
  }

  Future<void> _pickDay({bool end = false}) async {
    final base = end ? _e.end.subtract(const Duration(days: 1)) : _e.start;
    final d = await _pickDate(context, t, base);
    if (d == null) return;
    if (_e.allDay) {
      if (end) {
        final last = d.isBefore(dayOf(_e.start)) ? dayOf(_e.start) : d;
        _set(_e.copyWith(end: last.add(const Duration(days: 1))));
      } else {
        final span = _daysBetween(_e.start, _e.end);
        _set(_e.copyWith(start: d, end: d.add(Duration(days: math.max(1, span)))));
      }
    } else {
      final diff = _daysBetween(_e.start, d);
      _set(_e.copyWith(start: _shift(_e.start, days: diff), end: _shift(_e.end, days: diff)));
    }
  }

  void _toggleAllDay(bool on) {
    final d = dayOf(_e.start);
    if (on) {
      final last = dayOf(_e.end.subtract(const Duration(minutes: 1)));
      _set(_e.copyWith(allDay: true, start: d, end: (last.isBefore(d) ? d : last).add(const Duration(days: 1))));
    } else {
      final n = DateTime.now();
      final s = DateTime(d.year, d.month, d.day, d == dayOf(n) ? math.min(n.hour + 1, 23) : 9);
      _set(_e.copyWith(allDay: false, start: s, end: s.add(const Duration(hours: 1))));
    }
  }

  Widget _timeMenu({required bool end}) {
    final value = end ? _e.end : _e.start;
    final day = dayOf(_e.start);
    final options = <({DateTime at, String label})>[];
    if (end) {
      for (var m = 15; m <= 24 * 60; m += 15) {
        final at = _e.start.add(Duration(minutes: m));
        options.add((at: at, label: '${_hm(at)}   ${_dur(m)}'));
      }
    } else {
      for (var m = 0; m < 24 * 60; m += 15) {
        final at = _shift(day, minutes: m);
        options.add((at: at, label: _hm(at)));
      }
    }
    final current = options.where((o) => o.at == value).firstOrNull?.at;
    return PopupMenuButton<DateTime>(
      tooltip: end ? 'End time' : 'Start time',
      enabled: widget.editable,
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(maxHeight: 320, minWidth: 140),
      initialValue: current,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm + 2), side: BorderSide(color: t.line)),
      onSelected: (v) {
        if (end) {
          _set(_e.copyWith(end: v));
        } else {
          final len = _e.end.difference(_e.start);
          _set(_e.copyWith(start: v, end: v.add(len)));
        }
      },
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem(value: o.at, height: 32, child: Text(o.label, style: _ts(t.text, 13, tab: true))),
      ],
      child: IgnorePointer(child: _Pill(t, _hm(value), widget.editable ? () {} : null)),
    );
  }

  Widget _calMenu() {
    final g = widget.g;
    final cal = g.calendars.where((c) => c.id == _e.calId).firstOrNull;
    final square = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(3)),
    );
    final writable = g.calendars.where((c) => c.writable).toList();
    // Moving an existing event between calendars needs Google's move call; keep it to drafts and own events.
    return PopupMenuButton<String>(
      tooltip: 'Calendar',
      enabled: widget.editable && writable.length > 1,
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm + 2), side: BorderSide(color: t.line)),
      onSelected: (id) => _set(_e.copyWith(calId: id)),
      itemBuilder: (_) => [
        for (final c in writable)
          PopupMenuItem(
            value: c.id,
            height: 34,
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: Color(c.color), borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13))),
            ]),
          ),
      ],
      child: IgnorePointer(
        child: _Pill(t, cal?.name ?? 'Calendar', widget.editable ? () {} : null, leading: square),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ed = widget.editable;
    final g = widget.g;
    final lastDay = _e.allDay ? _e.end.subtract(const Duration(days: 1)) : _e.end;
    final cal = g.calendars.where((c) => c.id == _e.calId).firstOrNull;
    final readOnlyWhy = ed
        ? null
        : (!g.canEditCalendar
            ? 'Orbit can only read your calendar.'
            : '${cal?.name ?? 'This calendar'} is read-only.');

    return Container(
      decoration: BoxDecoration(color: t.side, border: Border(left: BorderSide(color: t.line))),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (_draft) _Seg(t, const ['Event', 'Task'], _task ? 1 : 0, (i) => setState(() => _task = i == 1)),
          const Spacer(),
          _IconBtn(t, Icons.close_rounded, 'Close  Esc', widget.onClose, size: 17),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 9, right: 2, left: 4),
            decoration: BoxDecoration(
              color: _task ? Colors.transparent : widget.color,
              borderRadius: BorderRadius.circular(3),
              border: _task ? Border.all(color: t.sub, width: 1.5) : null,
            ),
          ),
          Expanded(
            child: _panelField(
              t,
              _title,
              _task ? 'New task' : (_draft ? 'New event' : 'Untitled'),
              size: 18,
              w: FontWeight.w700,
              autofocus: _draft,
              maxLines: null,
              readOnly: !ed,
              onChanged: (v) {
                setState(() => _e = _e.copyWith(title: v));
                if (_draft) widget.onDraftChanged(_e);
              },
              onSubmitted: (_) => _save(),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PropRow(
                t,
                Icons.calendar_today_outlined,
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _Pill(t, _dateLabel(_e.start), ed ? () => _pickDay() : null),
                  if (!_task && _e.allDay && dayOf(lastDay) != dayOf(_e.start)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      child: Text('→', style: _ts(t.faint, 13)),
                    ),
                    _Pill(t, _dateLabel(lastDay), ed ? () => _pickDay(end: true) : null),
                  ],
                ]),
              ),
              if (!_task) ...[
                if (!_e.allDay)
                  _PropRow(
                    t,
                    Icons.schedule_rounded,
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _timeMenu(end: false),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                        child: Text('→', style: _ts(t.faint, 13)),
                      ),
                      _timeMenu(end: true),
                      if (dayOf(_e.end) != dayOf(_e.start) && _e.end != dayOf(_e.end))
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 5),
                          child: Text('next day', style: _ts(t.faint, 12)),
                        ),
                    ]),
                  ),
                _PropRow(
                  t,
                  Icons.wb_sunny_outlined,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 5, 0, 5),
                    child: Row(children: [
                      Text('All day', style: _ts(t.text, 13)),
                      const Spacer(),
                      IgnorePointer(ignoring: !ed, child: _Toggle(t, _e.allDay, _toggleAllDay)),
                    ]),
                  ),
                ),
                _PropRow(t, Icons.layers_outlined, Align(alignment: Alignment.centerLeft, child: _calMenu())),
                _PropRow(
                  t,
                  Icons.place_outlined,
                  _panelField(t, _place, ed ? 'Add location' : 'No location', readOnly: !ed,
                      onChanged: (v) => _set(_e.copyWith(location: v))),
                ),
                _PropRow(
                  t,
                  Icons.notes_rounded,
                  _panelField(t, _notes, ed ? 'Add description' : 'No description', maxLines: null, readOnly: !ed,
                      onChanged: (v) => _set(_e.copyWith(description: v))),
                ),
              ] else
                _PropRow(
                  t,
                  Icons.checklist_rounded,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _Seg(t, const ['Planner', 'Google'], _googleTask ? 1 : 0,
                        (i) => setState(() => _googleTask = i == 1 && g.canTasks)),
                  ),
                ),
              if (readOnlyWhy != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 0, 0),
                  child: Row(children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: t.faint),
                    const SizedBox(width: 6),
                    Expanded(child: Text(readOnlyWhy, style: _ts(t.sub, 12))),
                    if (!g.canEditCalendar) _Btn(t, 'Reconnect', widget.onReconnect, compact: true, ghost: true),
                  ]),
                ),
            ]),
          ),
        ),
        if (ed)
          Row(children: [
            if (!_draft) _Btn(t, 'Delete', widget.onDelete, compact: true, ghost: true, icon: Icons.delete_outline_rounded),
            const Spacer(),
            if (_draft) ...[
              _Btn(t, 'Cancel', widget.onClose, compact: true),
              const SizedBox(width: 8),
            ],
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _draft || _dirty ? 1 : 0.4,
              child: _Btn(t, _draft ? (_task ? 'Add task' : 'Create') : 'Save', _draft || _dirty ? _save : null,
                  compact: true, primary: true),
            ),
          ]),
      ]),
    );
  }
}

/// Read or edit a to-do: rename, move to another day, check off, delete.
class _CalTaskPanel extends StatefulWidget {
  const _CalTaskPanel({
    super.key,
    required this.t,
    required this.task,
    required this.onRename,
    required this.onMove,
    required this.onToggle,
    required this.onDelete,
    required this.onClose,
  });
  final _T t;
  final _CalTask task;
  final ValueChanged<String> onRename;
  final ValueChanged<DateTime> onMove;
  final VoidCallback onToggle, onDelete, onClose;

  @override
  State<_CalTaskPanel> createState() => _CalTaskPanelState();
}

class _CalTaskPanelState extends State<_CalTaskPanel> {
  late final _title = TextEditingController(text: widget.task.title);

  @override
  void dispose() {
    _commit();
    _title.dispose();
    super.dispose();
  }

  /// Renames on Enter and when the panel closes. Deferred, because closing
  /// happens while the tree is being torn down and the rename notifies.
  void _commit() {
    final v = _title.text.trim();
    if (v.isEmpty || v == widget.task.title) return;
    final rename = widget.onRename;
    scheduleMicrotask(() => rename(v));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, x = widget.task;
    return Container(
      decoration: BoxDecoration(color: t.side, border: Border(left: BorderSide(color: t.line))),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(x.planner != null ? 'Daily planner' : 'Google Tasks', style: _ts(t.sub, 12, w: FontWeight.w600)),
          ),
          const Spacer(),
          _IconBtn(t, Icons.close_rounded, 'Close  Esc', widget.onClose, size: 17),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5, left: 2), child: _Check(t, x.done, widget.onToggle)),
          Expanded(
            child: _panelField(t, _title, 'Untitled', size: 18, w: FontWeight.w700, maxLines: null,
                onSubmitted: (_) => _commit()),
          ),
        ]),
        const SizedBox(height: 6),
        _PropRow(
          t,
          Icons.calendar_today_outlined,
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(t, _dateLabel(x.day), () async {
              final d = await _pickDate(context, t, x.day);
              if (d != null) widget.onMove(d);
            }),
          ),
        ),
        if (x.planner != null)
          _PropRow(
            t,
            Icons.timelapse_rounded,
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 0, 6),
              child: Text('${_dur(x.planner!.minutes)}  ·  #${x.planner!.tag}', style: _ts(t.text, 13)),
            ),
          ),
        const Spacer(),
        Row(children: [
          _Btn(t, 'Delete', widget.onDelete, compact: true, ghost: true, icon: Icons.delete_outline_rounded),
          const Spacer(),
          _Btn(t, x.done ? 'Mark not done' : 'Mark done', widget.onToggle, compact: true, primary: !x.done),
        ]),
      ]),
    );
  }
}
