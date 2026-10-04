part of 'home_page.dart';

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

/// Shape rule for the whole planner: controls and inputs use 10, surfaces
/// use 16, checkmarks are circles. Nothing else.
const _rSm = 10.0, _rLg = 16.0;
const _fontFallback = ['Segoe UI', 'Roboto'];

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
    );

/// One palette. Cool neutrals plus a single emerald accent.
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
        accent = dark ? const Color(0xFF3DD68C) : const Color(0xFF138A55),
        onAccent = dark ? const Color(0xFF07140D) : const Color(0xFFFBFBFC),
        warn = dark ? const Color(0xFFF0757D) : const Color(0xFFC0392B);

  final bool dark;
  final Color bg, side, surface, raised, line, text, sub, faint, accent, onAccent, warn;
  Color get accentSoft => accent.withValues(alpha: dark ? 0.16 : 0.12);
}
