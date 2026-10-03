import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
  bool _disposed = false;
  NowPlaying? _cur;
  String? _fbKey, _fbPath; // fallback artwork (looked up online) for one track
  int _fbN = 0;

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
[void][Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.IInputStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
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
  if (($tick % 20 -eq 0) -and -not (Get-Process -Id __PID__ -ErrorAction SilentlyContinue)) { break }
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
  if ($force -or ($tick % 6 -eq 0)) {
    $out = '{}'
    try {
      $s = $mgr.GetCurrentSession()
      if ($s) {
        $p = Await ($s.TryGetMediaPropertiesAsync()) $propType
        $st = $s.GetPlaybackInfo().PlaybackStatus.ToString()
        $key = "$($p.Title)|$($p.Artist)|$($p.AlbumTitle)"
        if ($key -ne $lastKey) { $lastKey = $key; $artPath = ''; $artTries = 0 }
        if ($artPath -eq '' -and $artTries -lt 40 -and $p.Thumbnail) {
          $artTries++
          $bytes = $null
          try {
            $stream = Await ($p.Thumbnail.OpenReadAsync()) $streamType
            $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead([Windows.Storage.Streams.IInputStream]$stream)
            $ms = New-Object System.IO.MemoryStream
            $net.CopyTo($ms)
            if ($ms.Length -gt 0) { $bytes = $ms.ToArray() }
            $net.Dispose()
          } catch { Add-Content "__DIR__\aod_np_log.txt" "stream A: $($_.Exception.Message)" }
          if (-not $bytes) {
            try {
              $stream = Await ($p.Thumbnail.OpenReadAsync()) $streamType
              $size = [uint32]$stream.Size
              if ($size -gt 0) {
                $rd = [Windows.Storage.Streams.DataReader]::new($stream.GetInputStreamAt(0))
                [void](Await ($rd.LoadAsync($size)) ([uint32]))
                $b = New-Object byte[] $size
                $rd.ReadBytes($b)
                $bytes = $b
              }
            } catch { Add-Content "__DIR__\aod_np_log.txt" "stream B: $($_.Exception.Message)" }
          }
          if ($bytes -and $bytes.Length -gt 0) {
            $n++
            $artPath = "__DIR__\aod_art_$n.img"
            [System.IO.File]::WriteAllBytes($artPath, $bytes)
            if ($n -gt 2) { Remove-Item "__DIR__\aod_art_$($n-2).img" -Force }
          }
        }
        $out = @{ title = "$($p.Title)"; artist = "$($p.Artist)"; status = $st; art = $artPath } | ConvertTo-Json -Compress
      }
    } catch { }
    [Console]::Out.WriteLine($out)
    [Console]::Out.Flush()
  }
  $tick++
  if ($tick % 480 -eq 0) { [GC]::Collect() }
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
        _emit(null);
      } else {
        final k = '$title|$artist';
        var path = art.isEmpty ? null : art;
        if (path == null && _fbKey == k) path = _fbPath;
        _emit(NowPlaying(title, artist, status == 'Playing', path));
        if (path == null && _fbKey != k && title.isNotEmpty) _lookupArt(title, artist, k);
      }
    } catch (_) {}
  }

  void _emit(NowPlaying? n) {
    if (_disposed) return;
    _cur = n;
    onChanged(n);
  }

  /// Some players (Spotify at times) hand over no thumbnail. After a short
  /// grace period, fetch the cover from Apple's public iTunes Search API
  /// (title + artist are sent to Apple; no account or key needed).
  Future<void> _lookupArt(String title, String artist, String key) async {
    _fbKey = key;
    _fbPath = null;
    await Future.delayed(const Duration(milliseconds: 2500));
    if (_disposed || _cur?.key != key || _cur?.art != null) return;
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $title'.trim(),
        'media': 'music',
        'entity': 'song',
        'limit': '3',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final results = (jsonDecode(res.body) as Map)['results'] as List?;
      if (results == null) return;
      final want = title.toLowerCase();
      String? url;
      for (final r in results) {
        if (r is! Map) continue;
        final name = ((r['trackName'] as String?) ?? '').toLowerCase();
        final u = r['artworkUrl100'] as String?;
        if (u != null && name.isNotEmpty && (want.contains(name) || name.contains(want))) {
          url = u;
          break;
        }
      }
      if (url == null) return;
      final img = await http
          .get(Uri.parse(url.replaceAll('100x100bb', '400x400bb')))
          .timeout(const Duration(seconds: 8));
      if (img.statusCode != 200 || img.bodyBytes.isEmpty) return;
      final dir = Directory.systemTemp.path;
      final f = File('$dir${Platform.pathSeparator}aod_art_web_${++_fbN}.jpg');
      await f.writeAsBytes(img.bodyBytes);
      final old = _fbPath;
      if (_disposed || _fbKey != key) return;
      _fbPath = f.path;
      if (old != null) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
      final cur = _cur;
      if (cur != null && cur.key == key && cur.art == null) {
        _emit(NowPlaying(cur.title, cur.artist, cur.playing, f.path));
      }
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _proc?.kill();
  }
}
