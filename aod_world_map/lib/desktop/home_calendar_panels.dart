part of 'home_page.dart';

// The calendar's side panels for reading and editing an event or task
// (see home_calendar.dart).

// --------------------------------------------------------------- panels

/// A labelled property row in the side panel, Notion style.
class _PropRow extends StatelessWidget {
  const _PropRow(this.t, this.icon, this.child);
  final _T t;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 7), child: Icon(icon, size: 16, color: t.sub)),
          const SizedBox(width: 10),
          Expanded(child: child),
        ]),
      );
}

/// Small clickable value, like Notion's property pills.
class _Pill extends StatelessWidget {
  const _Pill(this.t, this.label, this.onTap, {this.leading});
  final _T t;
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => _Hover(
        onTap: onTap,
        builder: (h) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: h && onTap != null ? t.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13, w: FontWeight.w500, tab: true)),
            ),
          ]),
        ),
      );
}

/// Borderless text field for the panel.
Widget _panelField(_T t, TextEditingController c, String hint,
        {double size = 13,
        FontWeight w = FontWeight.w500,
        bool autofocus = false,
        int? maxLines = 1,
        bool readOnly = false,
        ValueChanged<String>? onChanged,
        ValueChanged<String>? onSubmitted}) =>
    TextField(
      controller: c,
      autofocus: autofocus,
      readOnly: readOnly,
      maxLines: maxLines,
      // Titles wrap but Enter still submits; only free text takes new lines.
      textInputAction: onSubmitted != null ? TextInputAction.done : null,
      minLines: 1,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: t.focus,
      style: _ts(t.text, size, w: w),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: _ts(t.faint, size, w: w),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      ),
    );

/// Read or edit an event. Changes stay local until Save (Enter in the title
/// saves too); a draft shows its changes on the grid as you make them.
class _CalEventPanel extends StatefulWidget {
  const _CalEventPanel({
    super.key,
    required this.t,
    required this.g,
    required this.e,
    required this.editable,
    required this.color,
    required this.onDraftChanged,
    required this.onSave,
    required this.onDelete,
    required this.onCreateTask,
    required this.onClose,
    required this.onReconnect,
  });
  final _T t;
  final GoogleService g;
  final CalEvent e;
  final bool editable;
  final Color color;
  final ValueChanged<CalEvent> onDraftChanged;
  final ValueChanged<CalEvent> onSave;
  final VoidCallback onDelete, onClose, onReconnect;
  final void Function(String title, DateTime day, bool google) onCreateTask;

  @override
  State<_CalEventPanel> createState() => _CalEventPanelState();
}

class _CalEventPanelState extends State<_CalEventPanel> {
  late CalEvent _e = widget.e;
  late final _title = TextEditingController(text: widget.e.title);
  late final _place = TextEditingController(text: widget.e.location);
  late final _notes = TextEditingController(text: widget.e.description);
  bool _task = false; // a draft can become a task instead
  bool _googleTask = false;

  _T get t => widget.t;
  bool get _draft => widget.e.isDraft;

  bool get _dirty =>
      _e.title != widget.e.title ||
      _e.start != widget.e.start ||
      _e.end != widget.e.end ||
      _e.allDay != widget.e.allDay ||
      _e.calId != widget.e.calId ||
      _e.location != widget.e.location ||
      _e.description != widget.e.description;

  @override
  void didUpdateWidget(_CalEventPanel old) {
    super.didUpdateWidget(old);
    // Moved or resized on the grid while open: take the new times.
    if (widget.e.start != old.e.start || widget.e.end != old.e.end || widget.e.allDay != old.e.allDay) {
      _e = _e.copyWith(start: widget.e.start, end: widget.e.end, allDay: widget.e.allDay);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _set(CalEvent n) {
    setState(() => _e = n);
    if (_draft) widget.onDraftChanged(n);
  }

  void _save() {
    if (_task) {
      widget.onCreateTask(_title.text, dayOf(_e.start), _googleTask);
      return;
    }
    if (!_draft && !_dirty) return;
    widget.onSave(_e.copyWith(title: _title.text.trim()));
  }

  Future<void> _pickDay({bool end = false}) async {
    final base = end ? _e.end.subtract(const Duration(days: 1)) : _e.start;
    final d = await _pickDate(context, t, base);
    if (d == null) return;
    if (_e.allDay) {
      if (end) {
        final last = d.isBefore(dayOf(_e.start)) ? dayOf(_e.start) : d;
        _set(_e.copyWith(end: last.add(const Duration(days: 1))));
      } else {
        final span = _daysBetween(_e.start, _e.end);
        _set(_e.copyWith(start: d, end: d.add(Duration(days: math.max(1, span)))));
      }
    } else {
      final diff = _daysBetween(_e.start, d);
      _set(_e.copyWith(start: _shift(_e.start, days: diff), end: _shift(_e.end, days: diff)));
    }
  }

  void _toggleAllDay(bool on) {
    final d = dayOf(_e.start);
    if (on) {
      final last = dayOf(_e.end.subtract(const Duration(minutes: 1)));
      _set(_e.copyWith(allDay: true, start: d, end: (last.isBefore(d) ? d : last).add(const Duration(days: 1))));
    } else {
      final n = DateTime.now();
      final s = DateTime(d.year, d.month, d.day, d == dayOf(n) ? math.min(n.hour + 1, 23) : 9);
      _set(_e.copyWith(allDay: false, start: s, end: s.add(const Duration(hours: 1))));
    }
  }

  Widget _timeMenu({required bool end}) {
    final value = end ? _e.end : _e.start;
    final day = dayOf(_e.start);
    final options = <({DateTime at, String label})>[];
    if (end) {
      for (var m = 15; m <= 24 * 60; m += 15) {
        final at = _e.start.add(Duration(minutes: m));
        options.add((at: at, label: '${_hm(at)}   ${_dur(m)}'));
      }
    } else {
      for (var m = 0; m < 24 * 60; m += 15) {
        final at = _shift(day, minutes: m);
        options.add((at: at, label: _hm(at)));
      }
    }
    final current = options.where((o) => o.at == value).firstOrNull?.at;
    return PopupMenuButton<DateTime>(
      tooltip: end ? 'End time' : 'Start time',
      enabled: widget.editable,
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(maxHeight: 320, minWidth: 140),
      initialValue: current,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm + 2), side: BorderSide(color: t.line)),
      onSelected: (v) {
        if (end) {
          _set(_e.copyWith(end: v));
        } else {
          final len = _e.end.difference(_e.start);
          _set(_e.copyWith(start: v, end: v.add(len)));
        }
      },
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem(value: o.at, height: 32, child: Text(o.label, style: _ts(t.text, 13, tab: true))),
      ],
      child: IgnorePointer(child: _Pill(t, _hm(value), widget.editable ? () {} : null)),
    );
  }

  Widget _calMenu() {
    final g = widget.g;
    final cal = g.calendars.where((c) => c.id == _e.calId).firstOrNull;
    final square = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(3)),
    );
    final writable = g.calendars.where((c) => c.writable).toList();
    // Moving an existing event between calendars needs Google's move call; keep it to drafts and own events.
    return PopupMenuButton<String>(
      tooltip: 'Calendar',
      enabled: widget.editable && writable.length > 1,
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rSm + 2), side: BorderSide(color: t.line)),
      onSelected: (id) => _set(_e.copyWith(calId: id)),
      itemBuilder: (_) => [
        for (final c in writable)
          PopupMenuItem(
            value: c.id,
            height: 34,
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: Color(c.color), borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13))),
            ]),
          ),
      ],
      child: IgnorePointer(
        child: _Pill(t, cal?.name ?? 'Calendar', widget.editable ? () {} : null, leading: square),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ed = widget.editable;
    final g = widget.g;
    final lastDay = _e.allDay ? _e.end.subtract(const Duration(days: 1)) : _e.end;
    final cal = g.calendars.where((c) => c.id == _e.calId).firstOrNull;
    final readOnlyWhy = ed
        ? null
        : (!g.canEditCalendar
            ? 'Meridian can only read your calendar.'
            : '${cal?.name ?? 'This calendar'} is read-only.');

    return Container(
      decoration: BoxDecoration(color: t.side, border: Border(left: BorderSide(color: t.line))),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (_draft) _Seg(t, const ['Event', 'Task'], _task ? 1 : 0, (i) => setState(() => _task = i == 1)),
          const Spacer(),
          _IconBtn(t, Icons.close_rounded, 'Close  Esc', widget.onClose, size: 17),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 9, right: 2, left: 4),
            decoration: BoxDecoration(
              color: _task ? Colors.transparent : widget.color,
              borderRadius: BorderRadius.circular(3),
              border: _task ? Border.all(color: t.sub, width: 1.5) : null,
            ),
          ),
          Expanded(
            child: _panelField(
              t,
              _title,
              _task ? 'New task' : (_draft ? 'New event' : 'Untitled'),
              size: 18,
              w: FontWeight.w700,
              autofocus: _draft,
              maxLines: null,
              readOnly: !ed,
              onChanged: (v) {
                setState(() => _e = _e.copyWith(title: v));
                if (_draft) widget.onDraftChanged(_e);
              },
              onSubmitted: (_) => _save(),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PropRow(
                t,
                Icons.calendar_today_outlined,
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _Pill(t, _dateLabel(_e.start), ed ? () => _pickDay() : null),
                  if (!_task && _e.allDay && dayOf(lastDay) != dayOf(_e.start)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      child: Text('→', style: _ts(t.faint, 13)),
                    ),
                    _Pill(t, _dateLabel(lastDay), ed ? () => _pickDay(end: true) : null),
                  ],
                ]),
              ),
              if (!_task) ...[
                if (!_e.allDay)
                  _PropRow(
                    t,
                    Icons.schedule_rounded,
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _timeMenu(end: false),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                        child: Text('→', style: _ts(t.faint, 13)),
                      ),
                      _timeMenu(end: true),
                      if (dayOf(_e.end) != dayOf(_e.start) && _e.end != dayOf(_e.end))
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 5),
                          child: Text('next day', style: _ts(t.faint, 12)),
                        ),
                    ]),
                  ),
                _PropRow(
                  t,
                  Icons.wb_sunny_outlined,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 5, 0, 5),
                    child: Row(children: [
                      Text('All day', style: _ts(t.text, 13)),
                      const Spacer(),
                      IgnorePointer(ignoring: !ed, child: _Toggle(t, _e.allDay, _toggleAllDay)),
                    ]),
                  ),
                ),
                _PropRow(t, Icons.layers_outlined, Align(alignment: Alignment.centerLeft, child: _calMenu())),
                _PropRow(
                  t,
                  Icons.place_outlined,
                  _panelField(t, _place, ed ? 'Add location' : 'No location', readOnly: !ed,
                      onChanged: (v) => _set(_e.copyWith(location: v))),
                ),
                _PropRow(
                  t,
                  Icons.notes_rounded,
                  _panelField(t, _notes, ed ? 'Add description' : 'No description', maxLines: null, readOnly: !ed,
                      onChanged: (v) => _set(_e.copyWith(description: v))),
                ),
              ] else
                _PropRow(
                  t,
                  Icons.checklist_rounded,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _Seg(t, const ['Planner', 'Google'], _googleTask ? 1 : 0,
                        (i) => setState(() => _googleTask = i == 1 && g.canTasks)),
                  ),
                ),
              if (readOnlyWhy != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 0, 0),
                  child: Row(children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: t.faint),
                    const SizedBox(width: 6),
                    Expanded(child: Text(readOnlyWhy, style: _ts(t.sub, 12))),
                    if (!g.canEditCalendar) _Btn(t, 'Reconnect', widget.onReconnect, compact: true, ghost: true),
                  ]),
                ),
            ]),
          ),
        ),
        if (ed)
          Row(children: [
            if (!_draft) _Btn(t, 'Delete', widget.onDelete, compact: true, ghost: true, icon: Icons.delete_outline_rounded),
            const Spacer(),
            if (_draft) ...[
              _Btn(t, 'Cancel', widget.onClose, compact: true),
              const SizedBox(width: 8),
            ],
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _draft || _dirty ? 1 : 0.4,
              child: _Btn(t, _draft ? (_task ? 'Add task' : 'Create') : 'Save', _draft || _dirty ? _save : null,
                  compact: true, primary: true),
            ),
          ]),
      ]),
    );
  }
}

/// Read or edit a to-do: rename, move to another day, check off, delete.
class _CalTaskPanel extends StatefulWidget {
  const _CalTaskPanel({
    super.key,
    required this.t,
    required this.task,
    required this.onRename,
    required this.onMove,
    required this.onToggle,
    required this.onDelete,
    required this.onClose,
  });
  final _T t;
  final _CalTask task;
  final ValueChanged<String> onRename;
  final ValueChanged<DateTime> onMove;
  final VoidCallback onToggle, onDelete, onClose;

  @override
  State<_CalTaskPanel> createState() => _CalTaskPanelState();
}

class _CalTaskPanelState extends State<_CalTaskPanel> {
  late final _title = TextEditingController(text: widget.task.title);

  @override
  void dispose() {
    _commit();
    _title.dispose();
    super.dispose();
  }

  /// Renames on Enter and when the panel closes. Deferred, because closing
  /// happens while the tree is being torn down and the rename notifies.
  void _commit() {
    final v = _title.text.trim();
    if (v.isEmpty || v == widget.task.title) return;
    final rename = widget.onRename;
    scheduleMicrotask(() => rename(v));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, x = widget.task;
    return Container(
      decoration: BoxDecoration(color: t.side, border: Border(left: BorderSide(color: t.line))),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(x.planner != null ? 'Daily planner' : 'Google Tasks', style: _ts(t.sub, 12, w: FontWeight.w600)),
          ),
          const Spacer(),
          _IconBtn(t, Icons.close_rounded, 'Close  Esc', widget.onClose, size: 17),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5, left: 2), child: _Check(t, x.done, widget.onToggle)),
          Expanded(
            child: _panelField(t, _title, 'Untitled', size: 18, w: FontWeight.w700, maxLines: null,
                onSubmitted: (_) => _commit()),
          ),
        ]),
        const SizedBox(height: 6),
        _PropRow(
          t,
          Icons.calendar_today_outlined,
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(t, _dateLabel(x.day), () async {
              final d = await _pickDate(context, t, x.day);
              if (d != null) widget.onMove(d);
            }),
          ),
        ),
        if (x.planner != null)
          _PropRow(
            t,
            Icons.timelapse_rounded,
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 0, 6),
              child: Text('${_dur(x.planner!.minutes)}  ·  #${x.planner!.tag}', style: _ts(t.text, 13)),
            ),
          ),
        const Spacer(),
        Row(children: [
          _Btn(t, 'Delete', widget.onDelete, compact: true, ghost: true, icon: Icons.delete_outline_rounded),
          const Spacer(),
          _Btn(t, x.done ? 'Mark not done' : 'Mark done', widget.onToggle, compact: true, primary: !x.done),
        ]),
      ]),
    );
  }
}
