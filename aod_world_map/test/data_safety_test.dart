import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian/desktop/app_files.dart';
import 'package:meridian/desktop/backup.dart';
import 'package:meridian/desktop/planner_model.dart';
import 'package:meridian/desktop/updates.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('data_safety_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File f(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  group('safe saves', () {
    test('write in one step, keep a backup of the old file, leave no temp file', () async {
      await writeFileSafely(f('a.json'), '{"v":1}', backup: true);
      await writeFileSafely(f('a.json'), '{"v":2}', backup: true);
      expect(f('a.json').readAsStringSync(), '{"v":2}');
      expect(f('a.json.bak').readAsStringSync(), '{"v":1}');
      expect(f('a.json.tmp').existsSync(), isFalse);
    });

    test('a planner file that will not parse loads from its backup', () async {
      final day = dayOf(DateTime.now());
      f('planner.json.bak').writeAsStringSync(
        jsonEncode({
          'tasks': [Task(id: 'x', title: 'kept', day: day).toJson()],
        }),
      );
      f('planner.json').writeAsStringSync('{"tasks": [ {"id": "x", "tit'); // cut off mid-save
      final p = PlannerModel(file: f('planner.json'));
      await p.load();
      expect(p.tasks.single.title, 'kept');
      expect(p.isNew, isFalse);
      p.dispose();
    });
  });

  group('backup file', () {
    test('round trip, notes included', () async {
      final src = Directory('${dir.path}${Platform.pathSeparator}src')..createSync();
      final dst = Directory('${dir.path}${Platform.pathSeparator}dst')..createSync();
      File('${src.path}/planner.json').writeAsStringSync('{"tasks":[]}');
      File('${src.path}/google.json').writeAsStringSync('{"refresh":"secret"}');
      Directory('${src.path}/notes').createSync();
      File('${src.path}/notes/123-abc.json').writeAsStringSync('{"id":"123-abc"}');

      final raw = await Backup.create(root: src);
      expect(raw, isNot(contains('secret')), reason: 'sign-in tokens stay out of backups');
      expect(await Backup.restore(raw, root: dst), 2);
      expect(File('${dst.path}/planner.json').readAsStringSync(), '{"tasks":[]}');
      expect(
        File('${dst.path}${Platform.pathSeparator}notes${Platform.pathSeparator}123-abc.json').existsSync(),
        isTrue,
      );
    });

    test('names outside the data folder are ignored', () async {
      final raw = jsonEncode({
        'files': {'../evil.json': '{}', 'notes/../../evil.json': '{}', 'planner.json': '{}'},
      });
      expect(await Backup.restore(raw, root: dir), 1);
      expect(File('${dir.parent.path}/evil.json').existsSync(), isFalse);
    });

    test('a file that is not a backup says so', () async {
      expect(() => Backup.restore('hello', root: dir), throwsFormatException);
      expect(() => Backup.restore('{"files":{}}', root: dir), throwsFormatException);
    });
  });

  group('updates', () {
    test('versions compare by number', () {
      expect(isNewerVersion('1.10.0', '1.9.3'), isTrue);
      expect(isNewerVersion('v1.2.0', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2', '1.2.0'), isFalse);
      expect(isNewerVersion('2.0.0-beta', '1.9.0'), isTrue);
      expect(isNewerVersion('1.1.9', '1.2.0'), isFalse);
    });

    test('reads a GitHub release and finds the installer', () {
      final r = UpdateCheck.parseRelease(
        jsonEncode({
          'tag_name': 'v1.3.0',
          'html_url': 'https://github.com/x/y/releases/tag/v1.3.0',
          'assets': [
            {'browser_download_url': 'https://github.com/x/y/releases/download/v1.3.0/notes.txt'},
            {'browser_download_url': 'https://github.com/x/y/releases/download/v1.3.0/Meridian-Setup-1.3.0.exe'},
          ],
        }),
      )!;
      expect(r.version, '1.3.0');
      expect(r.installer, endsWith('.exe'));
      expect(UpdateCheck.parseRelease(jsonEncode({'tag_name': 'v9', 'html_url': 'u', 'prerelease': true})), isNull);
    });

    test('kAppVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final v = RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(pubspec)!.group(1);
      expect(kAppVersion, v, reason: 'bump lib/desktop/updates.dart with pubspec.yaml');
    });
  });
}
