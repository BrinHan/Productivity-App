part of 'home_page.dart';

/// Settings > Your data: a backup file to keep, restoring one, and the
/// folder everything lives in.
class _DataSection extends StatefulWidget {
  const _DataSection({required this.t, required this.p, required this.row});
  final _T t;
  final PlannerModel p;
  final Widget Function(String title, String sub, Widget trailing, {bool last}) row;

  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  String? _note;
  bool _busy = false;

  static const _type = XTypeGroup(label: 'Meridian backup', extensions: ['json']);

  Future<void> _run(Future<String?> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    String? note;
    try {
      note = await job();
    } on FormatException catch (e) {
      note = e.message;
    } catch (e, st) {
      logError(e, st);
      note = 'That did not work: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = note;
    });
  }

  Future<String?> _export() async {
    final at = await getSaveLocation(suggestedName: Backup.suggestedName(), acceptedTypeGroups: const [_type]);
    if (at == null) return null;
    final path = at.path.toLowerCase().endsWith('.json') ? at.path : '${at.path}.json';
    await widget.p.flush(); // the backup includes the last change
    await File(path).writeAsString(await Backup.create());
    return 'Saved to $path';
  }

  Future<String?> _import() async {
    final f = await openFile(acceptedTypeGroups: const [_type]);
    if (f == null) return null;
    final n = await Backup.restore(await f.readAsString());
    return 'Restored $n ${n == 1 ? 'file' : 'files'}. The planner and island pick it up right away; '
        'quit and reopen Meridian for the rest.';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.row(
          'Back up',
          'One file with your tasks, settings and meeting notes. Keep it somewhere safe.',
          _Btn(t, 'Save backup', _busy ? null : () => _run(_export), compact: true),
        ),
        widget.row(
          'Restore',
          'Replaces what is here with a backup. The current files are kept beside it as .bak.',
          _Btn(t, 'Open backup', _busy ? null : () => _run(_import), compact: true),
        ),
        widget.row(
          'Data folder',
          appDataDir.path,
          _Btn(
            t,
            'Open',
            () => Process.start('explorer.exe', [appDataDir.path], mode: ProcessStartMode.detached),
            compact: true,
          ),
          last: _note == null,
        ),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(_note!, style: _ts(t.sub, 12.5, h: 1.4)),
          ),
      ],
    );
  }
}

/// Settings > About: the version, whether a newer one is out, and the logs
/// for a bug report.
class _AboutSection extends StatefulWidget {
  const _AboutSection({required this.t, required this.row});
  final _T t;
  final Widget Function(String title, String sub, Widget trailing, {bool last}) row;

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  Release? _update;
  bool _checking = false, _checked = false, _copied = false;

  @override
  void initState() {
    super.initState();
    _check(force: false);
  }

  Future<void> _check({required bool force}) async {
    setState(() => _checking = true);
    final r = await UpdateCheck.newer(force: force);
    if (!mounted) return;
    setState(() {
      _update = r;
      _checking = false;
      _checked = force || _checked;
    });
  }

  Future<void> _copyDiagnostics() async {
    final text = 'Meridian $kAppVersion\n${await Log.recent()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final u = _update;
    final status = _checking
        ? 'Checking for updates…'
        : u != null
        ? 'Meridian ${u.version} is out.'
        : _checked
        ? 'You have the latest version.'
        : 'Checks for a new version once a day.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.row(
          'Meridian $kAppVersion',
          status,
          u != null
              ? _Btn(
                  t,
                  u.installer != null ? 'Download' : 'See what\'s new',
                  () => openWeb(u.installer ?? u.page),
                  primary: true,
                  compact: true,
                )
              : _Btn(t, 'Check now', _checking ? null : () => _check(force: true), compact: true),
        ),
        widget.row(
          'Something wrong?',
          'Copies the recent error log, to paste into a bug report. It has no tasks or notes in it.',
          _Btn(t, _copied ? 'Copied' : 'Copy diagnostics', _copyDiagnostics, compact: true),
          last: true,
        ),
      ],
    );
  }
}
