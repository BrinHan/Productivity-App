part of 'home_page.dart';

/// One calm page to connect Google. Client registration is a one-time step
/// that Google requires for every desktop app; after it, sign-in is one button.
class _AccountView extends StatefulWidget {
  const _AccountView({required this.t, required this.g});
  final _T t;
  final GoogleService g;

  @override
  State<_AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<_AccountView> {
  final _id = TextEditingController(), _secret = TextEditingController();
  String? _formError;

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    if (!Platform.isWindows) return;
    try {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  void _save() {
    final id = _id.text.trim(), secret = _secret.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      setState(() => _formError = 'Enter both values from Google Cloud.');
      return;
    }
    if (!id.endsWith('.apps.googleusercontent.com')) {
      setState(() => _formError = 'The client ID should end with .apps.googleusercontent.com');
      return;
    }
    widget.g.setClient(id, secret);
    _id.clear();
    _secret.clear();
    setState(() => _formError = null);
  }

  Widget _setup() {
    final t = widget.t;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(_rLg),
        border: Border.all(color: t.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('One-time setup', style: _ts(t.text, 16, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Google asks every desktop app to register once. It takes about two minutes.',
            style: _ts(t.sub, 13, h: 1.45)),
        const SizedBox(height: 14),
        Text('Create a project and turn on the Calendar, Tasks and Drive APIs.', style: _ts(t.text, 13, h: 1.5)),
        const SizedBox(height: 6),
        Text('Add your Google account as a test user on the consent screen.', style: _ts(t.text, 13, h: 1.5)),
        const SizedBox(height: 6),
        Text('Create an OAuth client ID of type Desktop app, then paste its two values here.',
            style: _ts(t.text, 13, h: 1.5)),
        const SizedBox(height: 16),
        _Btn(t, 'Open Google Cloud', () => _open('https://console.cloud.google.com/apis/credentials'),
            icon: Icons.open_in_new_rounded, compact: true),
        const SizedBox(height: 20),
        _Labeled(t, 'Client ID', _id,
            hint: '123456-abc.apps.googleusercontent.com', onChanged: () {
          if (_formError != null) setState(() => _formError = null);
        }),
        const SizedBox(height: 14),
        _Labeled(t, 'Client secret', _secret, obscure: true, onChanged: () {
          if (_formError != null) setState(() => _formError = null);
        }),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_formError!, style: _ts(t.warn, 12.5)),
          ),
        const SizedBox(height: 18),
        _Btn(t, 'Save and continue', _save, primary: true),
      ]),
    );
  }

  Widget _signIn() {
    final t = widget.t, g = widget.g;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Btn(t, 'Continue with Google', g.busy ? null : g.signIn, primary: true, icon: Icons.login_rounded),
      const SizedBox(height: 14),
      Text('You approve access in your browser. Orbit never sees your Google password.',
          style: _ts(t.sub, 12.5, h: 1.5)),
      const SizedBox(height: 14),
      _Tap(
        t: t,
        radius: 6,
        onTap: g.busy ? null : g.clearClient,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text('Use a different client', style: _ts(t.sub, 12.5, w: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _account() {
    final t = widget.t, g = widget.g;
    final email = g.email ?? 'Google account';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(_rLg),
        border: Border.all(color: t.line),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.accentSoft),
          child: Text(email[0].toUpperCase(), style: _ts(t.accent, 18, w: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 15, w: FontWeight.w600)),
            Text('Connected', style: _ts(t.accent, 12.5, w: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        _Btn(t, 'Sign out', g.busy ? null : g.signOut, compact: true),
      ]),
    );
  }

  Widget _service(IconData icon, String name, String info, {Widget? actions, bool last = false}) {
    final t = widget.t;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(_rSm)),
              child: Icon(icon, size: 18, color: t.sub),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: _ts(t.text, 14, w: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(info, style: _ts(t.sub, 12.5)),
              ]),
            ),
          ]),
          if (actions != null) Padding(padding: const EdgeInsets.only(top: 12, left: 48), child: actions),
        ]),
      ),
      if (!last) _Hair(t),
    ]);
  }

  Widget _connections() {
    final t = widget.t, g = widget.g;
    final ev = g.events.length, tk = g.todos.length;
    final off = 'Available after you sign in';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What is connected', style: _ts(t.text, 16, w: FontWeight.w700)),
      const SizedBox(height: 4),
      _service(Icons.calendar_month_outlined, 'Calendar',
          g.signedIn ? '$ev ${ev == 1 ? 'event' : 'events'} today and tomorrow' : off),
      _service(Icons.checklist_rounded, 'Tasks',
          g.signedIn ? '$tk open ${tk == 1 ? 'task' : 'tasks'}, shown in today\'s column' : off),
      _service(
        Icons.cloud_outlined,
        'Drive backup',
        g.signedIn ? (g.status ?? 'Planner and settings, in a private app folder') : off,
        last: true,
        actions: g.signedIn
            ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Btn(t, 'Back up now', g.busy ? null : g.backupNow, compact: true),
                _Btn(t, 'Restore', g.busy ? null : g.restore, compact: true),
                const SizedBox(width: 6),
                Text('Auto', style: _ts(t.sub, 12.5)),
                _Toggle(t, g.autoBackup, g.setAutoBackup),
              ])
            : null,
      ),
      if (g.signedIn) ...[
        const SizedBox(height: 14),
        _Btn(t, 'Refresh now', g.loading ? null : () => g.refresh(force: true),
            compact: true, icon: Icons.refresh_rounded),
      ],
      const SizedBox(height: 22),
      Text('Access tokens stay in your Windows user profile. Signing out revokes them at Google.',
          style: _ts(t.sub, 12, h: 1.5)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, g = widget.g;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!g.configured) _setup() else if (!g.signedIn) _signIn() else _account(),
      if (g.error != null)
        Padding(padding: const EdgeInsets.only(top: 14), child: Text(g.error!, style: _ts(t.warn, 12.5, h: 1.45)))
      else if (g.status != null && !g.signedIn)
        Padding(padding: const EdgeInsets.only(top: 14), child: Text(g.status!, style: _ts(t.sub, 12.5))),
    ]);
    return _Page(
      t: t,
      title: 'Google account',
      subtitle: 'Sign in once. Your calendar and tasks appear in Orbit, and your planner backs up to your own Drive.',
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: c.maxWidth > 860
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: 56),
                  Expanded(flex: 4, child: _connections()),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  left,
                  const SizedBox(height: 32),
                  _connections(),
                ]),
        ),
      ),
    );
  }
}
