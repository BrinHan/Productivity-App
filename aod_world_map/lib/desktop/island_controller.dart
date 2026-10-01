import 'dart:async';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';

enum IslandState { hidden, idle, call, music, success }

/// What Windows reports as the current media session.
class NowPlaying {
  const NowPlaying(this.title, this.artist, this.playing);
  final String title, artist;
  final bool playing;
  String get key => '$title|$artist';
}

/// State + settings for the dynamic island. Shared by the real island window
/// and the inline preview in settings.
class IslandController extends ChangeNotifier {
  IslandState state = IslandState.hidden;
  NowPlaying? nowPlaying;
  bool _demoMusic = false; // the Music preview chip when nothing is playing
  bool near = false; // cursor is close to the island
  Timer? _timer;

  // ---- user settings ----
  double idleWidth = 260;
  Color mochiColor = const Color(0xFFF4EFE6); // soft white

  /// Where the little guy is looking: -1..1 on each axis.
  final ValueNotifier<Offset> gaze = ValueNotifier(Offset.zero);

  Size get idleSize => Size(idleWidth, (idleWidth * 0.22).roundToDouble());
  bool get visible => state != IslandState.hidden;
  bool get musicPlaying => (nowPlaying?.playing ?? false) || _demoMusic;
  IslandState get _resting => musicPlaying ? IslandState.music : IslandState.idle;

  void setIdleWidth(double w) {
    idleWidth = w.clamp(180.0, 360.0).toDouble();
    notifyListeners();
  }

  void setMochiColor(Color c) {
    mochiColor = c;
    notifyListeners();
  }

  /// Called with live data from Windows. A new track pops the island out.
  void setNowPlaying(NowPlaying? n) {
    final oldKey = nowPlaying?.key;
    final wasPlaying = nowPlaying?.playing ?? false;
    nowPlaying = n;
    final isPlaying = n?.playing ?? false;
    final busy = state == IslandState.call || state == IslandState.success;
    if (isPlaying && (!wasPlaying || n!.key != oldKey) && !busy) {
      preview(IslandState.music);
    } else if (!isPlaying && wasPlaying && !_demoMusic && state == IslandState.music) {
      _timer?.cancel();
      _set(near ? IslandState.idle : IslandState.hidden);
    } else {
      notifyListeners();
    }
  }

  /// Called by the cursor poller. Pops out when near, retreats when away.
  void setNear(bool v) {
    if (v == near) return;
    near = v;
    if (v) {
      _timer?.cancel();
      if (state == IslandState.hidden) _set(_resting);
    } else if (state == IslandState.idle || state == IslandState.music) {
      _later(const Duration(milliseconds: 700), () => _set(IslandState.hidden));
    }
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
    near = false;
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
    gaze.dispose();
    super.dispose();
  }
}
