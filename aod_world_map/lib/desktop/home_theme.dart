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

/// One palette: deep slate greys, one emerald accent for progress only.
/// Buttons and checks use the foreground colour, like shadcn's neutral theme.
class _T {
  _T(this.dark)
      : bg = dark ? const Color(0xFF1B2129) : const Color(0xFFF1F3F6),
        side = dark ? const Color(0xFF161B22) : const Color(0xFFE6E9EE),
        surface = dark ? const Color(0xFF222932) : const Color(0xFFFAFBFC),
        raised = dark ? const Color(0xFF2B333D) : const Color(0xFFEBEEF2),
        line = dark ? const Color(0xFF353E4A) : const Color(0xFFD8DDE4),
        text = dark ? const Color(0xFFE6EAF0) : const Color(0xFF1B222B),
        sub = dark ? const Color(0xFFA3ADBA) : const Color(0xFF5A6573),
        faint = dark ? const Color(0xFF737E8C) : const Color(0xFF8A94A1),
        focus = dark ? const Color(0xFF9AA5B3) : const Color(0xFF3C4652),
        accent = dark ? const Color(0xFF3DD68C) : const Color(0xFF138A55),
        onAccent = dark ? const Color(0xFF07140D) : const Color(0xFFFBFBFC),
        warn = dark ? const Color(0xFFF0757D) : const Color(0xFFC0392B),
        panel = dark ? const Color(0xFF1F2630) : const Color(0xFFE3E7EC),
        panelLine = dark ? const Color(0xFF323B47) : const Color(0xFFCDD3DB),
        panelCard = dark ? const Color(0xFF29313C) : const Color(0xFFEFF2F5);

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
  Set<String> calHidden = {};
  int calMode = 1; // Calendar page: 0 day, 1 week, 2 month
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
      calHidden = {for (final x in (j['calHidden'] as List? ?? const [])) '$x'};
      calMode = (j['calMode'] as int?) ?? 1;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = _file;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'font': font,
        'sidebar': sidebarOpen,
        'schedule': showSchedule,
        'calHidden': calHidden.toList(),
        'calMode': calMode,
      }));
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

  void toggleCal(String id) {
    calHidden = {...calHidden};
    if (!calHidden.remove(id)) calHidden.add(id);
    notifyListeners();
    _save();
  }

  void setCalMode(int v) {
    calMode = v;
    _save();
  }
}
