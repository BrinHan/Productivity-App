import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../aod/sky_toggle.dart';
import 'planner_model.dart';
import 'window_shell.dart';

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

String _fmt(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';

class _Hc {
  _Hc(this.dark)
      : bg = dark ? const Color(0xFF1C1C1E) : Colors.white,
        side = dark ? const Color(0xFF151517) : const Color(0xFFF1F1F1),
        card = dark ? const Color(0xFF2A2A2D) : Colors.white,
        border = dark ? const Color(0xFF3A3A3C) : const Color(0xFFE6E6E6),
        text = dark ? const Color(0xFFF2F2F7) : const Color(0xFF2B2B2B),
        sub = dark ? const Color(0xFF98989F) : const Color(0xFF8A8A8E);
  final bool dark;
  final Color bg, side, card, border, text, sub;
  static const green = Color(0xFF34C77B);
  static const orange = Color(0xFFF5A524);
  static const red = Color(0xFFFF6B6B);
}

enum _View { home, focus, planning, tasks, shutdown, week, review }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.shell,
    required this.planner,
    required this.isDark,
    required this.onDarkChanged,
  });
  final ShellController shell;
  final PlannerModel planner;
  final bool isDark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _View _view = _View.home;
  int _startOffset = 0;
  bool _board = true;
  String _tag = 'all';
  bool _hideDone = false;
  Timer? _clock;

  PlannerModel get p => widget.planner;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _Hc(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: c.bg,
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) => Column(
          children: [
            _TitleBar(c: c, shell: widget.shell),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(
                    c: c,
                    view: _view,
                    shutdown: p.shutdownToday,
                    onView: (v) => setState(() => _view = v),
                    onMap: widget.shell.showMap,
                    isDark: widget.isDark,
                    onDark: widget.onDarkChanged,
                  ),
                  Expanded(child: _content(c)),
                  _CalendarPanel(c: c, p: p, now: DateTime.now()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(_Hc c) {
    switch (_view) {
      case _View.home:
        return _boardView(c);
      case _View.focus:
        return _FocusView(c: c, p: p);
      case _View.planning:
        return _PlanningView(c: c, p: p);
      case _View.tasks:
        return _TaskListView(c: c, p: p);
      case _View.shutdown:
        return _ShutdownView(c: c, p: p, onMap: widget.shell.showMap);
      case _View.week:
        return _WeekView(
          c: c,
          p: p,
          onOpenDay: (offset) => setState(() {
            _startOffset = offset;
            _view = _View.home;
          }),
        );
      case _View.review:
        return _ReviewView(c: c, p: p);
    }
  }

  Widget _boardView(_Hc c) {
    final today = dayOf(DateTime.now());
    final count = _board ? 3 : 1;
    final days = [for (var i = 0; i < count; i++) today.add(Duration(days: _startOffset + i))];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          _Pill(c, Icons.today_outlined, 'Today', onTap: () => setState(() => _startOffset = 0)),
          const SizedBox(width: 8),
          _FilterButton(
            c: c,
            tag: _tag,
            hideDone: _hideDone,
            onTag: (t) => setState(() => _tag = t),
            onHide: () => setState(() => _hideDone = !_hideDone),
          ),
          const SizedBox(width: 8),
          _Pill(c, Icons.chevron_left, '', onTap: () => setState(() => _startOffset--)),
          const SizedBox(width: 4),
          _Pill(c, Icons.chevron_right, '', onTap: () => setState(() => _startOffset++)),
          const Spacer(),
          _Pill(
            c,
            _board ? Icons.view_list_outlined : Icons.view_column_outlined,
            _board ? 'List' : 'Board',
            onTap: () => setState(() => _board = !_board),
          ),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          itemCount: days.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (_, i) {
            var tasks = p.forDay(days[i]);
            if (_tag != 'all') tasks = tasks.where((t) => t.tag == _tag).toList();
            if (_hideDone) tasks = tasks.where((t) => !t.done).toList();
            return SizedBox(
              width: _board ? 300 : 620,
              child: _DayColumn(c: c, p: p, date: days[i], tasks: tasks),
            );
          },
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------- title bar

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.c, required this.shell});
  final _Hc c;
  final ShellController shell;

  @override
  Widget build(BuildContext context) => DragToMoveArea(
        child: Container(
          height: 42,
          color: c.side,
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(children: [
            Text('Orbit', style: TextStyle(color: c.sub, fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            _TbBtn(Icons.public, 'Screensaver map', c, shell.showMap),
            _TbBtn(Icons.picture_in_picture_alt_outlined, 'Minimize to island', c,
                () => shell.enterIsland()),
            _TbBtn(Icons.crop_square, 'Maximize', c, () => shell.toggleMaximize()),
            _TbBtn(Icons.close, 'Quit', c, () => shell.quit()),
          ]),
        ),
      );
}

class _TbBtn extends StatelessWidget {
  const _TbBtn(this.icon, this.tip, this.c, this.onTap);
  final IconData icon;
  final String tip;
  final _Hc c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tip,
        iconSize: 17,
        visualDensity: VisualDensity.compact,
        color: c.sub,
        icon: Icon(icon),
        onPressed: onTap,
      );
}

// --------------------------------------------------------------- sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.c,
    required this.view,
    required this.shutdown,
    required this.onView,
    required this.onMap,
    required this.isDark,
    required this.onDark,
  });
  final _Hc c;
  final _View view;
  final bool shutdown, isDark;
  final ValueChanged<_View> onView;
  final VoidCallback onMap;
  final ValueChanged<bool> onDark;

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 18, 0, 6),
        child: Text(t,
            style: TextStyle(color: c.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  Widget _nav(IconData icon, String label, _View v, {bool check = false}) => _Nav(
        c,
        icon,
        label,
        selected: view == v,
        check: check,
        onTap: () => onView(v),
      );

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        color: c.side,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 0, 14),
            child: Text('Orbit',
                style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          _nav(Icons.home_outlined, 'Home', _View.home),
          _nav(Icons.center_focus_strong_outlined, 'Focus', _View.focus),
          _section('DAY'),
          _nav(Icons.event_available_outlined, 'Daily planning', _View.planning),
          _nav(Icons.checklist, 'Daily task list', _View.tasks),
          _nav(Icons.bedtime_outlined, 'Daily shutdown', _View.shutdown, check: shutdown),
          _section('WEEK'),
          _nav(Icons.calendar_view_week, 'Weekly planning', _View.week),
          _nav(Icons.rate_review_outlined, 'Weekly review', _View.review),
          const Spacer(),
          _Nav(c, Icons.public, 'Screensaver map', onTap: onMap),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(children: [
              Text(isDark ? 'Dark' : 'Light', style: TextStyle(color: c.sub, fontSize: 12)),
              const Spacer(),
              SkyToggle(isNight: isDark, onChanged: onDark, em: 7),
            ]),
          ),
        ]),
      );
}

class _Nav extends StatelessWidget {
  const _Nav(this.c, this.icon, this.label, {this.selected = false, this.check = false, this.onTap});
  final _Hc c;
  final IconData icon;
  final String label;
  final bool selected, check;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? c.text.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 16, color: selected ? c.text : c.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
              if (check) const Icon(Icons.check, size: 14, color: _Hc.green),
            ]),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.c, this.icon, this.label, {this.onTap});
  final _Hc c;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: c.card,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 6 : 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: c.sub),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(label, style: TextStyle(color: c.text, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
        ),
      );
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.c,
    required this.tag,
    required this.hideDone,
    required this.onTag,
    required this.onHide,
  });
  final _Hc c;
  final String tag;
  final bool hideDone;
  final ValueChanged<String> onTag;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Filter tasks',
        onSelected: (v) => v == 'hide' ? onHide() : onTag(v),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: 'all', checked: tag == 'all', child: const Text('All tags')),
          CheckedPopupMenuItem(value: 'work', checked: tag == 'work', child: const Text('#work')),
          CheckedPopupMenuItem(
              value: 'personal', checked: tag == 'personal', child: const Text('#personal')),
          CheckedPopupMenuItem(value: 'health', checked: tag == 'health', child: const Text('#health')),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(value: 'hide', checked: hideDone, child: const Text('Hide completed')),
        ],
        child: IgnorePointer(
          child: _Pill(c, Icons.filter_list, tag == 'all' && !hideDone ? 'Filter' : 'Filter •'),
        ),
      );
}

// ----------------------------------------------------------- day column

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.c, required this.p, required this.date, required this.tasks});
  final _Hc c;
  final PlannerModel p;
  final DateTime date;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final all = p.forDay(date);
    final done = all.where((t) => t.done).length;
    final total = all.fold<int>(0, (s, t) => s + t.minutes);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_dayNames[date.weekday - 1],
            style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700)),
        Text('${_monthNames[date.month - 1]} ${date.day}',
            style: TextStyle(color: c.sub, fontSize: 13)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: all.isEmpty ? 0 : done / all.length,
            minHeight: 6,
            color: _Hc.green,
            backgroundColor: c.border,
          ),
        ),
        const SizedBox(height: 14),
        _AddTaskRow(c: c, total: total, onAdd: (t) => p.add(date, t)),
        const SizedBox(height: 10),
        for (final t in tasks) _TaskCard(c: c, p: p, task: t),
      ]),
    );
  }
}

class _AddTaskRow extends StatefulWidget {
  const _AddTaskRow({required this.c, required this.total, required this.onAdd});
  final _Hc c;
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
    if (v.trim().isEmpty) return;
    widget.onAdd(v.trim());
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        InkWell(onTap: () => _submit(_ctl.text), child: Icon(Icons.add, size: 16, color: c.sub)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _ctl,
            style: TextStyle(color: c.text, fontSize: 13),
            decoration: InputDecoration.collapsed(
              hintText: 'Add task',
              hintStyle: TextStyle(color: c.sub, fontSize: 13),
            ),
            onSubmitted: _submit,
          ),
        ),
        Text(_fmt(widget.total),
            style: TextStyle(color: c.sub, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Future<void> _rename(BuildContext context, PlannerModel p, Task t) async {
  final ctl = TextEditingController(text: t.title);
  final v = await showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('Rename task'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        onSubmitted: (s) => Navigator.of(dctx).pop(s),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dctx).pop(ctl.text), child: const Text('Save')),
      ],
    ),
  );
  ctl.dispose();
  if (v != null && v.trim().isNotEmpty) p.rename(t, v.trim());
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.c, required this.p, required this.task});
  final _Hc c;
  final PlannerModel p;
  final Task task;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Task options',
        iconSize: 16,
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz, size: 16, color: c.sub),
        onSelected: (v) {
          switch (v) {
            case 'edit':
              _rename(context, p, task);
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
              p.remove(task);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Rename')),
          PopupMenuItem(value: 'next', child: Text('Move to next day')),
          PopupMenuItem(value: 'prev', child: Text('Move to previous day')),
          PopupMenuItem(value: 'plus', child: Text('+15 min')),
          PopupMenuItem(value: 'minus', child: Text('−15 min')),
          PopupMenuItem(value: 'tag', child: Text('Switch tag')),
          PopupMenuItem(value: 'focus', child: Text('Use in Focus')),
          PopupMenuItem(value: 'del', child: Text('Delete')),
        ],
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.c, required this.p, required this.task});
  final _Hc c;
  final PlannerModel p;
  final Task task;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: task.done ? 0.55 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(task.title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                    )),
              ),
              InkWell(
                onTap: () => p.addMinutes(task, 15),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(4)),
                  child: Text(_fmt(task.minutes),
                      style: TextStyle(color: c.sub, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
              SizedBox(width: 24, height: 20, child: _TaskMenu(c: c, p: p, task: task)),
            ]),
            for (final s in task.subs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  _Check(done: s.done, c: c, onTap: () => p.toggleSub(task, s)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.title, style: TextStyle(color: c.text, fontSize: 13))),
                ]),
              ),
            const SizedBox(height: 10),
            Row(children: [
              _Check(done: task.done, c: c, onTap: () => p.toggle(task)),
              const Spacer(),
              InkWell(
                onTap: () => p.cycleTag(task),
                child: Text('#${task.tag}',
                    style: const TextStyle(
                        color: _Hc.orange, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
      );
}

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.c, required this.onTap});
  final bool done;
  final _Hc c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _Hc.green : Colors.transparent,
              border: Border.all(color: done ? _Hc.green : c.sub, width: 1.4),
            ),
            child: done ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
          ),
        ),
      );
}

// ------------------------------------------------------------ small views

class _ViewShell extends StatelessWidget {
  const _ViewShell({required this.c, required this.title, required this.subtitle, required this.child});
  final _Hc c;
  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: c.text, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: c.sub, fontSize: 13)),
          const SizedBox(height: 18),
          Expanded(child: child),
        ]),
      );
}

class _Btn extends StatelessWidget {
  const _Btn(this.c, this.label, this.onTap, {this.primary = false, this.icon});
  final _Hc c;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? _Hc.green : c.card,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primary ? _Hc.green : c.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: primary ? Colors.white : c.text),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                    color: primary ? Colors.white : c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
            ]),
          ),
        ),
      );
}

class _FocusView extends StatelessWidget {
  const _FocusView({required this.c, required this.p});
  final _Hc c;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final today = p.forDay(DateTime.now()).where((t) => !t.done).toList();
    final left = p.focusSeconds;
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');
    final progress = p.focusTotal == 0 ? 0.0 : 1 - left / p.focusTotal;
    final selected = today.contains(p.focusTask) ? p.focusTask : null;

    return _ViewShell(
      c: c,
      title: 'Focus',
      subtitle: 'One task, one timer.',
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  color: _Hc.green,
                  backgroundColor: c.border,
                ),
              ),
              Text('$mm:$ss',
                  style: TextStyle(
                      color: c.text, fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1.5)),
            ]),
          ),
          const SizedBox(height: 22),
          DropdownButton<Task?>(
            value: selected,
            hint: Text('Choose a task', style: TextStyle(color: c.sub)),
            dropdownColor: c.card,
            style: TextStyle(color: c.text, fontSize: 14),
            underline: const SizedBox.shrink(),
            items: [
              for (final t in today) DropdownMenuItem<Task?>(value: t, child: Text(t.title)),
            ],
            onChanged: p.pickFocusTask,
          ),
          const SizedBox(height: 14),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _Btn(c, p.focusRunning ? 'Pause' : 'Start', p.focusRunning ? p.pauseFocus : p.startFocus,
                primary: true, icon: p.focusRunning ? Icons.pause : Icons.play_arrow),
            const SizedBox(width: 8),
            _Btn(c, 'Reset', p.resetFocus, icon: Icons.restart_alt),
            const SizedBox(width: 8),
            _Btn(c, '25 / 50 min', () => p.setFocusMinutes(p.focusTotal == 25 * 60 ? 50 : 25)),
            if (selected != null) ...[
              const SizedBox(width: 8),
              _Btn(c, 'Complete task', () {
                p.toggle(selected);
                p.pickFocusTask(null);
              }, icon: Icons.check),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _PlanningView extends StatelessWidget {
  const _PlanningView({required this.c, required this.p});
  final _Hc c;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tasks = p.forDay(today);
    final planned = tasks.fold<int>(0, (s, t) => s + t.minutes);
    const capacity = 8 * 60;
    final over = planned > capacity;
    return _ViewShell(
      c: c,
      title: 'Plan your day',
      subtitle: '${_fmt(planned)} planned of ${_fmt(capacity)} available${over ? ' - too much' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (planned / capacity).clamp(0.0, 1.0),
            minHeight: 8,
            color: over ? _Hc.red : _Hc.green,
            backgroundColor: c.border,
          ),
        ),
        const SizedBox(height: 16),
        _AddTaskRow(c: c, total: planned, onAdd: (t) => p.add(today, t)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(children: [
            for (final t in tasks)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Row(children: [
                  _Check(done: t.done, c: c, onTap: () => p.toggle(t)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t.title, style: TextStyle(color: c.text, fontSize: 14))),
                  IconButton(
                    iconSize: 18,
                    color: c.sub,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => p.addMinutes(t, -15),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text(_fmt(t.minutes),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    iconSize: 18,
                    color: c.sub,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => p.addMinutes(t, 15),
                  ),
                  IconButton(
                    iconSize: 18,
                    color: c.sub,
                    tooltip: 'Move to tomorrow',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => p.moveDay(t, 1),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _TaskListView extends StatelessWidget {
  const _TaskListView({required this.c, required this.p});
  final _Hc c;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tasks = p.forDay(today);
    return _ViewShell(
      c: c,
      title: 'Today\'s tasks',
      subtitle: '${tasks.where((t) => t.done).length} of ${tasks.length} done',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _AddTaskRow(c: c, total: tasks.fold<int>(0, (s, t) => s + t.minutes), onAdd: (t) => p.add(today, t))),
          const SizedBox(width: 10),
          _Btn(c, 'Clear completed', () => p.clearCompleted(today), icon: Icons.delete_sweep_outlined),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(children: [
            for (final t in tasks)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Row(children: [
                  _Check(done: t.done, c: c, onTap: () => p.toggle(t)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t.title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          decoration: t.done ? TextDecoration.lineThrough : null,
                        )),
                  ),
                  Text('#${t.tag}', style: const TextStyle(color: _Hc.orange, fontSize: 11)),
                  const SizedBox(width: 10),
                  Text(_fmt(t.minutes), style: TextStyle(color: c.sub, fontSize: 12)),
                  SizedBox(width: 28, child: _TaskMenu(c: c, p: p, task: t)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ShutdownView extends StatelessWidget {
  const _ShutdownView({required this.c, required this.p, required this.onMap});
  final _Hc c;
  final PlannerModel p;
  final VoidCallback onMap;

  Widget _stat(String label, String value, Color col) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(color: col, fontSize: 30, fontWeight: FontWeight.w700)),
            Text(label, style: TextStyle(color: c.sub, fontSize: 12)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tasks = p.forDay(DateTime.now());
    final done = tasks.where((t) => t.done).toList();
    final left = tasks.where((t) => !t.done).toList();
    final doneMin = done.fold<int>(0, (s, t) => s + t.minutes);
    return _ViewShell(
      c: c,
      title: p.shutdownToday ? 'Shut down - see you tomorrow' : 'Daily shutdown',
      subtitle: 'Review today, then close the loop.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _stat('Completed', '${done.length}', _Hc.green),
          const SizedBox(width: 12),
          _stat('Still open', '${left.length}', left.isEmpty ? c.text : _Hc.orange),
          const SizedBox(width: 12),
          _stat('Time done', _fmt(doneMin), c.text),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Btn(c, 'Move ${left.length} unfinished to tomorrow', left.isEmpty ? null : p.moveUnfinishedToTomorrow,
              icon: Icons.arrow_forward),
          _Btn(c, p.shutdownToday ? 'Reopen day' : 'Finish shutdown',
              () => p.setShutdown(!p.shutdownToday),
              primary: !p.shutdownToday, icon: Icons.bedtime_outlined),
          _Btn(c, 'Open screensaver', onMap, icon: Icons.public),
        ]),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(children: [
            for (final t in left)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.circle_outlined, size: 14, color: _Hc.orange),
                  const SizedBox(width: 8),
                  Text(t.title, style: TextStyle(color: c.text, fontSize: 14)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({required this.c, required this.p, required this.onOpenDay});
  final _Hc c;
  final PlannerModel p;
  final ValueChanged<int> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return _ViewShell(
      c: c,
      title: 'Weekly planning',
      subtitle: 'Tap a day to open it on the board.',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _weekCard(monday.add(Duration(days: i)), today),
            ),
          ),
      ]),
    );
  }

  Widget _weekCard(DateTime d, DateTime today) {
    final tasks = p.forDay(d);
    final isToday = d == today;
    final mins = tasks.fold<int>(0, (s, t) => s + t.minutes);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onOpenDay(d.difference(today).inDays),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isToday ? _Hc.green : c.border, width: isToday ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_dayNames[d.weekday - 1].substring(0, 3).toUpperCase(),
              style: TextStyle(color: c.sub, fontSize: 10, fontWeight: FontWeight.w700)),
          Text('${d.day}', style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${tasks.length} tasks', style: TextStyle(color: c.text, fontSize: 12)),
          Text(_fmt(mins), style: TextStyle(color: c.sub, fontSize: 11)),
          const SizedBox(height: 8),
          for (final t in tasks.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.done ? c.sub : c.text,
                    fontSize: 11,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                  )),
            ),
        ]),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({required this.c, required this.p});
  final _Hc c;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final done = [for (final d in days) p.forDay(d).where((t) => t.done).length];
    final total = [for (final d in days) p.forDay(d).length];
    final sumDone = done.fold<int>(0, (a, b) => a + b);
    final sumTotal = total.fold<int>(0, (a, b) => a + b);
    final maxV = total.fold<int>(1, (a, b) => a > b ? a : b);
    final rate = sumTotal == 0 ? 0 : (sumDone / sumTotal * 100).round();
    return _ViewShell(
      c: c,
      title: 'Weekly review',
      subtitle: '$sumDone of $sumTotal tasks done - $rate% completion',
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${done[i]}/${total[i]}', style: TextStyle(color: c.sub, fontSize: 11)),
                const SizedBox(height: 6),
                Stack(alignment: Alignment.bottomCenter, children: [
                  Container(
                    height: 180 * total[i] / maxV + 4,
                    decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(6)),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    height: 180 * done[i] / maxV,
                    decoration: BoxDecoration(color: _Hc.green, borderRadius: BorderRadius.circular(6)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(_dayNames[i].substring(0, 3),
                    style: TextStyle(
                        color: days[i] == today ? c.text : c.sub,
                        fontSize: 11,
                        fontWeight: days[i] == today ? FontWeight.w700 : FontWeight.w500)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// -------------------------------------------------------------- calendar

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({required this.c, required this.p, required this.now});
  final _Hc c;
  final PlannerModel p;
  final DateTime now;

  static const _rowH = 56.0;
  static const _startHour = 6, _endHour = 20;
  static const _blockColors = [
    Color(0xFF7FD6E0), Color(0xFFB5A8FF), Color(0xFFFFC857), Color(0xFF8FE3A1), Color(0xFFFF9FB2),
  ];

  String _label(int h) => h == 12 ? '12 PM' : (h < 12 ? '$h AM' : '${h - 12} PM');

  @override
  Widget build(BuildContext context) {
    final hours = _endHour - _startHour;
    final nowPos = (now.hour + now.minute / 60 - _startHour).clamp(0.0, hours.toDouble()) * _rowH;
    final tasks = p.forDay(now);
    var cursor = 9 * 60; // today's tasks are scheduled back to back from 9:00
    final blocks = <Widget>[];
    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final top = (cursor - _startHour * 60) / 60 * _rowH;
      final h = (t.minutes / 60 * _rowH).clamp(22.0, 600.0).toDouble();
      cursor += t.minutes;
      blocks.add(Positioned(
        top: top + 1,
        left: 62,
        right: 10,
        height: h - 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => p.toggle(t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _blockColors[i % _blockColors.length].withValues(alpha: t.done ? 0.25 : 0.6),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.dark ? Colors.white : const Color(0xFF1C1C1E),
                  fontSize: 11,
                  decoration: t.done ? TextDecoration.lineThrough : null,
                )),
          ),
        ),
      ));
    }
    return Container(
      width: 290,
      decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_dayNames[now.weekday - 1].substring(0, 3).toUpperCase(),
                  style: TextStyle(color: c.sub, fontSize: 11, fontWeight: FontWeight.w700)),
              Text('${now.day}',
                  style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: hours * _rowH + 20,
              child: Stack(children: [
                for (var i = 0; i <= hours; i++)
                  Positioned(
                    top: i * _rowH,
                    left: 0,
                    right: 0,
                    child: Row(children: [
                      SizedBox(
                        width: 56,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Text(_label(_startHour + i),
                              style: TextStyle(color: c.sub, fontSize: 10)),
                        ),
                      ),
                      Expanded(child: Divider(height: 1, color: c.border)),
                    ]),
                  ),
                ...blocks,
                Positioned(
                  top: nowPos - 10,
                  left: 40,
                  right: 0,
                  child: Row(children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(color: _Hc.green, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 13, color: Colors.white),
                    ),
                    Expanded(child: Container(height: 1.5, color: _Hc.red)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
