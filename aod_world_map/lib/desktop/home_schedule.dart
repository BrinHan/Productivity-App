part of 'home_page.dart';

/// Right panel: today's planned tasks in the free time between Google
/// Calendar events. With both present, tasks and events get their own lane.
/// Drag a task to pin it to a time; right-click lets it fit itself in again.
class _SchedulePanel extends StatefulWidget {
  const _SchedulePanel({required this.t, required this.p, required this.g, required this.prefs, required this.placed});
  final _T t;
  final PlannerModel p;
  final GoogleService g;
  final _Prefs prefs;

  /// Where each of today's tasks sits, by task id (see [placeTasks]).
  final Map<String, List<({DateTime start, DateTime end})>> placed;

  @override
  State<_SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<_SchedulePanel> {
  static const _rowH = 56.0, _padT = 10.0;
  static const _gutter = 52.0; // hour labels; lines and blocks both start here
  late final ScrollController _sc;

  // The task being dragged and how far it has moved.
  String? _dragId;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final (from, to) = _hours(dayOf(n));
    final y = (n.hour + n.minute / 60 - from) * _rowH - 150;
    _sc = ScrollController(initialScrollOffset: y.clamp(0.0, (to - from) * _rowH).toDouble());
  }

  /// Minutes from [today]'s midnight, kept within the day.
  int _minute(DateTime d, DateTime today) => d.difference(today).inMinutes.clamp(0, 24 * 60).toInt();

  /// The hours shown: 6 AM to 9 PM, stretched to cover the workday, every
  /// event and every planned task.
  (int, int) _hours(DateTime today) {
    var from = math.min(6, widget.prefs.dayStart), to = math.max(21, widget.prefs.dayEnd);
    final spans = [
      for (final e in widget.g.events)
        if (!e.allDay && dayOf(e.start) == today) (start: e.start, end: e.end),
      for (final l in widget.placed.values) ...l,
    ];
    for (final s in spans) {
      from = math.min(from, _minute(s.start, today) ~/ 60);
      to = math.max(to, (_minute(s.end, today) + 59) ~/ 60);
    }
    return (from, to);
  }

  /// Pins [task] where the dragged piece [from] was dropped, on the quarter hour.
  void _drop(Task task, DateTime from, DateTime today) {
    final moved = _minute(from, today) + _dragDy / _rowH * 60;
    final m = ((moved / 15).round() * 15).clamp(0, 24 * 60 - task.minutes).toInt();
    setState(() => _dragId = null);
    widget.p.pin(task, today.add(Duration(minutes: m)));
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  String _hour(int h) => h == 12 ? '12 PM' : (h < 12 ? '$h AM' : '${h - 12} PM');

  Widget _block({
    required Color bar,
    required Color fill,
    required String title,
    String? sub,
    bool done = false,
    VoidCallback? onTap,
  }) {
    final t = widget.t;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
            color: fill,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 4, child: ColoredBox(color: bar)),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final titleStyle = _ts(done ? t.sub : t.text, 11.5,
                      w: FontWeight.w600, h: 1.2, deco: done ? TextDecoration.lineThrough : null);
                  final subStyle = _ts(t.sub, 10.5, tab: true);
                  // Too short for two lines: title and time share one.
                  if (c.maxHeight < 36) {
                    return ClipRect(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                          alignment: c.maxHeight < 22 ? Alignment.centerLeft : const Alignment(-1, -0.4),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: title, style: titleStyle),
                              if (sub != null) TextSpan(text: '  $sub', style: subStyle),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }
                  return ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: c.maxHeight < 50 ? 1 : 2, overflow: TextOverflow.ellipsis, style: titleStyle),
                        if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                      ]),
                    ),
                  );
                }),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, p = widget.p, g = widget.g;
    final now = DateTime.now();
    final today = dayOf(now);
    final (startHour, endHour) = _hours(today);
    final hours = endHour - startHour;
    final nowY = (now.hour + now.minute / 60 - startHour) * _rowH;
    final nowVisible = nowY >= 0 && nowY <= hours * _rowH;
    final tasks = p.forDay(now);
    int placedMinutes(Task x) =>
        (widget.placed[x.id] ?? const []).fold(0, (s, r) => s + r.end.difference(r.start).inMinutes);
    final unplaced = [for (final x in tasks) if (!x.done && placedMinutes(x) < x.minutes) x];
    final nextDay = today.add(const Duration(days: 1));
    final timed = [for (final e in g.events) if (!e.allDay && dayOf(e.start) == today) e];
    final allDay = [
      for (final e in g.events)
        if (e.allDay && e.start.isBefore(nextDay) && e.end.isAfter(today)) e,
    ];

    return Container(
      width: 300,
      decoration: BoxDecoration(color: t.panel, border: Border(left: BorderSide(color: t.panelLine))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(dayNames[now.weekday - 1], style: _ts(t.sub, 12.5, w: FontWeight.w600)),
              const Spacer(),
              if (g.signedIn && g.loading) Text('Syncing', style: _ts(t.sub, 11.5)),
            ]),
            Text('${now.day} ${monthNames[now.month - 1]}', style: _ts(t.text, 22, w: FontWeight.w700, ls: -0.5)),
            if (allDay.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in allDay)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: t.panelCard, borderRadius: BorderRadius.circular(8)),
                      child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 11.5, w: FontWeight.w600)),
                    ),
                  ),
              ]),
            ],
            if (unplaced.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Not enough free time for', style: _ts(t.warn, 11.5, w: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final x in unplaced)
                Text('${x.title}  ·  ${_dur(x.minutes - placedMinutes(x))} short',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.sub, 11.5, tab: true)),
            ],
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _sc,
            child: LayoutBuilder(builder: (context, c) {
              final height = hours * _rowH + _padT * 2;
              final items = <_Slot>[];

              for (final task in tasks) {
                final spans = widget.placed[task.id] ?? const [];
                for (var i = 0; i < spans.length; i++) {
                  final s = spans[i];
                  final dragging = _dragId == task.id;
                  final part = spans.length > 1 ? '  ·  part ${i + 1} of ${spans.length}' : '';
                  final pin = task.at != null && !task.done ? '  ·  pinned' : '';
                  items.add(_Slot(
                    s.start,
                    s.end,
                    dy: dragging ? _dragDy : 0,
                    child: Tooltip(
                      message: task.at != null ? 'Drag to move · right-click to fit it in again' : 'Drag to pin it to a time',
                      waitDuration: const Duration(milliseconds: 800),
                      child: GestureDetector(
                        onVerticalDragStart: (_) => setState(() {
                          _dragId = task.id;
                          _dragDy = 0;
                        }),
                        onVerticalDragUpdate: (d) => setState(() => _dragDy += d.delta.dy),
                        onVerticalDragEnd: (_) => _drop(task, s.start, today),
                        onVerticalDragCancel: () => setState(() => _dragId = null),
                        onSecondaryTap: task.at == null ? null : () => p.pin(task, null),
                        child: Opacity(
                          opacity: dragging ? 0.85 : 1,
                          child: _block(
                            bar: t.accent,
                            fill: task.done ? t.panelCard : t.accentSoft,
                            title: task.title,
                            sub: '${_clock(s.start)} – ${_clock(s.end)}$part$pin',
                            done: task.done,
                            onTap: () => p.toggle(task),
                          ),
                        ),
                      ),
                    ),
                  ));
                }
              }

              for (final e in timed) {
                items.add(_Slot(
                  e.start,
                  e.end,
                  child: _block(
                    bar: t.sub,
                    fill: t.panelCard,
                    title: e.title,
                    sub: '${_clock(e.start)} – ${_clock(e.end)}',
                  ),
                ));
              }

              // Blocks take the full width unless they overlap something;
              // then the overlapping ones share it side by side.
              const gap = 4.0, edge = 6.0;
              final width = c.maxWidth - _gutter - edge;
              final blocks = <Widget>[];
              for (final (slot, col, cols) in _columns(items)) {
                final w = (width - (cols - 1) * gap) / cols;
                final top = _padT + (_minute(slot.start, today) - startHour * 60) / 60 * _rowH + slot.dy;
                // True to length, less a sliver so back-to-back blocks stay apart.
                final h = (slot.end.difference(slot.start).inMinutes / 60 * _rowH - 3).clamp(14.0, 24 * _rowH).toDouble();
                blocks.add(Positioned(
                  top: top,
                  left: _gutter + col * (w + gap),
                  width: w,
                  height: h,
                  child: slot.child,
                ));
              }

              return SizedBox(
                height: height,
                child: Stack(children: [
                  for (var i = 0; i <= hours; i++)
                    Positioned(
                      top: _padT + i * _rowH - 7,
                      left: 0,
                      right: 0,
                      height: 14,
                      child: Row(children: [
                        SizedBox(
                          width: _gutter,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Text(_hour((startHour + i) % 24), style: _ts(t.faint, 10.5, tab: true)),
                          ),
                        ),
                        Expanded(child: _Hair(t, color: t.panelLine)),
                      ]),
                    ),
                  ...blocks,
                  if (nowVisible)
                    Positioned(
                      top: _padT + nowY - 4,
                      left: 50,
                      right: 0,
                      height: 8,
                      child: Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: t.accent)),
                        Expanded(child: Container(height: 1.5, color: t.accent)),
                      ]),
                    ),
                ]),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

/// Something on the day's timeline: a task (or a piece of one) or an event.
class _Slot {
  _Slot(this.start, this.end, {required this.child, this.dy = 0});
  final DateTime start, end;
  final Widget child;

  /// How far it is being dragged, in pixels.
  final double dy;
}

/// Lays [slots] out like a calendar: each run of overlapping slots is split
/// into columns, and a slot alone in its time gets the full width. Returns
/// each slot with its column and how many columns its run has. A slot being
/// dragged comes last, so it draws on top.
List<(_Slot, int, int)> _columns(List<_Slot> slots) {
  final sorted = [...slots]..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end); // longer first
    });
  final out = <(_Slot, int, int)>[];
  var run = <(_Slot, int)>[];
  var colEnds = <DateTime>[];
  DateTime? runEnd;

  void flush() {
    for (final (s, col) in run) {
      out.add((s, col, colEnds.length));
    }
    run = [];
    colEnds = [];
  }

  for (final s in sorted) {
    if (runEnd != null && !s.start.isBefore(runEnd)) flush();
    var col = colEnds.indexWhere((end) => !end.isAfter(s.start));
    if (col < 0) {
      col = colEnds.length;
      colEnds.add(s.end);
    } else {
      colEnds[col] = s.end;
    }
    run.add((s, col));
    runEnd = runEnd == null || run.length == 1 || s.end.isAfter(runEnd) ? s.end : runEnd;
  }
  flush();
  out.sort((a, b) => (a.$1.dy != 0 ? 1 : 0) - (b.$1.dy != 0 ? 1 : 0));
  return out;
}
