part of 'home_page.dart';

/// The morning ritual: today's tasks against the free time left between
/// meetings in the workday. Tasks carried over from earlier days come first,
/// so each one gets a decision.
class _PlanningView extends StatelessWidget {
  const _PlanningView({required this.t, required this.p, required this.busy, required this.prefs});
  final _T t;
  final PlannerModel p;

  /// Today's timed events from every calendar.
  final List<({DateTime start, DateTime end})> busy;
  final _Prefs prefs;

  String _summary(DayFit fit, DateTime now) {
    final planned = _dur(fit.planned);
    if (fit.free == 0 && now.hour >= prefs.dayEnd) {
      return fit.planned == 0
          ? 'Your workday is over and nothing is left open.'
          : 'Your workday is over, with $planned of tasks still open.';
    }
    final free = '${_dur(fit.free)} free';
    final around = fit.meetings > 0 ? '$free around ${_dur(fit.meetings)} of meetings' : free;
    if (fit.planned == 0) return 'Nothing planned yet. You have $around.';
    if (!fit.over) return '$planned of tasks, $around. It fits.';
    return '$planned of tasks, but only $around. ${_dur(fit.overBy)} will not fit.';
  }

  Widget _gap(({DateTime start, DateTime end}) g) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(_rSm)),
        child: Text('${_clock(g.start)} – ${_clock(g.end)}  ·  ${_dur(g.end.difference(g.start).inMinutes)}',
            style: _ts(t.text, 12, w: FontWeight.w600, tab: true)),
      );

  Widget _row(BuildContext context, Task task) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          _Check(t, task.done, () => p.toggle(task)),
          const SizedBox(width: 12),
          Expanded(child: _StrikeText(t, task.title, task.done, size: 14)),
          if (task.slipped > 0 && !task.done) ...[
            _SlipChip(t, task.slipped),
            const SizedBox(width: 6),
          ],
          _IconBtn(t, Icons.remove_rounded, 'Shorter by 15 min', () => p.addMinutes(task, -15)),
          SizedBox(
            width: 58,
            child: Text(_dur(task.minutes),
                textAlign: TextAlign.center, style: _ts(t.text, 13, w: FontWeight.w600, tab: true)),
          ),
          _IconBtn(t, Icons.add_rounded, 'Longer by 15 min', () => p.addMinutes(task, 15)),
          _IconBtn(t, Icons.arrow_forward_rounded, 'Move to tomorrow', () => p.moveDay(task, 1)),
          if (task.slipped >= 3)
            _IconBtn(t, Icons.delete_outline_rounded, 'Drop it', () => _deleteWithUndo(context, t, p, task)),
        ]),
      );

  Widget _section(BuildContext context, String label, List<Task> tasks) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(label, style: _ts(t.sub, 12.5, w: FontWeight.w600)),
        ),
        for (var i = 0; i < tasks.length; i++) ...[
          _row(context, tasks[i]),
          if (i < tasks.length - 1) _Hair(t),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tasks = p.forDay(now);
    final open = tasks.where((x) => !x.done);
    final fit = dayFit(
      now: now,
      day: now,
      startHour: prefs.dayStart,
      endHour: prefs.dayEnd,
      busy: busy,
      planned: open.fold<int>(0, (s, x) => s + x.minutes),
    );
    final slipped = [for (final x in tasks) if (x.slipped > 0 && !x.done) x];
    final rest = [for (final x in tasks) if (!slipped.contains(x)) x];
    final total = tasks.fold<int>(0, (s, x) => s + x.minutes);

    return _Page(
      t: t,
      title: 'Plan your day',
      subtitle: _summary(fit, now),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Bar(t, fit.free == 0 ? (fit.planned > 0 ? 1 : 0) : fit.planned / fit.free, warn: fit.over, height: 6),
        if (fit.gaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Free', style: _ts(t.sub, 12.5, w: FontWeight.w600)),
            const SizedBox(width: 2),
            for (final g in fit.gaps.take(6)) _gap(g),
          ]),
        ],
        if (fit.over && fit.planned > 0) ...[
          const SizedBox(height: 10),
          Text('Move something to tomorrow or shorten an estimate until it fits.', style: _ts(t.warn, 13)),
        ],
        const SizedBox(height: 20),
        _AddTaskRow(t: t, total: total, onAdd: (title) => p.add(now, title)),
        const SizedBox(height: 8),
        Expanded(
          child: tasks.isEmpty
              ? _Empty(t, Icons.event_available_outlined, 'Nothing planned', 'Add your first task above.')
              : ListView(children: [
                  if (slipped.isNotEmpty) _section(context, 'Carried over from earlier', slipped),
                  if (rest.isNotEmpty) _section(context, slipped.isEmpty ? 'Today' : 'New today', rest),
                ]),
        ),
      ]),
    );
  }
}

class _TaskListView extends StatelessWidget {
  const _TaskListView({required this.t, required this.p});
  final _T t;
  final PlannerModel p;

  Widget _row(Task task, bool last) => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            _Check(t, task.done, () => p.toggle(task)),
            const SizedBox(width: 12),
            Expanded(child: _StrikeText(t, task.title, task.done, size: 14)),
            if (task.slipped > 0 && !task.done) ...[
              _SlipChip(t, task.slipped),
              const SizedBox(width: 6),
            ],
            _TagChip(t, task.tag),
            const SizedBox(width: 14),
            Text(_dur(task.minutes), style: _ts(t.sub, 12, w: FontWeight.w600, tab: true)),
            const SizedBox(width: 4),
            SizedBox(width: 30, height: 30, child: _TaskMenu(t: t, p: p, task: task)),
          ]),
        ),
        if (!last) _Hair(t),
      ]);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tasks = p.forDay(today);
    final open = tasks.where((x) => !x.done).toList();
    final done = tasks.where((x) => x.done).toList();
    final total = tasks.fold<int>(0, (s, x) => s + x.minutes);
    return _Page(
      t: t,
      title: 'Today\'s tasks',
      subtitle: '${done.length} of ${tasks.length} done.',
      trailing: _Btn(t, 'Clear completed', done.isEmpty ? null : () => p.clearCompleted(today),
          icon: Icons.delete_sweep_outlined),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _AddTaskRow(t: t, total: total, onAdd: (title) => p.add(today, title)),
        const SizedBox(height: 8),
        Expanded(
          child: tasks.isEmpty
              ? _Empty(t, Icons.checklist_rounded, 'No tasks today', 'Add one above to get started.')
              : ListView(children: [
                  for (var i = 0; i < open.length; i++) _row(open[i], i == open.length - 1),
                  if (done.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 22, bottom: 4),
                      child: Text('Completed', style: _ts(t.sub, 12.5, w: FontWeight.w600)),
                    ),
                    for (var i = 0; i < done.length; i++) _row(done[i], i == done.length - 1),
                  ],
                ]),
        ),
      ]),
    );
  }
}
