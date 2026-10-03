import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';

import 'agenda_service.dart';
import 'planner_model.dart';

enum IslandState { hidden, notch, idle, open, call, music, success }

enum IslandPage { home, music, stocks, today, settings }

enum ShortcutKind { web, app, screensaver, planner }

class NowPlaying {
  const NowPlaying(this.title, this.artist, this.playing, [this.art]);
  final String title, artist;
  final bool playing;
  final String? art;
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

class IslandController extends ChangeNotifier {
  IslandState state = IslandState.hidden;
  IslandPage page = IslandPage.home;
  NowPlaying? nowPlaying;
  bool _demoMusic = false;
  bool near = false;
  bool _over = false;

  /// Runtime: Chrome is the foreground app.
  bool chromeMode = false;
  Timer? _timer, _overTimer, _saveTimer;

  // ---- user settings (saved) ----
  double idleWidth = 260;
  Color pipColor = const Color(0xFFF4EFE6);
  bool openOnHover = false;
  bool quietInChrome = true;
  bool musicHelper = true; // the PowerShell media-session reader
  String stockSymbol = 'AAPL';
  String stockRange = '1d'; // 1d | 5d | 1mo
  bool stockCandles = true; // false = bars
  List<IslandShortcut> shortcuts = defaultShortcuts();
  List<String> watchlist = ['AAPL', 'NVDA', 'TSLA', 'SNOW'];
  List<CalendarFeed> calendarFeeds = [];

  /// Set by main(): the same planner the Home page edits.
  PlannerModel? planner;
  final AgendaService agenda = AgendaService();

  final ValueNotifier<Offset> gaze = ValueNotifier(Offset.zero);

  /// Live geometry, published by the real island window.
  Size pillSize = const Size(260, 57);
  double pillDy = 0;

  void Function(String)? sendMusic;
  void Function(String)? openUrl;

  Size get idleSize => Size(idleWidth, (idleWidth * 0.22).roundToDouble());
  bool get visible => state != IslandState.hidden;
  bool get quiet => chromeMode && quietInChrome;
  bool get musicPlaying => (nowPlaying?.playing ?? false) || _demoMusic;
  IslandState get _resting =>
      quiet ? IslandState.notch : (musicPlaying ? IslandState.music : IslandState.idle);

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
      quietInChrome = (j['quietInChrome'] as bool?) ?? true;
      musicHelper = (j['musicHelper'] as bool?) ?? true;
      stockSymbol = (j['stockSymbol'] as String?) ?? 'AAPL';
      stockRange = (j['stockRange'] as String?) ?? '1d';
      stockCandles = (j['stockCandles'] as bool?) ?? true;
      final w = j['watchlist'];
      if (w is List) watchlist = [for (final e in w) if (e is String && e.isNotEmpty) e];
      final cal = j['calendars'];
      if (cal is List) {
        calendarFeeds = [
          for (final e in cal)
            if (e is Map<String, dynamic>) CalendarFeed.fromJson(e),
        ];
      }
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
          'quietInChrome': quietInChrome,
          'musicHelper': musicHelper,
          'stockSymbol': stockSymbol,
          'stockRange': stockRange,
          'stockCandles': stockCandles,
          'watchlist': watchlist,
          'calendars': [for (final f in calendarFeeds) f.toJson()],
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

  void setQuietInChrome(bool v) {
    quietInChrome = v;
    _applyQuiet();
    _persist();
  }

  void setMusicHelper(bool v) {
    musicHelper = v;
    notifyListeners();
    _persist();
  }

  void setStockSymbol(String s) {
    stockSymbol = s.trim().toUpperCase();
    notifyListeners();
    _persist();
  }

  void setStockRange(String r) {
    stockRange = r;
    notifyListeners();
    _persist();
  }

  void setStockCandles(bool v) {
    stockCandles = v;
    notifyListeners();
    _persist();
  }

  void addWatch(String sym) {
    final s = sym.trim().toUpperCase();
    if (s.isEmpty || watchlist.contains(s)) return;
    watchlist.add(s);
    notifyListeners();
    _persist();
  }

  void insertWatch(int index, String sym) {
    if (watchlist.contains(sym)) return;
    watchlist.insert(index.clamp(0, watchlist.length).toInt(), sym);
    notifyListeners();
    _persist();
  }

  void removeWatch(String sym) {
    watchlist.remove(sym);
    notifyListeners();
    _persist();
  }

  void addFeed(CalendarFeed f) {
    calendarFeeds.add(f);
    notifyListeners();
    _persist();
  }

  void removeFeed(CalendarFeed f) {
    calendarFeeds.remove(f);
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

  void setChromeMode(bool v) {
    if (chromeMode == v) return;
    chromeMode = v;
    _applyQuiet();
  }

  /// In Chrome (quiet mode) the island is only a tiny notch until clicked.
  void _applyQuiet() {
    if (quiet) {
      if (state == IslandState.idle || state == IslandState.music) _set(IslandState.notch);
    } else if (state == IslandState.notch) {
      _set(near ? _resting : IslandState.hidden);
    }
    notifyListeners();
  }

  void setNowPlaying(NowPlaying? n) {
    final oldKey = nowPlaying?.key;
    final wasPlaying = nowPlaying?.playing ?? false;
    nowPlaying = n;
    final isPlaying = n?.playing ?? false;
    final busy = state == IslandState.call ||
        state == IslandState.success ||
        state == IslandState.open;
    if (isPlaying && (!wasPlaying || n!.key != oldKey) && !busy && !quiet) {
      preview(IslandState.music);
    } else if (!isPlaying && wasPlaying && !_demoMusic && state == IslandState.music) {
      _timer?.cancel();
      _set(near ? IslandState.idle : IslandState.hidden);
    } else {
      notifyListeners();
    }
  }

  void setNear(bool v) {
    if (v == near) return;
    near = v;
    if (v) {
      _timer?.cancel();
      if (state == IslandState.hidden) _set(_resting);
    } else if (state == IslandState.idle ||
        state == IslandState.music ||
        state == IslandState.notch) {
      _later(const Duration(milliseconds: 700), () => _set(IslandState.hidden));
    } else if (state == IslandState.open && openOnHover) {
      _later(const Duration(milliseconds: 500), close);
    }
  }

  void setOverPill(bool v) {
    if (v == _over) return;
    _over = v;
    _overTimer?.cancel();
    if (v && openOnHover && !quiet && (state == IslandState.idle || state == IslandState.music)) {
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

  void preview(IslandState s) {
    _timer?.cancel();
    switch (s) {
      case IslandState.hidden:
        _set(IslandState.hidden);
      case IslandState.notch:
        _set(IslandState.notch);
        _hideSoon(3);
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
    chromeMode = false;
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
    agenda.dispose();
    super.dispose();
  }
}
