import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../foreground_app.dart';
import '../process_link.dart';
import 'annotation_model.dart';
import 'overlay_win32.dart';
import 'vision_agent.dart';

enum Tool { mouse, pen, highlighter, line, arrow, rect, ellipse, stamp, text, eraser, pixelEraser }

const kInkColors = <Color>[
  Color(0xFFFF3B30),
  Color(0xFFFFD60A),
  Color(0xFF34C759),
  Color(0xFF0A84FF),
  Color(0xFFFFFFFF),
  Color(0xFF1C1C1E),
];

/// The annotation overlay as its own process (`--overlay`): a transparent,
/// always-on-top window over the monitor the cursor was on when it started.
/// The island starts it on demand, and closing it frees everything it used.
///
/// With the Mouse tool the window lets every click through to the apps
/// underneath except over the toolbar and the Ask panel; with any drawing
/// tool it takes the pointer. Holding Ctrl while drawing lets clicks
/// through for a moment.
class OverlayShell extends ChangeNotifier {
  final AnnotationStore store = AnnotationStore();
  late final VisionAgent agent = VisionAgent(store);

  LinkServer? _server;
  Timer? _poll, _idleExit;
  bool _interactive = false, _ticking = false;
  int _n = 0;

  // ---- what the toolbar shows
  Tool tool = Tool.mouse;
  Color color = kInkColors.first;
  double width = 4; // 2 | 4 | 8
  StampKind stamp = StampKind.check;
  bool askOpen = false;
  bool shown = true;

  /// Bumped to pull focus into the Ask field.
  final ValueNotifier<int> askFocus = ValueNotifier(0);

  /// The screen's toolbar, panel and text editor, in window coordinates.
  List<Rect> Function() uiRegions = () => const [];

  /// True while a stroke is down or text is being typed (no Ctrl pass-through).
  bool busyDrawing = false;

  /// Last app in front that wasn't us; told to the AI.
  String? lastApp;

  bool get drawing => tool != Tool.mouse;

  Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// Single-instance lock. False if an overlay already runs (it was told to show).
  Future<bool> claim({bool ask = false}) async {
    _server = await LinkServer.bind(kOverlayPort, _onMessage);
    if (_server == null) await LinkServer.sendOnce(kOverlayPort, {'t': ask ? 'ask' : 'show'});
    return _server != null;
  }

  Future<void> init({bool ask = false}) async {
    await agent.loadKey();
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      title: 'AOD Overlay',
    );
    // main.cpp already sized it to the whole monitor.
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await _try(() => windowManager.setHasShadow(false));
      await _try(() => windowManager.setResizable(false));
      await _try(() => windowManager.setIgnoreMouseEvents(true, forward: true));
      await windowManager.show(inactive: true);
    });
    if (ask) openAsk();
    _poll = Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
  }

  void _onMessage(Map<String, dynamic> m, LinkPeer from) {
    switch ('${m['t']}') {
      case 'show':
        show();
      case 'toggle':
        shown ? hide() : show();
      case 'ask':
        show();
        openAsk();
      case 'quit':
        quit();
    }
  }

  // ---- toolbar state

  void setTool(Tool t) {
    if (t == Tool.stamp && tool == Tool.stamp) {
      // Clicking Stamp again cycles the stamp.
      stamp = StampKind.values[(stamp.index + 1) % StampKind.values.length];
    }
    tool = t;
    if (t != Tool.mouse) _try(() => windowManager.focus()); // keys (undo, Esc, text) come to us
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    if (tool == Tool.mouse || tool == Tool.eraser || tool == Tool.pixelEraser) setTool(Tool.pen);
    notifyListeners();
  }

  void setWidth(double w) {
    width = w;
    notifyListeners();
  }

  void openAsk() {
    askOpen = true;
    _try(() => windowManager.focus());
    askFocus.value++;
    notifyListeners();
  }

  void toggleAsk() => askOpen ? closeAsk() : openAsk();

  void closeAsk() {
    askOpen = false;
    notifyListeners();
  }

  // ---- visibility and lifetime

  Future<void> show() async {
    _idleExit?.cancel();
    if (shown) return;
    shown = true;
    await _try(() => windowManager.show(inactive: true));
    await _try(() => windowManager.setAlwaysOnTop(true));
    notifyListeners();
  }

  /// Hides but keeps the drawing; an overlay left hidden for a while quits.
  Future<void> hide() async {
    if (!shown) return;
    shown = false;
    tool = Tool.mouse;
    agent.cancel();
    notifyListeners();
    await _try(() => windowManager.hide());
    _idleExit?.cancel();
    _idleExit = Timer(const Duration(minutes: 5), quit);
    trimMemory();
  }

  Future<void> quit() async {
    _poll?.cancel();
    _idleExit?.cancel();
    agent.cancel();
    await _server?.close();
    await shutdownWindow();
  }

  // ---- pointer pass-through

  Future<void> _tick() async {
    if (_ticking || !shown) return;
    _ticking = true;
    try {
      _n++;
      final r = OverlayWin32.windowRect();
      if (r == null) return;
      final local = (OverlayWin32.cursor() - r.topLeft) / _dpr;
      final overUi = uiRegions().any((x) => x.inflate(4).contains(local));
      final ctrlPeek = OverlayWin32.keyDown(0x11) && !busyDrawing && !OverlayWin32.keyDown(0x10);
      final want = overUi || (drawing && !ctrlPeek);
      if (want != _interactive) {
        _interactive = want;
        await _try(() => windowManager.setIgnoreMouseEvents(!want, forward: true));
      }
      if (_n % 12 == 0) {
        final fg = ForegroundApp.current();
        if (fg != null && fg != ForegroundApp.own) lastApp = fg;
      }
    } catch (_) {
    } finally {
      _ticking = false;
    }
  }

  double get _dpr => ui.PlatformDispatcher.instance.views.firstOrNull?.devicePixelRatio ?? 1;

  // ---- capture for the AI

  /// Grabs the monitor under the overlay (without the overlay), draws your
  /// annotations on it, and shrinks it to what the model reads well.
  Future<ScreenCapture?> capture() async {
    final r = OverlayWin32.windowRect();
    if (r == null) return null;
    final dpr = _dpr;
    final logical = r.size / dpr;

    OverlayWin32.excludeFromCapture(true);
    ui.Image? shot;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 90)); // let DWM drop us from the frame
      shot = await OverlayWin32.grab(r);
    } finally {
      OverlayWin32.excludeFromCapture(false);
    }
    if (shot == null) return null;

    final user = recordShapes(store.shapes(Layer.user), logical);
    try {
      for (final maxEdge in const [1568.0, 1200.0, 900.0]) {
        final k = math.min(1.0, maxEdge / math.max(r.width, r.height));
        final w = (r.width * k).round(), h = (r.height * k).round();
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.drawImageRect(
          shot,
          Offset.zero & Size(shot.width.toDouble(), shot.height.toDouble()),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.medium,
        );
        final s = k * dpr; // logical overlay px -> image px
        c.scale(s);
        c.drawPicture(user);
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        pic.dispose();
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        if (data == null) return null;
        final png = data.buffer.asUint8List();
        if (png.length > 3600000 && maxEdge > 900) continue; // stay under the API's image limit
        return ScreenCapture(
          png: png,
          width: w,
          height: h,
          toLogical: 1 / s,
          overlay: logical,
          annotations: [for (final a in store.describeUser()) _scaleMap(a, s)],
          app: lastApp,
        );
      }
      return null;
    } finally {
      user.dispose();
      shot.dispose();
    }
  }

  /// Overlay coordinates in an annotation description -> image pixels.
  static Map<String, dynamic> _scaleMap(Map<String, dynamic> m, double s) => {
        for (final e in m.entries) e.key: e.key == 'step' ? e.value : _scale(e.value, s),
      };

  static Object? _scale(Object? v, double s) => switch (v) {
        num n => (n * s).round(),
        List l => [for (final x in l) _scale(x, s)],
        _ => v,
      };

  @override
  void dispose() {
    _poll?.cancel();
    _idleExit?.cancel();
    agent.dispose();
    store.dispose();
    askFocus.dispose();
    super.dispose();
  }
}
