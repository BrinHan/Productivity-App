part of 'home_page.dart';


/// Shape rule for the whole planner: controls and inputs use 6, surfaces
/// use 8, checkboxes use 6, toggles are pills. Nothing else. Small radii and
/// hairline borders instead of shadows keep it flat and document-like.
const _rSm = 6.0, _rLg = 8.0;
const _fontFallback = ['Segoe UI', 'Roboto'];

class _FontChoice {
  const _FontChoice(this.label, this.family, this.note);
  final String label, family, note;
}

const _fonts = [
  _FontChoice('Inter', 'Inter', 'Default, bundled with the app'),
  _FontChoice('Segoe UI', 'Segoe UI Variable Display', 'Built into Windows'),
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

/// A whole hour as the clock shows it: 9 AM, 12 PM, midnight.
String _hourLabel(int h) => h % 24 == 0 ? 'midnight' : _clock(DateTime(2000, 1, 1, h)).replaceFirst(':00', '');

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
      // Body text gets room to breathe; headings stay tight.
      height: h ?? (size <= 15 ? 1.45 : null),
      decoration: deco,
      fontFeatures: tab ? const [FontFeature.tabularFigures()] : null,
      // Variable fonts need the weight axis set explicitly. Static fonts ignore it.
      fontVariations: [FontVariation('wght', w.value.toDouble())],
    );

/// One palette in the spirit of Notion: warm neutrals on white (or near
/// black), hairline dividers, and one calm blue accent for selection,
/// progress and checks. Text tiers are the main text colour at lower
/// strength, pre-blended so they stay solid on any surface.
class _T {
  _T(this.dark)
      : bg = dark ? const Color(0xFF191919) : const Color(0xFFFFFFFF),
        side = dark ? const Color(0xFF202020) : const Color(0xFFF7F7F5),
        surface = dark ? const Color(0xFF202020) : const Color(0xFFFFFFFF),
        raised = dark ? const Color(0xFF37352F) : const Color(0xFFEBECED),
        line = dark ? const Color(0xFF2F2F2F) : const Color(0xFFE9E9E7), // text at ~9%
        text = dark ? const Color(0xFFE8E8E8) : const Color(0xFF37352F), // dark: white at 90%
        sub = dark ? const Color(0xFFA3A3A3) : const Color(0xFF73726D), // text at 60% / 70%
        faint = dark ? const Color(0xFF818181) : const Color(0xFF9B9A97), // text at 45% / 50%
        focus = dark ? const Color(0xFFA3A3A3) : const Color(0xFF37352F),
        accent = const Color(0xFF2383E2),
        onAccent = const Color(0xFFFFFFFF),
        warn = dark ? const Color(0xFFFF7369) : const Color(0xFFD44C47),
        panel = dark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
        panelLine = dark ? const Color(0xFF2F2F2F) : const Color(0xFFE9E9E7),
        panelCard = dark ? const Color(0xFF252525) : const Color(0xFFFFFFFF);

  final bool dark;
  final Color bg, side, surface, raised, line, text, sub, faint, focus, accent, onAccent, warn;
  final Color panel, panelLine, panelCard;
  Color get accentSoft => accent.withValues(alpha: dark ? 0.16 : 0.10);

  /// A tag's pastel: a soft tint behind text of the same hue, darker in
  /// light mode and lighter in dark mode so it reads at small sizes.
  ({Color bg, Color fg}) tag(String name) {
    final hue = switch (name) {
      'work' => 0,
      'personal' => 1,
      'health' => 2,
      _ => 3 + name.codeUnits.fold(0, (a, b) => a + b) % (_tagFg.length - 3),
    };
    final fg = (dark ? _tagFgDark : _tagFg)[hue];
    return dark
        ? (bg: Color.alphaBlend(fg.withValues(alpha: 0.2), bg), fg: fg)
        : (bg: _tagBg[hue], fg: fg);
  }
}

// Blue, pink, green, then yellow, purple, orange, red, brown for other tags.
const _tagBg = [
  Color(0xFFE7F3F8), Color(0xFFFAF1F5), Color(0xFFEDF3EC), Color(0xFFFBF3DB),
  Color(0xFFF6F3F9), Color(0xFFFBECDD), Color(0xFFFDEBEC), Color(0xFFF4EEEE),
];
const _tagFg = [
  Color(0xFF2B6F99), Color(0xFFA83F77), Color(0xFF3C7556), Color(0xFF8A6214),
  Color(0xFF7A4FA0), Color(0xFFA4560B), Color(0xFFB53F3A), Color(0xFF80553F),
];
const _tagFgDark = [
  Color(0xFF6FB0DA), Color(0xFFEC7DB8), Color(0xFF4DAB9A), Color(0xFFDFAB01),
  Color(0xFFB593E6), Color(0xFFFFA344), Color(0xFFFF7369), Color(0xFFC99A86),
];

/// Planner preferences, saved next to the other app files.
class _Prefs extends ChangeNotifier {
  static final _Prefs i = _Prefs();

  String font = 'Inter';
  bool sidebarOpen = true, showSchedule = true;
  Set<String> calHidden = {};
  int calMode = 1; // Calendar page: 0 day, 1 week, 2 month

  /// The workday, in whole hours, that daily planning fits tasks into.
  int dayStart = 9, dayEnd = 17;
  bool _loaded = false;

  File get _file => appDataFile('ui.json');

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
      dayStart = ((j['dayStart'] as num?)?.toInt() ?? 9).clamp(0, 23).toInt();
      dayEnd = ((j['dayEnd'] as num?)?.toInt() ?? 17).clamp(dayStart + 1, 24).toInt();
      notifyListeners();
    } catch (e, st) {
      logError(e, st);
    }
  }

  Future<void> _save() async {
    try {
      final f = _file;
      await f.parent.create(recursive: true);
      await writeFileSafely(f, jsonEncode({
        'font': font,
        'sidebar': sidebarOpen,
        'schedule': showSchedule,
        'calHidden': calHidden.toList(),
        'calMode': calMode,
        'dayStart': dayStart,
        'dayEnd': dayEnd,
      }));
    } catch (e, st) {
      logError(e, st);
    }
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

  /// Moves the start or end of the workday by an hour, keeping at least an
  /// hour between them.
  void setWorkday(int start, int end) {
    if (start < 0 || end > 24 || end - start < 1) return;
    dayStart = start;
    dayEnd = end;
    notifyListeners();
    _save();
  }

  void setCalMode(int v) {
    calMode = v;
    _save();
  }
}
