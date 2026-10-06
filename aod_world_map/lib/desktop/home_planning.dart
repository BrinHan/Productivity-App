part of 'home_page.dart';

class _PlanningView extends StatelessWidget {
  const _PlanningView({required this.t, required this.p});
  final _T t;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tasks = p.forDay(today);
    final planned = tasks.fold<int>(0, (s, x) => s + x.minutes);
    const capacity = 8 * 60;
    final over = planned > capacity;
    return _Page(
      t: t,
      title: 'Plan your day',
      subtitle: '${_dur(planned)} planned of ${_dur(capacity)} available${over ? '. That is too much for one day.' : '.'}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Bar(t, planned / capacity, warn: over, height: 6),
        const SizedBox(height: 20),
        _AddTaskRow(t: t, total: planned, onAdd: (title) => p.add(today, title)),
        const SizedBox(height: 8),
        Expanded(
          child: tasks.isEmpty
              ? _Empty(t, Icons.event_available_outlined, 'Nothing planned', 'Add your first task above.')
              : ListView(children: [
                  for (var i = 0; i < tasks.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        _Check(t, tasks[i].done, () => p.toggle(tasks[i])),
                        const SizedBox(width: 12),
                        Expanded(child: _StrikeText(t, tasks[i].title, tasks[i].done, size: 14)),
                        _IconBtn(t, Icons.remove_rounded, 'Shorter by 15 min', () => p.addMinutes(tasks[i], -15)),
                        SizedBox(
                          width: 58,
                          child: Text(_dur(tasks[i].minutes),
                              textAlign: TextAlign.center, style: _ts(t.text, 13, w: FontWeight.w600, tab: true)),
                        ),
                        _IconBtn(t, Icons.add_rounded, 'Longer by 15 min', () => p.addMinutes(tasks[i], 15)),
                        _IconBtn(t, Icons.arrow_forward_rounded, 'Move to tomorrow', () => p.moveDay(tasks[i], 1)),
                      ]),
                    ),
                    if (i < tasks.length - 1) _Hair(t),
                  ],
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
