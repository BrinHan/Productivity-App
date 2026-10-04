part of 'home_page.dart';

class _WeekView extends StatelessWidget {
  const _WeekView({required this.t, required this.p, required this.onOpenDay});
  final _T t;
  final PlannerModel p;
  final ValueChanged<int> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return _Page(
      t: t,
      title: 'Weekly planning',
      subtitle: 'Open a day to plan it on the board.',
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 6 ? 0 : 10),
              child: _cell(monday.add(Duration(days: i)), today),
            ),
          ),
      ]),
    );
  }

  Widget _cell(DateTime d, DateTime today) {
    final tasks = p.forDay(d);
    final isToday = d == today;
    final mins = tasks.fold<int>(0, (s, x) => s + x.minutes);
    return _Tap(
      t: t,
      radius: _rLg,
      onTap: () => onOpenDay(d.difference(today).inDays),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_rLg),
          border: Border.all(color: isToday ? t.accent : t.line, width: isToday ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_dayNames[d.weekday - 1].substring(0, 3), style: _ts(isToday ? t.accent : t.sub, 12, w: FontWeight.w600)),
          Text('${d.day}', style: _ts(t.text, 26, w: FontWeight.w600, ls: -0.6, tab: true)),
          const SizedBox(height: 6),
          Text(tasks.isEmpty ? 'Free' : '${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'}, ${_dur(mins)}',
              style: _ts(t.sub, 11.5)),
          const SizedBox(height: 10),
          for (final x in tasks.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(x.done ? t.sub : t.text, 12, deco: x.done ? TextDecoration.lineThrough : null)),
            ),
          if (tasks.length > 5) Text('+${tasks.length - 5} more', style: _ts(t.sub, 11.5)),
        ]),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.t, required this.p});
  final _T t;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final done = [for (final d in days) p.forDay(d).where((x) => x.done).length];
    final total = [for (final d in days) p.forDay(d).length];
    final sumDone = done.fold<int>(0, (a, b) => a + b);
    final sumTotal = total.fold<int>(0, (a, b) => a + b);
    final maxV = total.fold<int>(1, (a, b) => a > b ? a : b);
    final rate = sumTotal == 0 ? 0 : (sumDone / sumTotal * 100).round();
    const chartH = 200.0;
    return _Page(
      t: t,
      title: 'Weekly review',
      subtitle: 'How this week went.',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 220,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$rate%', style: _ts(t.accent, 64, w: FontWeight.w300, ls: -2.5, tab: true)),
            const SizedBox(height: 4),
            Text('$sumDone of $sumTotal tasks done this week.', style: _ts(t.sub, 13.5, h: 1.45)),
          ]),
        ),
        const SizedBox(width: 40),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${done[i]}/${total[i]}', style: _ts(t.sub, 11.5, tab: true)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 34,
                    height: chartH,
                    child: Stack(alignment: Alignment.bottomCenter, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: chartH * total[i] / maxV,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: t.line),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: chartH * done[i] / maxV,
                        decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(8)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text(_dayNames[i].substring(0, 3),
                      style: _ts(days[i] == today ? t.text : t.sub, 12,
                          w: days[i] == today ? FontWeight.w700 : FontWeight.w500)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
