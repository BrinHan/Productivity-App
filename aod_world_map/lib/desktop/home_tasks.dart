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

/// Bottom drawer: handle, centred title and description, body, footer buttons.
Future<T?> _drawer<T>(
  BuildContext context,
  _T t, {
  required String title,
  required String description,
  required Widget Function(void Function(T?) close) body,
  required List<Widget> Function(void Function(T?) close) footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.surface,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    constraints: const BoxConstraints(maxWidth: double.infinity),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      side: BorderSide(color: t.line),
    ),
    builder: (sheet) {
      void close(T? v) => Navigator.of(sheet).pop(v);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          Container(
            width: 100,
            height: 8,
            decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(4)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title, textAlign: TextAlign.center, style: _ts(t.text, 18, w: FontWeight.w600, ls: -0.3)),
                const SizedBox(height: 6),
                Text(description, textAlign: TextAlign.center, style: _ts(t.sub, 14, h: 1.45)),
                const SizedBox(height: 20),
                body(close),
                const SizedBox(height: 24),
                Row(children: footer(close)),
              ]),
            ),
          ),
        ]),
      );
    },
  );
}

Future<void> _rename(BuildContext context, _T t, PlannerModel p, Task task) async {
  final ctl = TextEditingController(text: task.title);
  final v = await _drawer<String>(
    context,
    t,
    title: 'Rename task',
    description: 'Give this task a clearer name.',
    body: (close) => _Labeled(t, 'Task name', ctl, autofocus: true, onSubmitted: (s) => close(s)),
    footer: (close) => [
      Expanded(child: _Btn(t, 'Save', () => close(ctl.text), primary: true, fill: true)),
      const SizedBox(width: 12),
      Expanded(child: _Btn(t, 'Cancel', () => close(null), fill: true)),
    ],
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
        final r = p.add(task.day, task.title, minutes: task.minutes, tag: task.tag)..slipped = task.slipped;
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
                  child: _StrikeText(t, task.title, task.done, size: 14, w: FontWeight.w600, h: 1.3),
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
                        padding: const EdgeInsets.all(2),
                        child: _TagChip(t, task.tag),
                      ),
                    ),
                  ),
                  if (task.slipped > 0 && !task.done) ...[
                    const SizedBox(width: 4),
                    _SlipChip(t, task.slipped),
                  ],
                ]),
              ]),
            ),
            SizedBox(width: 30, height: 30, child: _TaskMenu(t: t, p: p, task: task)),
          ]),
        ),
      );
}
