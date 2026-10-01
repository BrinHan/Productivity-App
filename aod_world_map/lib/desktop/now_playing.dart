import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'island_controller.dart';

/// Reads the Windows "media session" (the thing media keys control) using a
/// single long-lived, hidden PowerShell process that prints one JSON line
/// every 1.5 s. It exits by itself if this app dies.
class NowPlayingService {
  NowPlayingService(this.onChanged);
  final void Function(NowPlaying?) onChanged;

  Process? _proc;
  StreamSubscription<String>? _sub;
  String _last = '';

  static const _script = r'''
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  $t.Wait(-1) | Out-Null
  $t.Result
}
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$propType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
$mgr = Await ($mgrType::RequestAsync()) $mgrType
while ($true) {
  if (-not (Get-Process -Id __PID__ -ErrorAction SilentlyContinue)) { break }
  $out = '{}'
  try {
    $s = $mgr.GetCurrentSession()
    if ($s) {
      $p = Await ($s.TryGetMediaPropertiesAsync()) $propType
      $st = $s.GetPlaybackInfo().PlaybackStatus.ToString()
      $out = @{ title = "$($p.Title)"; artist = "$($p.Artist)"; status = $st } | ConvertTo-Json -Compress
    }
  } catch { }
  [Console]::Out.WriteLine($out)
  [Console]::Out.Flush()
  Start-Sleep -Milliseconds 1500
}
''';

  Future<void> start() async {
    if (!Platform.isWindows) return;
    try {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}aod_nowplaying.ps1');
      await file.writeAsString(_script.replaceAll('__PID__', '$pid'));
      _proc = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        file.path,
      ]);
      _sub = _proc!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      _proc!.stderr.drain<void>();
    } catch (_) {}
  }

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty || line == _last) return;
    _last = line;
    try {
      final m = jsonDecode(line);
      if (m is! Map) return;
      final title = (m['title'] as String?) ?? '';
      final artist = (m['artist'] as String?) ?? '';
      final status = (m['status'] as String?) ?? '';
      if (title.isEmpty && artist.isEmpty) {
        onChanged(null);
      } else {
        onChanged(NowPlaying(title, artist, status == 'Playing'));
      }
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _proc?.kill();
  }
}
