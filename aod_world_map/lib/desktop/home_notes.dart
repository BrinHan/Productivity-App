part of 'home_page.dart';

String _hms(Duration d) {
  final h = d.inHours;
  final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _when(DateTime d) {
  final n = DateTime.now();
  final diff = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  final c = _clock(d);
  if (diff == 0) return 'Today $c';
  if (diff == 1) return 'Yesterday $c';
  return '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}, $c';
}

String _lenText(Duration d) => d.inMinutes < 1 ? '${d.inSeconds}s' : '${d.inMinutes} min';

/// Slow red pulse for "recording".
class _RecDot extends StatefulWidget {
  const _RecDot(this.color, {this.size = 8});
  final Color color;
  final double size;

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
        ),
      );
}

/// Live audio level: a dotted line (like Notion's) or small bars.
class _LevelPainter extends CustomPainter {
  _LevelPainter(this.levels, this.color, {this.bars = false});
  final List<double> levels;
  final Color color;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    final n = levels.length;
    if (n == 0) return;
    final dx = size.width / n;
    final cy = size.height / 2;
    final p = Paint()..isAntiAlias = true;
    for (var i = 0; i < n; i++) {
      final l = levels[i].clamp(0.0, 1.0).toDouble();
      p.color = color.withValues(alpha: 0.30 + 0.70 * l);
      final x = dx * (i + 0.5);
      if (bars) {
        final h = 3 + (size.height - 3) * l;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, cy), width: math.max(1.5, dx * 0.55), height: h),
              const Radius.circular(2)),
          p,
        );
      } else {
        canvas.drawCircle(Offset(x, cy), 1.3 + 2.7 * l, p);
      }
    }
  }

  @override
  bool shouldRepaint(_LevelPainter o) => true;
}

/// Sidebar card shown while a meeting is being recorded.
class _RecordingChip extends StatelessWidget {
  const _RecordingChip({required this.t, required this.notes, required this.onOpen});
  final _T t;
  final NotesService notes;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final paused = notes.state == RecState.paused;
    final finishing = notes.state == RecState.finishing;
    final label = finishing
        ? 'Finishing transcript'
        : (paused ? 'Paused' : 'Recording ${notes.current?.appName ?? ''}'.trim());
    return _Tap(
      t: t,
      radius: _rLg,
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(_rLg),
          border: Border.all(color: t.warn.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (paused || finishing)
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: t.sub))
            else
              _RecDot(t.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 12.5, w: FontWeight.w600)),
            ),
            ValueListenableBuilder<int>(
              valueListenable: notes.tick,
              builder: (_, __, ___) => Text(_hms(notes.elapsed), style: _ts(t.sub, 12, tab: true)),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 18,
            child: ValueListenableBuilder<int>(
              valueListenable: notes.tick,
              builder: (_, __, ___) => CustomPaint(
                size: const Size(double.infinity, 18),
                painter: _LevelPainter(notes.levels.sublist(notes.levels.length - 28), t.warn, bars: true),
              ),
            ),
          ),
          if (!finishing) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _Btn(t, paused ? 'Resume' : 'Pause', paused ? notes.resume : notes.pause,
                    compact: true, fill: true),
              ),
              const SizedBox(width: 6),
              Expanded(child: _Btn(t, 'Stop', notes.stop, compact: true, fill: true)),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Window bar pill, so recording stays visible with the sidebar hidden.
class _RecPill extends StatelessWidget {
  const _RecPill({required this.t, required this.notes, required this.onTap});
  final _T t;
  final NotesService notes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Tap(
        t: t,
        radius: 14,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            notes.state == RecState.recording
                ? _RecDot(t.warn)
                : Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: t.sub)),
            const SizedBox(width: 8),
            ValueListenableBuilder<int>(
              valueListenable: notes.tick,
              builder: (_, __, ___) => Text(
                notes.state == RecState.finishing ? 'Finishing' : _hms(notes.elapsed),
                style: _ts(t.text, 12, w: FontWeight.w600, tab: true),
              ),
            ),
          ]),
        ),
      );
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({super.key, required this.t, required this.note, required this.onChanged});
  final _T t;
  final MeetingNote note;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _c = TextEditingController(text: widget.note.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return TextField(
      controller: _c,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: _ts(t.text, 14.5, h: 1.55),
      cursorColor: t.focus,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: 'Write your own notes here',
        hintStyle: _ts(t.sub, 14.5),
      ),
    );
  }
}

class _NotesView extends StatefulWidget {
  const _NotesView({required this.t, required this.notes});
  final _T t;
  final NotesService notes;

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  String? _selected, _lastActive;
  int _tab = 0; // 0 notes, 1 transcript
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  MeetingNote? get _current {
    final n = widget.notes;
    if (_selected != null) {
      for (final x in n.notes) {
        if (x.id == _selected) return x;
      }
    }
    return n.active ?? (n.notes.isEmpty ? null : n.notes.first);
  }

  Future<void> _openSetup() async {
    final d = NotesService.whisperDir;
    try {
      await d.create(recursive: true);
      await Process.start('explorer.exe', [d.path], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  Future<void> _confirmDelete(MeetingNote note) async {
    final t = widget.t;
    final ok = await _drawer<bool>(
      context,
      t,
      title: 'Delete this note?',
      description: 'The transcript and your notes are removed from this computer.',
      body: (close) => const SizedBox.shrink(),
      footer: (close) => [
        Expanded(child: _Btn(t, 'Delete', () => close(true), primary: true, fill: true)),
        const SizedBox(width: 12),
        Expanded(child: _Btn(t, 'Cancel', () => close(false), fill: true)),
      ],
    );
    if (ok == true) widget.notes.delete(note);
  }

  Widget _banner(
    _T t, {
    required String title,
    required String body,
    Widget? action,
    bool warn = false,
  }) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(_rLg),
          border: Border.all(color: warn ? t.warn.withValues(alpha: 0.5) : t.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _ts(warn ? t.warn : t.text, 13.5, w: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(body, style: _ts(t.sub, 12.5, h: 1.45)),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 10), child: action),
        ]),
      );

  Widget _tile(_T t, NotesService n, MeetingNote x, bool selected) {
    final isActive = n.active == x;
    return _Tap(
      t: t,
      selected: selected,
      onTap: () => setState(() => _selected = x.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13.5, w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${_when(x.startedAt)}, ${isActive ? 'recording' : _lenText(x.length)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.sub, 12)),
            ]),
          ),
          if (isActive) _RecDot(t.warn),
        ]),
      ),
    );
  }

  Widget _list(_T t, NotesService n, MeetingNote? cur) => Container(
        width: 288,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: t.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
            child: Row(children: [
              Text('Notes', style: _ts(t.text, 24, w: FontWeight.w700, ls: -0.6)),
              const Spacer(),
              Text('${n.notes.length}', style: _ts(t.sub, 13, tab: true)),
            ]),
          ),
          if (n.error != null) _banner(t, title: 'Could not record', body: n.error!, warn: true),
          if (!n.ready)
            _banner(
              t,
              title: 'Set up transcription',
              body: 'Meridian transcribes on this computer. Install the speech model once and recordings will work.',
              action: _Btn(t, 'Open setup folder', _openSetup, compact: true, icon: Icons.folder_open_rounded),
            ),
          if (n.detected != null && !n.recording && n.ready)
            _banner(
              t,
              title: '${n.detected!.appName} meeting detected',
              body: 'Record it and transcribe the audio.',
              action: _Btn(t, 'Take notes', () => n.start(n.detected!), primary: true, compact: true),
            ),
          Expanded(
            child: n.notes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      'No meeting notes yet. Meridian offers to take notes when it detects Zoom, Google Meet or Teams.',
                      style: _ts(t.sub, 13, h: 1.5),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    children: [for (final x in n.notes) _tile(t, n, x, x.id == cur?.id)],
                  ),
          ),
        ]),
      );

  Widget _tabPill(_T t, IconData icon, String label, int i) => _Tap(
        t: t,
        radius: 20,
        selected: _tab == i,
        onTap: () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: _tab == i ? t.text : t.sub),
            const SizedBox(width: 6),
            Text(label, style: _ts(_tab == i ? t.text : t.sub, 13, w: FontWeight.w600)),
          ]),
        ),
      );

  Widget _controls(_T t, NotesService n, MeetingNote note) {
    if (n.active != note) {
      return Text(_lenText(note.length), style: _ts(t.sub, 13, tab: true));
    }
    if (n.state == RecState.finishing) {
      return Text('Finishing transcript...', style: _ts(t.sub, 13));
    }
    final paused = n.state == RecState.paused;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ValueListenableBuilder<int>(
        valueListenable: n.tick,
        builder: (_, __, ___) => Text(_hms(n.elapsed), style: _ts(t.sub, 13, w: FontWeight.w600, tab: true)),
      ),
      const SizedBox(width: 12),
      _Btn(t, paused ? 'Resume' : 'Pause', paused ? n.resume : n.pause, compact: true),
      const SizedBox(width: 8),
      _Tap(
        t: t,
        onTap: n.stop,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: t.warn.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(_rSm),
          ),
          child: Text('Stop', style: _ts(t.warn, 13, w: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _transcript(_T t, NotesService n, MeetingNote note) {
    final live = n.active == note;
    if (note.segments.isEmpty) {
      return Text(
        live
            ? 'Listening to ${note.app}. Text appears about every 10 seconds.'
            : 'No speech was captured for this meeting.',
        style: _ts(t.sub, 14, h: 1.5),
      );
    }
    if (live && _tab == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    return ListView(controller: _scroll, children: [
      for (final s in note.segments)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 54, child: Text(_hms(Duration(seconds: s.at)), style: _ts(t.sub, 12.5, tab: true))),
            Expanded(child: SelectableText(s.text, style: _ts(t.text, 14.5, h: 1.55))),
          ]),
        ),
    ]);
  }

  Widget _detail(_T t, NotesService n, MeetingNote note) {
    final heading = _ts(t.text, 34, w: FontWeight.w700, ls: -1, h: 1.15);
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 34, 48, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${note.title} ', style: heading),
                  TextSpan(text: '@${_when(note.startedAt)}', style: heading.copyWith(color: t.sub)),
                ])),
              ),
              _IconBtn(t, Icons.copy_rounded, 'Copy transcript', () {
                Clipboard.setData(ClipboardData(text: note.transcript));
              }),
              _IconBtn(t, Icons.delete_outline_rounded, 'Delete note',
                  n.active == note ? null : () => _confirmDelete(note)),
            ]),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(_rLg),
                  border: Border.all(color: t.line),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Row(children: [
                      Icon(Icons.event_note_outlined, size: 18, color: t.sub),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${note.title} ', style: _ts(t.text, 18, w: FontWeight.w700, ls: -0.3)),
                          TextSpan(
                              text: '@${_when(note.startedAt).split(' ').first}',
                              style: _ts(t.sub, 18, w: FontWeight.w700, ls: -0.3)),
                        ])),
                      ),
                    ]),
                  ),
                  _Hair(t),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(children: [
                      _tabPill(t, Icons.edit_outlined, 'Notes', 0),
                      const SizedBox(width: 4),
                      _tabPill(t, Icons.notes_rounded, 'Transcript', 1),
                      const SizedBox(width: 16),
                      Expanded(
                        child: n.active == note
                            ? SizedBox(
                                height: 24,
                                child: ValueListenableBuilder<int>(
                                  valueListenable: n.tick,
                                  builder: (_, __, ___) => CustomPaint(
                                    size: const Size(double.infinity, 24),
                                    painter: _LevelPainter(n.levels, t.text),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 12),
                      _controls(t, n, note),
                    ]),
                  ),
                  _Hair(t),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: _tab == 0
                          ? _NoteEditor(
                              key: ValueKey(note.id),
                              t: t,
                              note: note,
                              onChanged: (v) => n.setText(note, v),
                            )
                          : _transcript(t, n, note),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, n = widget.notes;
    final act = n.active;
    if (act != null && _lastActive != act.id) {
      _lastActive = act.id;
      _selected = act.id;
    }
    final cur = _current;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _list(t, n, cur),
      Expanded(
        child: cur == null
            ? Center(
                child: _Empty(t, Icons.graphic_eq_rounded, 'No note selected',
                    'Join a Zoom, Meet or Teams call and Meridian will offer to take notes.'),
              )
            : _detail(t, n, cur),
      ),
    ]);
  }
}
