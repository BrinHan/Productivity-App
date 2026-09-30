import 'dart:ui' show Brightness, Color;

/// All colours used by the face. Instances are const singletons so painters
/// can compare them by identity in `shouldRepaint`.
class AodPalette {
  const AodPalette._({
    required this.background,
    required this.day,
    required this.twilight,
    required this.night,
    required this.terminator,
    required this.user,
    required this.userHalo,
    required this.city,
    required this.text,
  });

  final Color background, day, twilight, night, terminator, user, userHalo, city, text;

  /// Light theme -> greys. Dark theme -> red on black (like the watch).
  /// [alwaysOn] swaps in a dimmed, low-energy variant of either.
  factory AodPalette.resolve(Brightness brightness, {bool alwaysOn = false}) {
    if (brightness == Brightness.light) return alwaysOn ? _lightDim : _light;
    return alwaysOn ? _darkDim : _dark;
  }

  static const _dark = AodPalette._(
    background: Color(0xFF000000),
    day: Color(0xFFFF3B30),
    twilight: Color(0xFF8F2620),
    night: Color(0xFF32100D),
    terminator: Color(0xFFFF3B30),
    user: Color(0xFFFF8A80),
    userHalo: Color(0xFFFF3B30),
    city: Color(0xFFFF3B30),
    text: Color(0xFFFF3B30),
  );
  static const _darkDim = AodPalette._(
    background: Color(0xFF000000),
    day: Color(0xFF9A241D),
    twilight: Color(0xFF5E1712),
    night: Color(0xFF250B09),
    terminator: Color(0xFF9A241D),
    user: Color(0xFFC8362C),
    userHalo: Color(0xFF9A241D),
    city: Color(0xFF9A241D),
    text: Color(0xFF9A241D),
  );
  static const _light = AodPalette._(
    background: Color(0xFFF2F2F7),
    day: Color(0xFF6E6E73),
    twilight: Color(0xFFB5B5BA),
    night: Color(0xFFDCDCE0),
    terminator: Color(0xFF3A3A3C),
    user: Color(0xFF000000),
    userHalo: Color(0xFF000000),
    city: Color(0xFF3A3A3C),
    text: Color(0xFF1C1C1E),
  );
  static const _lightDim = AodPalette._(
    background: Color(0xFFF8F8FA),
    day: Color(0xFF9A9AA0),
    twilight: Color(0xFFC8C8CC),
    night: Color(0xFFE6E6E9),
    terminator: Color(0xFF8E8E93),
    user: Color(0xFF48484A),
    userHalo: Color(0xFF8E8E93),
    city: Color(0xFF8E8E93),
    text: Color(0xFF636366),
  );
}