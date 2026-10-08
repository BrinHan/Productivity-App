import 'dart:io';

/// Everything Meridian saves lives here. The app window, the island and the
/// overlay all share it, and watch it to pick up each other's changes.
Directory get appDataDir {
  final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
  return Directory('$base${Platform.pathSeparator}AodWorldMap');
}

File appDataFile(String name) => File('${appDataDir.path}${Platform.pathSeparator}$name');

Directory appDataFolder(String name) => Directory('${appDataDir.path}${Platform.pathSeparator}$name');

/// How old the `.bak` copy may get before a save refreshes it. An hour back
/// is far enough to undo a bad save, and close enough to lose little.
const kBackupEvery = Duration(hours: 1);

File backupOf(File f) => File('${f.path}.bak');

/// Saves [raw] to [f] without ever leaving it half written: the text goes to
/// a temporary file first, which then takes the old file's place in one step.
/// With [backup], the file as it was is kept as `.bak` at most once an hour.
///
/// The other processes may be reading [f] at that moment, which makes the
/// swap fail on Windows, so it is retried briefly before falling back to a
/// plain write.
Future<void> writeFileSafely(File f, String raw, {bool backup = false}) async {
  await f.parent.create(recursive: true);
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(raw, flush: true);
  if (backup && await f.exists()) {
    final bak = backupOf(f);
    final age = await bak.exists() ? DateTime.now().difference(await bak.lastModified()) : null;
    if (age == null || age >= kBackupEvery) {
      try {
        await f.copy(bak.path);
      } on FileSystemException {
        // A missing backup is not worth failing the save over.
      }
    }
  }
  for (var i = 0; ; i++) {
    try {
      await tmp.rename(f.path);
      return;
    } on FileSystemException {
      if (i >= 4) break;
      await Future<void>.delayed(Duration(milliseconds: 20 * (i + 1)));
    }
  }
  await f.writeAsString(raw, flush: true);
  try {
    await tmp.delete();
  } on FileSystemException {
    // Left over; the next save writes over it.
  }
}

/// Reads [f], or its `.bak` when [f] is missing or [valid] rejects it.
/// Null when neither holds anything usable.
Future<String?> readWithBackup(File f, bool Function(String raw) valid) async {
  for (final g in [f, backupOf(f)]) {
    try {
      if (!await g.exists()) continue;
      final raw = await g.readAsString();
      if (valid(raw)) return raw;
    } on Exception {
      continue; // unreadable or not valid JSON: try the backup
    }
  }
  return null;
}
