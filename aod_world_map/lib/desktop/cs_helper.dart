import 'dart:io';

import 'app_files.dart';
import 'log.dart';

/// Compiles a small C# helper with the .NET Framework compiler that ships
/// with Windows, once, into %APPDATA%\AodWorldMap\bin\<name>.exe. Returns its
/// path, or null when this Windows has no compiler or the build fails.
///
/// [name] should carry a version suffix ('aod_media_v4'): bump it whenever
/// [source] changes so the old build is not reused. [refs] are extra
/// references; paths may use {fw} (the framework folder) and {md}
/// (System32\WinMetadata).
Future<String?> buildCsHelper(String name, String source, {List<String> refs = const []}) async {
  try {
    final s = Platform.pathSeparator;
    final bin = appDataFolder('bin');
    final exe = File('${bin.path}$s$name.exe');
    if (await exe.exists()) return exe.path;
    final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final fw = '$win${s}Microsoft.NET${s}Framework64${s}v4.0.30319';
    final md = '$win${s}System32${s}WinMetadata';
    final csc = File('$fw${s}csc.exe');
    if (!await csc.exists()) return null;
    await bin.create(recursive: true);
    final src = File('${bin.path}$s$name.cs');
    await src.writeAsString(source);
    final r = await Process.run(csc.path, [
      '-nologo',
      '-optimize+',
      '-target:winexe', // no console window; stdout still reaches us through the pipe
      '-out:${exe.path}',
      for (final ref in refs) '-r:${ref.replaceAll('{fw}', fw).replaceAll('{md}', md)}',
      src.path,
    ]);
    try {
      await src.delete();
    } catch (e, st) {
      logError(e, st);
    }
    return r.exitCode == 0 && await exe.exists() ? exe.path : null;
  } catch (_) {
    return null;
  }
}
