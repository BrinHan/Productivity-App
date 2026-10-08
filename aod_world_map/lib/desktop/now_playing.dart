import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cs_helper.dart';
import 'island_controller.dart';
import 'log.dart';

/// Reads the Windows media session (what media keys control) through one
/// hidden, long-lived PowerShell process. It prints a JSON line about once a
/// second, saves the album art to a temp file when the track changes, and
/// accepts play/pause/next/prev through a small command file. It exits by
/// itself if this app dies.
class NowPlayingService {
  NowPlayingService(this.onChanged, {this.onBands});
  final void Function(NowPlaying?) onChanged;

  /// Five 0..1 levels (sub-bass, bass, low-mid, high-mid, treble) about 30
  /// times a second while something plays. Only the compiled helper sends
  /// them; the PowerShell fallback does not.
  final void Function(List<double>)? onBands;

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
        $tl = $s.GetTimelineProperties()
        $out = @{ title = "$($p.Title)"; artist = "$($p.Artist)"; album = "$($p.AlbumTitle)"; app = "$($s.SourceAppUserModelId)"; status = $st; art = $artPath; posMs = [long]$tl.Position.TotalMilliseconds; durMs = [long]($tl.EndTime - $tl.StartTime).TotalMilliseconds; at = $tl.LastUpdatedTime.ToUnixTimeMilliseconds() } | ConvertTo-Json -Compress
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

  /// Same job as [_script], as a tiny C# program, plus the visualizer: while
  /// something plays it listens to the speaker output (WASAPI loopback) and
  /// prints five band levels ("V ..."). Compiled once with the C# compiler
  /// that ships with Windows; it runs in about 14 MB where the PowerShell
  /// host needs about 70. Bump the version when this changes.
  static const _csVersion = 'v4';
  static const _cs = r'''
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Windows.Foundation;
using Windows.Media.Control;
using Windows.Storage.Streams;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorCom { }

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator
{
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice
{
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[ComImport, Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioClient
{
    [PreserveSig] int Initialize(int shareMode, int streamFlags, long hnsBufferDuration, long hnsPeriodicity, IntPtr pFormat, IntPtr audioSessionGuid);
    [PreserveSig] int GetBufferSize(out uint bufferFrames);
    [PreserveSig] int GetStreamLatency(out long latency);
    [PreserveSig] int GetCurrentPadding(out uint padding);
    [PreserveSig] int IsFormatSupported(int shareMode, IntPtr pFormat, out IntPtr closestMatch);
    [PreserveSig] int GetMixFormat(out IntPtr deviceFormat);
    [PreserveSig] int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);
    [PreserveSig] int Start();
    [PreserveSig] int Stop();
    [PreserveSig] int Reset();
    [PreserveSig] int SetEventHandle(IntPtr eventHandle);
    [PreserveSig] int GetService(ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
}

[ComImport, Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioCaptureClient
{
    [PreserveSig] int GetBuffer(out IntPtr data, out uint numFrames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
    [PreserveSig] int ReleaseBuffer(uint numFrames);
    [PreserveSig] int GetNextPacketSize(out uint numFrames);
}

/// Five loudness bands from what the speakers are playing: sub-bass, bass,
/// low-mid, high-mid, treble. Each band keeps its own recent peak, so quiet
/// and loud tracks both fill the bars.
static class Spectrum
{
    public const int N = 2048;
    static readonly float[] ring = new float[N];
    static int pos = 0;
    static readonly double[] win = MakeWindow();
    static readonly double[] re = new double[N], im = new double[N];
    static readonly double[] lo = { 20, 60, 250, 1000, 4000 };
    static readonly double[] hi = { 60, 250, 1000, 4000, 14000 };
    static readonly double[] peak = { 0, 0, 0, 0, 0 };
    public static volatile bool Playing;

    static double[] MakeWindow()
    {
        var w = new double[N];
        for (int i = 0; i < N; i++) w[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1));
        return w;
    }

    public static void Push(float s) { ring[pos] = s; pos = (pos + 1) % N; }

    static void Fft(double[] xr, double[] xi)
    {
        int n = xr.Length;
        for (int i = 1, j = 0; i < n; i++)
        {
            int bit = n >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) { double t = xr[i]; xr[i] = xr[j]; xr[j] = t; t = xi[i]; xi[i] = xi[j]; xi[j] = t; }
        }
        for (int len = 2; len <= n; len <<= 1)
        {
            double ang = -2 * Math.PI / len, wr = Math.Cos(ang), wi = Math.Sin(ang);
            for (int i = 0; i < n; i += len)
            {
                double cr = 1, ci = 0;
                for (int k = 0; k < len / 2; k++)
                {
                    int a = i + k, b = i + k + len / 2;
                    double br = xr[b] * cr - xi[b] * ci, bi = xr[b] * ci + xi[b] * cr;
                    xr[b] = xr[a] - br; xi[b] = xi[a] - bi;
                    xr[a] += br; xi[a] += bi;
                    double nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
                }
            }
        }
    }

    public static string Bands(int rate)
    {
        for (int i = 0; i < N; i++) { re[i] = ring[(pos + i) % N] * win[i]; im[i] = 0; }
        Fft(re, im);
        var sb = new StringBuilder("V");
        var dbs = new double[5];
        double top = 0;
        for (int b = 0; b < 5; b++)
        {
            int k0 = Math.Max(1, (int)(lo[b] * N / rate));
            int k1 = Math.Min(N / 2, Math.Max(k0 + 1, (int)(hi[b] * N / rate)));
            double sum = 0;
            for (int k = k0; k < k1; k++) sum += re[k] * re[k] + im[k] * im[k];
            dbs[b] = 10 * Math.Log10(sum / (k1 - k0) + 1e-12);
            // The loudest recent level is the top of the bar. The top sinks
            // slowly so a quiet passage still moves.
            peak[b] = Math.Max(Math.Max(dbs[b], peak[b] - 0.12), 6);
            top = Math.Max(top, peak[b]);
        }
        for (int b = 0; b < 5; b++)
        {
            // A band far under the loudest one stays low instead of filling up
            // on what spills over from its neighbour.
            double ceil = Math.Max(peak[b], top - 18);
            double v = (dbs[b] - (ceil - 36)) / 36;
            v = Math.Max(0, Math.Min(1, v));
            v = Math.Pow(v, 1.6); // more contrast between hits and the rest
            sb.Append(' ').Append(v.ToString("0.00", CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }
}

static class NowPlayingHelper
{
    static readonly object outLock = new object();
    static StreamWriter stdout;

    static void Say(string s) { lock (outLock) { stdout.WriteLine(s); } }

    static T Await<T>(IAsyncOperation<T> op)
    {
        while (op.Status == AsyncStatus.Started) Thread.Sleep(5);
        if (op.Status != AsyncStatus.Completed) throw new Exception("async " + op.Status);
        return op.GetResults();
    }

    static string Esc(string s)
    {
        if (s == null) return "";
        var b = new StringBuilder();
        foreach (var c in s)
        {
            if (c == (char)34 || c == (char)92) { b.Append((char)92); b.Append(c); }
            else if (c < 0x20) b.Append(((char)92).ToString() + "u" + ((int)c).ToString("x4"));
            else b.Append(c);
        }
        return b.ToString();
    }

    static bool Alive(int pid)
    {
        try { return !Process.GetProcessById(pid).HasExited; } catch { return false; }
    }

    static byte[] Art(GlobalSystemMediaTransportControlsSessionMediaProperties p)
    {
        if (p.Thumbnail == null) return null;
        try
        {
            var s = Await(p.Thumbnail.OpenReadAsync());
            var size = (uint)s.Size;
            if (size == 0) return null;
            var rd = new DataReader(s.GetInputStreamAt(0));
            Await(rd.LoadAsync(size));
            var b = new byte[size];
            rd.ReadBytes(b);
            return b;
        }
        catch { return null; }
    }

    // ---- speaker loopback, only while something is playing ----

    static void AudioLoop()
    {
        while (true)
        {
            if (!Spectrum.Playing) { Thread.Sleep(300); continue; }
            try { Capture(); } catch { }
            Thread.Sleep(1000);
        }
    }

    static void Capture()
    {
        IMMDevice dev = null;
        IAudioClient ac = null;
        IAudioCaptureClient cap = null;
        IntPtr fmt = IntPtr.Zero;
        try
        {
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) return; // render, multimedia
            Guid iid = typeof(IAudioClient).GUID;
            object o;
            if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return;
            ac = (IAudioClient)o;
            if (ac.GetMixFormat(out fmt) != 0) return;
            int tag = Marshal.ReadInt16(fmt, 0) & 0xFFFF;
            int ch = Marshal.ReadInt16(fmt, 2);
            int rate = Marshal.ReadInt32(fmt, 4);
            int bits = Marshal.ReadInt16(fmt, 14);
            bool isFloat = tag == 3 || (tag == 0xFFFE && (Marshal.ReadInt16(fmt, 24) & 0xFFFF) == 3);
            if (ac.Initialize(0, 0x00020000, 2000000, 0, fmt, IntPtr.Zero) != 0) return; // shared, loopback
            Guid cg = typeof(IAudioCaptureClient).GUID;
            object so;
            if (ac.GetService(ref cg, out so) != 0) return;
            cap = (IAudioCaptureClient)so;
            ac.Start();
            var fbuf = new float[0];
            var sbuf = new short[0];
            DateTime last = DateTime.UtcNow, heard = DateTime.UtcNow;
            while (Spectrum.Playing)
            {
                Thread.Sleep(10);
                uint size;
                bool got = false;
                while (cap.GetNextPacketSize(out size) == 0 && size > 0)
                {
                    IntPtr data;
                    uint frames, flags;
                    ulong dp, qp;
                    if (cap.GetBuffer(out data, out frames, out flags, out dp, out qp) != 0) break;
                    int n = (int)frames;
                    got = true;
                    if ((flags & 2) != 0 || data == IntPtr.Zero)
                    {
                        for (int i = 0; i < n; i++) Spectrum.Push(0);
                    }
                    else if (isFloat && bits == 32)
                    {
                        int c = n * ch;
                        if (fbuf.Length < c) fbuf = new float[c];
                        Marshal.Copy(data, fbuf, 0, c);
                        for (int i = 0; i < n; i++)
                        {
                            float s = 0;
                            for (int k = 0; k < ch; k++) s += fbuf[i * ch + k];
                            Spectrum.Push(s / ch);
                        }
                    }
                    else if (bits == 16)
                    {
                        int c = n * ch;
                        if (sbuf.Length < c) sbuf = new short[c];
                        Marshal.Copy(data, sbuf, 0, c);
                        for (int i = 0; i < n; i++)
                        {
                            float s = 0;
                            for (int k = 0; k < ch; k++) s += sbuf[i * ch + k];
                            Spectrum.Push(s / ch / 32768f);
                        }
                    }
                    cap.ReleaseBuffer(frames);
                }
                var now = DateTime.UtcNow;
                // Nothing for a while (output device switched?): start over.
                if (got) heard = now; else if ((now - heard).TotalSeconds > 3) return;
                if ((now - last).TotalMilliseconds >= 33) { last = now; Say(Spectrum.Bands(rate)); }
            }
        }
        finally
        {
            try { if (ac != null) ac.Stop(); } catch { }
            if (fmt != IntPtr.Zero) Marshal.FreeCoTaskMem(fmt);
            if (cap != null) Marshal.ReleaseComObject(cap);
            if (ac != null) Marshal.ReleaseComObject(ac);
            if (dev != null) Marshal.ReleaseComObject(dev);
        }
    }

    static int Main(string[] args)
    {
        int parent = int.Parse(args[0]);
        string dir = args[1];
        string cmdFile = Path.Combine(dir, "aod_np_cmd.txt");
        stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        stdout.AutoFlush = true;
        new Thread(AudioLoop) { IsBackground = true }.Start();
        var mgr = Await(GlobalSystemMediaTransportControlsSessionManager.RequestAsync());
        string lastKey = "", artPath = "";
        int artTries = 0, n = 0, tick = 0;
        while (true)
        {
            if (tick % 20 == 0 && !Alive(parent)) return 0;
            bool force = false;
            if (File.Exists(cmdFile))
            {
                string cmd = "";
                try { cmd = File.ReadAllText(cmdFile).Trim(); File.Delete(cmdFile); } catch { }
                try
                {
                    var s = mgr.GetCurrentSession();
                    if (s != null)
                    {
                        if (cmd == "toggle") Await(s.TryTogglePlayPauseAsync());
                        else if (cmd == "next") Await(s.TrySkipNextAsync());
                        else if (cmd == "prev") Await(s.TrySkipPreviousAsync());
                        Thread.Sleep(250);
                    }
                }
                catch { }
                force = true;
            }
            if (force || tick % 6 == 0)
            {
                string line = "{}";
                bool playing = false;
                try
                {
                    var s = mgr.GetCurrentSession();
                    if (s != null)
                    {
                        var p = Await(s.TryGetMediaPropertiesAsync());
                        var st = s.GetPlaybackInfo().PlaybackStatus.ToString();
                        playing = st == "Playing";
                        var key = p.Title + "|" + p.Artist + "|" + p.AlbumTitle;
                        if (key != lastKey) { lastKey = key; artPath = ""; artTries = 0; }
                        if (artPath == "" && artTries < 40 && p.Thumbnail != null)
                        {
                            artTries++;
                            var bytes = Art(p);
                            if (bytes != null && bytes.Length > 0)
                            {
                                n++;
                                artPath = Path.Combine(dir, "aod_art_" + n + ".img");
                                File.WriteAllBytes(artPath, bytes);
                                if (n > 2) { try { File.Delete(Path.Combine(dir, "aod_art_" + (n - 2) + ".img")); } catch { } }
                            }
                        }
                        var tl = s.GetTimelineProperties();
                        long posMs = (long)tl.Position.TotalMilliseconds;
                        long durMs = (long)(tl.EndTime - tl.StartTime).TotalMilliseconds;
                        long at = tl.LastUpdatedTime.ToUnixTimeMilliseconds();
                        line = "{\"title\":\"" + Esc(p.Title) + "\",\"artist\":\"" + Esc(p.Artist) +
                               "\",\"album\":\"" + Esc(p.AlbumTitle) + "\",\"app\":\"" + Esc(s.SourceAppUserModelId) +
                               "\",\"status\":\"" + st + "\",\"art\":\"" + Esc(artPath) +
                               "\",\"posMs\":" + posMs + ",\"durMs\":" + durMs + ",\"at\":" + at + "}";
                    }
                }
                catch { }
                Spectrum.Playing = playing;
                try { Say(line); } catch { return 0; }
                if (tick % 2400 == 0) GC.Collect();
            }
            tick++;
            Thread.Sleep(250);
        }
    }
}
''';

  /// Path to the compiled helper, building it on first use. Null when this
  /// Windows has no .NET Framework compiler; the PowerShell script is used then.
  static Future<String?> _helperExe() => buildCsHelper('aod_media_$_csVersion', _cs, refs: const [
        r'{fw}\System.Runtime.dll',
        r'{md}\Windows.Foundation.winmd',
        r'{md}\Windows.Media.winmd',
        r'{md}\Windows.Storage.winmd',
      ]);

  Future<void> start() async {
    if (!Platform.isWindows) return;
    try {
      final dir = Directory.systemTemp.path;
      final exe = await _helperExe();
      if (_disposed) return;
      if (exe != null) {
        _proc = await Process.start(exe, ['$pid', dir]);
        _sub = _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
        _proc!.stderr.drain<void>();
        return;
      }
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
    } catch (e, st) {
      logError(e, st);
    }
  }

  /// 'toggle' | 'next' | 'prev'
  Future<void> send(String cmd) async {
    try {
      await File(_cmdPath).writeAsString(cmd);
    } catch (e, st) {
      logError(e, st);
    }
  }

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.startsWith('V ')) {
      final parts = line.substring(2).split(' ');
      if (parts.length == 5 && !_disposed) {
        onBands?.call([for (final p in parts) (double.tryParse(p) ?? 0).clamp(0.0, 1.0).toDouble()]);
      }
      return;
    }
    if (line.isEmpty || line == _last) return;
    _last = line;
    try {
      final m = jsonDecode(line);
      if (m is! Map) return;
      final title = (m['title'] as String?) ?? '';
      final artist = (m['artist'] as String?) ?? '';
      final status = (m['status'] as String?) ?? '';
      final art = (m['art'] as String?) ?? '';
      final album = (m['album'] as String?) ?? '';
      final app = (m['app'] as String?) ?? '';
      final posMs = (m['posMs'] as num?)?.toInt() ?? 0;
      final durMs = (m['durMs'] as num?)?.toInt() ?? 0;
      final at = (m['at'] as num?)?.toInt() ?? 0;
      final pos = Duration(milliseconds: posMs), len = Duration(milliseconds: durMs);
      final posAt = at > 0 ? DateTime.fromMillisecondsSinceEpoch(at) : null;
      if (title.isEmpty && artist.isEmpty) {
        _emit(null);
      } else {
        final k = '$title|$artist';
        var path = art.isEmpty ? null : art;
        if (path == null && _fbKey == k) path = _fbPath;
        _emit(NowPlaying(title, artist, status == 'Playing', path, album, app, pos, len, posAt));
        if (path == null && _fbKey != k && title.isNotEmpty) _lookupArt(title, artist, k);
      }
    } catch (e, st) {
      logError(e, st);
    }
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
        } catch (e, st) {
          logError(e, st);
        }
      }
      final cur = _cur;
      if (cur != null && cur.key == key && cur.art == null) {
        _emit(NowPlaying(
            cur.title, cur.artist, cur.playing, f.path, cur.album, cur.app, cur.position, cur.length, cur.positionAt));
      }
    } catch (e, st) {
      logError(e, st);
    }
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _proc?.kill();
  }
}
