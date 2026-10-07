part of 'home_page.dart';

/// Right panel: today's planned tasks plus Google Calendar events at their
/// real times. With both present, tasks and events get their own lane.
class _SchedulePanel extends StatefulWidget {
  const _SchedulePanel({required this.t, required this.p, required this.g});
  final _T t;
  final PlannerModel p;
  final GoogleService g;

  @override
  State<_SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<_SchedulePanel> {
  static const _rowH = 56.0, _padT = 10.0;
  static const _gutter = 52.0; // hour labels; lines and blocks both start here
  static const _startHour = 6, _endHour = 21;
  late final ScrollController _sc;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final y = (n.hour + n.minute / 60 - _startHour) * _rowH - 150;
    _sc = ScrollController(initialScrollOffset: y.clamp(0.0, (_endHour - _startHour) * _rowH).toDouble());
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
          // Square on the left so the bar runs the full height; rounded
          // corners there would trim it into notches.
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
          child: ColoredBox(
            color: fill,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 3, child: ColoredBox(color: bar)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _ts(done ? t.sub : t.text, 11.5,
                            w: FontWeight.w600, h: 1.2, deco: done ? TextDecoration.lineThrough : null)),
                    if (sub != null)
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.sub, 10.5, tab: true)),
                  ]),
                ),
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
    final hours = _endHour - _startHour;
    final nowY = (now.hour + now.minute / 60 - _startHour) * _rowH;
    final nowVisible = nowY >= 0 && nowY <= hours * _rowH;
    final tasks = p.forDay(now);
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
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _sc,
            child: LayoutBuilder(builder: (context, c) {
              // Two lanes only when there are both; otherwise one gets the full width.
              final lanes = timed.isNotEmpty && tasks.isNotEmpty ? 2 : 1;
              // Blocks run to the panel edge, where the hour lines end.
              final laneW = (c.maxWidth - _gutter - (lanes - 1) * 6) / lanes;
              final eventLeft = lanes == 2 ? _gutter + laneW + 6 : _gutter;
              final height = hours * _rowH + _padT * 2;
              final blocks = <Widget>[];

              var cursor = 9 * 60; // planned tasks run back to back from 9:00
              for (final task in tasks) {
                final top = _padT + (cursor - _startHour * 60) / 60 * _rowH;
                final h = (task.minutes / 60 * _rowH).clamp(28.0, 600.0).toDouble();
                cursor += task.minutes;
                blocks.add(Positioned(
                  top: top,
                  left: _gutter,
                  width: laneW,
                  height: h,
                  child: _block(
                    bar: t.accent,
                    fill: task.done ? t.panelCard : t.accentSoft,
                    title: task.title,
                    done: task.done,
                    onTap: () => p.toggle(task),
                  ),
                ));
              }

              for (final e in timed) {
                final sMin = e.start.hour * 60 + e.start.minute;
                final top = _padT + (sMin - _startHour * 60) / 60 * _rowH;
                final mins = e.end.difference(e.start).inMinutes;
                final h = (mins / 60 * _rowH).clamp(30.0, 600.0).toDouble();
                if (top + h < _padT || top > height) continue;
                blocks.add(Positioned(
                  top: top,
                  left: eventLeft,
                  width: laneW,
                  height: h,
                  child: _block(
                    bar: t.sub,
                    fill: t.panelCard,
                    title: e.title,
                    sub: _clock(e.start),
                  ),
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
                            child: Text(_hour(_startHour + i), style: _ts(t.faint, 10.5, tab: true)),
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
