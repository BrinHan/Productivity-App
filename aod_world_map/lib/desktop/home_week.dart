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
          Text(dayNames[d.weekday - 1].substring(0, 3), style: _ts(isToday ? t.accent : t.sub, 12, w: FontWeight.w600)),
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

  Widget _card(Widget child) => _Card(t, padding: 20, child: child);

  Widget _stat(String value, String label, {bool accent = false}) => Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(_rLg),
          border: Border.all(color: t.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: _ts(accent ? t.accent : t.text, 28, w: FontWeight.w700, ls: -0.6, tab: true)),
          const SizedBox(height: 2),
          Text(label, style: _ts(t.sub, 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final perDay = [for (final d in days) p.forDay(d)];
    final done = [for (final x in perDay) x.where((t) => t.done).length];
    final total = [for (final x in perDay) x.length];
    final sumDone = done.fold<int>(0, (a, b) => a + b);
    final sumTotal = total.fold<int>(0, (a, b) => a + b);
    final all = perDay.expand((x) => x);
    final minsTotal = all.fold<int>(0, (a, x) => a + x.minutes);
    final minsDone = all.where((x) => x.done).fold<int>(0, (a, x) => a + x.minutes);
    final maxV = total.fold<int>(1, (a, b) => a > b ? a : b);
    final rate = sumTotal == 0 ? 0 : (sumDone / sumTotal * 100).round();
    const chartH = 160.0;

    // Each day: a faint full-height track, planned tasks in soft blue, done in solid blue.
    Widget bar(int i) {
      final isToday = days[i] == today;
      Widget fill(int n, Color c) => AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            height: chartH * n / maxV,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(_rSm)),
          );
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(total[i] == 0 ? '' : '${done[i]}/${total[i]}', style: _ts(t.sub, 11.5, tab: true)),
        const SizedBox(height: 8),
        SizedBox(
          width: 28,
          height: chartH,
          child: Stack(alignment: Alignment.bottomCenter, children: [
            Container(
              decoration: BoxDecoration(color: t.line.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(_rSm)),
            ),
            fill(total[i], t.accentSoft),
            fill(done[i], t.accent),
          ]),
        ),
        const SizedBox(height: 8),
        Text(dayNames[i].substring(0, 3),
            style: _ts(isToday ? t.text : t.sub, 12, w: isToday ? FontWeight.w700 : FontWeight.w500)),
      ]);
    }

    return _Page(
      t: t,
      title: 'Weekly review',
      subtitle: 'How this week went, Monday to Sunday.',
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: sumTotal == 0
              ? _card(_Empty(t, Icons.insights_outlined, 'Nothing to review yet',
                  'Plan a few tasks this week, then come back at the end of it to see how it went.'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _stat('$rate%', 'of tasks done', accent: true),
                    _stat('$sumDone of $sumTotal', sumTotal == 1 ? 'task finished' : 'tasks finished'),
                    _stat(_dur(minsDone), 'of ${_dur(minsTotal)} planned'),
                  ]),
                  const SizedBox(height: 16),
                  _card(Row(children: [for (var i = 0; i < 7; i++) Expanded(child: bar(i))])),
                ]),
        ),
      ),
    );
  }
}
