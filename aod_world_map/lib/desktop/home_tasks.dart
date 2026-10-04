part of 'home_page.dart';

class _AddTaskRow extends StatefulWidget {
  const _AddTaskRow({required this.t, required this.total, required this.onAdd});
  final _T t;
  final int total;
  final ValueChanged<String> onAdd;

  @override
  State<_AddTaskRow> createState() => _AddTaskRowState();
}

class _AddTaskRowState extends State<_AddTaskRow> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final s = v.trim();
    if (s.isEmpty) return;
    widget.onAdd(s);
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return TextField(
      controller: _ctl,
      style: _ts(t.text, 13),
      cursorColor: t.accent,
      onSubmitted: _submit,
      decoration: _deco(
        t,
        'Add a task',
        prefix: Icon(Icons.add_rounded, size: 18, color: t.sub),
        suffix: widget.total > 0
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(_dur(widget.total), style: _ts(t.sub, 12, w: FontWeight.w600, tab: true)),
                ),
              )
            : null,
      ),
    );
  }
}

Future<void> _rename(BuildContext context, _T t, PlannerModel p, Task task) async {
  final ctl = TextEditingController(text: task.title);
  final v = await showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_rLg),
        side: BorderSide(color: t.line),
      ),
      title: Text('Rename task', style: _ts(t.text, 16, w: FontWeight.w700)),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: ctl,
          autofocus: true,
          style: _ts(t.text, 13),
          cursorColor: t.accent,
          decoration: _deco(t, 'Task name'),
          onSubmitted: (s) => Navigator.of(dctx).pop(s),
        ),
      ),
      actions: [
        _Btn(t, 'Cancel', () => Navigator.of(dctx).pop(), compact: true),
        _Btn(t, 'Save', () => Navigator.of(dctx).pop(ctl.text), primary: true, compact: true),
      ],
    ),
  );
  ctl.dispose();
  if (v != null && v.trim().isNotEmpty) p.rename(task, v.trim());
}

/// Delete with an Undo bar instead of a confirm dialog.
void _deleteWithUndo(BuildContext context, _T t, PlannerModel p, Task task) {
  final m = ScaffoldMessenger.of(context);
  p.remove(task);
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    width: 360,
    backgroundColor: t.raised,
    duration: const Duration(seconds: 5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_rSm),
      side: BorderSide(color: t.line),
    ),
    content: Text('Deleted "${task.title}"', maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13)),
    action: SnackBarAction(
      label: 'Undo',
      textColor: t.accent,
      onPressed: () {
        final r = p.add(task.day, task.title, minutes: task.minutes, tag: task.tag);
        for (final s in task.subs) {
          r.subs.add(Sub(s.title, s.done));
        }
        if (task.done) {
          p.toggle(r);
        } else {
          p.rename(r, r.title);
        }
      },
    ),
  ));
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.t, required this.p, required this.task});
  final _T t;
  final PlannerModel p;
  final Task task;

  PopupMenuItem<String> _item(String v, String label, {bool danger = false}) => PopupMenuItem(
        value: v,
        height: 38,
        child: Text(label, style: _ts(danger ? t.warn : t.text, 13)),
      );

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Task options',
        padding: EdgeInsets.zero,
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rSm + 2),
          side: BorderSide(color: t.line),
        ),
        icon: Icon(Icons.more_horiz_rounded, size: 18, color: t.sub),
        onSelected: (v) {
          switch (v) {
            case 'edit':
              _rename(context, t, p, task);
            case 'next':
              p.moveDay(task, 1);
            case 'prev':
              p.moveDay(task, -1);
            case 'plus':
              p.addMinutes(task, 15);
            case 'minus':
              p.addMinutes(task, -15);
            case 'tag':
              p.cycleTag(task);
            case 'focus':
              p.pickFocusTask(task);
            case 'del':
              _deleteWithUndo(context, t, p, task);
          }
        },
        itemBuilder: (_) => [
          _item('edit', 'Rename'),
          _item('next', 'Move to next day'),
          _item('prev', 'Move to previous day'),
          _item('plus', '+15 min'),
          _item('minus', '−15 min'),
          _item('tag', 'Switch tag'),
          _item('focus', 'Use in Focus'),
          _item('del', 'Delete', danger: true),
        ],
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.t, required this.p, required this.task});
  final _T t;
  final PlannerModel p;
  final Task task;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: task.done ? 0.55 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(_rLg),
            border: Border.all(color: t.line),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: _Check(t, task.done, () => p.toggle(task)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(task.title,
                      style: _ts(t.text, 14,
                          w: FontWeight.w600, h: 1.3, deco: task.done ? TextDecoration.lineThrough : null)),
                ),
                for (final s in task.subs)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      _Check(t, s.done, () => p.toggleSub(task, s), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.title, style: _ts(s.done ? t.sub : t.text, 13))),
                    ]),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Tooltip(
                    message: 'Add 15 minutes',
                    child: _Tap(
                      t: t,
                      radius: 6,
                      onTap: () => p.addMinutes(task, 15),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text(_dur(task.minutes), style: _ts(t.sub, 12, w: FontWeight.w600, tab: true)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Switch tag',
                    child: _Tap(
                      t: t,
                      radius: 6,
                      onTap: () => p.cycleTag(task),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text('#${task.tag}', style: _ts(t.sub, 12)),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
            SizedBox(width: 30, height: 30, child: _TaskMenu(t: t, p: p, task: task)),
          ]),
        ),
      );
}
