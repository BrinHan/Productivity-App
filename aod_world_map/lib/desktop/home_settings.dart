part of 'home_page.dart';

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    required this.t,
    required this.prefs,
    required this.isDark,
    required this.onDark,
    required this.g,
    required this.p,
    required this.onAccount,
  });
  final _T t;
  final _Prefs prefs;
  final bool isDark;
  final ValueChanged<bool> onDark;
  final GoogleService g;
  final PlannerModel p;
  final VoidCallback onAccount;

  Widget _head(String s) => Padding(
        padding: const EdgeInsets.only(top: 30, bottom: 6),
        child: Text(s, style: _ts(t.text, 16, w: FontWeight.w700)),
      );

  Widget _row(String title, String sub, Widget trailing, {bool last = false}) => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _ts(t.text, 14, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: _ts(t.sub, 12.5, h: 1.4)),
              ]),
            ),
            const SizedBox(width: 16),
            trailing,
          ]),
        ),
        if (!last) _Hair(t),
      ]);

  Widget _fontRow(_FontChoice f) {
    final selected = prefs.font == f.family;
    TextStyle own(TextStyle s) => s.copyWith(fontFamily: f.family, fontFamilyFallback: _fontFallback);
    return _Tap(
      t: t,
      selected: selected,
      onTap: () => prefs.setFont(f.family),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(width: 60, child: Text('Aa', style: own(_ts(t.text, 24, w: FontWeight.w600)))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.label, style: own(_ts(t.text, 14, w: FontWeight.w600))),
              Text(f.note, style: _ts(t.sub, 12)),
            ]),
          ),
          if (selected) Icon(Icons.check_rounded, size: 18, color: t.text),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _Page(
        t: t,
        title: 'Settings',
        subtitle: 'Make Meridian look and feel the way you work.',
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _head('Appearance'),
                _row('Theme', 'Light or dark.', _Seg(t, const ['Light', 'Dark'], isDark ? 1 : 0, (i) => onDark(i == 1)),
                    last: true),
                Padding(
                  padding: const EdgeInsets.only(top: 22, bottom: 4),
                  child: Text('Font', style: _ts(t.text, 14, w: FontWeight.w600)),
                ),
                Text('Applies everywhere in the planner.', style: _ts(t.sub, 12.5)),
                const SizedBox(height: 10),
                for (final f in _fonts) _fontRow(f),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Satoshi and Proxima Nova are licensed separately, so they are not bundled. '
                    'Install them in Windows and they work here. Until then they show in Segoe UI.',
                    style: _ts(t.sub, 12, h: 1.5),
                  ),
                ),
                _head('Layout'),
                _row('Sidebar', 'Hide it for more room. Also Ctrl+B.', _Toggle(t, prefs.sidebarOpen, prefs.setSidebar)),
                _row('Schedule panel', 'The day timeline on the right.', _Toggle(t, prefs.showSchedule, prefs.setSchedule)),
                _row(
                  'Workday',
                  'Daily planning fits your tasks into the free time between meetings in these hours.',
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _IconBtn(t, Icons.remove_rounded, 'Start an hour earlier',
                        () => prefs.setWorkday(prefs.dayStart - 1, prefs.dayEnd)),
                    _IconBtn(t, Icons.add_rounded, 'Start an hour later',
                        () => prefs.setWorkday(prefs.dayStart + 1, prefs.dayEnd)),
                    SizedBox(
                      width: 150,
                      child: Text('${_hourLabel(prefs.dayStart)} – ${_hourLabel(prefs.dayEnd)}',
                          textAlign: TextAlign.center, style: _ts(t.text, 13, w: FontWeight.w600, tab: true)),
                    ),
                    _IconBtn(t, Icons.remove_rounded, 'End an hour earlier',
                        () => prefs.setWorkday(prefs.dayStart, prefs.dayEnd - 1)),
                    _IconBtn(t, Icons.add_rounded, 'End an hour later',
                        () => prefs.setWorkday(prefs.dayStart, prefs.dayEnd + 1)),
                  ]),
                  last: true,
                ),
                _head('Account'),
                _row('Google account', g.signedIn ? (g.email ?? 'Connected') : 'Not connected',
                    _Btn(t, g.signedIn ? 'Manage' : 'Connect', onAccount, compact: true),
                    last: true),
                _head('Your data'),
                _DataSection(t: t, p: p, row: _row),
                _head('About'),
                _AboutSection(t: t, row: _row),
                _head('Other screens'),
                Text('The map and the island keep their own settings: the gear on the map, and the gear tab in the island.',
                    style: _ts(t.sub, 13, h: 1.5)),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      );
}
