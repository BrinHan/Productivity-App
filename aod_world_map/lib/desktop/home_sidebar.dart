part of 'home_page.dart';

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.t,
    required this.view,
    required this.shutdown,
    required this.onView,
    required this.onMap,
    required this.isDark,
    required this.onDark,
    required this.g,
    required this.notes,
  });
  final _T t;
  final _View view;
  final bool shutdown, isDark;
  final ValueChanged<_View> onView;
  final VoidCallback onMap;
  final ValueChanged<bool> onDark;
  final GoogleService g;
  final NotesService notes;

  Widget _group(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 0, 6),
        child: Text(title, style: _ts(t.sub, 12, w: FontWeight.w600)),
      );

  Widget _nav(IconData icon, String label, _View v, {bool check = false, bool dot = false}) =>
      _NavItem(t, icon, label, selected: view == v, check: check, dot: dot, onTap: () => onView(v));

  @override
  Widget build(BuildContext context) => Container(
        width: 232,
        decoration: BoxDecoration(
          color: t.side,
          border: Border(right: BorderSide(color: t.line)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 16),
            child: Text('Orbit', style: _ts(t.text, 18, w: FontWeight.w700, ls: -0.5)),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _nav(Icons.home_outlined, 'Home', _View.home),
                _nav(Icons.calendar_month_outlined, 'Calendar', _View.calendar),
                _nav(Icons.timer_outlined, 'Focus', _View.focus),
                _nav(Icons.graphic_eq_rounded, 'Notes', _View.notes, dot: notes.recording),
                _group('Day'),
                _nav(Icons.event_available_outlined, 'Daily planning', _View.planning),
                _nav(Icons.checklist_rounded, 'Daily task list', _View.tasks),
                _nav(Icons.bedtime_outlined, 'Daily shutdown', _View.shutdown, check: shutdown),
                _group('Week'),
                _nav(Icons.calendar_view_week_outlined, 'Weekly planning', _View.week),
                _nav(Icons.insights_outlined, 'Weekly review', _View.review),
              ]),
            ),
          ),
          if (notes.recording) ...[
            _RecordingChip(t: t, notes: notes, onOpen: () => onView(_View.notes)),
            const SizedBox(height: 8),
          ],
          _AccountChip(t: t, g: g, selected: view == _View.account, onTap: () => onView(_View.account)),
          const SizedBox(height: 4),
          _nav(Icons.settings_outlined, 'Settings', _View.settings),
          _NavItem(t, Icons.public, 'Screensaver map', onTap: onMap),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(children: [
              Text(isDark ? 'Dark' : 'Light', style: _ts(t.sub, 12.5)),
              const Spacer(),
              SkyToggle(isNight: isDark, onChanged: onDark, em: 7),
            ]),
          ),
        ]),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.t, this.icon, this.label,
      {this.selected = false, this.check = false, this.dot = false, this.onTap});
  final _T t;
  final IconData icon;
  final String label;
  final bool selected, check, dot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _Tap(
        t: t,
        onTap: onTap,
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Icon(icon, size: 17, color: selected ? t.accent : t.sub),
            const SizedBox(width: 11),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(selected ? t.text : t.sub, 13.5, w: selected ? FontWeight.w600 : FontWeight.w500)),
            ),
            if (dot) _RecDot(t.warn),
            if (check) Icon(Icons.check_rounded, size: 15, color: t.accent),
          ]),
        ),
      );
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.t, required this.g, required this.selected, required this.onTap});
  final _T t;
  final GoogleService g;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final email = g.email ?? '';
    final initial = email.isEmpty ? 'G' : email[0].toUpperCase();
    return _Tap(
      t: t,
      onTap: onTap,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: g.signedIn ? t.accentSoft : t.raised),
            child: g.signedIn
                ? Text(initial, style: _ts(t.accent, 14, w: FontWeight.w700))
                : Icon(Icons.person_outline_rounded, size: 18, color: t.sub),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.signedIn ? (email.isEmpty ? 'Google' : email) : 'Connect Google',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13, w: FontWeight.w600)),
              Text(g.signedIn ? 'Connected' : 'Calendar, tasks, backup',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.sub, 11.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}
