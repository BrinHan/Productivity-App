part of 'home_page.dart';

class _ShutdownView extends StatelessWidget {
  const _ShutdownView({required this.t, required this.p, required this.onMap});
  final _T t;
  final PlannerModel p;
  final VoidCallback onMap;

  Widget _stat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: _ts(color, 44, w: FontWeight.w300, ls: -1.5, tab: true)),
          const SizedBox(height: 2),
          Text(label, style: _ts(t.sub, 13)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final tasks = p.forDay(DateTime.now());
    final done = tasks.where((x) => x.done).toList();
    final left = tasks.where((x) => !x.done).toList();
    final doneMin = done.fold<int>(0, (s, x) => s + x.minutes);
    return _Page(
      t: t,
      title: p.shutdownToday ? 'Shut down. See you tomorrow.' : 'Daily shutdown',
      subtitle: 'Review today, then close the loop. Anything still open moves to tomorrow on its own, marked as slipped.',
      child: ListView(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _stat('Completed', '${done.length}', t.accent),
            VerticalDivider(width: 56, thickness: 1, color: t.line),
            _stat('Still open', '${left.length}', t.text),
            VerticalDivider(width: 56, thickness: 1, color: t.line),
            _stat('Time done', _dur(doneMin), t.text),
          ]),
        ),
        const SizedBox(height: 28),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _Btn(t, 'Move ${left.length} to tomorrow', left.isEmpty ? null : p.moveUnfinishedToTomorrow,
              icon: Icons.arrow_forward_rounded),
          _Btn(t, p.shutdownToday ? 'Reopen day' : 'Finish shutdown', () => p.setShutdown(!p.shutdownToday),
              primary: !p.shutdownToday, icon: Icons.bedtime_outlined),
          _Btn(t, 'Open screensaver', onMap, icon: Icons.public),
        ]),
        const SizedBox(height: 28),
        if (left.isEmpty && tasks.isNotEmpty)
          _Empty(t, Icons.task_alt_rounded, 'All done', 'Nothing left to move. Finish the shutdown when you are ready.')
        else if (left.isNotEmpty) ...[
          Text('Still open', style: _ts(t.sub, 12.5, w: FontWeight.w600)),
          const SizedBox(height: 4),
          for (var i = 0; i < left.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(left[i].title, style: _ts(t.text, 14))),
                if (left[i].slipped > 0) ...[
                  _SlipChip(t, left[i].slipped),
                  const SizedBox(width: 10),
                ],
                Text(_dur(left[i].minutes), style: _ts(t.sub, 12, w: FontWeight.w600, tab: true)),
                const SizedBox(width: 6),
                _IconBtn(t, Icons.task_alt_rounded, 'Done after all', () => p.toggle(left[i])),
                _IconBtn(t, Icons.arrow_forward_rounded, 'Tomorrow', () => p.slip(left[i])),
                _IconBtn(t, Icons.delete_outline_rounded, 'Drop it', () => _deleteWithUndo(context, t, p, left[i])),
              ]),
            ),
            if (i < left.length - 1) _Hair(t),
          ],
        ],
      ]),
    );
  }
}
