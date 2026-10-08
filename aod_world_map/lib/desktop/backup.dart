import 'dart:convert';
import 'dart:io';

import 'app_files.dart';

/// A whole-Meridian backup as one JSON file the user keeps wherever they
/// like: the planner, island and planner-window settings, the drawing tools,
/// and every meeting note. Same shape as the Drive backup, with notes added.
///
/// Sign-in tokens and the Anthropic key are left out on purpose: a backup
/// file gets emailed and synced around, and both are easy to set up again.
class Backup {
  Backup._();

  static const settingsFiles = ['planner.json', 'island.json', 'ui.json', 'overlay.json'];

  /// Only these names are ever written on restore, so a hand-edited or
  /// hostile file can't put anything outside the data folder.
  static final _noteName = RegExp(r'^notes/[A-Za-z0-9_-]+\.json$');

  static bool allowed(String name) => settingsFiles.contains(name) || _noteName.hasMatch(name);

  /// The backup's contents, ready to save.
  static Future<String> create({Directory? root}) async {
    final dir = root ?? appDataDir;
    final s = Platform.pathSeparator;
    final files = <String, String>{};
    for (final n in settingsFiles) {
      final f = File('${dir.path}$s$n');
      if (await f.exists()) files[n] = await f.readAsString();
    }
    final notes = Directory('${dir.path}${s}notes');
    if (await notes.exists()) {
      await for (final f in notes.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        final name = 'notes/${f.uri.pathSegments.last}';
        if (allowed(name)) files[name] = await f.readAsString();
      }
    }
    return const JsonEncoder.withIndent(' ')
        .convert({'app': 'meridian', 'v': 1, 'created': DateTime.now().toIso8601String(), 'files': files});
  }

  /// Writes a backup's files over the current ones (each old file is kept
  /// as `.bak` first). Returns how many files were restored. Throws a
  /// [FormatException] with a message for the user when [raw] isn't one.
  static Future<int> restore(String raw, {Directory? root}) async {
    final Object? j;
    try {
      j = jsonDecode(raw);
    } on FormatException {
      throw const FormatException("That file isn't a Meridian backup.");
    }
    final files = j is Map ? j['files'] : null;
    if (files is! Map || files.isEmpty) throw const FormatException("That file isn't a Meridian backup.");
    final dir = root ?? appDataDir;
    var n = 0;
    for (final e in files.entries) {
      final name = '${e.key}';
      final body = e.value;
      if (!allowed(name) || body is! String) continue;
      final f = File('${dir.path}${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}');
      await writeFileSafely(f, body, backup: true);
      n++;
    }
    if (n == 0) throw const FormatException('That backup has nothing Meridian can restore.');
    return n;
  }

  /// A file name for today's backup.
  static String suggestedName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Meridian backup ${d.year}-${two(d.month)}-${two(d.day)}.json';
  }
}
