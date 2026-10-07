part of 'home_page.dart';

/// First run: four short steps instead of an empty app. Say what Meridian
/// is, bring in a calendar, add today's tasks, then point at the island.
/// Every step can be skipped; nothing here is needed to use the planner.
class _WelcomeView extends StatefulWidget {
  const _WelcomeView({
    required this.t,
    required this.p,
    required this.g,
    required this.feeds,
    required this.onAddFeed,
    required this.onDone,
  });
  final _T t;
  final PlannerModel p;
  final GoogleService g;
  final List<String> feeds; // labels of the calendar links added so far
  final void Function(String label, String url) onAddFeed;
  final VoidCallback onDone;

  @override
  State<_WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<_WelcomeView> {
  static const _steps = 4;
  static const _lengths = [15, 30, 60, 120];
  static const _ideas = ['Homework', 'Study', 'Readings', 'Workout', 'Errands'];

  int _step = 0;
  int _length = 1; // index into _lengths
  final _task = TextEditingController(), _url = TextEditingController();
  final _taskFocus = FocusNode();
  String? _urlError;

  _T get t => widget.t;
  List<Task> get _today => widget.p.forDay(DateTime.now());

  @override
  void dispose() {
    _task.dispose();
    _url.dispose();
    _taskFocus.dispose();
    super.dispose();
  }

  void _go(int step) => setState(() => _step = step.clamp(0, _steps - 1).toInt());

  void _addTask(String v) {
    final s = v.trim();
    if (s.isEmpty) return;
    widget.p.add(DateTime.now(), s, minutes: _lengths[_length]);
    _task.clear();
    _taskFocus.requestFocus();
  }

  void _addFeed() {
    final url = _url.text.trim();
    final ok = url.startsWith('http://') || url.startsWith('https://') || url.startsWith('webcal');
    if (!ok) {
      setState(() => _urlError = 'Paste the calendar link. It starts with https:// or webcal://');
      return;
    }
    widget.onAddFeed('Calendar ${widget.feeds.length + 1}', url);
    _url.clear();
    setState(() => _urlError = null);
  }

  // ------------------------------------------------------------- pieces

  Widget _title(String s) => Text(s, style: _ts(t.text, 28, w: FontWeight.w700, ls: -0.7, h: 1.15));

  Widget _body(String s) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(s, style: _ts(t.sub, 14.5, h: 1.5)),
  );

  Widget _point(IconData icon, String s) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(_rSm)),
          child: Icon(icon, size: 17, color: t.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(s, style: _ts(t.text, 14)),
          ),
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: BorderRadius.circular(_rLg),
      border: Border.all(color: t.line),
    ),
    child: child,
  );

  Widget _done(String s) => Row(
    children: [
      Icon(Icons.check_circle_rounded, size: 18, color: t.accent),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _ts(t.text, 13.5, w: FontWeight.w600),
        ),
      ),
    ],
  );

  Widget _dots() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < _steps; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(right: 6),
          width: i == _step ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(color: i <= _step ? t.accent : t.line, borderRadius: BorderRadius.circular(3)),
        ),
    ],
  );

  // -------------------------------------------------------------- steps

  Widget _hello() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Plan your day in a minute'),
      _body(
        'Meridian keeps today\'s plan at the top of your screen. There is nothing to build or '
        'set up: add what you need to do, and it is there whenever you glance up.',
      ),
      const SizedBox(height: 8),
      _point(Icons.checklist_rounded, 'Write down today\'s tasks and roughly how long each takes'),
      _point(Icons.calendar_today_outlined, 'See your classes and events right beside them'),
      _point(Icons.space_dashboard_outlined, 'Tick things off from the island, without opening this window'),
    ],
  );

  Widget _calendar() {
    final g = widget.g;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Bring in your calendar'),
        _body(
          'Your classes and plans show up beside your tasks, so you can see how much time you really have. '
          'You can skip this and add one later.',
        ),
        const SizedBox(height: 22),
        if (g.configured)
          _card(
            g.signedIn
                ? _done('Google connected${g.email == null ? '' : ' as ${g.email}'}')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Calendar', style: _ts(t.text, 14.5, w: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'You approve access in your browser. Meridian never sees your password.',
                        style: _ts(t.sub, 13, h: 1.45),
                      ),
                      const SizedBox(height: 14),
                      _Btn(
                        t,
                        g.busy ? 'Waiting for Google' : 'Continue with Google',
                        g.busy ? null : g.signIn,
                        icon: Icons.login_rounded,
                        compact: true,
                      ),
                      if (g.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(g.error!, style: _ts(t.warn, 12.5, h: 1.45)),
                        ),
                    ],
                  ),
          ),
        if (g.configured) const SizedBox(height: 12),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                g.configured ? 'Or paste a calendar link' : 'Paste a calendar link',
                style: _ts(t.text, 14.5, w: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'From Canvas, Outlook, Apple or your school\'s portal. Look for "iCal", "Subscribe" or "Calendar feed".',
                style: _ts(t.sub, 13, h: 1.45),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _url,
                      style: _ts(t.text, 14),
                      cursorColor: t.focus,
                      onChanged: (_) {
                        if (_urlError != null) setState(() => _urlError = null);
                      },
                      onSubmitted: (_) => _addFeed(),
                      decoration: _deco(t, 'https://…/calendar.ics'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Btn(t, 'Add', _addFeed),
                ],
              ),
              if (_urlError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_urlError!, style: _ts(t.warn, 12.5)),
                ),
              for (final f in widget.feeds) Padding(padding: const EdgeInsets.only(top: 12), child: _done('$f added')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tasks() {
    final today = _today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('What do you need to do today?'),
        _body('Type a task and press Enter. Pick about how long it will take; you can change it later.'),
        const SizedBox(height: 22),
        TextField(
          controller: _task,
          focusNode: _taskFocus,
          autofocus: true,
          style: _ts(t.text, 14),
          cursorColor: t.focus,
          onSubmitted: _addTask,
          decoration: _deco(t, 'Read chapter 4', prefix: Icon(Icons.add_rounded, size: 18, color: t.sub)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Takes about', style: _ts(t.sub, 13)),
            _Seg(t, [for (final m in _lengths) _dur(m)], _length, (i) => setState(() => _length = i)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final idea in _ideas)
              _Tap(
                t: t,
                onTap: () => _addTask(idea),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_rSm),
                    border: Border.all(color: t.line),
                  ),
                  child: Text('+ $idea', style: _ts(t.sub, 13)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (today.isNotEmpty)
          _card(
            Column(
              children: [
                for (var i = 0; i < today.length; i++) ...[
                  if (i > 0) _Hair(t),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            today[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _ts(t.text, 14),
                          ),
                        ),
                        Text(_dur(today[i].minutes), style: _ts(t.sub, 13, tab: true)),
                        const SizedBox(width: 4),
                        _IconBtn(t, Icons.close_rounded, 'Remove', () => widget.p.remove(today[i]), size: 16),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _ready() {
    final today = _today;
    final total = today.fold(0, (a, x) => a + x.minutes);
    final summary = today.isEmpty
        ? 'Your board is ready whenever you are.'
        : 'You have ${today.length} ${today.length == 1 ? 'task' : 'tasks'} today, about ${_dur(total)} of work.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('You\'re all set'),
        _body(summary),
        const SizedBox(height: 8),
        _point(
          Icons.vertical_align_top_rounded,
          'Look at the top of your screen. That small pill is the island: click it and open Today to see your plan and tick tasks off.',
        ),
        _point(Icons.nights_stay_outlined, 'At the end of the day, Shutdown moves anything unfinished to tomorrow.'),
        _point(Icons.view_week_outlined, 'On Sundays, Weekly planning lays out the week ahead.'),
      ],
    );
  }

  // ------------------------------------------------------------- layout

  Widget _buttons() {
    final hasCal = widget.g.signedIn || widget.feeds.isNotEmpty;
    final (String label, VoidCallback action) = switch (_step) {
      0 => ('Get started', () => _go(1)),
      1 => (hasCal ? 'Next' : 'Skip for now', () => _go(2)),
      2 => (_today.isEmpty ? 'Skip for now' : 'Next', () => _go(3)),
      _ => ('Open my day', widget.onDone),
    };
    return Row(
      children: [
        if (_step == 0)
          _Btn(t, 'Skip', widget.onDone, ghost: true)
        else
          _Btn(t, 'Back', () => _go(_step - 1), ghost: true),
        const Spacer(),
        _Btn(t, label, action, primary: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_step) {
      0 => _hello(),
      1 => _calendar(),
      2 => _tasks(),
      _ => _ready(),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dots(),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                child: KeyedSubtree(key: ValueKey(_step), child: page),
              ),
              const SizedBox(height: 32),
              _buttons(),
            ],
          ),
        ),
      ),
    );
  }
}
