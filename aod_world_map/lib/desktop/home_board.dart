part of 'home_page.dart';

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.t,
    required this.tag,
    required this.hideDone,
    required this.onTag,
    required this.onHide,
  });
  final _T t;
  final String tag;
  final bool hideDone;
  final ValueChanged<String> onTag;
  final VoidCallback onHide;

  CheckedPopupMenuItem<String> _item(String v, String label, bool checked) => CheckedPopupMenuItem(
        value: v,
        checked: checked,
        height: 38,
        child: Text(label, style: _ts(t.text, 13)),
      );

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Filter tasks',
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rSm + 2),
          side: BorderSide(color: t.line),
        ),
        onSelected: (v) => v == 'hide' ? onHide() : onTag(v),
        itemBuilder: (_) => [
          _item('all', 'All tags', tag == 'all'),
          _item('work', '#work', tag == 'work'),
          _item('personal', '#personal', tag == 'personal'),
          _item('health', '#health', tag == 'health'),
          const PopupMenuDivider(),
          _item('hide', 'Hide completed', hideDone),
        ],
        child: IgnorePointer(
          child: _Btn(t, tag == 'all' && !hideDone ? 'Filter' : 'Filtered', () {},
              compact: true, icon: Icons.filter_list_rounded),
        ),
      );
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.t,
    required this.p,
    required this.g,
    required this.date,
    required this.tasks,
    required this.isToday,
  });
  final _T t;
  final PlannerModel p;
  final GoogleService g;
  final DateTime date;
  final List<Task> tasks;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final all = p.forDay(date);
    final done = all.where((x) => x.done).length;
    final total = all.fold<int>(0, (s, x) => s + x.minutes);
    final gtasks = isToday ? g.todos : const <GoogleTask>[];
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_dayNames[date.weekday - 1], style: _ts(t.text, 24, w: FontWeight.w700, ls: -0.6)),
          if (isToday) ...[
            const SizedBox(width: 10),
            Text('Today', style: _ts(t.accent, 13, w: FontWeight.w600)),
          ],
        ]),
        const SizedBox(height: 2),
        Text('${_monthNames[date.month - 1]} ${date.day}', style: _ts(t.sub, 13)),
        const SizedBox(height: 14),
        _Bar(t, all.isEmpty ? 0 : done / all.length),
        const SizedBox(height: 8),
        Text(all.isEmpty ? 'Nothing planned yet' : '$done of ${all.length} done, ${_dur(total)} planned',
            style: _ts(t.sub, 12, tab: true)),
        const SizedBox(height: 16),
        _AddTaskRow(t: t, total: total, onAdd: (title) => p.add(date, title)),
        const SizedBox(height: 12),
        if (all.isEmpty && gtasks.isEmpty)
          _Empty(t, Icons.edit_calendar_outlined, 'A clear day', 'Add a task above to plan it.'),
        if (all.isNotEmpty && tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Everything here is hidden by your filter.', style: _ts(t.sub, 13)),
          ),
        for (final task in tasks) _TaskCard(t: t, p: p, task: task),
        if (gtasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text('Google Tasks', style: _ts(t.sub, 12, w: FontWeight.w600)),
          ),
          for (final gt in gtasks)
            _Tap(
              t: t,
              onTap: () => g.completeTask(gt),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(children: [
                  _Check(t, false, () => g.completeTask(gt), size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(gt.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13.5))),
                  if (gt.due != null) ...[
                    const SizedBox(width: 8),
                    Text('${_monthNames[gt.due!.month - 1].substring(0, 3)} ${gt.due!.day}',
                        style: _ts(t.sub, 12, tab: true)),
                  ],
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
