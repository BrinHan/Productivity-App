import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'annotation_model.dart';
import 'overlay_shell.dart';
import 'overlay_win32.dart';

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key, required this.shell});
  final OverlayShell shell;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AOD Overlay',
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true, canvasColor: Colors.transparent),
        home: Material(type: MaterialType.transparency, child: OverlayScreen(shell: shell)),
      );
}

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key, required this.shell});
  final OverlayShell shell;

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> with SingleTickerProviderStateMixin {
  OverlayShell get shell => widget.shell;
  AnnotationStore get store => shell.store;

  final _barKey = GlobalKey(), _panelKey = GlobalKey(), _textKey = GlobalKey();
  final _focus = FocusNode();

  // toolbar drag: where the bar's top-left is while it is being dragged
  Offset? _drag;
  Offset _dragFrom = Offset.zero, _dragGrab = Offset.zero, _dragPointer = Offset.zero;
  Size _dragBar = Size.zero;

  // live stroke
  OneEuro? _filter;
  final LiveInk _live = LiveInk();
  Offset _start = Offset.zero;
  bool _invertedEraser = false;

  // text tool
  Offset? _textAt;
  final _text = TextEditingController();
  final _textFocus = FocusNode();

  // AI layer animation: a clock that runs only while something animates
  late final Ticker _ticker = createTicker((_) {
    _clock.value++;
    if (!_animating()) _ticker.stop();
  });
  final ValueNotifier<int> _clock = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    shell.uiRegions = _regions;
    store.addListener(_syncTicker);
    _textFocus.addListener(() {
      if (!_textFocus.hasFocus) _commitText();
    });
  }

  @override
  void dispose() {
    store.removeListener(_syncTicker);
    _ticker.dispose();
    _clock.dispose();
    _live.dispose();
    _focus.dispose();
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  List<Rect> _regions() => [
        for (final k in [_barKey, _panelKey, _textKey])
          if (k.currentContext?.findRenderObject() case final RenderBox b when b.attached)
            b.localToGlobal(Offset.zero) & b.size,
      ];

  bool _animating() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return store.shapes(Layer.ai).any((s) => now - s.born < (s is PulseShape ? PulseShape.pulseMs + 100 : 450));
  }

  void _syncTicker() {
    if (_animating() && !_ticker.isActive) _ticker.start();
  }

  // ---------------------------------------------------------------- input

  bool get _shift => OverlayWin32.keyDown(0x10);

  Tool get _tool => _invertedEraser ? Tool.eraser : shell.tool;
  double get _strokeWidth => shell.tool == Tool.highlighter ? math.max(12, shell.width * 4) : shell.width;
  double get _eraserRadius => math.max(7, shell.width * 3);
  Color get _ink => shell.tool == Tool.highlighter ? shell.color.withValues(alpha: 0.4) : shell.color;

  void _down(PointerDownEvent e) {
    if (!shell.drawing) return;
    if (e.buttons == kSecondaryMouseButton) {
      shell.setTool(Tool.mouse); // right-click: back to the mouse
      return;
    }
    if (_textAt != null) {
      _commitText();
      return;
    }
    final p = e.localPosition;
    _start = p;
    _invertedEraser = e.kind == PointerDeviceKind.invertedStylus; // the pen's eraser end
    shell.busyDrawing = true;
    switch (_tool) {
      case Tool.pen:
      case Tool.highlighter:
      case Tool.pixelEraser:
        _filter = OneEuro();
        final erase = _tool == Tool.pixelEraser;
        _live.begin(
          p,
          color: erase ? const Color(0xFF000000) : _ink,
          width: erase ? _eraserRadius * 2 : _strokeWidth,
          pressure: e.kind == PointerDeviceKind.stylus && shell.tool == Tool.pen ? e.pressure : null,
          highlighter: !erase && shell.tool == Tool.highlighter,
          eraser: erase,
        );
      case Tool.line:
      case Tool.arrow:
      case Tool.rect:
      case Tool.ellipse:
        _updateLive(p);
      case Tool.stamp:
        final steps = store.shapes(Layer.user).whereType<StampShape>().where((s) => s.kind == StampKind.step).length;
        store.add(Layer.user,
            StampShape(color: shell.color, kind: shell.stamp, at: p, size: 18 + shell.width * 4, step: steps + 1));
        shell.busyDrawing = false;
      case Tool.text:
        setState(() => _textAt = p);
        _text.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) => _textFocus.requestFocus());
      case Tool.eraser:
        store.eraseAt(Layer.user, p, _eraserRadius / 2);
      case Tool.mouse:
        shell.busyDrawing = false;
    }
  }

  void _move(PointerMoveEvent e) {
    if (!shell.busyDrawing) return;
    final p = e.localPosition;
    switch (_tool) {
      case Tool.pen:
      case Tool.highlighter:
      case Tool.pixelEraser:
        if (!_live.active) return;
        final f = _filter!.filter(p, e.timeStamp.inMicroseconds / 1e6);
        if ((f - _live.points.last).distance < 0.75) return; // sub-pixel moves add nothing
        _live.add(f, e.pressure);
      case Tool.line:
      case Tool.arrow:
      case Tool.rect:
      case Tool.ellipse:
        _updateLive(p);
      case Tool.eraser:
        store.eraseAt(Layer.user, p, _eraserRadius / 2);
      default:
        break;
    }
  }

  void _up(PointerEvent e) {
    if (!shell.busyDrawing || _textAt != null) return;
    shell.busyDrawing = false;
    final live = store.active.value;
    store.active.value = null;
    final pts = _live.points, pr = _live.pressures;
    switch (_tool) {
      case Tool.pen:
      case Tool.highlighter:
        if (pts.isEmpty) break;
        final keep = simplify(pts, 0.4);
        store.add(
          Layer.user,
          StrokeShape(
            color: _live.color,
            width: _live.width,
            points: [for (final i in keep) pts[i]],
            pressures: pr == null ? null : [for (final i in keep) pr[i]],
            highlighter: _live.highlighter,
          ),
        );
      case Tool.pixelEraser:
        if (pts.isEmpty) break;
        store.add(Layer.user, EraseShape(points: [for (final i in simplify(pts, 0.4)) pts[i]], radius: _live.width / 2));
      case Tool.line:
      case Tool.arrow:
      case Tool.rect:
      case Tool.ellipse:
        if (live != null && live.bounds.longestSide >= 3) store.add(Layer.user, live);
      case Tool.eraser:
        store.commitErase(Layer.user);
      default:
        break;
    }
    _live.end();
    _filter = null;
    _invertedEraser = false;
  }

  /// Rebuilds the in-progress line or box. Only the live painter repaints.
  void _updateLive(Offset to) {
    final c = shell.color, w = _strokeWidth;
    store.active.value = switch (_tool) {
      Tool.line || Tool.arrow =>
        LineShape(color: c, width: w, a: _start, b: _shift ? _snap15(_start, to) : to, arrow: shell.tool == Tool.arrow),
      Tool.rect || Tool.ellipse =>
        RectShape(color: c, width: w, rect: _box(_start, to), ellipse: shell.tool == Tool.ellipse),
      _ => null,
    };
  }

  /// Shift: square/circle. Alt: from the centre.
  Rect _box(Offset a, Offset b) {
    var d = b - a;
    if (_shift) {
      final s = math.max(d.dx.abs(), d.dy.abs());
      d = Offset(s * (d.dx < 0 ? -1 : 1), s * (d.dy < 0 ? -1 : 1));
    }
    if (OverlayWin32.keyDown(0x12)) return Rect.fromCenter(center: a, width: d.dx.abs() * 2, height: d.dy.abs() * 2);
    return Rect.fromPoints(a, a + d);
  }

  static Offset _snap15(Offset a, Offset b) {
    final d = b - a;
    const step = math.pi / 12;
    final ang = (math.atan2(d.dy, d.dx) / step).round() * step;
    return a + Offset(math.cos(ang), math.sin(ang)) * d.distance;
  }

  void _commitText() {
    final at = _textAt;
    if (at == null) return;
    final t = _text.text.trim();
    if (t.isNotEmpty) {
      store.add(Layer.user, TextShape(color: shell.color, at: at, text: t, fontSize: 14 + shell.width * 2));
    }
    _text.clear();
    shell.busyDrawing = false;
    setState(() => _textAt = null);
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus != _focus) return KeyEventResult.ignored; // typing in a field
    final k = HardwareKeyboard.instance;
    final key = e.logicalKey;
    if (k.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        k.isShiftPressed ? store.redo(Layer.user) : store.undo(Layer.user);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        store.redo(Layer.user);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      shell.drawing ? shell.setTool(Tool.mouse) : shell.hide();
      return KeyEventResult.handled;
    }
    final t = const {
      'm': Tool.mouse,
      'p': Tool.pen,
      'h': Tool.highlighter,
      'l': Tool.line,
      'a': Tool.arrow,
      'r': Tool.rect,
      'o': Tool.ellipse,
      's': Tool.stamp,
      't': Tool.text,
      'e': Tool.eraser,
      'x': Tool.pixelEraser,
    }[key.keyLabel.toLowerCase()];
    if (t == null) return KeyEventResult.ignored;
    shell.setTool(t);
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- toolbar dock

  static const _margin = EdgeInsets.fromLTRB(16, 16, 16, 84);

  void _dragStart(DragStartDetails d) {
    final box = _barKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    _dragPointer = _dragGrab = d.globalPosition;
    _dragBar = box.size;
    _dragFrom = box.localToGlobal(Offset.zero);
    setState(() => _drag = _dragFrom);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_drag == null) return;
    final size = MediaQuery.sizeOf(context);
    _dragPointer = d.globalPosition;
    final at = _dragFrom + (_dragPointer - _dragGrab);
    setState(() => _drag = Offset(
          at.dx.clamp(0.0, math.max(0.0, size.width - _dragBar.width)),
          at.dy.clamp(0.0, math.max(0.0, size.height - _dragBar.height)),
        ));
  }

  void _dragEnd() {
    if (_drag == null) return;
    shell.setDock(_nearestDock(_dragPointer, MediaQuery.sizeOf(context)));
    setState(() => _drag = null);
  }

  static Dock _nearestDock(Offset p, Size size) {
    final d = {
      Dock.top: p.dy,
      Dock.bottom: size.height - p.dy,
      Dock.left: p.dx,
      Dock.right: size.width - p.dx,
    };
    return d.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  static Alignment _align(Dock d) => switch (d) {
        Dock.top => Alignment.topCenter,
        Dock.bottom => Alignment.bottomCenter,
        Dock.left => Alignment.centerLeft,
        Dock.right => Alignment.centerRight,
      };

  /// Toolbar plus (when open) the Ask panel, laid out for [dock]: the panel
  /// always sits on the screen side of the bar.
  Widget _dockedBar(Dock dock) {
    final bar = _bar(dock);
    if (!shell.askOpen) return bar;
    final panel = _panel();
    return switch (dock) {
      Dock.top || Dock.bottom => Column(
          mainAxisSize: MainAxisSize.min,
          verticalDirection: dock == Dock.top ? VerticalDirection.down : VerticalDirection.up,
          children: [bar, const SizedBox(height: 8), panel],
        ),
      Dock.left || Dock.right => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: dock == Dock.left ? TextDirection.ltr : TextDirection.rtl,
          children: [bar, const SizedBox(width: 8), panel],
        ),
    };
  }

  /// While dragging: the bar under the cursor, and the Ask panel (same
  /// state, so nothing typed is lost) held on the same side as when docked.
  List<Widget> _draggedBar(Dock dock, Offset at, Size size) => [
        Positioned(left: at.dx, top: at.dy, child: RepaintBoundary(child: _bar(dock))),
        if (shell.askOpen)
          switch (dock) {
            Dock.bottom => Positioned(left: at.dx, bottom: size.height - at.dy + 8, child: _panel()),
            Dock.top => Positioned(left: at.dx, top: at.dy + _dragBar.height + 8, child: _panel()),
            Dock.left => Positioned(left: at.dx + _dragBar.width + 8, top: at.dy, child: _panel()),
            Dock.right => Positioned(right: size.width - at.dx + 8, top: at.dy, child: _panel()),
          },
      ];

  Widget _panel() => _AskPanel(key: _panelKey, shell: shell);

  Widget _bar(Dock dock) => _Toolbar(
      key: _barKey,
      shell: shell,
      axis: dock == Dock.left || dock == Dock.right ? Axis.vertical : Axis.horizontal,
      onDragStart: _dragStart,
      onDragUpdate: _dragUpdate,
      onDragEnd: _dragEnd,
    );

  /// A soft glow on the edge the bar will snap to when you let go.
  Widget _snapHint(Size size) {
    final d = _nearestDock(_dragPointer, size);
    final vertical = d == Dock.left || d == Dock.right;
    return Align(
      alignment: _align(d),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: vertical ? 5 : 220,
          height: vertical ? 220 : 5,
          decoration: BoxDecoration(
            color: const Color(0x99FFFFFF),
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [BoxShadow(color: Color(0x66FFFFFF), blurRadius: 12)],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: shell,
        builder: (context, _) {
          final drag = _drag;
          return MouseRegion(
            cursor: shell.drawing
                ? (shell.tool == Tool.text ? SystemMouseCursors.text : SystemMouseCursors.precise)
                : MouseCursor.defer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: const SizedBox.expand(),
                ),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _UserLayerPainter(store, _live, erasing: shell.tool == Tool.pixelEraser),
                      size: Size.infinite,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _LivePainter(store.active, _live), size: Size.infinite),
                  ),
                ),
                IgnorePointer(
                  child: RepaintBoundary(child: CustomPaint(painter: _AiPainter(store, _clock), size: Size.infinite)),
                ),
                if (_textAt != null)
                  Positioned(
                    left: _textAt!.dx,
                    top: _textAt!.dy - 6,
                    child: SizedBox(
                      key: _textKey,
                      width: 360,
                      child: TextField(
                        controller: _text,
                        focusNode: _textFocus,
                        cursorColor: shell.color,
                        style:
                            TextStyle(color: shell.color, fontSize: 14 + shell.width * 2, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Type, then Enter',
                          hintStyle: const TextStyle(color: Color(0x88FFFFFF)),
                          filled: true,
                          fillColor: const Color(0x661C1C1E),
                          border: OutlineInputBorder(borderSide: BorderSide(color: shell.color)),
                        ),
                        onSubmitted: (_) => _commitText(),
                      ),
                    ),
                  ),
                if (drag != null) ...[
                  IgnorePointer(child: _snapHint(size)),
                  ..._draggedBar(shell.dock, drag, size),
                ] else
                  Padding(
                    padding: _margin,
                    child: Align(
                      alignment: _align(shell.dock),
                      // Settles into place when it snaps to a new edge.
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(shell.dock),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: 0.4 + 0.6 * t,
                          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                        ),
                        child: RepaintBoundary(child: _dockedBar(shell.dock)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ painters

/// Your layer, recorded into a Picture only when the document changes.
class _UserLayerPainter extends CustomPainter {
  _UserLayerPainter(this.store, this.live, {required this.erasing})
      : super(repaint: erasing ? Listenable.merge([store, live]) : store);
  final AnnotationStore store;
  final LiveInk live;
  final bool erasing;

  @override
  void paint(Canvas canvas, Size size) {
    final s = store.layers[Layer.user]!;
    if (s.dirty || s.cache == null) {
      s.cache?.dispose();
      s.cache = recordShapes(s.shapes, size);
      s.dirty = false;
    }
    if (erasing && live.active && live.eraser) {
      // Preview the pixel eraser cutting through this layer only.
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawPicture(s.cache!);
      live.paint(canvas);
      canvas.restore();
    } else {
      canvas.drawPicture(s.cache!);
    }
  }

  @override
  bool shouldRepaint(_UserLayerPainter old) => old.erasing != erasing || old.store != store || old.live != live;
}

/// What is under the pen right now: a freehand stroke, or a line or box.
class _LivePainter extends CustomPainter {
  _LivePainter(this.active, this.live) : super(repaint: Listenable.merge([active, live]));
  final ValueNotifier<Shape?> active;
  final LiveInk live;

  @override
  void paint(Canvas canvas, Size size) {
    if (live.active && !live.eraser) live.paint(canvas);
    final s = active.value;
    if (s == null || s is EraseShape) return;
    s.paint(canvas, size, 1);
  }

  @override
  bool shouldRepaint(_LivePainter old) => old.active != active || old.live != live;
}

/// The AI layer. Few shapes, animated as they arrive.
class _AiPainter extends CustomPainter {
  _AiPainter(this.store, this.clock) : super(repaint: Listenable.merge([store, clock]));
  final AnnotationStore store;
  final ValueNotifier<int> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = store.shapes(Layer.ai);
    if (shapes.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Spotlights first, so marks sit on top of the dimming.
    for (final s in shapes.whereType<SpotlightShape>()) {
      s.paint(canvas, size, Curves.easeOut.transform(((now - s.born) / 350).clamp(0.0, 1.0)));
    }
    for (final s in shapes) {
      if (s is SpotlightShape) continue;
      s.paint(canvas, size, Curves.easeOutCubic.transform(((now - s.born) / 420).clamp(0.0, 1.0)));
    }
  }

  @override
  bool shouldRepaint(_AiPainter old) => old.store != store;
}

// ------------------------------------------------------------------ toolbar

const _panelBg = Color(0xF21C1C1E);

/// The tool strip. Horizontal on the top and bottom edges; on the left and
/// right it stands upright, top to bottom (wrapping into a second column if
/// the screen is too short for one).
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    super.key,
    required this.shell,
    required this.axis,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });
  final OverlayShell shell;
  final Axis axis;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;

  static const double thickness = 48;

  static IconData stampIcon(StampKind k) => switch (k) {
        StampKind.check => Icons.check_rounded,
        StampKind.cross => Icons.close_rounded,
        StampKind.question => Icons.question_mark_rounded,
        StampKind.star => Icons.star_rounded,
        StampKind.step => Icons.looks_one_rounded,
      };

  Widget _tool(Tool t, IconData icon, String tip) =>
      _Btn(icon: icon, tip: tip, axis: axis, on: shell.tool == t, onTap: () => shell.setTool(t));

  @override
  Widget build(BuildContext context) {
    final s = shell.store;
    final vertical = axis == Axis.vertical;
    final sep = _Sep(axis: axis);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Container(
        padding: vertical ? const EdgeInsets.symmetric(vertical: 6) : const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Wrap(
          direction: axis,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                onPanStart: onDragStart,
                onPanUpdate: onDragUpdate,
                onPanEnd: (_) => onDragEnd(),
                onPanCancel: onDragEnd,
                child: SizedBox(
                  width: vertical ? thickness : 22,
                  height: vertical ? 22 : thickness,
                  child: RotatedBox(
                    quarterTurns: vertical ? 1 : 0,
                    child: const Icon(Icons.drag_indicator_rounded, size: 18, color: Color(0x80FFFFFF)),
                  ),
                ),
              ),
            ),
            _tool(Tool.mouse, Icons.near_me_rounded, 'Mouse: click through (M / Esc)'),
            _tool(Tool.pen, Icons.edit_rounded, 'Pen (P)'),
            _tool(Tool.highlighter, Icons.border_color_rounded, 'Highlighter (H)'),
            _tool(Tool.line, Icons.horizontal_rule_rounded, 'Line (L, Shift snaps)'),
            _tool(Tool.arrow, Icons.north_east_rounded, 'Arrow (A, Shift snaps)'),
            _tool(Tool.rect, Icons.crop_square_rounded, 'Rectangle (R, Shift square, Alt from centre)'),
            _tool(Tool.ellipse, Icons.circle_outlined, 'Ellipse (O)'),
            _tool(Tool.stamp, stampIcon(shell.stamp), 'Stamp (S, click again to change)'),
            _tool(Tool.text, Icons.text_fields_rounded, 'Text (T)'),
            _tool(Tool.eraser, Icons.auto_fix_normal_rounded, 'Eraser: whole marks (E)'),
            _tool(Tool.pixelEraser, Icons.blur_on_rounded, 'Eraser: pixels (X)'),
            sep,
            for (final c in kInkColors)
              _Dot(color: c, axis: axis, on: shell.color.toARGB32() == c.toARGB32(), onTap: () => shell.setColor(c)),
            sep,
            for (final (i, w) in kInkWidths.indexed)
              _Btn(
                tip: 'Width',
                axis: axis,
                on: shell.width == w,
                onTap: () => shell.setWidth(w),
                child: Container(
                  width: 6.0 + 4 * i,
                  height: 6.0 + 4 * i,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            sep,
            _Btn(
                icon: Icons.undo_rounded,
                tip: 'Undo (Ctrl+Z)',
                axis: axis,
                enabled: s.canUndo(Layer.user),
                onTap: () => s.undo(Layer.user)),
            _Btn(
                icon: Icons.redo_rounded,
                tip: 'Redo (Ctrl+Y)',
                axis: axis,
                enabled: s.canRedo(Layer.user),
                onTap: () => s.redo(Layer.user)),
            _Btn(
              icon: Icons.delete_sweep_rounded,
              tip: 'Clear all',
              axis: axis,
              enabled: !s.isEmpty,
              onTap: () {
                s.clear(Layer.user);
                s.dismissAi();
              },
            ),
            sep,
            _Btn(
              icon: Icons.auto_awesome_rounded,
              tip: 'Ask AI about the screen (Ctrl+Shift+Space)',
              axis: axis,
              on: shell.askOpen,
              accent: true,
              onTap: shell.toggleAsk,
            ),
            _Btn(
                icon: Icons.visibility_off_rounded,
                tip: 'Hide (Ctrl+Shift+A brings it back)',
                axis: axis,
                onTap: shell.hide),
            _Btn(icon: Icons.close_rounded, tip: 'Close annotations', axis: axis, onTap: shell.close),
          ],
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep({required this.axis});
  final Axis axis;
  @override
  Widget build(BuildContext context) {
    final h = axis == Axis.horizontal;
    return SizedBox(
      width: h ? 9 : _Toolbar.thickness,
      height: h ? _Toolbar.thickness : 9,
      child: Center(child: Container(width: h ? 1 : 22, height: h ? 22 : 1, color: const Color(0x33FFFFFF))),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    this.icon,
    this.child,
    required this.tip,
    required this.onTap,
    this.on = false,
    this.enabled = true,
    this.accent = false,
    this.axis = Axis.horizontal,
  });
  final Axis axis;
  final IconData? icon;
  final Widget? child;
  final String tip;
  final VoidCallback onTap;
  final bool on, enabled, accent;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled ? const Color(0x40FFFFFF) : (on ? Colors.white : (accent ? kAiColor : const Color(0xCCFFFFFF)));
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            margin: axis == Axis.horizontal
                ? const EdgeInsets.symmetric(horizontal: 1)
                : const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: on ? (accent ? kAiColor.withValues(alpha: 0.45) : const Color(0x33FFFFFF)) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: child ?? Icon(icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.on, required this.onTap, this.axis = Axis.horizontal});
  final Axis axis;
  final Color color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            margin: axis == Axis.horizontal
                ? const EdgeInsets.symmetric(horizontal: 2)
                : const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: on ? Colors.white : const Color(0x55FFFFFF), width: on ? 2.5 : 1),
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------ ask panel

class _AskPanel extends StatefulWidget {
  const _AskPanel({super.key, required this.shell});
  final OverlayShell shell;

  @override
  State<_AskPanel> createState() => _AskPanelState();
}

class _AskPanelState extends State<_AskPanel> {
  final _q = TextEditingController();
  final _key = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _capturing = false;

  OverlayShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    shell.askFocus.addListener(_grabFocus);
    shell.agent.addListener(_follow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _grabFocus());
  }

  @override
  void dispose() {
    shell.askFocus.removeListener(_grabFocus);
    shell.agent.removeListener(_follow);
    _q.dispose();
    _key.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _grabFocus() {
    if (mounted) _focus.requestFocus();
  }

  /// Keep the newest text in view while it streams.
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final q = _q.text.trim();
    if (q.isEmpty || _capturing) return;
    setState(() => _capturing = true);
    final cap = await shell.capture();
    if (!mounted) return;
    setState(() => _capturing = false);
    if (cap == null) {
      shell.agent.fail('Could not capture the screen.');
      return;
    }
    _q.clear();
    await shell.agent.ask(q, cap);
  }

  @override
  Widget build(BuildContext context) {
    final a = shell.agent;
    return ListenableBuilder(
      listenable: Listenable.merge([a, shell.store]),
      builder: (context, _) {
        final hasAi = shell.store.shapes(Layer.ai).isNotEmpty;
        return Container(
          width: 460,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kAiColor.withValues(alpha: 0.35)),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: kAiColor),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Ask about your screen',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  if (a.question.isNotEmpty)
                    _Btn(icon: Icons.add_comment_rounded, tip: 'New conversation', onTap: a.reset),
                  _Btn(icon: Icons.expand_more_rounded, tip: 'Close panel', onTap: shell.closeAsk),
                ],
              ),
              if (!a.hasKey)
                ..._keyEntry()
              else ...[
                if (a.question.isNotEmpty || a.error != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(top: 6, bottom: 6, right: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (a.question.isNotEmpty)
                            Text(a.question, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12.5)),
                          const SizedBox(height: 6),
                          if (a.answer.isNotEmpty)
                            SelectableText(a.answer,
                                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                          if (a.busy && a.answer.isEmpty)
                            const Text('Looking…', style: TextStyle(color: kAiColor, fontSize: 13)),
                          if (a.error != null)
                            Text(a.error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                if (hasAi && !a.busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        _pill('Keep marks', Icons.push_pin_rounded, shell.store.keepAi),
                        const SizedBox(width: 6),
                        _pill('Dismiss', Icons.layers_clear_rounded, shell.store.dismissAi),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _q,
                        focusNode: _focus,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        cursorColor: kAiColor,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: a.question.isEmpty ? 'What am I looking at? How do I…?' : 'Follow up…',
                          hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                          filled: true,
                          fillColor: const Color(0x14FFFFFF),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border:
                              OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (a.busy || _capturing)
                      _Btn(icon: Icons.stop_rounded, tip: 'Stop', accent: true, onTap: a.cancel)
                    else
                      _Btn(icon: Icons.arrow_upward_rounded, tip: 'Ask (Enter)', accent: true, onTap: _send),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String text, IconData icon, VoidCallback onTap) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: Colors.white70),
              const SizedBox(width: 5),
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
      );

  List<Widget> _keyEntry() => [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Paste an Anthropic API key to turn this on. It is saved to %APPDATA%\\AodWorldMap\\anthropic.key '
            '(or set ANTHROPIC_API_KEY).',
            style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12.5),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _key,
                focusNode: _focus,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onSubmitted: shell.agent.saveKey,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'sk-ant-…',
                  hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                  filled: true,
                  fillColor: const Color(0x14FFFFFF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _Btn(
                icon: Icons.check_rounded,
                tip: 'Save key',
                accent: true,
                onTap: () => shell.agent.saveKey(_key.text)),
          ],
        ),
      ];
}
