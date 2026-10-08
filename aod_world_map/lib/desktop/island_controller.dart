import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;

import 'action_items.dart';
import 'agenda_service.dart';
import 'app_catalog.dart' show InstalledApp;
import 'app_files.dart';
import 'google_service.dart';
import 'island_services.dart';
import 'log.dart';
import 'meeting_detector.dart';
import 'notes_model.dart';
import 'notes_service.dart';
import 'planner_model.dart';
import 'unlock_glyphs.dart' show kUnlockAnimation;
import 'unlock_watch.dart';
import 'updates.dart';

/// [verify]: Windows Hello is checking you on the Hello screen; the island
/// scans until it answers, then shows [success]. [focus]: a focus session
/// from the planner, shown until it is reset or completed. [actions]: a
/// finished meeting's suggested to-dos. [upcoming]: a call with a join link
/// starts in a few minutes. [timer]: a countdown timer is running, shown
/// like the iPhone's timer live activity.
enum IslandState { hidden, notch, idle, open, call, music, verify, success, meeting, focus, actions, upcoming, timer }

/// [capture] is the one-line box the quick-capture hotkey opens; it has no tab.
enum IslandPage { home, music, stocks, today, clock, weather, clipboard, settings, capture }

enum ShortcutKind { web, app, screensaver, planner }

/// What the island pops up for, five minutes ahead.
enum Reminders { off, calls, all }

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
  Timer? _timer, _overTimer, _saveTimer, _dwellTimer;

  /// How long the cursor has to rest at the top middle before the hidden
  /// island (or Chrome notch) shows, so passing by doesn't pop it up.
  static const kRevealDwell = Duration(milliseconds: 900);

  // ---- user settings (saved) ----
  double idleWidth = 260;
  Color pipColor = const Color(0xFFF4EFE6);
  bool openOnHover = false;
  bool quietInChrome = true;

  /// Pop the music pill up when the song changes while already playing.
  /// Resuming after a pause always pops it up.
  bool popOnTrackChange = false;

  /// What pops up five minutes ahead: calls with a join link, or every
  /// timed event and planner task.
  Reminders reminders = Reminders.all;

  /// Minutes away before the Hello screen comes up; 0 is off.
  int helloAfter = 5;
  bool musicHelper = true; // the PowerShell media-session reader
  String stockSymbol = 'AAPL';
  String stockRange = '1d'; // 1d | 5d | 1mo
  bool stockCandles = true; // false = bars
  List<IslandShortcut> shortcuts = defaultShortcuts();
  List<String> watchlist = ['AAPL', 'NVDA', 'TSLA', 'SNOW'];
  List<CalendarFeed> calendarFeeds = [];

  /// Weather in °F rather than °C.
  bool fahrenheit = Platform.localeName.endsWith('US');

  // ---- island tabs (they run in the island process) ----
  final TimerModel timers = TimerModel();
  final WeatherService weather = WeatherService();
  final ClipboardHistory clipboard = ClipboardHistory();

  /// The call starting soon, while [IslandState.upcoming] shows it.
  AgendaEvent? soon;
  final Set<String> _soonShown = {};
  Timer? _soonTimer, _weatherTimer;

  /// When the timer last went off, for the Clock page to say so.
  DateTime? rangAt;

  /// How Pip dresses right now, for the weather and the hour.
  PipLook get pipLook => lookFor(weather.now, DateTime.now());

  /// Hands the keyboard back to the app that had it before the quick-capture
  /// hotkey (set by the island process).
  void Function()? giveBackFocus;

  /// Set by main(): the same planner the Home page edits. The island
  /// follows its focus session.
  PlannerModel? get planner => _planner;
  PlannerModel? _planner;
  set planner(PlannerModel? p) {
    if (!inApp) {
      _planner?.removeListener(_onPlanner);
      p?.addListener(_onPlanner);
    }
    _planner = p;
    if (!inApp) _onPlanner();
  }
  final AgendaService agenda = AgendaService();
  final GoogleService google;
  final NotesService notes;
  MeetingInfo? offer;

  /// A finished meeting and the to-dos found in it, while [IslandState.actions] asks.
  ({MeetingNote note, List<String> items})? actionOffer;

  /// Opens the planner on its Notes page (set by the island process).
  void Function()? openNotes;
  Timer? _gTimer, _updateTimer;

  /// A newer Meridian on GitHub, once the daily check has found one. The
  /// settings tab wears a dot and the settings page says so.
  Release? update;

  Future<void> checkForUpdate({bool force = false}) async {
    final r = await UpdateCheck.newer(force: force);
    if (r?.version == update?.version) return;
    update = r;
    notifyListeners();
  }

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
  bool get focusActive => planner?.focusActive ?? false;
  bool get timerActive => timers.running;

  /// A live activity (focus session or timer) that stays on screen.
  IslandState? get _live => focusActive ? IslandState.focus : (timerActive ? IslandState.timer : null);

  IslandState get _resting => quiet ? IslandState.notch : (_live ?? (musicPlaying ? IslandState.music : IslandState.idle));

  /// Where the island goes when the cursor is away: hidden, unless a focus
  /// session or timer is on, which stays on screen like a live activity.
  IslandState get _away => quiet ? IslandState.hidden : (_live ?? IslandState.hidden);

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
    notes.onFinished = offerActions;
    notes.startWatching();
    timers.onDone = _timerDone;
    timers.addListener(_onTimers);
    weather.refresh();
    _weatherTimer ??= Timer.periodic(const Duration(minutes: 15), (_) => weather.refresh());
    clipboard.start();
    _soonTimer ??= Timer.periodic(const Duration(seconds: 20), (_) => _checkSoon());
    _gTimer ??= Timer.periodic(const Duration(minutes: 2), (_) => google.autoBackupTick());
    // A minute after starting, so it never slows down signing in.
    _updateTimer ??= Timer(const Duration(minutes: 1), () {
      checkForUpdate();
      _updateTimer = Timer.periodic(const Duration(hours: 6), (_) => checkForUpdate());
    });
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
      final raw = await readWithBackup(_file, (raw) => jsonDecode(raw) is Map<String, dynamic>);
      if (raw == null || raw == _lastJson) return;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return;
      _lastJson = raw;
      idleWidth = ((j['idleWidth'] as num?) ?? 260).toDouble().clamp(180.0, 360.0).toDouble();
      pipColor = Color((j['pipColor'] as int?) ?? pipColor.toARGB32());
      openOnHover = (j['openOnHover'] as bool?) ?? false;
      quietInChrome = (j['quietInChrome'] as bool?) ?? true;
      popOnTrackChange = (j['popOnTrackChange'] as bool?) ?? false;
      reminders = Reminders.values.where((r) => r.name == j['reminders']).firstOrNull ?? Reminders.all;
      helloAfter = (j['helloAfter'] as num?)?.toInt() ?? 5;
      musicHelper = (j['musicHelper'] as bool?) ?? true;
      stockSymbol = (j['stockSymbol'] as String?) ?? 'AAPL';
      stockRange = (j['stockRange'] as String?) ?? '1d';
      stockCandles = (j['stockCandles'] as bool?) ?? true;
      final w = j['watchlist'];
      if (w is List) watchlist = [for (final e in w) if (e is String && e.isNotEmpty) e];
      fahrenheit = (j['fahrenheit'] as bool?) ?? fahrenheit;
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
    } catch (e, st) {
      logError(e, st);
    }
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
          'reminders': reminders.name,
          'helloAfter': helloAfter,
          'musicHelper': musicHelper,
          'stockSymbol': stockSymbol,
          'stockRange': stockRange,
          'stockCandles': stockCandles,
          'watchlist': watchlist,
          'fahrenheit': fahrenheit,
          'calendars': [for (final f in calendarFeeds) f.toJson()],
          'shortcuts': [for (final s in shortcuts) s.toJson()],
        });
        _lastJson = raw;
        await writeFileSafely(f, raw, backup: true);
      } catch (e, st) {
        logError(e, st);
      }
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

  void setReminders(Reminders v) {
    reminders = v;
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

  void setFahrenheit(bool v) {
    fahrenheit = v;
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
      if (state == IslandState.idle ||
          state == IslandState.music ||
          state == IslandState.focus ||
          state == IslandState.timer) {
        _set(IslandState.notch);
      }
    } else if (state == IslandState.notch) {
      _set(near ? _resting : _away);
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
        state == IslandState.open ||
        state == IslandState.actions;
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
      _set(near ? _resting : _away);
    } else {
      notifyListeners();
    }
  }

  void setNear(bool v) {
    if (v == near) return;
    near = v;
    _dwellTimer?.cancel();
    if (v) {
      _timer?.cancel();
      if (state == IslandState.hidden) {
        _dwellTimer = Timer(kRevealDwell, () {
          if (near && state == IslandState.hidden) _set(_resting);
        });
      }
    } else if (state == IslandState.idle ||
        state == IslandState.music ||
        state == IslandState.notch) {
      _later(const Duration(milliseconds: 700), () => _set(_away));
    } else if (state == IslandState.open && openOnHover) {
      _later(const Duration(milliseconds: 500), close);
    }
  }

  void setOverPill(bool v) {
    if (v == _over) return;
    _over = v;
    _overTimer?.cancel();
    bool resting() =>
        state == IslandState.idle ||
        state == IslandState.music ||
        state == IslandState.focus ||
        state == IslandState.timer;
    if (v && openOnHover && !quiet && resting()) {
      _overTimer = Timer(const Duration(milliseconds: 350), () {
        if (_over && resting()) open(restingPage);
      });
    }
  }

  /// The page a tap on the resting pill opens.
  IslandPage get restingPage => switch (state) {
        IslandState.music => IslandPage.music,
        IslandState.focus => IslandPage.today,
        IslandState.timer => IslandPage.clock,
        _ => IslandPage.home,
      };

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
    _set(near ? _resting : _away);
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
      case IslandState.focus:
        _set(IslandState.focus);
        if (!focusActive) _hideSoon(4);
      case IslandState.actions:
        offerActions(
          MeetingNote(
            id: 'demo',
            title: 'Zoom meeting',
            app: 'Zoom',
            startedAt: DateTime.now(),
            segments: [NoteSegment(0, "I'll send the deck to Sarah by Friday. We need to update the pricing page.")],
          ),
          demo: true,
        );
      case IslandState.upcoming:
        final now = DateTime.now();
        soon = AgendaEvent('Team standup', now.add(const Duration(minutes: 4)),
            now.add(const Duration(minutes: 34)), false, '', 0,
            link: 'https://meet.google.com/abc-defg-hij');
        _set(IslandState.upcoming);
        _later(const Duration(seconds: 20), dismissSoon);
      case IslandState.timer:
        timers.setPick(const Duration(minutes: 1));
        timers.start();
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
    _set(near ? _resting : _away);
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
    _set(near ? _resting : _away);
    notes.start(m);
  }

  void declineMeeting() {
    if (state != IslandState.meeting) return;
    _timer?.cancel();
    offer = null;
    _set(near ? _resting : _away);
  }

  /// A recording ended: offer to put the to-dos it found on today's list.
  void offerActions(MeetingNote n, {bool demo = false}) {
    final items = [for (final x in extractActionItems(n)) if (!n.taken.contains(x)) x];
    const busy = {IslandState.open, IslandState.call, IslandState.success, IslandState.verify, IslandState.meeting};
    if (items.isEmpty || busy.contains(state)) return;
    actionOffer = (note: n, items: items);
    _demoActions = demo;
    _set(IslandState.actions);
    notifyListeners();
    _later(const Duration(seconds: 30), dismissActions);
  }

  bool _demoActions = false;

  void acceptActions() {
    final o = actionOffer;
    if (state != IslandState.actions || o == null) return;
    if (!_demoActions) {
      final today = DateTime.now();
      for (final x in o.items) {
        planner?.add(today, x);
      }
      notes.markTaken(o.note, o.items);
    }
    dismissActions();
  }

  /// Opens the note in the planner to pick which ones to keep.
  void reviewActions() {
    if (state != IslandState.actions) return;
    dismissActions();
    openNotes?.call();
  }

  void dismissActions() {
    if (state != IslandState.actions) return;
    _timer?.cancel();
    actionOffer = null;
    _set(near ? _resting : _away);
  }

  // ---------------------------------------------------------- quick capture

  /// The quick-capture hotkey: open the one-line box.
  void capture() {
    if (state == IslandState.call || state == IslandState.success || state == IslandState.verify) return;
    open(IslandPage.capture);
  }

  /// Done capturing (added, or Esc): put the island and the keyboard back.
  void endCapture() {
    if (state == IslandState.open && page == IslandPage.capture) {
      page = IslandPage.home;
      close();
    }
    giveBackFocus?.call();
  }

  // ------------------------------------------------------- upcoming meeting

  /// How long before a call the island counts down to it.
  static const kSoonLead = Duration(minutes: 5);

  /// [AgendaEvent.feed] for a reminder made from a planner task with a time.
  static const kTaskFeed = -1;

  /// The task behind the reminder showing, if it is one.
  Task? soonTask;

  /// What the island pops up for ahead of time, from [reminders]: timed
  /// planner tasks and every timed event, or only calls with a join link.
  List<AgendaEvent> _remindable() {
    if (reminders == Reminders.off) return const [];
    final calls = reminders == Reminders.calls;
    return [
      for (final e in [...google.events, ...agenda.events])
        if (!e.allDay && (!calls || e.link.isNotEmpty)) e,
      if (!calls)
        for (final t in planner?.tasks ?? const <Task>[])
          if (!t.done && t.at != null)
            AgendaEvent(t.title, t.at!, t.at!.add(Duration(minutes: t.minutes)), false, '', kTaskFeed),
    ];
  }

  void _checkSoon() {
    final now = DateTime.now();
    if (soon != null && now.isAfter(soon!.start.add(const Duration(minutes: 5)))) dismissSoon();
    AgendaEvent? next;
    for (final e in _remindable()) {
      final until = e.start.difference(now);
      if (until > kSoonLead || until < const Duration(minutes: -2)) continue;
      if (_soonShown.contains(_soonKey(e))) continue;
      if (next == null || e.start.isBefore(next.start)) next = e;
    }
    if (next == null) return;
    const busy = {IslandState.open, IslandState.call, IslandState.success, IslandState.verify, IslandState.meeting};
    if (busy.contains(state)) return; // try again on the next check
    _soonShown.add(_soonKey(next));
    soon = next;
    soonTask = next.feed == kTaskFeed
        ? planner?.tasks.where((t) => t.at == next!.start && t.title == next.title).firstOrNull
        : null;
    _timer?.cancel();
    _set(IslandState.upcoming);
  }

  String _soonKey(AgendaEvent e) => '${e.title}|${e.start.millisecondsSinceEpoch}';

  void joinSoon() {
    final e = soon;
    if (e == null) return;
    openUrl?.call(e.link);
    dismissSoon();
  }

  /// Starts a focus session on the task the reminder is for.
  void focusSoon() {
    final t = soonTask, p = planner;
    if (t != null && p != null) {
      p.pickFocusTask(t);
      p.startFocus();
    }
    dismissSoon();
  }

  void dismissSoon() {
    soon = null;
    soonTask = null;
    if (state == IslandState.upcoming) _set(near ? _resting : _away);
  }

  // ----------------------------------------------------------------- timers

  bool _timerWas = false;

  /// The timer started or stopped: bring its pill up or put it away, the
  /// same way a focus session does.
  void _onTimers() {
    final on = timerActive;
    if (on == _timerWas) return;
    _timerWas = on;
    const busy = {
      IslandState.open,
      IslandState.call,
      IslandState.success,
      IslandState.verify,
      IslandState.meeting,
      IslandState.actions,
      IslandState.upcoming,
      IslandState.focus,
    };
    if (busy.contains(state) || quiet) {
      notifyListeners();
    } else if (on) {
      _timer?.cancel();
      _set(IslandState.timer);
    } else if (state == IslandState.timer) {
      _set(near ? _resting : _away);
    }
  }

  void _timerDone() {
    rangAt = DateTime.now();
    SystemSound.play(SystemSoundType.alert);
    if (state == IslandState.call || state == IslandState.verify || state == IslandState.success) return;
    open(IslandPage.clock);
  }

  // Whether the planner's focus session was on, and had run out, last time.
  bool _focusWas = false, _finishedWas = false;

  /// The planner changed (it ticks every second while focusing): follow its
  /// focus session in and out of the pill.
  void _onPlanner() {
    final active = focusActive, finished = planner?.focusFinished ?? false;
    if (active == _focusWas && finished == _finishedWas) return;
    _focusWas = active;
    _finishedWas = finished;
    const busy = {
      IslandState.open,
      IslandState.call,
      IslandState.success,
      IslandState.verify,
      IslandState.meeting,
      IslandState.actions,
      IslandState.upcoming,
    };
    if (busy.contains(state) || quiet) {
      notifyListeners();
    } else if (active) {
      _timer?.cancel(); // e.g. a music preview counting down to hide
      _set(IslandState.focus);
    } else if (state == IslandState.focus) {
      _set(near ? _resting : _away);
    }
  }

  void reset() {
    _timer?.cancel();
    _overTimer?.cancel();
    _dwellTimer?.cancel();
    near = false;
    _over = false;
    _demoMusic = false;
    chromeMode = false;
    state = IslandState.hidden;
    notifyListeners();
  }

  void _afterSuccess() => _set(near ? _resting : _away);

  void _hideSoon(int seconds) => _later(Duration(seconds: seconds), () {
        if (!near) _set(_away);
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
    _planner?.removeListener(_onPlanner);
    _timer?.cancel();
    _overTimer?.cancel();
    _saveTimer?.cancel();
    _dwellTimer?.cancel();
    gaze.dispose();
    agenda.dispose();
    _gTimer?.cancel();
    _updateTimer?.cancel();
    _soonTimer?.cancel();
    _weatherTimer?.cancel();
    timers.removeListener(_onTimers);
    timers.dispose();
    weather.dispose();
    clipboard.dispose();
    google.dispose();
    notes.dispose();
    super.dispose();
  }
}
