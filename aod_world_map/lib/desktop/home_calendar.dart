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

String _dateLabel(DateTime d) => '${_calShortDays[d.weekday % 7]}, ${monthNames[d.month - 1].substring(0, 3)} ${d.day}';

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
  late double _scroll; // hour at the top of the time grid
  final _focus = FocusNode(debugLabel: 'calendar');

  _T get t => widget.t;
  GoogleService get g => widget.g;
  PlannerModel get p => widget.p;

  @override
  void initState() {
    super.initState();
    _mode = _CalMode.values[_Prefs.i.calMode.clamp(0, 2)];
    final n = DateTime.now();
    _scroll = math.max(0, n.hour - 2).toDouble();
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
        return '${monthNames[a.month - 1].substring(0, 3)}$y – ${monthNames[b.month - 1].substring(0, 3)} ${b.year}';
      }
    }
    return '${monthNames[_anchor.month - 1]} ${_anchor.year}';
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
    final reduce = MediaQuery.of(context).disableAnimations || Motion.reduced;
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
              ?banner,
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
          // The title gives way (with an ellipsis) when the window is narrow.
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(_title,
                  key: ValueKey(_title),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(t.text, 22, w: FontWeight.w700, ls: -0.5)),
            ),
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
            ? 'Meridian can only read your calendar. Reconnect Google once to add and edit events.'
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
        Text('${monthNames[_month.month - 1]} ${_month.year}', style: _ts(t.text, 13, w: FontWeight.w600)),
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
