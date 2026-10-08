part of 'home_page.dart';

// The calendar's Month view (see home_calendar.dart).

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
    final label = d.day == 1 ? '${monthNames[d.month - 1]} 1' : '${d.day}';
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
