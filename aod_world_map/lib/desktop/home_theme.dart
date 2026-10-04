part of 'home_page.dart';

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

/// Shape rule for the whole planner: controls and inputs use 8, surfaces
/// use 14, checkboxes use 6, toggles are pills. Nothing else.
const _rSm = 8.0, _rLg = 14.0;
const _fontFallback = ['Segoe UI', 'Roboto'];

class _FontChoice {
  const _FontChoice(this.label, this.family, this.note);
  final String label, family, note;
}

const _fonts = [
  _FontChoice('Segoe UI', 'Segoe UI Variable Display', 'Current default, built into Windows'),
  _FontChoice('Inter', 'Inter', 'Bundled with the app'),
  _FontChoice('Geist', 'Geist', 'Bundled with the app'),
  _FontChoice('Plus Jakarta Sans', 'Plus Jakarta Sans', 'Bundled with the app'),
  _FontChoice('Satoshi', 'Satoshi', 'Install it in Windows first, then pick it'),
  _FontChoice('Proxima Nova', 'Proxima Nova', 'Install it in Windows first, then pick it'),
];

String _dur(int m) {
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '${r}m';
  if (r == 0) return '${h}h';
  return '${h}h ${r}m';
}

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '$h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
}

TextStyle _ts(
  Color color,
  double size, {
  FontWeight w = FontWeight.w500,
  double ls = 0,
  double? h,
  bool tab = false,
  TextDecoration? deco,
}) =>
    TextStyle(
      color: color,
      fontSize: size,
      fontWeight: w,
      letterSpacing: ls,
      height: h,
      decoration: deco,
      fontFeatures: tab ? const [FontFeature.tabularFigures()] : null,
      // Variable fonts need the weight axis set explicitly. Static fonts ignore it.
      fontVariations: [FontVariation('wght', w.value.toDouble())],
    );

/// One palette: cool neutrals, one emerald accent for progress only.
/// Buttons and checks use the foreground colour, like shadcn's neutral theme.
class _T {
  _T(this.dark)
      : bg = dark ? const Color(0xFF0F0F11) : const Color(0xFFF4F4F5),
        side = dark ? const Color(0xFF0B0B0D) : const Color(0xFFEBEBED),
        surface = dark ? const Color(0xFF17171A) : const Color(0xFFFBFBFC),
        raised = dark ? const Color(0xFF212125) : const Color(0xFFEEEEF0),
        line = dark ? const Color(0xFF2B2B31) : const Color(0xFFDEDEE2),
        text = dark ? const Color(0xFFEDEDEF) : const Color(0xFF18181B),
        sub = dark ? const Color(0xFFA1A1AA) : const Color(0xFF5F5F68),
        faint = dark ? const Color(0xFF71717A) : const Color(0xFF8E8E96),
        focus = dark ? const Color(0xFF9A9AA3) : const Color(0xFF3F3F46),
        accent = dark ? const Color(0xFF3DD68C) : const Color(0xFF138A55),
        onAccent = dark ? const Color(0xFF07140D) : const Color(0xFFFBFBFC),
        warn = dark ? const Color(0xFFF0757D) : const Color(0xFFC0392B),
        panel = dark ? const Color(0xFF181D25) : const Color(0xFFE7E8EB),
        panelLine = dark ? const Color(0xFF283039) : const Color(0xFFD2D4D9),
        panelCard = dark ? const Color(0xFF222934) : const Color(0xFFF2F3F5);

  final bool dark;
  final Color bg, side, surface, raised, line, text, sub, faint, focus, accent, onAccent, warn;
  final Color panel, panelLine, panelCard;
  Color get accentSoft => accent.withValues(alpha: dark ? 0.16 : 0.12);
}

/// Planner preferences, saved next to the other app files.
class _Prefs extends ChangeNotifier {
  static final _Prefs i = _Prefs();

  String font = 'Segoe UI Variable Display';
  bool sidebarOpen = true, showSchedule = true;
  bool _loaded = false;

  File get _file {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final s = Platform.pathSeparator;
    return File('$base${s}AodWorldMap${s}ui.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _file;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final fam = j['font'];
      if (fam is String && _fonts.any((x) => x.family == fam)) font = fam;
      sidebarOpen = (j['sidebar'] as bool?) ?? true;
      showSchedule = (j['schedule'] as bool?) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = _file;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'font': font, 'sidebar': sidebarOpen, 'schedule': showSchedule}));
    } catch (_) {}
  }

  void setFont(String v) {
    font = v;
    notifyListeners();
    _save();
  }

  void setSidebar(bool v) {
    sidebarOpen = v;
    notifyListeners();
    _save();
  }

  void setSchedule(bool v) {
    showSchedule = v;
    notifyListeners();
    _save();
  }
}
