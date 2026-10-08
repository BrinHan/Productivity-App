// Renders the README screenshots and GIF frames offscreen, with demo data.
//
//   APPDATA=<empty scratch dir> MEDIA_OUT=<frames dir> ALBUM_ART=<png>
//     flutter test tool/readme/capture_test.dart
//
// then run tool/readme/make_media.py to turn the frames into docs/media.
// APPDATA must point at an empty scratch folder: the planner and island save
// there, and the demo data is written there.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:meridian/aod/aod_face.dart';
import 'package:meridian/aod/dot_grid.dart';
import 'package:meridian/aod/solar_math.dart';
import 'package:meridian/desktop/agenda_service.dart';
import 'package:meridian/desktop/app_catalog.dart';
import 'package:meridian/desktop/dynamic_island.dart';
import 'package:meridian/desktop/home_page.dart';
import 'package:meridian/desktop/island_controller.dart';
import 'package:meridian/desktop/planner_model.dart';
import 'package:meridian/desktop/unlock_watch.dart';
import 'package:meridian/desktop/window_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _out = _env['MEDIA_OUT']!;

// ------------------------------------------------------------------ fonts

Future<void> _font(String family, List<String> paths) async {
  final l = FontLoader(family);
  for (final p in paths) {
    l.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await l.load();
}

Future<void> _fonts() async {
  const win = r'C:\Windows\Fonts';
  // Every weight Windows ships, so w800 text doesn't fall back to boxes.
  const segoe = ['segoeui', 'segoeuib', 'seguisb', 'segoeuil', 'segoeuisl', 'seguibl', 'seguisym'];
  await _font('Segoe UI', [for (final f in segoe) '$win\\$f.ttf']);
  await _font('Segoe UI Variable Display', ['$win\\SegUIVar.ttf']);
  await _font('Inter', ['assets/fonts/Inter.ttf']);
  await _font('MaterialIcons', ['build/windows/x64/runner/Debug/data/flutter_assets/fonts/MaterialIcons-Regular.otf']);
}

// -------------------------------------------------------------- demo data

DateTime get _today {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Planner tasks for this week, written where PlannerModel.load reads them.
void _writePlanner() {
  final d = _today;
  var n = 0;
  Map<String, dynamic> task(int day, String title, int minutes, String tag,
          {bool done = false, List<List<Object>> subs = const []}) =>
      {
        'id': 'demo-${n++}',
        'title': title,
        'tag': tag,
        'day': d.add(Duration(days: day)).toIso8601String(),
        'minutes': minutes,
        'done': done,
        'subs': [for (final s in subs) {'t': s[0], 'd': s[1]}],
      };
  final tasks = [
    task(0, 'Morning review', 15, 'work', done: true),
    task(0, 'Ship the island app picker', 90, 'work', subs: [
      ['List Start menu apps', true],
      ['Search and Enter to add', true],
      ['Real app icons', false],
    ]),
    task(0, 'Write the README', 60, 'work'),
    task(0, 'Gym: upper body', 45, 'health'),
    task(0, 'Call Mom', 20, 'personal'),
    task(1, 'Design review prep', 45, 'work'),
    task(1, 'Grocery run', 30, 'personal'),
    task(2, 'Quarterly planning doc', 120, 'work'),
    task(2, 'Run 5k', 40, 'health'),
    task(3, 'Dentist', 60, 'personal'),
    task(4, 'Release Meridian 1.2', 60, 'work'),
    task(-1, 'Inbox zero', 30, 'work', done: true),
  ];
  final f = File('${_env['APPDATA']}\\AodWorldMap\\planner.json');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(jsonEncode({'tasks': tasks}));
}

String _ics() {
  String at(int day, int h, int m) {
    final t = _today.add(Duration(days: day, hours: h, minutes: m));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}00';
  }

  final events = [
    [0, 9, 30, 10, 0, 'Standup'],
    [0, 11, 0, 12, 0, 'Design review'],
    [0, 13, 0, 13, 45, 'Lunch with Sam'],
    [0, 15, 30, 16, 30, 'Focus: island polish'],
    [1, 10, 0, 11, 0, '1:1 with manager'],
    [1, 14, 0, 15, 0, 'Product sync'],
    [2, 9, 30, 10, 0, 'Standup'],
    [3, 16, 0, 17, 0, 'Team demo'],
    [5, 11, 0, 13, 0, 'Brunch'],
  ];
  final b = StringBuffer('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Meridian//Demo//EN\r\n');
  var i = 0;
  for (final e in events) {
    final day = e[0] as int;
    b.write('BEGIN:VEVENT\r\nUID:demo-${i++}@meridian\r\n'
        'DTSTART:${at(day, e[1] as int, e[2] as int)}\r\n'
        'DTEND:${at(day, e[3] as int, e[4] as int)}\r\n'
        'SUMMARY:${e[5]}\r\nEND:VEVENT\r\n');
  }
  b.write('END:VCALENDAR\r\n');
  return b.toString();
}

/// Serves the demo calendar on localhost; returns its URL.
Future<String> _serveCalendar() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final body = utf8.encode(_ics());
  server.listen((r) {
    r.response.headers.contentType = ContentType('text', 'calendar', charset: 'utf-8');
    r.response.add(body);
    r.response.close();
  });
  return 'http://127.0.0.1:${server.port}/demo.ics';
}

const _pickerApps = [
  'Google Chrome', 'Spotify', 'Visual Studio Code', 'Discord', 'Calculator', 'Terminal', 'Notepad',
  'File Explorer', 'Settings', 'Paint', 'Outlook', 'Microsoft Edge', 'Snipping Tool', 'Photos',
];

// -------------------------------------------------------------- capturing

/// Lets real file and network work finish between fake-clock frames,
/// while animations run on: [ms] of 16 ms frames. (The island's springs
/// take one capped step per frame, so a single long pump barely moves them.)
Future<void> settle(WidgetTester t, {int ms = 1500}) async {
  for (var i = 0; i < ms ~/ 16; i++) {
    if (i % 4 == 0) await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 16));
  }
}

class Cam {
  Cam(this.t, this.key);
  final WidgetTester t;
  final GlobalKey key;
  final Map<String, int> _next = {};

  Future<void> shot(String name, {double ratio = 2}) async {
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final im = await b.toImage(pixelRatio: ratio);
      final png = await im.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$_out/$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  /// Appends [frames] frames, [ms] apart, to `$_out/<clip>/0000.png` ...
  Future<void> clip(String clip, int frames, {int ms = 40, double ratio = 1, Future<void> Function(int)? each}) async {
    for (var i = 0; i < frames; i++) {
      await each?.call(i);
      // Springs step once per frame: advance in 16 ms frames, capture once.
      for (var left = ms; left > 0; left -= 16) {
        await t.pump(Duration(milliseconds: left < 16 ? left : 16));
      }
      if (i % 5 == 0) await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      final n = _next[clip] ?? 0;
      _next[clip] = n + 1;
      await shot('$clip/${n.toString().padLeft(4, '0')}', ratio: ratio);
    }
  }
}

/// A stage of the given size; [child] is drawn inside a RepaintBoundary.
Future<Cam> stage(WidgetTester t, Size size, Widget child, {bool dark = true}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  final key = GlobalKey();
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
    darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: RepaintBoundary(key: key, child: child),
  ));
  return Cam(t, key);
}

/// A soft desktop-like backdrop for the island to hang over.
Widget backdrop(Widget child) => DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A4A63), Color(0xFF6B5B7B), Color(0xFFB08A7A)],
        ),
      ),
      child: child,
    );

/// An island controller with the demo planner, calendar and track.
Future<IslandController> _island(WidgetTester t, PlannerModel planner) async {
  final url = (await t.runAsync(_serveCalendar))!;
  final c = IslandController()
    ..planner = planner
    ..near = true
    ..calendarFeeds = [CalendarFeed('Work', url)];
  await t.runAsync(() => c.agenda.refresh(c.calendarFeeds, force: true));
  return c;
}

NowPlaying _track() => NowPlaying('Golden Hour', 'Demo Artist', true, _env['ALBUM_ART'], 'Sunset Sessions',
    'Spotify.exe', const Duration(seconds: 74), const Duration(minutes: 3, seconds: 29), DateTime.now());

/// A testWidgets that renders with Windows typography (Segoe UI). The
/// override is checked before tearDown runs, so it is undone in here.
void capture(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  setUpAll(() {
    expect(_env['APPDATA']!.contains('scratchpad'), isTrue, reason: 'point APPDATA at a scratch folder');
    _writePlanner();
  });
  // Real HTTP for live stock prices and the local demo calendar.
  setUp(() => HttpOverrides.global = null);

  capture('map', (t) async {
    await t.runAsync(_fonts);
    final grid = DotGrid.fromPolygons();
    const user = GeoPoint(40.71, -74.0);
    final start = DateTime.utc(2026, 10, 6, 17, 30);
    var now = start;
    late StateSetter set;
    final cam = await stage(
      t,
      const Size(1280, 720),
      StatefulBuilder(builder: (_, s) {
        set = s;
        return Scaffold(
          backgroundColor: Colors.black,
          body: AodWorldMapFace(
            grid: grid,
            utcTime: now,
            user: user,
            locationLabel: 'New York, United States',
            localUtcOffset: const Duration(hours: -4),
          ),
        );
      }),
    );
    await settle(t, ms: 500);
    await cam.shot('map');
    // A day in five seconds.
    await cam.clip('map_day', 100, ms: 50, ratio: 0.5, each: (i) async {
      set(() => now = start.add(Duration(minutes: (i * 14.4).round())));
    });
    await t.pumpWidget(const SizedBox());
  });

  capture('island', (t) async {
    await t.runAsync(_fonts);
    final planner = PlannerModel();
    await t.runAsync(planner.load);
    final c = await _island(t, planner);
    final cam = await stage(
      t,
      const Size(760, 500),
      backdrop(Material(
        type: MaterialType.transparency,
        child: Align(alignment: Alignment.topCenter, child: DynamicIsland(controller: c)),
      )),
    );
    c.preview(IslandState.idle);
    await settle(t);
    await cam.shot('island_idle');

    // Warm up: open once so the stocks load, then close.
    c.open();
    await settle(t, ms: 5000);
    await cam.shot('island_home');
    c.setPage(IslandPage.today);
    await settle(t, ms: 2000);
    await cam.shot('island_today');
    c.close();
    await settle(t);

    // Idle pill -> open home -> today -> home -> close.
    await cam.clip('island_tour', 15);
    c.open();
    await cam.clip('island_tour', 50);
    c.setPage(IslandPage.today);
    await cam.clip('island_tour', 50);
    c.setPage(IslandPage.home);
    await cam.clip('island_tour', 35);
    c.close();
    await cam.clip('island_tour', 25);

    // Music: the pill pops up when a song starts, then the Music tab.
    c.setNowPlaying(_track());
    await cam.clip('island_music', 60);
    await cam.shot('island_music_pill');
    c.open(IslandPage.music);
    await cam.clip('island_music', 60);
    await cam.shot('island_music');
    c.close();
    await cam.clip('island_music', 20);

    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  capture('unlock', (t) async {
    final c = IslandController();
    final cam = await stage(
      t,
      const Size(420, 200),
      backdrop(Material(
        type: MaterialType.transparency,
        child: Align(alignment: Alignment.topCenter, child: DynamicIsland(controller: c)),
      )),
    );
    // As on the Hello screen: scan while Windows Hello decides, then the check.
    for (final m in UnlockMethod.values) {
      c.verifying(m);
      await cam.clip('unlock_${m.name}', m == UnlockMethod.pin ? 20 : 45);
      c.unlocked(m);
      await cam.clip('unlock_${m.name}', 70);
      await settle(t, ms: 1200);
    }
    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  capture('picker', (t) async {
    await t.runAsync(_fonts);
    final all = (await t.runAsync(AppCatalog.load))!;
    // ignore: invalid_use_of_visible_for_testing_member
    AppCatalog.debugCached = [for (final a in all) if (_pickerApps.contains(a.name)) a];
    await t.runAsync(() async {
      for (final a in AppCatalog.cached) {
        if (a.icon.isNotEmpty) await precacheImage(FileImage(File(a.icon)), t.binding.rootElement!);
      }
    });
    final c = IslandController()..near = true;
    final cam = await stage(
      t,
      const Size(640, 400),
      backdrop(Material(
        type: MaterialType.transparency,
        child: Align(alignment: Alignment.topCenter, child: DynamicIsland(controller: c)),
      )),
    );
    c.open(IslandPage.settings);
    await settle(t);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle(t, ms: 600);
    await cam.clip('picker', 25);
    await t.tap(find.text('Add app'));
    await cam.clip('picker', 30);
    for (final ch in ['s', 'sp', 'spo']) {
      await t.enterText(find.byType(TextField), ch);
      await cam.clip('picker', 8);
    }
    await cam.clip('picker', 14);
    await cam.shot('picker_search');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await cam.clip('picker', 10);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await cam.clip('picker', 40);
    await cam.shot('picker_added');

    c.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  capture('planner', (t) async {
    await t.runAsync(_fonts);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    final planner = PlannerModel();
    await t.runAsync(planner.load);
    final shell = ShellController(mode: AppMode.home);
    final url = (await t.runAsync(_serveCalendar))!;
    shell.island
      ..planner = planner
      ..calendarFeeds = [CalendarFeed('Work', url)];
    await t.runAsync(() => shell.island.agenda.refresh(shell.island.calendarFeeds, force: true));

    for (final dark in [true, false]) {
      final cam = await stage(
        t,
        const Size(1400, 860),
        HomePage(shell: shell, planner: planner, isDark: dark, onDarkChanged: (_) {}),
        dark: dark,
      );
      await settle(t, ms: 1500);
      final mode = dark ? 'dark' : 'light';
      await cam.shot('planner_home_$mode', ratio: 1.5);
      if (!dark) break;
      for (final (label, name) in [
        ('Calendar', 'calendar'),
        ('Daily task list', 'tasks'),
        ('Weekly planning', 'week'),
      ]) {
        await t.tap(find.text(label).first);
        await settle(t, ms: 1200);
        await cam.shot('planner_${name}_$mode', ratio: 1.5);
      }
      await t.tap(find.text('Home').first);
      await settle(t, ms: 800);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
