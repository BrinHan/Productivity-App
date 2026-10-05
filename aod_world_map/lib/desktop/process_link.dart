import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// The app runs as two processes from the same exe:
///
///  * the island (`--island`): always running, small, owns the background
///    work (meeting notes, media helper, tray, Drive backup);
///  * the app window (map / planner): opened and closed at will. Closing it
///    frees everything it used.
///
/// They talk over loopback TCP, one JSON object per line. Each side also
/// holds its port as a single-instance lock.
const kIslandPort = 47811;
const kAppPort = 47812;

typedef LinkHandler = void Function(Map<String, dynamic> msg, LinkPeer from);

class LinkPeer {
  LinkPeer(this._socket);
  final Socket _socket;
  bool _closed = false;

  void send(Map<String, dynamic> msg) {
    if (_closed) return;
    try {
      _socket.write('${jsonEncode(msg)}\n');
    } catch (_) {
      _closed = true;
    }
  }

  void close() {
    _closed = true;
    _socket.destroy();
  }
}

Stream<Map<String, dynamic>> _lines(Socket s) => utf8.decoder
    .bind(s)
    .transform(const LineSplitter())
    .map((l) {
      try {
        final j = jsonDecode(l);
        return j is Map<String, dynamic> ? j : const <String, dynamic>{};
      } catch (_) {
        return const <String, dynamic>{};
      }
    })
    .where((m) => m.isNotEmpty);

class LinkServer {
  LinkServer._(this._server, this._onMessage);
  final ServerSocket _server;
  final LinkHandler _onMessage;
  final Set<LinkPeer> peers = {};
  void Function(LinkPeer)? onConnect;

  /// Null when the port is taken, which means another instance is running.
  static Future<LinkServer?> bind(int port, LinkHandler onMessage) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      final link = LinkServer._(s, onMessage);
      s.listen(link._accept);
      return link;
    } on SocketException {
      return null;
    }
  }

  void _accept(Socket s) {
    final peer = LinkPeer(s);
    peers.add(peer);
    onConnect?.call(peer);
    _lines(s).listen(
      (m) => _onMessage(m, peer),
      onDone: () => peers.remove(peer),
      onError: (_) => peers.remove(peer),
      cancelOnError: true,
    );
  }

  void broadcast(Map<String, dynamic> msg) {
    for (final p in [...peers]) {
      p.send(msg);
    }
  }

  Future<void> close() async {
    for (final p in [...peers]) {
      p.close();
    }
    await _server.close();
  }

  /// Fire one message at whoever holds [port]. False if nobody does.
  static Future<bool> sendOnce(int port, Map<String, dynamic> msg) async {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 600));
      s.write('${jsonEncode(msg)}\n');
      await s.flush();
      await s.close();
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isUp(int port) => sendOnce(port, const {'t': 'ping'});
}

/// Keeps a connection to [port] open, reconnecting while the other side is
/// away. Used by the app window to follow the island.
class LinkClient {
  LinkClient(this.port, this.onMessage, {this.onConnect});
  final int port;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function()? onConnect;

  Socket? _s;
  Timer? _retry;
  bool _stopped = false;
  bool get connected => _s != null;

  void start() => _connect();

  Future<void> _connect() async {
    if (_stopped || _s != null) return;
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
      _s = s;
      onConnect?.call();
      _lines(s).listen(onMessage, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _s?.destroy();
    _s = null;
    if (_stopped) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), _connect);
  }

  bool send(Map<String, dynamic> msg) {
    final s = _s;
    if (s == null) return false;
    try {
      s.write('${jsonEncode(msg)}\n');
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _stopped = true;
    _retry?.cancel();
    _s?.destroy();
    _s = null;
  }
}

/// Starts another copy of this exe, detached, with [args].
Future<void> spawnSelf(List<String> args) async {
  try {
    await Process.start(Platform.resolvedExecutable, args, mode: ProcessStartMode.detached);
  } catch (_) {}
}

/// Watches the app's data folder so a change saved by the other process
/// shows up here. Handlers get the path inside the folder ('planner.json',
/// 'notes\\123.json', ...).
class DataWatch {
  DataWatch(this.dir, this.onChange);
  final Directory dir;
  final void Function(String name) onChange;
  StreamSubscription<FileSystemEvent>? _sub;
  final Map<String, Timer> _debounce = {};

  void start() {
    try {
      dir.createSync(recursive: true);
      _sub = dir.watch(recursive: true).listen((e) {
        if (e.path.length <= dir.path.length) return;
        final name = e.path.substring(dir.path.length + 1);
        // Saves arrive as several events; act once things settle.
        _debounce[name]?.cancel();
        _debounce[name] = Timer(const Duration(milliseconds: 250), () {
          _debounce.remove(name);
          onChange(name);
        });
      });
    } catch (_) {}
  }

  void stop() {
    _sub?.cancel();
    for (final t in _debounce.values) {
      t.cancel();
    }
  }
}

Directory get appDataDir {
  final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
  return Directory('$base${Platform.pathSeparator}AodWorldMap');
}

int Function(int, int, int)? _setWs;
int Function()? _curProc;

/// Hands this process's idle pages back to Windows (what Task Manager shows
/// as memory). Pages that are needed again come back on their own.
void trimMemory() {
  if (!Platform.isWindows) return;
  try {
    if (_setWs == null) {
      final k = ffi.DynamicLibrary.open('kernel32.dll');
      _curProc = k.lookupFunction<ffi.IntPtr Function(), int Function()>('GetCurrentProcess');
      _setWs = k.lookupFunction<ffi.Int32 Function(ffi.IntPtr, ffi.IntPtr, ffi.IntPtr), int Function(int, int, int)>(
          'SetProcessWorkingSetSize');
    }
    _setWs!(_curProc!(), -1, -1);
  } catch (_) {}
}

/// Ends this process. windowManager.destroy() tears the engine down while
/// plugin callbacks are still in flight and crashes in flutter_windows.dll on
/// the way out, so hide the window and exit instead.
Future<void> shutdownWindow() async {
  try {
    await windowManager.hide();
  } catch (_) {}
  exit(0);
}
