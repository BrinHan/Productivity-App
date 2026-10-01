import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'island_controller.dart';

/// Reads the Windows media session (what media keys control) through one
/// hidden, long-lived PowerShell process. It prints a JSON line about once a
/// second, saves the album art to a temp file when the track changes, and
/// accepts play/pause/next/prev through a small command file. It exits by
/// itself if this app dies.
class NowPlayingService {
  NowPlayingService(this.onChanged);
  final void Function(NowPlaying?) onChanged;

  Process? _proc;
  StreamSubscription<String>? _sub;
  String _last = '';

  String get _cmdPath => '${Directory.systemTemp.path}${Platform.pathSeparator}aod_np_cmd.txt';

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
[void][Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
$mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$propType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
$streamType = [Windows.Storage.Streams.IRandomAccessStreamWithContentType]
$mgr = Await ($mgrType::RequestAsync()) $mgrType
$cmdFile = '__DIR__\aod_np_cmd.txt'
$lastKey = ''
$artPath = ''
$artTries = 0
$n = 0
$tick = 0
while ($true) {
  if (-not (Get-Process -Id __PID__ -ErrorAction SilentlyContinue)) { break }
  $force = $false
  if (Test-Path $cmdFile) {
    $cmd = (Get-Content $cmdFile -Raw).Trim()
    Remove-Item $cmdFile -Force
    try {
      $s = $mgr.GetCurrentSession()
      if ($s) {
        if ($cmd -eq 'toggle') { [void](Await ($s.TryTogglePlayPauseAsync()) ([bool])) }
        elseif ($cmd -eq 'next') { [void](Await ($s.TrySkipNextAsync()) ([bool])) }
        elseif ($cmd -eq 'prev') { [void](Await ($s.TrySkipPreviousAsync()) ([bool])) }
        Start-Sleep -Milliseconds 250
      }
    } catch { }
    $force = $true
  }
  if ($force -or ($tick % 4 -eq 0)) {
    $out = '{}'
    try {
      $s = $mgr.GetCurrentSession()
      if ($s) {
        $p = Await ($s.TryGetMediaPropertiesAsync()) $propType
        $st = $s.GetPlaybackInfo().PlaybackStatus.ToString()
        $key = "$($p.Title)|$($p.Artist)|$($p.AlbumTitle)"
        if ($key -ne $lastKey) { $lastKey = $key; $artPath = ''; $artTries = 0 }
        if ($artPath -eq '' -and $artTries -lt 6 -and $p.Thumbnail) {
          $artTries++
          try {
            $stream = Await ($p.Thumbnail.OpenReadAsync()) $streamType
            $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
            $ms = New-Object System.IO.MemoryStream
            $net.CopyTo($ms)
            if ($ms.Length -gt 0) {
              $n++
              $artPath = "__DIR__\aod_art_$n.img"
              [System.IO.File]::WriteAllBytes($artPath, $ms.ToArray())
              if ($n -gt 2) { Remove-Item "__DIR__\aod_art_$($n-2).img" -Force }
            }
            $net.Dispose()
          } catch { }
        }
        $out = @{ title = "$($p.Title)"; artist = "$($p.Artist)"; status = $st; art = $artPath } | ConvertTo-Json -Compress
      }
    } catch { }
    [Console]::Out.WriteLine($out)
    [Console]::Out.Flush()
  }
  $tick++
  Start-Sleep -Milliseconds 250
}
''';

  Future<void> start() async {
    if (!Platform.isWindows) return;
    try {
      final dir = Directory.systemTemp.path;
      final file = File('$dir${Platform.pathSeparator}aod_nowplaying.ps1');
      await file.writeAsString(_script.replaceAll('__PID__', '$pid').replaceAll('__DIR__', dir));
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

  /// 'toggle' | 'next' | 'prev'
  Future<void> send(String cmd) async {
    try {
      await File(_cmdPath).writeAsString(cmd);
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
      final art = (m['art'] as String?) ?? '';
      if (title.isEmpty && artist.isEmpty) {
        onChanged(null);
      } else {
        onChanged(NowPlaying(title, artist, status == 'Playing', art.isEmpty ? null : art));
      }
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
    _proc?.kill();
  }
}
