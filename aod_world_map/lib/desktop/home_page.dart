import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../aod/sky_toggle.dart';
import 'window_shell.dart';

const _dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

class Sub {
  Sub(this.title, [this.done = false]);
  final String title;
  bool done;
}

class Task {
  Task(this.title, {this.minutes = 30, this.tag = 'work', List<Sub>? subs, this.done = false})
      : subs = subs ?? [];
  final String title;
  final int minutes;
  final String tag;
  final List<Sub> subs;
  bool done;
}

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
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.shell,
    required this.isDark,
    required this.onDarkChanged,
  });
  final ShellController shell;
  final bool isDark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _clock;

  final List<List<Task>> _tasks = [
    [
      Task('Blog post research', minutes: 300, subs: [
        Sub('Making a list of productivity apps'),
        Sub('Check what apps people are using'),
      ]),
      Task('meeting'),
    ],
    [
      Task('Weekly meeting', minutes: 60),
      Task('Daily planning', done: true),
    ],
    [],
  ];

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _Hc(Theme.of(context).brightness == Brightness.dark);
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _TitleBar(c: c, shell: widget.shell),
          Expanded(
            child: Row(
              children: [
                _Sidebar(
                  c: c,
                  shell: widget.shell,
                  isDark: widget.isDark,
                  onDark: widget.onDarkChanged,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(children: [
                          _Pill(c, Icons.today_outlined, 'Today'),
                          const SizedBox(width: 8),
                          _Pill(c, Icons.filter_list, 'Filter'),
                          const Spacer(),
                          _Pill(c, Icons.view_column_outlined, 'Board'),
                        ]),
                      ),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(16),
                          itemCount: _tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 16),
                          itemBuilder: (_, i) => SizedBox(
                            width: 300,
                            child: _DayColumn(
                              c: c,
                              date: now.add(Duration(days: i)),
                              tasks: _tasks[i],
                              onChanged: () => setState(() {}),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _CalendarPanel(c: c, now: now),
              ],
            ),
          ),
        ],
      ),
    );
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
          child: Row(
            children: [
              Text('Orbit',
                  style: TextStyle(color: c.sub, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              _TbBtn(Icons.public, 'Screensaver map', c, shell.showMap),
              _TbBtn(Icons.picture_in_picture_alt_outlined, 'Minimize to island', c,
                  () => shell.enterIsland()),
              _TbBtn(Icons.crop_square, 'Maximize', c, () => shell.toggleMaximize()),
              _TbBtn(Icons.close, 'Quit', c, () => shell.quit()),
            ],
          ),
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
    required this.shell,
    required this.isDark,
    required this.onDark,
  });
  final _Hc c;
  final ShellController shell;
  final bool isDark;
  final ValueChanged<bool> onDark;

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 18, 0, 6),
        child: Text(t,
            style: TextStyle(
                color: c.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        color: c.side,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 0, 14),
              child: Row(children: [
                Text('Orbit',
                    style: TextStyle(
                        color: c.text, fontSize: 15, fontWeight: FontWeight.w700)),
                Icon(Icons.keyboard_arrow_down, size: 18, color: c.sub),
              ]),
            ),
            _Nav(c, Icons.home_outlined, 'Home', selected: true),
            _Nav(c, Icons.center_focus_strong_outlined, 'Focus'),
            _section('DAY'),
            _Nav(c, Icons.event_available_outlined, 'Daily planning', check: true),
            _Nav(c, Icons.checklist, 'Daily task list'),
            _Nav(c, Icons.bedtime_outlined, 'Daily shutdown'),
            _section('WEEK'),
            _Nav(c, Icons.calendar_view_week, 'Weekly planning'),
            _Nav(c, Icons.rate_review_outlined, 'Weekly review'),
            const Spacer(),
            _Nav(c, Icons.public, 'Screensaver map', onTap: shell.showMap),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(children: [
                Text(isDark ? 'Dark' : 'Light',
                    style: TextStyle(color: c.sub, fontSize: 12)),
                const Spacer(),
                SkyToggle(isNight: isDark, onChanged: onDark, em: 7),
              ]),
            ),
          ],
        ),
      );
}

class _Nav extends StatelessWidget {
  const _Nav(this.c, this.icon, this.label,
      {this.selected = false, this.check = false, this.onTap});
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
          onTap: onTap ?? () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 16, color: c.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: c.text, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              if (check) Icon(Icons.check, size: 14, color: c.sub),
            ]),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.c, this.icon, this.label);
  final _Hc c;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c.sub),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: c.text, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
      );
}

// ----------------------------------------------------------- day column

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.c,
    required this.date,
    required this.tasks,
    required this.onChanged,
  });
  final _Hc c;
  final DateTime date;
  final List<Task> tasks;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final done = tasks.where((t) => t.done).length;
    final total = tasks.fold<int>(0, (s, t) => s + t.minutes);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dayNames[date.weekday - 1],
              style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700)),
          Text('${_monthNames[date.month - 1]} ${date.day}',
              style: TextStyle(color: c.sub, fontSize: 13)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: tasks.isEmpty ? 0 : done / tasks.length,
              minHeight: 6,
              color: _Hc.green,
              backgroundColor: c.border,
            ),
          ),
          const SizedBox(height: 14),
          _AddTaskRow(
            c: c,
            total: total,
            onAdd: (title) {
              tasks.add(Task(title));
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          for (final t in tasks) _TaskCard(c: c, task: t, onChanged: onChanged),
        ],
      ),
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
        Icon(Icons.add, size: 16, color: c.sub),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _ctl,
            style: TextStyle(color: c.text, fontSize: 13),
            decoration: InputDecoration.collapsed(
              hintText: 'Add task',
              hintStyle: TextStyle(color: c.sub, fontSize: 13),
            ),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              widget.onAdd(v.trim());
              _ctl.clear();
            },
          ),
        ),
        Text(_fmt(widget.total),
            style: TextStyle(color: c.sub, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.c, required this.task, required this.onChanged});
  final _Hc c;
  final Task task;
  final VoidCallback onChanged;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(task.title,
                      style: TextStyle(
                          color: c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_fmt(task.minutes),
                      style: TextStyle(
                          color: c.sub, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
              for (final s in task.subs)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    _Check(done: s.done, c: c, onTap: () {
                      s.done = !s.done;
                      onChanged();
                    }),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.title,
                          style: TextStyle(color: c.text, fontSize: 13)),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
              Row(children: [
                _Check(done: task.done, c: c, onTap: () {
                  task.done = !task.done;
                  for (final s in task.subs) {
                    s.done = task.done;
                  }
                  onChanged();
                }),
                const Spacer(),
                Text('#${task.tag}',
                    style: const TextStyle(
                        color: _Hc.orange, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
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
          child: Container(
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

// -------------------------------------------------------------- calendar

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({required this.c, required this.now});
  final _Hc c;
  final DateTime now;

  static const _rowH = 56.0;
  static const _startHour = 6, _endHour = 18;

  String _label(int h) => h == 12 ? '12 PM' : (h < 12 ? '$h AM' : '${h - 12} PM');

  @override
  Widget build(BuildContext context) {
    final hours = _endHour - _startHour;
    final nowPos =
        (now.hour + now.minute / 60 - _startHour).clamp(0.0, hours.toDouble()) * _rowH;
    return Container(
      width: 290,
      decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_dayNames[now.weekday - 1].substring(0, 3).toUpperCase(),
                    style: TextStyle(
                        color: c.sub, fontSize: 11, fontWeight: FontWeight.w700)),
                Text('${now.day}',
                    style: TextStyle(
                        color: c.text, fontSize: 22, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: hours * _rowH + 20,
                child: Stack(
                  children: [
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
                    Positioned(
                      top: (10 - _startHour) * _rowH + 4,
                      left: 62,
                      right: 10,
                      height: _rowH * 0.5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7FD6E0).withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Take-Off',
                            style: TextStyle(color: c.text, fontSize: 11)),
                      ),
                    ),
                    Positioned(
                      top: nowPos - 10,
                      left: 40,
                      right: 0,
                      child: Row(children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                              color: _Hc.green, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 13, color: Colors.white),
                        ),
                        Expanded(child: Container(height: 1.5, color: const Color(0xFFFF6B6B))),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
