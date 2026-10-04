import 'window_scan.dart';

enum MeetingApp { zoom, meet, teams }

class MeetingInfo {
  const MeetingInfo(this.app, this.key, this.pid, this.title);
  factory MeetingInfo.demo() => const MeetingInfo(MeetingApp.zoom, 'demo', 0, 'Zoom Meeting');

  final MeetingApp app;
  final String key; // same meeting = same key
  final int pid; // process whose audio tree gets captured
  final String title;

  String get appName {
    switch (app) {
      case MeetingApp.zoom:
        return 'Zoom';
      case MeetingApp.meet:
        return 'Google Meet';
      case MeetingApp.teams:
        return 'Microsoft Teams';
    }
  }

  /// A browser shows only its active tab's title, so a Meet call can look
  /// gone while it still runs. Never auto-stop those.
  bool get autoStop => app != MeetingApp.meet;
}

class MeetingDetector {
  static const _browsers = {
    'chrome.exe', 'msedge.exe', 'brave.exe', 'firefox.exe', 'opera.exe', 'vivaldi.exe',
  };
  static final _meet = RegExp(r'Meet\s*[-\u2013]\s*([a-z]{3}-[a-z]{4}-[a-z]{3})');

  static bool _teams(String title) {
    final l = title.toLowerCase();
    return l.contains('| microsoft teams') && (l.contains('meeting') || l.contains('call'));
  }

  static MeetingInfo? detect(List<WinInfo> wins) {
    MeetingInfo? zoom, teams, meet;
    for (final w in wins) {
      final t = w.title;
      if (w.exe == 'zoom.exe' && (t.startsWith('Zoom Meeting') || t.contains('Zoom Webinar'))) {
        zoom ??= MeetingInfo(MeetingApp.zoom, 'zoom', w.pid, t);
      } else if ((w.exe == 'ms-teams.exe' || w.exe == 'teams.exe') && _teams(t)) {
        teams ??= MeetingInfo(MeetingApp.teams, 'teams', w.pid, t);
      } else if (_browsers.contains(w.exe)) {
        final m = _meet.firstMatch(t);
        if (m != null || t.contains('meet.google.com')) {
          meet ??= MeetingInfo(MeetingApp.meet, 'meet:${m?.group(1) ?? ''}', w.pid, t);
        }
      }
    }
    return zoom ?? teams ?? meet;
  }
}
