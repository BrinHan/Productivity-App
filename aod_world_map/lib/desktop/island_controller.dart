import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';

import 'agenda_service.dart';
import 'app_catalog.dart' show InstalledApp;
import 'app_files.dart';
import 'google_service.dart';
import 'meeting_detector.dart';
import 'notes_service.dart';
import 'planner_model.dart';
import 'unlock_glyphs.dart' show kUnlockAnimation;
import 'unlock_watch.dart';

/// [verify]: Windows Hello is checking you on the Hello screen; the island
/// scans until it answers, then shows [success].
enum IslandState { hidden, notch, idle, open, call, music, verify, success, meeting }

enum IslandPage { home, music, stocks, today, settings }

enum ShortcutKind { web, app, screensaver, planner }

class NowPlaying {
  const NowPlaying(this.title, this.artist, this.playing,
      [this.art, this.album = '', this.app = '', this.position = Duration.zero, this.length = Duration.zero, this.positionAt]);
  final String title, artist;
  final bool playing;
  final String? art;

  /// Album title, when the player gives one.
  final String album;

  /// The playing app's id from Windows (e.g. 'Spotify.exe', 'chrome').
  final String app;

  /// Where the track was at [positionAt], and how long it is (zero when the
  /// player doesn't say).
  final Duration position, length;
  final DateTime? positionAt;

  /// Where the track is now: the player only reports on changes, so this
  /// runs the clock on from its last report while playing.
  Duration get positionNow {
    if (length <= Duration.zero) return Duration.zero;
    var p = position;
    if (playing && positionAt != null) p += DateTime.now().difference(positionAt!);
    if (p < Duration.zero) return Duration.zero;
    return p > length ? length : p;
  }
  String get key => '$title|$artist';
}

/// Live loudness of five bands of what the speakers play, for the
/// visualizer: sub-bass, bass, low-mid, high-mid, treble, each 0..1.
/// Arrives about 30 times a second; the bars read it every frame, so there
/// is nothing to notify.
class AudioBands {
  List<double> values = const [0, 0, 0, 0, 0];
  DateTime _at = DateTime(2000);
  bool _seen = false;

  /// Levels arrived a moment ago (something is playing right now).
  bool get live => DateTime.now().difference(_at).inMilliseconds < 400;

  /// The helper measures audio at all (the PowerShell fallback does not).
  bool get supported => _seen;

  void set(List<double> v) {
    values = v;
    _at = DateTime.now();
    _seen = true;
  }
}

class IslandShortcut {
  IslandShortcut({
    required this.label,
    required this.kind,
    this.target = '',
    required this.color,
    required this.icon,
    this.image = '',
  });
  String label;
  ShortcutKind kind;
  String target;
  Color color;
  String icon;

  /// The app's own icon (a PNG picked from the Start menu); when set it is
  /// shown instead of [icon] on [color].
  String image;

  Map<String, dynamic> toJson() => {
        'label': label,
        'kind': kind.name,
        'target': target,
        'color': color.toARGB32(),
        'icon': icon,
        if (image.isNotEmpty) 'image': image,
      };

  static IslandShortcut fromJson(Map<String, dynamic> j) => IslandShortcut(
        label: (j['label'] as String?) ?? 'Shortcut',
        kind: ShortcutKind.values
            .firstWhere((k) => k.name == j['kind'], orElse: () => ShortcutKind.web),
        target: (j['target'] as String?) ?? '',
        color: Color((j['color'] as int?) ?? 0xFF3B8BFF),
        icon: (j['icon'] as String?) ?? 'bolt',
        image: (j['image'] as String?) ?? '',
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
  /// [inApp]: the copy inside the app window. It edits the island's settings
  /// and shares Google and notes with the planner, but the island process
  /// owns the background work (meeting detection, recording, backups).
  IslandController({this.inApp = false})
      : google = GoogleService(backups: !inApp, inbox: inApp),
        notes = NotesService(remote: inApp);
  final bool inApp;

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

  /// Pop the music pill up when the song changes while already playing.
  /// Resuming after a pause always pops it up.
  bool popOnTrackChange = false;

  /// Minutes away before the Hello screen comes up; 0 is off.
  int helloAfter = 5;
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
  final GoogleService google;
  final NotesService notes;
  MeetingInfo? offer;
  Timer? _gTimer;

  final ValueNotifier<Offset> gaze = ValueNotifier(Offset.zero);
  final AudioBands bands = AudioBands();

  /// Live geometry, published by the real island window.
  Size pillSize = const Size(260, 57);
  double pillDy = 0;

  void Function(String)? sendMusic;
  void Function(String)? openUrl;

  /// Opens the screen annotation overlay (set by the island process).
  void Function()? startAnnotate;

  Size get idleSize => Size(idleWidth, (idleWidth * 0.22).roundToDouble());
  /// What the success animation shows: how Windows was last unlocked.
  UnlockMethod unlockMethod = UnlockMethod.face;

  bool get visible => state != IslandState.hidden;
  bool get quiet => chromeMode && quietInChrome;
  bool get musicPlaying => (nowPlaying?.playing ?? false) || _demoMusic;
  IslandState get _resting =>
      quiet ? IslandState.notch : (musicPlaying ? IslandState.music : IslandState.idle);

  // ---------------------------------------------------------- persistence

  File get _file => appDataFile('island.json');

  String? _lastJson; // island.json as this process last read or wrote it

  Future<void> load() async {
    await google.load();
    await loadSettings();
    if (inApp) {
      await notes.loadNotes();
      return;
    }
    notes.onOffer = offerMeeting;
    notes.startWatching();
    _gTimer ??= Timer.periodic(const Duration(minutes: 2), (_) => google.autoBackupTick());
  }

  /// The other process changed a setting.
  Future<void> reloadSettings() async {
    if (_saveTimer?.isActive == true) return;
    final before = _lastJson;
    await loadSettings();
    if (_lastJson != before) notifyListeners();
  }

  Future<void> loadSettings() async {
    try {
      final f = _file;
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      if (raw == _lastJson) return;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return;
      _lastJson = raw;
      idleWidth = ((j['idleWidth'] as num?) ?? 260).toDouble().clamp(180.0, 360.0).toDouble();
      pipColor = Color((j['pipColor'] as int?) ?? pipColor.toARGB32());
      openOnHover = (j['openOnHover'] as bool?) ?? false;
      quietInChrome = (j['quietInChrome'] as bool?) ?? true;
      popOnTrackChange = (j['popOnTrackChange'] as bool?) ?? false;
      helloAfter = (j['helloAfter'] as num?)?.toInt() ?? 5;
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
        final raw = jsonEncode({
          'idleWidth': idleWidth,
          'pipColor': pipColor.toARGB32(),
          'openOnHover': openOnHover,
          'quietInChrome': quietInChrome,
          'popOnTrackChange': popOnTrackChange,
          'helloAfter': helloAfter,
          'musicHelper': musicHelper,
          'stockSymbol': stockSymbol,
          'stockRange': stockRange,
          'stockCandles': stockCandles,
          'watchlist': watchlist,
          'calendars': [for (final f in calendarFeeds) f.toJson()],
          'shortcuts': [for (final s in shortcuts) s.toJson()],
        });
        _lastJson = raw;
        await f.writeAsString(raw);
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

  void setPopOnTrackChange(bool v) {
    popOnTrackChange = v;
    notifyListeners();
    _persist();
  }

  void setHelloAfter(int minutes) {
    helloAfter = minutes;
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

  void addAppShortcut(InstalledApp app) {
    shortcuts.add(IslandShortcut(
      label: app.name,
      kind: ShortcutKind.app,
      target: app.target,
      color: const Color(0xFF3B8BFF),
      icon: 'bolt',
      image: app.icon,
    ));
    shortcutsChanged();
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

  // When playback last stopped, and on which song: a skip can report a
  // split-second pause, which must not count as resuming.
  DateTime? _stoppedAt;
  String? _stoppedKey;

  void setNowPlaying(NowPlaying? n) {
    final oldKey = nowPlaying?.key;
    final wasPlaying = nowPlaying?.playing ?? false;
    nowPlaying = n;
    final isPlaying = n?.playing ?? false;
    if (wasPlaying && !isPlaying) {
      _stoppedAt = DateTime.now();
      _stoppedKey = oldKey;
    }
    final busy = state == IslandState.call ||
        state == IslandState.success ||
        state == IslandState.verify ||
        state == IslandState.open;
    // Resuming always shows the pill; a new song (a skip, or the next track
    // starting) only when that's switched on in settings.
    var pop = false;
    if (isPlaying && !wasPlaying) {
      final blip = _stoppedAt != null &&
          n!.key != _stoppedKey &&
          DateTime.now().difference(_stoppedAt!) < const Duration(seconds: 3);
      pop = !blip || popOnTrackChange;
    } else if (isPlaying && n!.key != oldKey) {
      pop = popOnTrackChange;
    }
    if (pop && !busy && !quiet) {
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
    if (state == IslandState.call || state == IslandState.success || state == IslandState.verify) return;
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
      case IslandState.meeting:
        offerMeeting(MeetingInfo.demo());
      case IslandState.verify:
        verifying(unlockMethod);
      case IslandState.success:
        _set(IslandState.success);
        _later(kUnlockAnimation + const Duration(milliseconds: 300), _afterSuccess);
    }
  }

  void accept() {
    if (state == IslandState.call) {
      unlockMethod = UnlockMethod.face;
      preview(IslandState.success);
    }
  }

  /// Windows locked: put the island away. (The lock screen is a secure
  /// desktop no app can draw on, so it is out of reach until you are back.)
  void locked() {
    _timer?.cancel();
    _set(IslandState.hidden);
  }

  /// Back from the lock screen, or past the Hello screen: show how you
  /// got in. After [verifying], the scan carries on into the check.
  void unlocked(UnlockMethod m) {
    unlockMethod = m;
    preview(IslandState.success);
  }

  /// The Hello screen asked Windows Hello to check you. [likely] is the
  /// glyph to scan with (how you usually sign in) until it answers.
  void verifying(UnlockMethod likely) {
    _timer?.cancel();
    unlockMethod = likely;
    _set(IslandState.verify);
  }

  /// Windows Hello said no (or you cancelled): put the scan away.
  void verifyFailed() {
    if (state != IslandState.verify) return;
    _set(near ? _resting : IslandState.hidden);
  }

  void decline() {
    if (state != IslandState.call) return;
    _timer?.cancel();
    _set(IslandState.idle);
    if (!near) _hideSoon(1);
  }

  /// A meeting window appeared: ask from the island whether to take notes.
  void offerMeeting(MeetingInfo m) {
    if (state == IslandState.call || state == IslandState.success) return;
    offer = m;
    _set(IslandState.meeting);
    notifyListeners();
    _later(const Duration(seconds: 25), declineMeeting);
  }

  void acceptMeeting() {
    final m = offer;
    if (state != IslandState.meeting || m == null) return;
    _timer?.cancel();
    offer = null;
    _set(near ? _resting : IslandState.hidden);
    notes.start(m);
  }

  void declineMeeting() {
    if (state != IslandState.meeting) return;
    _timer?.cancel();
    offer = null;
    _set(near ? _resting : IslandState.hidden);
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
    _gTimer?.cancel();
    google.dispose();
    notes.dispose();
    super.dispose();
  }
}
