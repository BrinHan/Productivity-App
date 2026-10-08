part of 'home_page.dart';

// The calendar's Day and Week views (see home_calendar.dart).

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

typedef _AllDayItem = ({CalEvent? e, _CalTask? task, int a, int b, int lane});

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
  /// Hour at the top of the view (not pixels: the hour height follows the window).
  final double scroll;
  final ValueChanged<double> onScroll;

  static const gutter = 56.0;

  /// An hour is a twelfth of the visible grid, so a day reads the same on a
  /// laptop and a big monitor, within sensible limits.
  static const hoursInView = 12.0, minRowH = 44.0, maxRowH = 96.0;

  @override
  State<_CalTimeGrid> createState() => _CalTimeGridState();
}

class _CalTimeGridState extends State<_CalTimeGrid> {
  // Created on first build, after the hour height is known.
  late final ScrollController _sc = ScrollController(initialScrollOffset: _topHour * _rowH)
    ..addListener(() {
      _topHour = _sc.offset / _rowH;
      widget.onScroll(_topHour);
    });
  late double _topHour = widget.scroll;
  double _rowH = _CalTimeGrid.minRowH;
  final _stackKey = GlobalKey(), _viewKey = GlobalKey();
  Timer? _tick;
  double _colW = 1;

  _GridDrag? _kind;
  CalEvent? _orig;
  int _day0 = 0;
  double _min0 = 0;
  CalEvent? _preview;

  /// Minutes between the pointer and the snapped preview while moving or
  /// resizing, so the lifted block tracks the pointer 1:1 while the slot
  /// it will land in snaps to 15 minutes underneath it.
  double _residual = 0;

  static const gutter = _CalTimeGrid.gutter;
  double get rowH => _rowH;

  /// Fits the hour height to the visible grid; keeps the same hour on top.
  void _fitRows(double viewH) {
    final r = (viewH / _CalTimeGrid.hoursInView).clamp(_CalTimeGrid.minRowH, _CalTimeGrid.maxRowH).toDouble();
    if ((r - _rowH).abs() < 0.5) return;
    final top = _topHour;
    _rowH = r;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      _sc.jumpTo((top * _rowH).clamp(0.0, _sc.position.maxScrollExtent));
    });
  }

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
          _residual = a.min - _min0 - dm;
          _preview = o!.copyWith(
            start: _shift(o.start, days: dd, minutes: dm),
            end: _shift(o.end, days: dd, minutes: dm),
          );
        case _GridDrag.resize:
          final dm = ((a.min - _min0) / 15).round() * 15;
          var end = _shift(o!.end, minutes: dm);
          _residual = a.min - _min0 - dm;
          if (end.difference(o.start).inMinutes < 15) {
            end = o.start.add(const Duration(minutes: 15));
            _residual = 0; // at the shortest length the edge stops
          }
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
      _residual = 0;
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
        _residual = 0;
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
    // One clock reading per build, so the now line, its label and the
    // "past" shading on events can never disagree by a minute.
    final now = DateTime.now();
    final today = dayOf(now);
    final allDay = _allDayLanes();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _dayLabels(today),
      _allDayRow(allDay.items, allDay.lanes),
      Expanded(child: _hourGrid(now, today)),
    ]);
  }

  /// All-day events span the days they cover and tasks sit on their day.
  /// Each takes the first lane that's free by the time it starts.
  ({List<_AllDayItem> items, int lanes}) _allDayLanes() {
    final days = widget.days, first = days.first;
    final items = <_AllDayItem>[];
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

    final events = widget.events.where((e) => e.allDay).toList()
      ..sort((x, y) {
        final c = x.start.compareTo(y.start);
        return c != 0 ? c : y.end.compareTo(x.end);
      });
    for (final e in events) {
      final a = math.max(0, _daysBetween(first, e.start));
      final lastDay = e.end.isAfter(e.start) ? e.end.subtract(const Duration(minutes: 1)) : e.start;
      final b = math.min(days.length - 1, _daysBetween(first, lastDay));
      if (b >= a) place(e, null, a, b);
    }
    for (final x in widget.tasks) {
      final i = _daysBetween(first, x.day);
      if (i >= 0 && i < days.length) place(null, x, i, i);
    }
    return (items: items, lanes: laneEnds.length);
  }

  Widget _dayLabels(DateTime today) {
    final t = widget.t, days = widget.days;
    return SizedBox(
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
    );
  }

  Widget _allDayRow(List<_AllDayItem> items, int lanes) {
    final t = widget.t, days = widget.days;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: math.max(1, lanes) * 22.0 + 6,
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
                  child: _allDayChip(context, x, colW),
                ),
            ]);
          }),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _allDayChip(BuildContext context, _AllDayItem x, double colW) {
    final t = widget.t, e = x.e;
    if (e != null) {
      return _dayDraggable(
        context,
        _CalDrag(e: e),
        _AllDayChip(t: t, e: e, color: widget.color(e), selected: widget.isSel(e), onTap: () => widget.onSelect(e)),
        enabled: widget.canEdit(e) && !e.isDraft,
        width: colW - 4,
      );
    }
    final task = x.task!;
    return _dayDraggable(
      context,
      _CalDrag(task: task),
      _TaskChip(
        t: t,
        task: task,
        selected: widget.selTask == task.key,
        onTap: () => widget.onSelect(task.key),
        onToggle: () => widget.onToggleTask(task),
      ),
      width: colW - 4,
    );
  }

  /// The scrolling 24-hour grid, drawn back to front.
  Widget _hourGrid(DateTime now, DateTime today) {
    return LayoutBuilder(builder: (context, view) {
      _fitRows(view.maxHeight);
      return SingleChildScrollView(
        key: _viewKey,
        controller: _sc,
        child: SizedBox(
          key: _stackKey,
          height: 24 * rowH + 12,
          child: LayoutBuilder(builder: (context, c) {
            final colW = (c.maxWidth - gutter - 8) / widget.days.length;
            _colW = colW;
            final todayCol = widget.days.indexOf(today);
            return Stack(children: [
              ..._hourLines(),
              ..._daySeparators(colW),
              _emptyTime(),
              ..._eventBlocks(colW, now),
              ..._dragPreview(colW),
              if (todayCol >= 0) ..._nowLine(colW, todayCol, now),
            ]);
          }),
        ),
      );
    });
  }

  List<Widget> _hourLines() {
    final t = widget.t;
    return [
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
    ];
  }

  List<Widget> _daySeparators(double colW) => [
        for (var i = 0; i < widget.days.length; i++)
          Positioned(
            left: gutter + colW * i,
            top: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: widget.t.line.withValues(alpha: 0.7)),
          ),
      ];

  /// Empty time: click for a one-hour event, drag to draw one.
  Widget _emptyTime() {
    final can = widget.canCreate;
    return Positioned(
      left: gutter,
      right: 8,
      top: 0,
      bottom: 0,
      child: MouseRegion(
        cursor: can ? SystemMouseCursors.precise : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tapEmpty(d.globalPosition),
          onPanStart: can ? (d) => _start(_GridDrag.create, d.globalPosition) : null,
          onPanUpdate: can ? (d) => _update(d.globalPosition) : null,
          onPanEnd: can ? (_) => _end() : null,
          onPanCancel: can ? _cancel : null,
        ),
      ),
    );
  }

  List<Widget> _eventBlocks(double colW, DateTime now) {
    final days = widget.days, lifted = _orig;
    return [
      for (var i = 0; i < days.length; i++)
        for (final s in _layoutDay(widget.events, days[i])) _eventBlock(s, i, colW, now, lifted),
    ];
  }

  Widget _eventBlock(_CalSeg s, int day, double colW, DateTime now, CalEvent? lifted) {
    final top = 6 + (s.s.hour + s.s.minute / 60) * rowH;
    final h = math.max(18.0, s.end.difference(s.s).inMinutes / 60 * rowH);
    final indent = s.level * 8.0;
    final w = (colW - 4 - indent) / s.slots;
    return Positioned(
      left: gutter + colW * day + 2 + indent + w * s.slot,
      top: top + 1,
      width: w - (s.slots > 1 ? 2 : 0),
      height: h - 2,
      child: Opacity(
        // The original stays put, faded, while its copy follows the pointer.
        opacity: lifted != null && s.e.same(lifted) ? 0.35 : 1,
        child: _TimedBlock(
          t: widget.t,
          e: s.e,
          color: widget.color(s.e),
          stacked: s.level > 0,
          selected: widget.isSel(s.e),
          past: s.e.end.isBefore(now),
          editable: widget.canEdit(s.e),
          onTap: () => widget.onSelect(s.e),
          onMove: (g) => _start(_GridDrag.move, g, s.e),
          onResize: (g) => _start(_GridDrag.resize, g, s.e),
          onDrag: _update,
          onEnd: _end,
          onCancel: _cancel,
        ),
      ),
    );
  }

  /// The thing being dragged, drawn above everything. While moving or
  /// resizing it follows the pointer exactly; a faint outline marks the
  /// 15-minute slot it will land in.
  List<Widget> _dragPreview(double colW) {
    final pv = _preview;
    if (pv == null) return const [];
    final t = widget.t;
    final lifting = _kind != _GridDrag.create;
    final off = _residual / 60 * rowH;
    final blocks = <Widget>[];
    for (var i = 0; i < widget.days.length; i++) {
      for (final s in _layoutDay([pv], widget.days[i])) {
        final top = 6 + (s.s.hour + s.s.minute / 60) * rowH;
        final h = math.max(18.0, s.end.difference(s.s).inMinutes / 60 * rowH);
        final slide = _kind == _GridDrag.move ? off : 0.0;
        final grow = _kind == _GridDrag.resize && s.end == pv.end ? off : 0.0;
        if (lifting) {
          final c = widget.color(pv);
          blocks.add(Positioned(
            left: gutter + colW * i + 2,
            top: top + 1,
            width: colW - 4,
            height: h - 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: c.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ));
        }
        blocks.add(Positioned(
          left: gutter + colW * i + 2,
          top: top + 1 + slide,
          width: colW - 4,
          height: math.max(18.0, h + grow) - 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.line),
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
    return blocks;
  }

  /// Strong across today, faint across the rest of the week.
  List<Widget> _nowLine(double colW, int todayCol, DateTime now) {
    final y = 6 + (now.hour + now.minute / 60) * rowH;
    return [
      if (widget.days.length > 1)
        Positioned(
          left: gutter,
          right: 8,
          top: y,
          height: 1,
          child: IgnorePointer(child: ColoredBox(color: _calRed.withValues(alpha: 0.3))),
        ),
      Positioned(
        left: gutter + colW * todayCol,
        width: colW,
        top: y - 0.75,
        height: 1.5,
        child: const IgnorePointer(child: ColoredBox(color: _calRed)),
      ),
      Positioned(
        left: 6,
        width: gutter - 12,
        top: y - 8,
        height: 16,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _calRed, borderRadius: BorderRadius.circular(4)),
          child: Text(_hm(now), style: _ts(Colors.white, 10, w: FontWeight.w700, tab: true)),
        ),
      ),
    ];
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
                    builder: (_, v, _) => CustomPaint(painter: _TickPainter(v, Colors.white)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                // Merged so the planner's chosen font carries through.
                style: DefaultTextStyle.of(context).style.merge(
                    _ts(done ? t.sub : t.text, 11, w: FontWeight.w600, deco: done ? TextDecoration.lineThrough : null)
                        .copyWith(decorationColor: t.sub)),
                child: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
