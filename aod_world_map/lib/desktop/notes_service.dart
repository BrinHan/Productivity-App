import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_files.dart';
import 'meeting_detector.dart';
import 'notes_model.dart';
import 'window_scan.dart';

enum RecState { idle, recording, paused, finishing }

class _Chunk {
  _Chunk(this.path, this.note, this.at);
  final String path;
  final MeetingNote note;
  final DateTime at;
}

/// Watches for meetings, records the meeting app's own audio through a small
/// helper (WASAPI process loopback), and transcribes it on this computer with
/// whisper.cpp. Notes are saved as JSON files under %APPDATA%\AodWorldMap\notes.
class NotesService extends ChangeNotifier {
  /// [remote]: the app window's copy. The island process records; this one
  /// mirrors its state through [applySnapshot] and forwards the buttons
  /// through [send].
  NotesService({this.remote = false});
  final bool remote;
  bool Function(Map<String, dynamic>)? send;

  final List<MeetingNote> notes = [];
  MeetingNote? active;
  MeetingInfo? current, detected;
  RecState state = RecState.idle;
  String? error, status;
  void Function(MeetingInfo)? onOffer;

  /// Ticks about 10 times a second while recording (elapsed time, levels).
  final ValueNotifier<int> tick = ValueNotifier(0);
  final List<double> levels = List<double>.filled(56, 0.0, growable: true);

  Timer? _watch, _clock, _saveTimer, _readyTimer;
  Process? _proc;
  StreamSubscription<String>? _out;
  Completer<void> _done = Completer<void>();
  bool _gotReady = false, _working = false, _stopping = false;
  final List<_Chunk> _queue = [];
  final Map<String, DateTime> _seen = {};
  final Set<String> _asked = {};
  Directory? _chunkDir;
  File? _cmd;
  DateTime? _pauseAt;
  Duration _pausedFor = Duration.zero;
  String _stderr = '';

  bool get recording => state != RecState.idle;

  Duration get elapsed {
    final n = active;
    if (n == null) return Duration.zero;
    final end = state == RecState.paused ? (_pauseAt ?? DateTime.now()) : DateTime.now();
    final d = end.difference(n.startedAt) - _pausedFor;
    return d.isNegative ? Duration.zero : d;
  }

  // ------------------------------------------------------------- paths

  static String get _s => Platform.pathSeparator;

  static Directory get whisperDir => appDataFolder('whisper');
  static Directory get notesDir => appDataFolder('notes');

  String get _exe => '${whisperDir.path}${_s}whisper-cli.exe';
  String get _model => '${whisperDir.path}${_s}ggml-base.en.bin';

  bool get ready => File(_exe).existsSync() && File(_model).existsSync();

  // ----------------------------------------------------------- storage

  Future<void> loadNotes() => _loadNotes();

  Future<void> _loadNotes() async {
    try {
      final d = notesDir;
      if (!await d.exists()) return;
      final out = <MeetingNote>[];
      await for (final f in d.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final j = jsonDecode(await f.readAsString());
          if (j is Map<String, dynamic>) out.add(MeetingNote.fromJson(j));
        } catch (_) {}
      }
      out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      // The live note comes from the island, not from its half-written file.
      final live = active;
      if (live != null) {
        out
          ..removeWhere((x) => x.id == live.id)
          ..insert(0, live);
      }
      notes
        ..clear()
        ..addAll(out);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save(MeetingNote n) async {
    try {
      final d = notesDir;
      await d.create(recursive: true);
      await File('${d.path}$_s${n.id}.json').writeAsString(jsonEncode(n.toJson()));
    } catch (_) {}
  }

  void setText(MeetingNote n, String v) {
    n.text = v;
    _saveTimer?.cancel();
    // The island is writing the live note's file, so it saves that text too.
    if (remote && n.id == active?.id) {
      _saveTimer = Timer(const Duration(milliseconds: 300), () => _send({'t': 'notes.text', 'id': n.id, 'text': v}));
      return;
    }
    _saveTimer = Timer(const Duration(milliseconds: 500), () => _save(n));
  }

  Future<void> delete(MeetingNote n) async {
    if (n.id == active?.id) return;
    notes.remove(n);
    notifyListeners();
    try {
      final f = File('${notesDir.path}$_s${n.id}.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // --------------------------------------------------------- detection

  void startWatching() {
    if (!Platform.isWindows || _watch != null) return;
    _loadNotes();
    _watch = Timer.periodic(const Duration(seconds: 3), (_) => _scan());
  }

  void _scan() {
    final m = MeetingDetector.detect(WindowScan.list());
    final now = DateTime.now();
    if (detected?.key != m?.key) {
      detected = m;
      notifyListeners();
    }
    if (m != null) {
      _seen[m.key] = now;
      if (!recording && !_asked.contains(m.key)) {
        _asked.add(m.key);
        onOffer?.call(m);
      }
    }
    // A meeting that vanished for 90 seconds is over, so a later one asks again.
    _seen.removeWhere((k, t) {
      final gone = now.difference(t).inSeconds > 90;
      if (gone) _asked.remove(k);
      return gone;
    });
    final c = current;
    if (recording && state != RecState.finishing && c != null && c.autoStop) {
      final seen = _seen[c.key];
      if (seen == null || now.difference(seen).inSeconds > 30) stop();
    }
  }

  // --------------------------------------------------------- recording

  // ------------------------------------------------- island <-> app window

  bool _send(Map<String, dynamic> msg) {
    final ok = send?.call(msg) ?? false;
    if (!ok) {
      error = 'The island is not running, so recording is unavailable. Reopen the app to start it.';
      notifyListeners();
    }
    return ok;
  }

  static Map<String, dynamic> _meetingJson(MeetingInfo m) =>
      {'app': m.app.name, 'key': m.key, 'pid': m.pid, 'title': m.title};

  static MeetingInfo? _meeting(Object? j) {
    if (j is! Map) return null;
    final app = MeetingApp.values.where((a) => a.name == j['app']).firstOrNull;
    if (app == null) return null;
    return MeetingInfo(app, '${j['key']}', (j['pid'] as num?)?.toInt() ?? 0, '${j['title'] ?? ''}');
  }

  /// Island side: everything the app window needs to draw the Notes page.
  Map<String, dynamic> snapshot() => {
        't': 'notes',
        'state': state.name,
        'status': status,
        'error': error,
        'detected': detected == null ? null : _meetingJson(detected!),
        'active': active?.toJson(),
        'pausedMs': _pausedFor.inMilliseconds,
        'pauseAt': _pauseAt?.toIso8601String(),
        'levels': [for (final v in levels) (v * 100).round()],
      };

  String _sig = '';

  /// App side: take the island's state.
  void applySnapshot(Map<String, dynamic> j) {
    state = RecState.values.where((s) => s.name == j['state']).firstOrNull ?? RecState.idle;
    status = j['status'] as String?;
    error = j['error'] as String?;
    detected = _meeting(j['detected']);
    _pausedFor = Duration(milliseconds: (j['pausedMs'] as num?)?.toInt() ?? 0);
    final pa = j['pauseAt'] as String?;
    _pauseAt = pa == null ? null : DateTime.tryParse(pa);
    final lv = j['levels'];
    if (lv is List && lv.length == levels.length) {
      for (var i = 0; i < lv.length; i++) {
        levels[i] = ((lv[i] as num?) ?? 0) / 100;
      }
    }
    final was = active;
    final a = j['active'];
    if (a is Map<String, dynamic>) {
      final n = MeetingNote.fromJson(a);
      // Keep what is being typed here; the island only echoes it back.
      final local = notes.where((x) => x.id == n.id).firstOrNull;
      if (local != null) {
        n.text = _saveTimer?.isActive == true ? local.text : n.text;
        notes[notes.indexOf(local)] = n;
      } else {
        notes.insert(0, n);
      }
      active = n;
    } else {
      active = null;
    }
    tick.value++;
    // Level updates arrive ten times a second; rebuild the page only when
    // something other than the level line changed.
    final sig = '${state.name}|$status|$error|${detected?.key}|${active?.id}|${active?.segments.length}';
    if (sig != _sig) {
      _sig = sig;
      notifyListeners();
    }
    if (was != null && active == null) _loadNotes(); // the finished note is on disk now
  }

  /// Island side: a button pressed in the app window.
  void handleCommand(Map<String, dynamic> j) {
    switch (j['t']) {
      case 'notes.start':
        final m = _meeting(j['m']);
        if (m != null) start(m);
      case 'notes.stop':
        stop();
      case 'notes.pause':
        pause();
      case 'notes.resume':
        resume();
      case 'notes.text':
        final n = active;
        if (n != null && n.id == j['id']) setText(n, '${j['text'] ?? ''}');
    }
  }

  Future<bool> start(MeetingInfo m) async {
    if (remote) return _send({'t': 'notes.start', 'm': _meetingJson(m)});
    if (recording) return false;
    error = null;
    if (!Platform.isWindows) {
      error = 'Meeting notes work on Windows only.';
      notifyListeners();
      return false;
    }
    if (!ready) {
      error = 'Transcription is not set up yet. Install the speech model once, then try again.';
      notifyListeners();
      return false;
    }
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}';
    final note = MeetingNote(id: id, title: '${m.appName} meeting', app: m.appName, startedAt: now);
    notes.insert(0, note);
    active = note;
    current = m;
    state = RecState.recording;
    status = 'Starting...';
    _gotReady = false;
    _stopping = false;
    _stderr = '';
    _pausedFor = Duration.zero;
    _pauseAt = null;
    _done = Completer<void>();
    levels.fillRange(0, levels.length, 0.0);
    final tmp = Directory.systemTemp.path;
    _chunkDir = Directory('$tmp${_s}orbit_chunks_$id')..createSync(recursive: true);
    _cmd = File('$tmp${_s}orbit_cap_cmd.txt');
    try {
      if (_cmd!.existsSync()) _cmd!.deleteSync();
    } catch (_) {}
    notifyListeners();

    try {
      final script = File('$tmp${_s}orbit_capture.ps1');
      await script.writeAsString(_script);
      final p = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-MTA',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '${m.pid}',
        _chunkDir!.path,
        '$pid',
        _cmd!.path,
      ]);
      _proc = p;
      _out = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
      p.stderr.transform(utf8.decoder).listen((e) {
        if (_stderr.length < 2000) _stderr += e;
      });
      unawaited(p.exitCode.then(_onExit));
    } catch (e) {
      _failStart('Could not start audio capture: $e');
      return false;
    }
    _readyTimer = Timer(const Duration(seconds: 25), () {
      if (!_gotReady && recording) {
        _failStart('Audio capture did not start. It needs Windows 10 version 2004 or newer. ${_stderr.trim()}');
      }
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
    return true;
  }

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    if (line == 'READY') {
      _gotReady = true;
      status = 'Listening';
      notifyListeners();
    } else if (line == 'DONE') {
      if (!_done.isCompleted) _done.complete();
    } else if (line.startsWith('ERR ')) {
      _failStart(line.substring(4));
    } else if (line.startsWith('L ')) {
      final v = double.tryParse(line.substring(2)) ?? 0.0;
      levels
        ..removeAt(0)
        ..add(state == RecState.paused ? 0.0 : v);
      tick.value++;
    } else if (line.startsWith('C|')) {
      final p = line.split('|');
      if (p.length >= 3) _enqueue(p[1], double.tryParse(p[2]) ?? 0.0);
    }
  }

  void _onExit(int code) {
    if (!_done.isCompleted) _done.complete();
    if (_stopping || !recording) return;
    if (!_gotReady) {
      _failStart('Audio capture exited ($code). ${_stderr.trim()}');
      return;
    }
    error = 'Audio capture stopped unexpectedly.';
    stop();
  }

  void _failStart(String msg) {
    if (!recording) return;
    error = msg;
    _stopping = true;
    _proc?.kill();
    _proc = null;
    _out?.cancel();
    _out = null;
    _queue.clear();
    final n = active;
    if (n != null) {
      if (n.segments.isEmpty) {
        notes.remove(n);
      } else {
        n.endedAt ??= DateTime.now();
        _save(n);
      }
    }
    _cleanup();
    notifyListeners();
  }

  void pause() {
    if (remote) {
      _send({'t': 'notes.pause'});
      return;
    }
    if (state != RecState.recording) return;
    state = RecState.paused;
    _pauseAt = DateTime.now();
    notifyListeners();
  }

  void resume() {
    if (remote) {
      _send({'t': 'notes.resume'});
      return;
    }
    if (state != RecState.paused) return;
    final at = _pauseAt;
    if (at != null) _pausedFor += DateTime.now().difference(at);
    _pauseAt = null;
    state = RecState.recording;
    notifyListeners();
  }

  Future<void> stop() async {
    if (remote) {
      _send({'t': 'notes.stop'});
      return;
    }
    if (!recording || state == RecState.finishing) return;
    final note = active;
    _stopping = true;
    state = RecState.finishing;
    status = 'Finishing transcript...';
    notifyListeners();
    try {
      await _cmd?.writeAsString('stop');
    } catch (_) {}
    final p = _proc;
    if (p != null) {
      await Future.any<void>([_done.future, Future<void>.delayed(const Duration(seconds: 6))]);
      p.kill();
    }
    _proc = null;
    await _out?.cancel();
    _out = null;
    final until = DateTime.now().add(const Duration(minutes: 3));
    while ((_working || _queue.isNotEmpty) && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (note != null) {
      note.endedAt = DateTime.now();
      await _save(note);
    }
    _cleanup();
    notifyListeners();
  }

  void _cleanup() {
    _clock?.cancel();
    _readyTimer?.cancel();
    try {
      _chunkDir?.deleteSync(recursive: true);
    } catch (_) {}
    active = null;
    current = null;
    state = RecState.idle;
    status = null;
    _pauseAt = null;
    levels.fillRange(0, levels.length, 0.0);
    tick.value++;
  }

  // ----------------------------------------------------- transcription

  void _enqueue(String path, double rms) {
    final n = active;
    if (n == null || state == RecState.paused || rms < 0.004) {
      _delete(path);
      return;
    }
    _queue.add(_Chunk(path, n, DateTime.now()));
    _pump();
  }

  void _delete(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  Future<void> _pump() async {
    if (_working) return;
    _working = true;
    try {
      while (_queue.isNotEmpty) {
        final c = _queue.removeAt(0);
        final text = await _transcribe(c.path);
        _delete(c.path);
        if (text.isEmpty) continue;
        final at = c.at.difference(c.note.startedAt).inSeconds - 10;
        c.note.segments.add(NoteSegment(at < 0 ? 0 : at, text));
        await _save(c.note);
        notifyListeners();
      }
    } finally {
      _working = false;
    }
  }

  Future<String> _transcribe(String wav) async {
    try {
      final r = await Process.run(
        _exe,
        ['-m', _model, '-f', wav, '-nt', '-np', '-l', 'en', '-t', '4'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
        workingDirectory: whisperDir.path,
      );
      if (r.exitCode != 0) {
        error = 'The speech model failed: ${(r.stderr as String).trim().split('\n').first}';
        notifyListeners();
        return '';
      }
      return _clean(r.stdout as String);
    } catch (e) {
      error = 'The speech model could not run: $e';
      notifyListeners();
      return '';
    }
  }

  static String _clean(String s) {
    final t = s
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Whisper invents these on near-silence.
    const junk = {'you', 'thanks for watching!', 'thank you for watching!'};
    return junk.contains(t.toLowerCase()) ? '' : t;
  }

  @override
  void dispose() {
    _watch?.cancel();
    _clock?.cancel();
    _saveTimer?.cancel();
    _readyTimer?.cancel();
    _proc?.kill();
    tick.dispose();
    super.dispose();
  }

  // ------------------------------------------------------ capture helper

  /// Records ONE app's audio (and its child processes) with WASAPI process
  /// loopback, mixes to 16 kHz mono, and writes 10 second WAV chunks.
  /// stdout: READY | L <level> | C|<wav>|<rms> | DONE | ERR <message>
  static const _script = r'''
param([int]$TargetPid, [string]$OutDir, [int]$ParentPid, [string]$CmdFile)
$ErrorActionPreference = 'Stop'
$src = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace Orbit
{
  [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IActivateAudioInterfaceAsyncOperation
  {
    void GetActivateResult(out int activateResult, [MarshalAs(UnmanagedType.IUnknown)] out object activatedInterface);
  }

  [ComImport, Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IActivateAudioInterfaceCompletionHandler
  {
    void ActivateCompleted(IActivateAudioInterfaceAsyncOperation activateOperation);
  }

  [ComImport, Guid("94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IAgileObject { }

  [ComImport, Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IAudioClient
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
  public interface IAudioCaptureClient
  {
    [PreserveSig] int GetBuffer(out IntPtr data, out uint numFrames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
    [PreserveSig] int ReleaseBuffer(uint numFrames);
    [PreserveSig] int GetNextPacketSize(out uint numFrames);
  }

  [ComVisible(true)]
  public class Handler : IActivateAudioInterfaceCompletionHandler, IAgileObject
  {
    public ManualResetEvent Done = new ManualResetEvent(false);
    public int Hr = -1;
    public object Client;

    public void ActivateCompleted(IActivateAudioInterfaceAsyncOperation op)
    {
      int hr;
      object o;
      op.GetActivateResult(out hr, out o);
      Hr = hr;
      Client = o;
      Done.Set();
    }
  }

  public static class Capture
  {
    static readonly Guid IidClient = new Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2");
    static readonly Guid IidCapture = new Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317");

    [DllImport("Mmdevapi.dll", ExactSpelling = true, PreserveSig = false)]
    static extern void ActivateAudioInterfaceAsync(
      [MarshalAs(UnmanagedType.LPWStr)] string deviceInterfacePath,
      [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
      IntPtr activationParams,
      IActivateAudioInterfaceCompletionHandler completionHandler,
      out IActivateAudioInterfaceAsyncOperation activationOperation);

    static void Say(string s)
    {
      Console.Out.WriteLine(s);
      Console.Out.Flush();
    }

    static IAudioClient Activate(uint pid)
    {
      IntPtr ap = Marshal.AllocHGlobal(12);
      Marshal.WriteInt32(ap, 0, 1);            // PROCESS_LOOPBACK
      Marshal.WriteInt32(ap, 4, (int)pid);     // target process
      Marshal.WriteInt32(ap, 8, 0);            // include the process tree
      IntPtr pv = Marshal.AllocHGlobal(24);    // PROPVARIANT (x64)
      for (int i = 0; i < 24; i++) Marshal.WriteByte(pv, i, 0);
      Marshal.WriteInt16(pv, 0, (short)65);    // VT_BLOB
      Marshal.WriteInt32(pv, 8, 12);
      Marshal.WriteIntPtr(pv, 16, ap);
      Handler h = new Handler();
      IActivateAudioInterfaceAsyncOperation op;
      ActivateAudioInterfaceAsync("VAD\\Process_Loopback", IidClient, pv, h, out op);
      if (!h.Done.WaitOne(8000)) throw new Exception("activation timed out");
      if (h.Hr < 0) throw new Exception("activation failed 0x" + h.Hr.ToString("X"));
      return (IAudioClient)h.Client;
    }

    static bool Alive(int pid)
    {
      try
      {
        Process p = Process.GetProcessById(pid);
        return !p.HasExited;
      }
      catch (Exception)
      {
        return false;
      }
    }

    static void WriteChunk(string dir, int idx, List<short> samples, double sq, int n)
    {
      string path = Path.Combine(dir, "chunk_" + idx.ToString("0000") + ".wav");
      int dataLen = samples.Count * 2;
      using (FileStream fs = new FileStream(path, FileMode.Create))
      using (BinaryWriter w = new BinaryWriter(fs))
      {
        w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
        w.Write(36 + dataLen);
        w.Write(System.Text.Encoding.ASCII.GetBytes("WAVE"));
        w.Write(System.Text.Encoding.ASCII.GetBytes("fmt "));
        w.Write(16);
        w.Write((short)1);
        w.Write((short)1);
        w.Write(16000);
        w.Write(32000);
        w.Write((short)2);
        w.Write((short)16);
        w.Write(System.Text.Encoding.ASCII.GetBytes("data"));
        w.Write(dataLen);
        byte[] bytes = new byte[dataLen];
        Buffer.BlockCopy(samples.ToArray(), 0, bytes, 0, dataLen);
        w.Write(bytes);
      }
      double rms = n > 0 ? Math.Sqrt(sq / n) / 32768.0 : 0.0;
      Say("C|" + path + "|" + rms.ToString("0.0000", CultureInfo.InvariantCulture));
    }

    public static void Run(int targetPid, string outDir, int parentPid, string cmdFile)
    {
      try
      {
        IntPtr fmt = Marshal.AllocHGlobal(18);   // 48 kHz, stereo, 16-bit PCM
        Marshal.WriteInt16(fmt, 0, (short)1);
        Marshal.WriteInt16(fmt, 2, (short)2);
        Marshal.WriteInt32(fmt, 4, 48000);
        Marshal.WriteInt32(fmt, 8, 192000);
        Marshal.WriteInt16(fmt, 12, (short)4);
        Marshal.WriteInt16(fmt, 14, (short)16);
        Marshal.WriteInt16(fmt, 16, (short)0);

        // Process loopback rejects NOPERSIST with AUDCLNT_E_INVALID_STREAM_FLAG.
        int loop = 0x00020000, evt = 0x00040000;
        int auto = unchecked((int)0x80000000) | 0x08000000;
        int[] flagSets = new int[] { loop | evt | auto, loop | evt };

        AutoResetEvent ev = new AutoResetEvent(false);
        IAudioClient client = null;
        string lastErr = "no attempt";
        for (int i = 0; i < flagSets.Length && client == null; i++)
        {
          try
          {
            IAudioClient c = Activate((uint)targetPid);
            int hr = c.Initialize(0, flagSets[i], 2000000L, 0L, fmt, IntPtr.Zero);
            if (hr != 0) { lastErr = "initialize 0x" + hr.ToString("X"); continue; }
            hr = c.SetEventHandle(ev.SafeWaitHandle.DangerousGetHandle());
            if (hr != 0) { lastErr = "event 0x" + hr.ToString("X"); continue; }
            client = c;
          }
          catch (Exception e)
          {
            lastErr = e.Message;
          }
        }
        if (client == null) { Say("ERR " + lastErr); return; }

        Guid gc = IidCapture;
        object svc;
        int hr2 = client.GetService(ref gc, out svc);
        if (hr2 != 0) { Say("ERR capture service 0x" + hr2.ToString("X")); return; }
        IAudioCaptureClient cap = (IAudioCaptureClient)svc;
        hr2 = client.Start();
        if (hr2 != 0) { Say("ERR start 0x" + hr2.ToString("X")); return; }
        Say("READY");

        List<short> pending = new List<short>(170000);
        int chunkIdx = 0, acc = 0, accN = 0, chunkN = 0;
        double chunkSq = 0, peak = 0;
        DateTime lastLevel = DateTime.UtcNow, lastCheck = DateTime.UtcNow;
        bool stop = false;

        while (!stop)
        {
          ev.WaitOne(100);
          uint size;
          while (cap.GetNextPacketSize(out size) == 0 && size > 0)
          {
            IntPtr data;
            uint frames, flags;
            ulong dp, qp;
            if (cap.GetBuffer(out data, out frames, out flags, out dp, out qp) != 0) break;
            int n = (int)frames;
            if (n > 0)
            {
              short[] buf = new short[n * 2];
              if ((flags & 2) == 0 && data != IntPtr.Zero) Marshal.Copy(data, buf, 0, n * 2);
              for (int f = 0; f < n; f++)
              {
                acc += buf[f * 2] + buf[f * 2 + 1];
                accN += 2;
                if (accN == 6)
                {
                  short s = (short)(acc / 6);
                  pending.Add(s);
                  chunkSq += (double)s * (double)s;
                  chunkN++;
                  double a = Math.Abs((double)s);
                  if (a > peak) peak = a;
                  acc = 0;
                  accN = 0;
                }
              }
            }
            cap.ReleaseBuffer(frames);
          }

          DateTime now = DateTime.UtcNow;
          if ((now - lastLevel).TotalMilliseconds >= 100)
          {
            double lv = Math.Min(1.0, peak / 32768.0 * 3.0);
            Say("L " + lv.ToString("0.000", CultureInfo.InvariantCulture));
            peak = 0;
            lastLevel = now;
          }
          if (pending.Count >= 160000)
          {
            chunkIdx++;
            WriteChunk(outDir, chunkIdx, pending, chunkSq, chunkN);
            pending.Clear();
            chunkSq = 0;
            chunkN = 0;
          }
          if ((now - lastCheck).TotalSeconds >= 2)
          {
            lastCheck = now;
            if (!Alive(parentPid)) break;
            if (File.Exists(cmdFile))
            {
              string cmd = "";
              try { cmd = File.ReadAllText(cmdFile).Trim(); } catch (Exception) { }
              if (cmd == "stop") stop = true;
            }
          }
        }

        if (pending.Count >= 16000)
        {
          chunkIdx++;
          WriteChunk(outDir, chunkIdx, pending, chunkSq, chunkN);
        }
        try { client.Stop(); } catch (Exception) { }
        Say("DONE");
      }
      catch (Exception e)
      {
        Say("ERR " + e.Message);
      }
    }
  }
}
'@
try {
  Add-Type -TypeDefinition $src -Language CSharp
  [Orbit.Capture]::Run($TargetPid, $OutDir, $ParentPid, $CmdFile)
} catch {
  [Console]::Out.WriteLine('ERR ' + $_.Exception.Message)
  [Console]::Out.Flush()
}
''';
}
