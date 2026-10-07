import 'dart:io';

/// Everything Meridian saves lives here. The app window, the island and the
/// overlay all share it, and watch it to pick up each other's changes.
Directory get appDataDir {
  final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
  return Directory('$base${Platform.pathSeparator}AodWorldMap');
}

File appDataFile(String name) => File('${appDataDir.path}${Platform.pathSeparator}$name');

Directory appDataFolder(String name) => Directory('${appDataDir.path}${Platform.pathSeparator}$name');
