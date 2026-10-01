import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';

enum IslandState { hidden, idle, open, call, music, success }

enum IslandPage { home, music, settings }

enum ShortcutKind { web, app, screensaver, planner }

/// What Windows reports as the current media session.
class NowPlaying {
  const NowPlaying(this.title, this.artist, this.playing, [this.art]);
  final String title, artist;
  final bool playing;
  final String? art; // path to the extracted album art file
  String get key => '$title|$artist';
}

class IslandShortcut {
  IslandShortcut({
    required this.label,
    required this.kind,
    this.target = '',
    required this.color,
    required this.icon,
  });
  String label;
  ShortcutKind kind;
  String target;
  Color color;
  String icon;

  Map<String, dynamic> toJson() => {
        'label': label,
        'kind': kind.name,
        'target': target,
        'color': color.toARGB32(),
        'icon': icon,
      };

  static IslandShortcut fromJson(Map<String, dynamic> j) => IslandShortcut(
        label: (j['label'] as String?) ?? 'Shortcut',
        kind: ShortcutKind.values
            .firstWhere((k) => k.name == j['kind'], orElse: () => ShortcutKind.web),
        target: (j['target'] as String?) ?? '',
        color: Color((j['color'] as int?) ?? 0xFF3B8BFF),
        icon: (j['icon'] as String?) ?? 'bolt',
      );
}

List<IslandShortcut> defaultShortcuts() => [
      IslandShortcut(
        label: 'Yahoo Finance',
        kind: ShortcutKind.web,
        target: 'https://finance.yahoo.com',
        color: const Color(0xFF7B5CFF),
        icon: 'show_chart',
      ),
      IslandShortcut(
        label: 'VS Code',
        kind: ShortcutKind.app,
        target: 'code',
        color: const Color(0xFF3B8BFF),
        icon: 'code',
      ),
      IslandShortcut(
        label: 'Screensaver',
        kind: ShortcutKind.screensaver,
        color: const Color(0xFFFF8A3D),
        icon: 'public',
      ),
      IslandShortcut(
        label: 'Planner',
        kind: ShortcutKind.planner,
        color: const Color(0xFF34C77B),
        icon: 'checklist',
      ),
    ];

/// State + settings for the dynamic island. Shared by the real island window
/// and the inline preview in the settings panel.
class IslandController extends ChangeNotifier {
  IslandState state = IslandState.hidden;
  IslandPage page = IslandPage.home;
  NowPlaying? nowPlaying;
  bool _demoMusic = false;
  bool near = false; // cursor near the island
  bool _over = false; // cursor over the pill itself
  Timer? _timer, _overTimer, _saveTimer;

  // ---- user settings (saved to disk) ----
  double idleWidth = 260;
  Color pipColor = const Color(0xFFF4EFE6); // soft white
  bool openOnHover = false; // default: click the pill to open
  List<IslandShortcut> shortcuts = defaultShortcuts();

  /// Where the character looks: -1..1 on each axis.
  final ValueNotifier<Offset> gaze = ValueNotifier(Offset.zero);

  /// Live pill geometry, published by the real island window.
  Size pillSize = const Size(260, 57);
  double pillDy = 0;

  /// Set by the shell: sends 'toggle' | 'next' | 'prev' to the media player.
  void Function(String)? sendMusic;

  Size get idleSize => Size(idleWidth, (idleWidth * 0.22).roundToDouble());
  bool get visible => state != IslandState.hidden;
  bool get musicPlaying => (nowPlaying?.playing ?? false) || _demoMusic;
  IslandState get _resting => musicPlaying ? IslandState.music : IslandState.idle;

  // ---------------------------------------------------------- persistence

  File get _file {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final s = Platform.pathSeparator;
    return File('$base${s}AodWorldMap${s}island.json');
  }

  Future<void> load() async {
    try {
      final f = _file;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map<String, dynamic>) return;
      idleWidth = ((j['idleWidth'] as num?) ?? 260).toDouble().clamp(180.0, 360.0).toDouble();
      pipColor = Color((j['pipColor'] as int?) ?? pipColor.toARGB32());
      openOnHover = (j['openOnHover'] as bool?) ?? false;
      final s = j['shortcuts'];
      if (s is List) {
        final list = [
          for (final e in s)
            if (e is Map<String, dynamic>) IslandShortcut.fromJson(e),
        ];
        if (list.isNotEmpty) shortcuts = list;
      }
    } catch (_) {}
  }

  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final f = _file;
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode({
          'idleWidth': idleWidth,
          'pipColor': pipColor.toARGB32(),
          'openOnHover': openOnHover,
          'shortcuts': [for (final s in shortcuts) s.toJson()],
        }));
      } catch (_) {}
    });
  }

  // ------------------------------------------------------------- settings

  void setIdleWidth(double w) {
    idleWidth = w.clamp(180.0, 360.0).toDouble();
    notifyListeners();
    _persist();
  }

  void setPipColor(Color c) {
    pipColor = c;
    notifyListeners();
    _persist();
  }

  void setOpenOnHover(bool v) {
    openOnHover = v;
    notifyListeners();
    _persist();
  }

  void shortcutsChanged() {
    notifyListeners();
    _persist();
  }

  void addShortcut() {
    shortcuts.add(IslandShortcut(
      label: 'New',
      kind: ShortcutKind.web,
      target: 'https://',
      color: const Color(0xFF22C3D6),
      icon: 'language',
    ));
    shortcutsChanged();
  }

  void removeShortcut(IslandShortcut s) {
    shortcuts.remove(s);
    shortcutsChanged();
  }

  // ----------------------------------------------------------- state flow

  /// Called with live data from Windows. A new track pops the island out.
  void setNowPlaying(NowPlaying? n) {
    final oldKey = nowPlaying?.key;
    final wasPlaying = nowPlaying?.playing ?? false;
    nowPlaying = n;
    final isPlaying = n?.playing ?? false;
    final busy = state == IslandState.call ||
        state == IslandState.success ||
        state == IslandState.open;
    if (isPlaying && (!wasPlaying || n!.key != oldKey) && !busy) {
      preview(IslandState.music);
    } else if (!isPlaying && wasPlaying && !_demoMusic && state == IslandState.music) {
      _timer?.cancel();
      _set(near ? IslandState.idle : IslandState.hidden);
    } else {
      notifyListeners();
    }
  }

  /// Cursor is near the island. Peeks out when near, retreats when away.
  void setNear(bool v) {
    if (v == near) return;
    near = v;
    if (v) {
      _timer?.cancel();
      if (state == IslandState.hidden) _set(_resting);
    } else if (state == IslandState.idle || state == IslandState.music) {
      _later(const Duration(milliseconds: 700), () => _set(IslandState.hidden));
    } else if (state == IslandState.open && openOnHover) {
      _later(const Duration(milliseconds: 500), close);
    }
  }

  /// Cursor is directly over the pill (used by "open on hover").
  void setOverPill(bool v) {
    if (v == _over) return;
    _over = v;
    _overTimer?.cancel();
    if (v && openOnHover && (state == IslandState.idle || state == IslandState.music)) {
      _overTimer = Timer(const Duration(milliseconds: 350), () {
        if (_over && (state == IslandState.idle || state == IslandState.music)) {
          open(state == IslandState.music ? IslandPage.music : IslandPage.home);
        }
      });
    }
  }

  void open([IslandPage p = IslandPage.home]) {
    if (state == IslandState.call || state == IslandState.success) return;
    _timer?.cancel();
    page = p;
    if (state == IslandState.open) {
      notifyListeners();
    } else {
      _set(IslandState.open);
    }
  }

  void setPage(IslandPage p) {
    page = p;
    notifyListeners();
  }

  void close() {
    if (state != IslandState.open) return;
    _timer?.cancel();
    _set(near ? _resting : IslandState.hidden);
  }

  /// Jump to a state (preview chips, tray menu, new track).
  void preview(IslandState s) {
    _timer?.cancel();
    switch (s) {
      case IslandState.hidden:
        _set(IslandState.hidden);
      case IslandState.idle:
        _set(IslandState.idle);
        _hideSoon(3);
      case IslandState.open:
        open();
      case IslandState.music:
        _demoMusic = !(nowPlaying?.playing ?? false);
        _set(IslandState.music);
        _hideSoon(6);
      case IslandState.call:
        _set(IslandState.call);
        _later(const Duration(seconds: 15), decline);
      case IslandState.success:
        _set(IslandState.success);
        _later(const Duration(milliseconds: 2300), _afterSuccess);
    }
  }

  void accept() {
    if (state == IslandState.call) preview(IslandState.success);
  }

  void decline() {
    if (state != IslandState.call) return;
    _timer?.cancel();
    _set(IslandState.idle);
    if (!near) _hideSoon(1);
  }

  void reset() {
    _timer?.cancel();
    _overTimer?.cancel();
    near = false;
    _over = false;
    _demoMusic = false;
    state = IslandState.hidden;
    notifyListeners();
  }

  void _afterSuccess() => _set(near ? _resting : IslandState.hidden);

  void _hideSoon(int seconds) => _later(Duration(seconds: seconds), () {
        if (!near) _set(IslandState.hidden);
      });

  void _later(Duration d, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(d, f);
  }

  void _set(IslandState s) {
    if (state == s) return;
    state = s;
    if (s == IslandState.hidden) _demoMusic = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _overTimer?.cancel();
    _saveTimer?.cancel();
    gaze.dispose();
    super.dispose();
  }
}
