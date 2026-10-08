import 'dart:io';

import 'app_files.dart';

/// A small error log per process in `%APPDATA%\AodWorldMap\logs`, so a
/// report like "my calendar stopped syncing" comes with something to read.
/// Settings > About copies the recent lines for a bug report.
class Log {
  Log._();

  /// Which process is writing: app, island or overlay. Set once in main.
  static String process = 'app';

  /// A log grows to this, then moves to `.1` (replacing the older one).
  static const maxBytes = 512 * 1024;

  /// The same error is written at most this often, so a failure inside a
  /// timer that ticks every 60 ms does not flood the file.
  static const repeatEvery = Duration(minutes: 10);

  static final _lastSeen = <String, DateTime>{};

  static Directory get dir => appDataFolder('logs');
  static File get file => File('${dir.path}${Platform.pathSeparator}$process.log');

  static void info(String message) => _write('INFO', message);

  static void error(Object e, [StackTrace? st]) {
    final key = '$e';
    final now = DateTime.now();
    final last = _lastSeen[key];
    if (last != null && now.difference(last) < repeatEvery) return;
    _lastSeen[key] = now;
    if (_lastSeen.length > 200) _lastSeen.remove(_lastSeen.keys.first);
    _write('ERROR', st == null ? key : '$key\n${_trim(st)}');
  }

  /// The first few frames say where it happened; the rest is the framework.
  static String _trim(StackTrace st) => st.toString().split('\n').take(6).map((l) => '    $l').join('\n');

  static void _write(String level, String message) {
    try {
      final f = file;
      f.parent.createSync(recursive: true);
      if (f.existsSync() && f.lengthSync() > maxBytes) {
        f.renameSync('${f.path}.1');
      }
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $level $message\n', mode: FileMode.append);
    } catch (_) {
      // Nowhere left to report a failure to log.
    }
  }

  /// The last [lines] lines of every process's log, newest file last, for
  /// pasting into a bug report.
  static Future<String> recent({int lines = 80}) async {
    final out = StringBuffer();
    for (final p in const ['app', 'island', 'overlay']) {
      final f = File('${dir.path}${Platform.pathSeparator}$p.log');
      if (!await f.exists()) continue;
      final all = await f.readAsLines();
      out.writeln('== $p.log ==');
      for (final l in all.skip(all.length > lines ? all.length - lines : 0)) {
        out.writeln(l);
      }
    }
    return out.isEmpty ? 'No errors logged.' : out.toString();
  }
}

/// For a `catch` whose failure is not worth bothering the user with, but is
/// worth knowing about later.
void logError(Object e, [StackTrace? st]) => Log.error(e, st);
