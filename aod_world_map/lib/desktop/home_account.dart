part of 'home_page.dart';

/// Google page. Sign-in is one button: the app ships its own OAuth client,
/// so nobody needs a Google Cloud project. The old paste-your-own-client
/// form lives under Advanced for builds that have no bundled client.
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
  bool _advanced = false;

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

  Widget _card({required Widget child}) {
    final t = widget.t;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(_rLg),
        border: Border.all(color: t.line),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------------ sign in

  Widget _perm(IconData icon, String title, String body) {
    final t = widget.t;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: t.sub),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _ts(t.text, 13.5, w: FontWeight.w600)),
            Text(body, style: _ts(t.sub, 12.5, h: 1.4)),
          ]),
        ),
      ]),
    );
  }

  Widget _signIn() {
    final t = widget.t, g = widget.g;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sign in with Google', style: _ts(t.text, 16, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('One click. You approve access in your browser and Orbit never sees your password.',
            style: _ts(t.sub, 13, h: 1.45)),
        const SizedBox(height: 18),
        _Btn(t, g.busy ? 'Waiting for Google' : 'Continue with Google', g.busy ? null : g.signIn,
            primary: true, icon: Icons.login_rounded),
        const SizedBox(height: 22),
        Text('Orbit asks for', style: _ts(t.text, 13, w: FontWeight.w600)),
        _perm(Icons.calendar_month_outlined, 'Calendar', 'Read your events.'),
        _perm(Icons.checklist_rounded, 'Tasks', 'Read your tasks and tick them off.'),
        if (kGoogleReadMail) _perm(Icons.mail_outline_rounded, 'Gmail', 'Read your inbox. Nothing is sent or deleted.'),
        _perm(Icons.cake_outlined, 'Contacts', 'Read birthdays.'),
        _perm(Icons.cloud_outlined, 'Drive', 'A private app folder for backups. Your files stay untouched.'),
        const SizedBox(height: 18),
        Text(
          'You can untick any of these on Google\'s screen and the rest still works. '
          'If Google says it has not verified this app, choose Advanced, then continue.',
          style: _ts(t.sub, 12, h: 1.5),
        ),
      ]),
    );
  }

  Widget _notBundled() {
    final t = widget.t;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Google sign-in is not set up in this build', style: _ts(t.text, 16, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Run or build with --dart-define-from-file=google_client.json so the app includes its Google client.',
            style: _ts(t.sub, 13, h: 1.45)),
        const SizedBox(height: 16),
        _Tap(
          t: t,
          radius: 6,
          onTap: () => setState(() => _advanced = !_advanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Advanced: use my own client', style: _ts(t.sub, 12.5, w: FontWeight.w600)),
              Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: t.sub),
            ]),
          ),
        ),
        if (_advanced) ...[
          const SizedBox(height: 14),
          _Btn(t, 'Open Google Cloud', () => _open('https://console.cloud.google.com/apis/credentials'),
              icon: Icons.open_in_new_rounded, compact: true),
          const SizedBox(height: 16),
          _Labeled(t, 'Client ID', _id, hint: '123456-abc.apps.googleusercontent.com', onChanged: () {
            if (_formError != null) setState(() => _formError = null);
          }),
          const SizedBox(height: 14),
          _Labeled(t, 'Client secret', _secret, obscure: true, onChanged: () {
            if (_formError != null) setState(() => _formError = null);
          }),
          if (_formError != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_formError!, style: _ts(t.warn, 12.5))),
          const SizedBox(height: 16),
          _Btn(t, 'Save and continue', _save, primary: true),
        ],
      ]),
    );
  }

  Widget _account() {
    final t = widget.t, g = widget.g;
    final mail = g.email ?? 'Google account';
    return _card(
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.raised),
          child: Text(mail[0].toUpperCase(), style: _ts(t.text, 18, w: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mail, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 15, w: FontWeight.w600)),
            Text(g.loading ? 'Syncing' : 'Connected', style: _ts(t.accent, 12.5, w: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        _Btn(t, 'Sign out', g.busy ? null : g.signOut, compact: true),
      ]),
    );
  }

  // ------------------------------------------------------- connections

  Widget _service(IconData icon, String name, String info, {Widget? actions, bool last = false, bool off = false}) {
    final t = widget.t;
    return Column(children: [
      Opacity(
        opacity: off ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
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
      ),
      if (!last) _Hair(t),
    ]);
  }

  String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  Widget _connections() {
    final t = widget.t, g = widget.g;
    final inn = g.signedIn;
    const off = 'Available after you sign in';
    const denied = 'Not allowed on the consent screen';
    String info(bool can, String ok) => !inn ? off : (can ? ok : denied);
    String when(DateTime? d) => d == null ? 'Never backed up from this PC' : 'Last backup ${_clock(d)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What is connected', style: _ts(t.text, 16, w: FontWeight.w700)),
      const SizedBox(height: 4),
      _service(Icons.calendar_month_outlined, 'Calendar',
          info(g.canCalendar, '${_n(g.events.length, 'event', 'events')} today and tomorrow')),
      _service(Icons.checklist_rounded, 'Tasks',
          info(g.canTasks, '${_n(g.todos.length, 'open task', 'open tasks')}, shown in today\'s column')),
      if (kGoogleReadMail)
        _service(Icons.mail_outline_rounded, 'Gmail', info(g.canMail, '${g.unread} unread in your inbox')),
      _service(Icons.cake_outlined, 'Contacts',
          info(g.canContacts, '${_n(g.birthdays.length, 'birthday', 'birthdays')} in the next 30 days')),
      _service(
        Icons.photo_library_outlined,
        'Photos',
        'Google no longer lets apps read your photo library',
        off: true,
      ),
      _service(
        Icons.cloud_outlined,
        'Drive backup',
        !inn ? off : (g.canDrive ? (g.status ?? when(g.lastSync)) : denied),
        last: true,
        actions: inn && g.canDrive
            ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Btn(t, 'Back up now', g.busy ? null : g.backupNow, compact: true),
                _Btn(t, 'Restore', g.busy ? null : g.restore, compact: true),
                const SizedBox(width: 6),
                Text('Auto', style: _ts(t.sub, 12.5)),
                _Toggle(t, g.autoBackup, g.setAutoBackup),
              ])
            : null,
      ),
      if (inn) ...[
        const SizedBox(height: 14),
        _Btn(t, 'Refresh now', g.loading ? null : () => g.refresh(force: true),
            compact: true, icon: Icons.refresh_rounded),
      ],
      const SizedBox(height: 22),
      Text('Sign-in tokens stay in your Windows user profile. Signing out revokes them at Google. '
          'Backups include your iCal links.',
          style: _ts(t.sub, 12, h: 1.5)),
    ]);
  }

  // ---------------------------------------------------- inbox, birthdays

  Widget _inbox() {
    final t = widget.t, g = widget.g;
    if (!g.signedIn || !g.canMail) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Inbox', style: _ts(t.text, 16, w: FontWeight.w700)),
          const SizedBox(width: 10),
          Text('${g.unread} unread', style: _ts(t.sub, 12.5, tab: true)),
          const Spacer(),
          _Btn(t, 'Open Gmail', () => _open('https://mail.google.com/mail/u/0/#inbox'), ghost: true, compact: true),
        ]),
        const SizedBox(height: 6),
        if (g.mail.isEmpty)
          _Empty(t, Icons.mark_email_read_outlined, 'Inbox zero', 'No unread mail right now.')
        else
          for (var i = 0; i < g.mail.length; i++) ...[
            _Tap(
              t: t,
              onTap: () => _open('https://mail.google.com/mail/u/0/#inbox/${g.mail[i].threadId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.mail[i].from, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13.5, w: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(g.mail[i].subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.sub, 12.5)),
                ]),
              ),
            ),
            if (i < g.mail.length - 1) _Hair(t),
          ],
      ]),
    );
  }

  Widget _birthdays() {
    final t = widget.t, g = widget.g;
    if (!g.signedIn || !g.canContacts || g.birthdays.isEmpty) return const SizedBox.shrink();
    final today = dayOf(DateTime.now());
    String label(DateTime d) {
      final diff = d.difference(today).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      return '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Birthdays', style: _ts(t.text, 16, w: FontWeight.w700)),
        const SizedBox(height: 6),
        for (var i = 0; i < g.birthdays.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              Expanded(child: Text(g.birthdays[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(t.text, 13.5, w: FontWeight.w600))),
              if (g.birthdays[i].age != null) ...[
                Text('turns ${g.birthdays[i].age}', style: _ts(t.sub, 12.5, tab: true)),
                const SizedBox(width: 12),
              ],
              SizedBox(width: 64, child: Text(label(g.birthdays[i].date), textAlign: TextAlign.right, style: _ts(t.sub, 12.5, tab: true))),
            ]),
          ),
          if (i < g.birthdays.length - 1) _Hair(t),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, g = widget.g;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!g.configured) _notBundled() else if (!g.signedIn) _signIn() else _account(),
      if (g.error != null)
        Padding(padding: const EdgeInsets.only(top: 14), child: Text(g.error!, style: _ts(t.warn, 12.5, h: 1.45)))
      else if (g.status != null && !g.signedIn)
        Padding(padding: const EdgeInsets.only(top: 14), child: Text(g.status!, style: _ts(t.sub, 12.5))),
      _inbox(),
      _birthdays(),
    ]);
    return _Page(
      t: t,
      title: 'Google account',
      subtitle: 'Sign in once. Calendar, tasks, mail and birthdays appear in Orbit, and your planner backs up to your own Drive.',
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
