import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app_files.dart';
import '../foreground_app.dart';
import '../process_link.dart';
import 'annotation_model.dart';
import 'overlay_win32.dart';
import 'vision_agent.dart';

enum Tool { mouse, pen, highlighter, vanish, line, arrow, rect, ellipse, stamp, text, eraser, pixelEraser }

/// Toolbar buttons that hold several tools. Click one to pick its last-used
/// tool; click it again for a flyout with its types, colour and thickness.
/// Each group keeps its own colour and thickness.
enum ToolGroup { pen, shape, stamp, text, eraser }

const kGroupTools = <ToolGroup, List<Tool>>{
  ToolGroup.pen: [Tool.pen, Tool.highlighter, Tool.vanish],
  ToolGroup.shape: [Tool.line, Tool.arrow, Tool.rect, Tool.ellipse],
  ToolGroup.stamp: [Tool.stamp],
  ToolGroup.text: [Tool.text],
  ToolGroup.eraser: [Tool.eraser, Tool.pixelEraser],
};

ToolGroup? groupOf(Tool t) {
  for (final e in kGroupTools.entries) {
    if (e.value.contains(t)) return e.key;
  }
  return null;
}

/// The screen edge the toolbar is docked to. Left and right stand it upright.
enum Dock { top, bottom, left, right }

/// The three stroke widths the toolbar offers.
const kInkWidths = <double>[1.5, 3, 6];

const kInkColors = <Color>[
  Color(0xFFFF3B30),
  Color(0xFFFFD60A),
  Color(0xFF34C759),
  Color(0xFF0A84FF),
  Color(0xFFFFFFFF),
  Color(0xFF1C1C1E),
];

/// The annotation overlay as its own process (`--overlay`): a transparent,
/// always-on-top window over the monitor the cursor is on.
///
/// Starting a Flutter process takes a second or two, so the island keeps one
/// waiting hidden (`--standby`) and opening it is only a show. Closing it
/// wipes the drawing and hides it again, ready for next time.
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
  Dock dock = Dock.bottom;

  /// Per group: the tool it picks, its colour and its thickness.
  final Map<ToolGroup, Tool> lastTool = {for (final e in kGroupTools.entries) e.key: e.value.first};
  final Map<ToolGroup, Color> colors = {for (final g in ToolGroup.values) g: kInkColors.first};
  final Map<ToolGroup, double> widths = {for (final g in ToolGroup.values) g: kInkWidths[1]};

  ToolGroup? get group => groupOf(tool);

  /// The colour and thickness the current tool draws with.
  Color get color => colors[group ?? ToolGroup.pen]!;
  double get width => widths[group ?? ToolGroup.pen]!;
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

  /// Single-instance lock. False if an overlay already runs (it was told to
  /// show, unless this one was only meant to wait in standby).
  Future<bool> claim({bool ask = false, bool standby = false}) async {
    _server = await LinkServer.bind(kOverlayPort, _onMessage);
    if (_server == null && !standby) await LinkServer.sendOnce(kOverlayPort, {'t': ask ? 'ask' : 'show'});
    return _server != null;
  }

  /// [standby]: start hidden and wait to be shown.
  Future<void> init({bool ask = false, bool standby = false}) async {
    shown = !standby;
    await agent.loadKey();
    await _loadPrefs();
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      title: 'Meridian Overlay',
    );
    // main.cpp already sized it to the whole monitor.
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await _try(() => windowManager.setHasShadow(false));
      await _try(() => windowManager.setResizable(false));
      await _clickThrough(true);
      if (!standby) await windowManager.show(inactive: true);
    });
    if (standby) {
      // main.cpp showed it off-screen, since Flutter never draws into a
      // window that was hidden for its first frames. Once they (after
      // runApp) have landed, hide it; show() moves it back on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer(const Duration(milliseconds: 300), () async {
          if (!shown) await _try(() => windowManager.hide());
          trimMemory();
        });
      });
    }
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
    tool = t;
    final g = groupOf(t);
    if (g != null && lastTool[g] != t) {
      lastTool[g] = t;
      _savePrefs();
    }
    if (t != Tool.mouse) _try(() => windowManager.focus()); // keys (undo, Esc, text) come to us
    notifyListeners();
  }

  void setStamp(StampKind k) {
    stamp = k;
    setTool(Tool.stamp);
  }

  /// Changing a group's colour or size also picks that group.
  void setColor(ToolGroup g, Color c) {
    colors[g] = c;
    _pick(g);
  }

  void setWidth(ToolGroup g, double w) {
    widths[g] = w;
    _pick(g);
  }

  void _pick(ToolGroup g) {
    if (group != g) {
      setTool(lastTool[g]!);
    } else {
      notifyListeners();
    }
    _savePrefs();
  }

  void setDock(Dock d) {
    if (d == dock) return;
    dock = d;
    notifyListeners();
    _savePrefs();
  }

  File get _prefsFile => appDataFile('overlay.json');

  Future<void> _loadPrefs() async {
    try {
      final j = jsonDecode(await _prefsFile.readAsString());
      if (j is! Map) return;
      dock = Dock.values.where((d) => d.name == j['dock']).firstOrNull ?? dock;
      final groups = j['groups'];
      if (groups is! Map) return;
      for (final g in ToolGroup.values) {
        final m = groups[g.name];
        if (m is! Map) continue;
        final t = Tool.values.where((x) => x.name == m['tool']).firstOrNull;
        if (t != null && groupOf(t) == g) lastTool[g] = t;
        if (m['color'] case final int c) colors[g] = Color(c);
        if (m['width'] case final num w when kInkWidths.contains(w.toDouble())) widths[g] = w.toDouble();
      }
    } catch (_) {}
  }

  void _savePrefs() => _try(() async {
        await _prefsFile.parent.create(recursive: true);
        await _prefsFile.writeAsString(jsonEncode({
          'dock': dock.name,
          'groups': {
            for (final g in ToolGroup.values)
              g.name: {'tool': lastTool[g]!.name, 'color': colors[g]!.toARGB32(), 'width': widths[g]},
          },
        }));
      });

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
    OverlayWin32.coverCursorMonitor(); // it may have been waiting on another screen
    await _try(() => windowManager.show(inactive: true));
    await _try(() => windowManager.setAlwaysOnTop(true));
    notifyListeners();
    _repaintAfterShow();
  }

  /// Frames drawn while the window was hidden never reach the screen, and
  /// with nothing changed Flutter would not draw again until the pointer
  /// moved over something. Push a few fresh frames as the window appears.
  void _repaintAfterShow() {
    final b = WidgetsBinding.instance;
    void frame() {
      if (!shown) return;
      for (final v in b.renderViews) {
        v.markNeedsPaint();
      }
      b.scheduleForcedFrame();
    }

    frame();
    for (final ms in const [16, 50, 120, 250]) {
      Timer(Duration(milliseconds: ms), frame);
    }
  }

  /// Hides but keeps the drawing; left hidden for a while, it is wiped.
  Future<void> hide() async {
    if (!shown) return;
    shown = false;
    tool = Tool.mouse;
    agent.cancel();
    notifyListeners();
    await _try(() => windowManager.hide());
    _idleExit?.cancel();
    _idleExit = Timer(const Duration(minutes: 5), _wipe);
    trimMemory();
  }

  /// The toolbar's close: wipe the drawing and go back to standby. The
  /// process stays so the next open is instant.
  Future<void> close() async {
    _wipe();
    // Let the empty frame land before hiding, so the next show never
    // flashes the old drawing.
    await WidgetsBinding.instance.endOfFrame;
    await hide();
    _idleExit?.cancel();
  }

  void _wipe() {
    agent.reset();
    store.reset();
    askOpen = false;
    tool = Tool.mouse;
    notifyListeners();
  }

  /// Ends the process (the island quitting).

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
        await _clickThrough(!want);
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

  Future<void> _clickThrough(bool on) async {
    await _try(() => windowManager.setIgnoreMouseEvents(on, forward: true));
    if (on) OverlayWin32.showLayered();
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
