import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Vector annotation document. Everything on screen is a [Shape] in one of
/// two layers: what you drew, and what the AI drew. Edits are [Op]s so
/// undo/redo is exact and the AI can never touch your layer.

enum Layer { user, ai }

enum StampKind { check, cross, question, star, step }

const kAiColor = Color(0xFFBF5AF2);

int _nextId = 0;
String newShapeId() => 's${_nextId++}';

sealed class Shape {
  Shape({String? id, required this.color, this.width = 4}) : id = id ?? newShapeId();
  final String id;
  final Color color;
  final double width;

  /// When it appeared; drives the AI draw-on animation.
  final int born = DateTime.now().millisecondsSinceEpoch;

  Rect get bounds;
  bool hitTest(Offset p, double r) => bounds.inflate(r + width / 2).contains(p);

  /// [t] is draw-on progress (0..1); [size] is the whole overlay.
  void paint(Canvas c, Size size, double t);

  /// A copy for the user layer (AI "Keep"), or null if it is only a pointer.
  Shape? keep() => null;

  /// Short description for the AI, in overlay coordinates.
  Map<String, dynamic> describe() => {'type': runtimeType.toString(), 'bounds': rectJson(bounds)};

  Paint strokePaint([double t = 1]) => Paint()
    ..color = color.withValues(alpha: color.a * t.clamp(0.0, 1.0))
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
}

List<int> rectJson(Rect r) => [r.left.round(), r.top.round(), r.width.round(), r.height.round()];

/// Draws [path] from the start up to [t] of its length.
void _drawPartial(Canvas c, Path path, Paint p, double t) {
  if (t >= 1) {
    c.drawPath(path, p);
    return;
  }
  for (final m in path.computeMetrics()) {
    c.drawPath(m.extractPath(0, m.length * t), p);
  }
}

// ------------------------------------------------------------------ strokes

class StrokeShape extends Shape {
  StrokeShape({required super.color, super.width, required this.points, this.pressures, this.highlighter = false})
      : bounds = boundsOf(points);
  final List<Offset> points;
  final List<double>? pressures; // stylus only
  final bool highlighter;
  @override
  final Rect bounds;
  Path? _path;

  static Rect boundsOf(List<Offset> p) {
    if (p.isEmpty) return Rect.zero;
    var l = p.first.dx, t = p.first.dy, r = l, b = t;
    for (final o in p) {
      l = math.min(l, o.dx);
      t = math.min(t, o.dy);
      r = math.max(r, o.dx);
      b = math.max(b, o.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Path get path => _path ??= smoothPath(points);

  @override
  bool hitTest(Offset p, double r) {
    if (!super.hitTest(p, r)) return false;
    final reach = r + width / 2;
    if (points.length == 1) return (points.first - p).distance <= reach;
    for (var i = 1; i < points.length; i++) {
      if (distToSegment(p, points[i - 1], points[i]) <= reach) return true;
    }
    return false;
  }

  @override
  void paint(Canvas c, Size size, double t) {
    if (points.isEmpty) return;
    final paint = strokePaint();
    if (highlighter) {
      // One path, so overlaps don't stack darker; multiply keeps text readable.
      paint
        ..strokeCap = StrokeCap.square
        ..blendMode = BlendMode.multiply;
    }
    if (points.length == 1) {
      c.drawCircle(points.first, width / 2, paint..style = PaintingStyle.fill);
      return;
    }
    final pr = pressures;
    if (pr == null || highlighter) {
      c.drawPath(path, paint);
      return;
    }
    // Pressure: short round-capped segments of varying width.
    for (var i = 1; i < points.length; i++) {
      final p = (pr[i - 1] + pr[i]) / 2;
      paint.strokeWidth = width * (0.35 + 0.9 * p.clamp(0.0, 1.0));
      c.drawLine(points[i - 1], points[i], paint);
    }
  }

  @override
  Shape? keep() => this;

  @override
  Map<String, dynamic> describe() => {'type': highlighter ? 'highlight' : 'pen', 'bounds': rectJson(bounds)};
}

/// Pixel eraser: clears whatever was drawn before it in the same layer.
class EraseShape extends Shape {
  EraseShape({required this.points, required double radius}) : super(color: const Color(0xFF000000), width: radius * 2);
  final List<Offset> points;
  late final Path _path = smoothPath(points);
  @override
  Rect get bounds => StrokeShape.boundsOf(points);
  @override
  bool hitTest(Offset p, double r) => false;

  @override
  void paint(Canvas c, Size size, double t) {
    final p = strokePaint()..blendMode = BlendMode.clear;
    if (points.length == 1) {
      c.drawCircle(points.first, width / 2, p..style = PaintingStyle.fill);
    } else {
      c.drawPath(_path, p);
    }
  }
}

/// The freehand stroke under the pen right now (pen, highlighter or pixel
/// eraser). Points are appended in place and the smoothed path grows with
/// them, so a move costs the same at the end of a long stroke as at the
/// start. Draws exactly what the finished [StrokeShape] / [EraseShape] would.
class LiveInk extends ChangeNotifier {
  final List<Offset> points = [];
  List<double>? pressures;
  Color color = const Color(0xFF000000);
  double width = 4;
  bool highlighter = false, eraser = false;
  bool get active => points.isNotEmpty;

  Path _path = Path(); // up to the midpoint of the last segment
  ui.Picture? _frozen; // pressure segments already drawn
  int _frozenTo = 0;

  @visibleForTesting
  Path get debugPath => _path;

  void begin(Offset p,
      {required Color color, required double width, double? pressure, bool highlighter = false, bool eraser = false}) {
    _reset();
    this.color = color;
    this.width = width;
    this.highlighter = highlighter;
    this.eraser = eraser;
    points.add(p);
    pressures = pressure == null ? null : [pressure];
    _path = Path()..moveTo(p.dx, p.dy);
    notifyListeners();
  }

  void add(Offset p, [double? pressure]) {
    points.add(p);
    pressures?.add(pressure ?? 0.5);
    final n = points.length;
    if (n >= 3) {
      // Same curve smoothPath builds: through the midpoint of each segment.
      final c = points[n - 2], mid = (c + p) / 2;
      _path.quadraticBezierTo(c.dx, c.dy, mid.dx, mid.dy);
    }
    notifyListeners();
  }

  void end() {
    _reset();
    notifyListeners();
  }

  void _reset() {
    points.clear();
    pressures = null;
    _frozen?.dispose();
    _frozen = null;
    _frozenTo = 0;
  }

  Paint _paint() {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (eraser) p.blendMode = BlendMode.clear;
    if (highlighter) {
      p
        ..strokeCap = StrokeCap.square
        ..blendMode = BlendMode.multiply;
    }
    return p;
  }

  void paint(Canvas c) {
    final n = points.length;
    if (n == 0) return;
    final paint = _paint();
    if (n == 1) {
      c.drawCircle(points.first, width / 2, paint..style = PaintingStyle.fill);
      return;
    }
    final pr = pressures;
    if (pr != null && !highlighter && !eraser) {
      // Each segment is its own round-capped line, so finished ones can be
      // kept in a Picture instead of being redrawn every frame.
      void seg(Canvas k, int i) {
        paint.strokeWidth = width * (0.35 + 0.9 * ((pr[i - 1] + pr[i]) / 2).clamp(0.0, 1.0));
        k.drawLine(points[i - 1], points[i], paint);
      }

      if (n - 1 - _frozenTo > 64) {
        final rec = ui.PictureRecorder();
        final k = Canvas(rec);
        if (_frozen != null) k.drawPicture(_frozen!);
        for (var i = math.max(1, _frozenTo + 1); i < n; i++) {
          seg(k, i);
        }
        _frozen?.dispose();
        _frozen = rec.endRecording();
        _frozenTo = n - 1;
      }
      if (_frozen != null) c.drawPicture(_frozen!);
      for (var i = math.max(1, _frozenTo + 1); i < n; i++) {
        seg(c, i);
      }
      return;
    }
    if (n < 3) {
      c.drawLine(points[0], points[1], paint);
      return;
    }
    c.drawPath(Path.from(_path)..lineTo(points.last.dx, points.last.dy), paint);
  }

  @override
  void dispose() {
    _frozen?.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------------ shapes

class RectShape extends Shape {
  RectShape({required super.color, super.width, required this.rect, this.ellipse = false, this.label, this.rounded = false});
  final Rect rect;
  final bool ellipse, rounded;
  final String? label;
  @override
  Rect get bounds => rect;

  @override
  bool hitTest(Offset p, double r) {
    final reach = r + width / 2;
    if (!rect.inflate(reach).contains(p)) return false;
    if (ellipse) {
      final c = rect.center, a = rect.width / 2, b = rect.height / 2;
      if (a < 1 || b < 1) return true;
      final d = math.sqrt(math.pow((p.dx - c.dx) / a, 2) + math.pow((p.dy - c.dy) / b, 2));
      return (d - 1).abs() * math.min(a, b) <= reach;
    }
    return !rect.deflate(reach).contains(p);
  }

  late final Path _path = ellipse
      ? (Path()..addOval(rect))
      : (Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rounded ? 8 : 2))));

  @override
  void paint(Canvas c, Size size, double t) {
    _drawPartial(c, _path, strokePaint(), t);
    if (label != null) paintTag(c, label!, rect.topLeft + const Offset(0, -6), color, t);
  }

  @override
  Shape? keep() => RectShape(color: color, width: width, rect: rect, ellipse: ellipse, label: label, rounded: rounded);

  @override
  Map<String, dynamic> describe() =>
      {'type': ellipse ? 'ellipse' : 'rectangle', 'bounds': rectJson(rect), 'label': ?label};
}

class LineShape extends Shape {
  LineShape({required super.color, super.width, required this.a, required this.b, this.arrow = false, this.label});
  final Offset a, b;
  final bool arrow;
  final String? label;
  @override
  Rect get bounds => Rect.fromPoints(a, b);
  @override
  bool hitTest(Offset p, double r) => distToSegment(p, a, b) <= r + width / 2 + (arrow ? 4 : 0);

  @override
  void paint(Canvas c, Size size, double t) {
    final p = strokePaint();
    final d = b - a;
    final len = d.distance;
    if (len < 0.5) return;
    final dir = d / len;
    final head = arrow ? math.max(10.0, width * 3.5) : 0.0;
    // Shorten the shaft so its round cap doesn't poke through the tip.
    final shaftEnd = arrow ? b - dir * (head * 0.6) : b;
    c.drawLine(a, Offset.lerp(a, shaftEnd, t.clamp(0.0, 1.0))!, p);
    if (arrow && t > 0.85) {
      const ang = 28 * math.pi / 180;
      Offset rot(double s) => Offset(
            dir.dx * math.cos(s) - dir.dy * math.sin(s),
            dir.dx * math.sin(s) + dir.dy * math.cos(s),
          );
      final l = b - rot(ang) * head, r = b - rot(-ang) * head;
      final h = Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(l.dx, l.dy)
        ..lineTo(r.dx, r.dy)
        ..close();
      c.drawPath(h, Paint()..color = p.color..isAntiAlias = true);
      c.drawPath(h, p..strokeWidth = math.min(width, 3));
    }
    if (label != null) paintTag(c, label!, a, color, t, above: a.dy <= b.dy);
  }

  @override
  Shape? keep() => LineShape(color: color, width: width, a: a, b: b, arrow: arrow, label: label);

  @override
  Map<String, dynamic> describe() => {
        'type': arrow ? 'arrow' : 'line',
        'from': [a.dx.round(), a.dy.round()],
        'to': [b.dx.round(), b.dy.round()],
        'label': ?label,
      };
}

class StampShape extends Shape {
  StampShape({required super.color, required this.kind, required this.at, this.size = 34, this.step = 0}) : super(width: 4);
  final StampKind kind;
  final Offset at; // centre
  final double size;
  final int step;
  @override
  Rect get bounds => Rect.fromCenter(center: at, width: size, height: size);

  @override
  void paint(Canvas c, Size s, double t) {
    final r = bounds;
    final k = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(k);
    c.translate(-at.dx, -at.dy);
    final p = strokePaint()..strokeWidth = size * 0.12;
    switch (kind) {
      case StampKind.check:
        c.drawPath(
            Path()
              ..moveTo(r.left + r.width * .15, r.top + r.height * .55)
              ..lineTo(r.left + r.width * .40, r.top + r.height * .80)
              ..lineTo(r.left + r.width * .88, r.top + r.height * .20),
            p);
      case StampKind.cross:
        final i = r.deflate(r.width * .2);
        c.drawLine(i.topLeft, i.bottomRight, p);
        c.drawLine(i.topRight, i.bottomLeft, p);
      case StampKind.question:
      case StampKind.star:
      case StampKind.step:
        final filled = kind == StampKind.step;
        c.drawCircle(at, size / 2, Paint()..color = filled ? color : const Color(0xE61C1C1E));
        if (!filled) c.drawCircle(at, size / 2 - 1.5, p..strokeWidth = 3);
        final glyph = switch (kind) { StampKind.question => '?', StampKind.star => '★', _ => '$step' };
        final tp = TextPainter(
          text: TextSpan(
            text: glyph,
            style: TextStyle(
                color: filled ? const Color(0xFFFFFFFF) : color, fontSize: size * 0.56, fontWeight: FontWeight.w800),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
        tp.dispose();
    }
    c.restore();
  }

  @override
  Shape? keep() => StampShape(color: color, kind: kind, at: at, size: size, step: step);

  @override
  Map<String, dynamic> describe() => {
        'type': 'stamp',
        'kind': kind.name,
        if (kind == StampKind.step) 'step': step,
        'at': [at.dx.round(), at.dy.round()],
      };
}

class TextShape extends Shape {
  TextShape({required super.color, required this.at, required this.text, this.fontSize = 22, this.boxed = false})
      : super(width: 0);
  final Offset at; // top-left
  final String text;
  final double fontSize;
  final bool boxed; // AI labels sit on a dark pill
  TextPainter? _tp;

  TextPainter get tp => _tp ??= TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: boxed ? const Color(0xFFFFFFFF) : color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: boxed ? null : const [Shadow(color: Color(0x99000000), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 420);

  @override
  Rect get bounds => (at & tp.size).inflate(boxed ? 8 : 0);

  @override
  void paint(Canvas c, Size size, double t) {
    final a = t.clamp(0.0, 1.0);
    if (boxed) {
      final box = RRect.fromRectAndRadius(bounds, const Radius.circular(10));
      c.drawRRect(box, Paint()..color = const Color(0xFF1C1C1E).withValues(alpha: 0.9 * a));
      c.drawRRect(box, Paint()..color = color.withValues(alpha: a)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    if (a < 1) {
      c.saveLayer(bounds.inflate(4), Paint()..color = Color.fromRGBO(0, 0, 0, a));
      tp.paint(c, at);
      c.restore();
    } else {
      tp.paint(c, at);
    }
  }

  @override
  Shape? keep() => TextShape(color: color, at: at, text: text, fontSize: fontSize, boxed: boxed);

  @override
  Map<String, dynamic> describe() => {'type': 'text', 'text': text, 'bounds': rectJson(bounds)};
}

/// AI: dims everything except [rect].
class SpotlightShape extends Shape {
  SpotlightShape({required this.rect}) : super(color: kAiColor, width: 3);
  final Rect rect;
  @override
  Rect get bounds => rect;
  @override
  bool hitTest(Offset p, double r) => false;

  @override
  void paint(Canvas c, Size size, double t) {
    final hole = RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(12));
    c.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole),
      Paint()..color = Color.fromRGBO(0, 0, 0, 0.45 * t.clamp(0.0, 1.0)),
    );
    c.drawRRect(hole, strokePaint(t));
  }
}

/// AI: a pulsing "here" marker. Pulses for a few seconds, then rests.
class PulseShape extends Shape {
  PulseShape({required this.at}) : super(color: kAiColor, width: 3);
  final Offset at;
  static const pulseMs = 4000;
  @override
  Rect get bounds => Rect.fromCircle(center: at, radius: 40);
  @override
  bool hitTest(Offset p, double r) => false;

  @override
  void paint(Canvas c, Size size, double t) {
    final age = DateTime.now().millisecondsSinceEpoch - born;
    if (age < pulseMs) {
      for (var k = 0; k < 2; k++) {
        final ph = ((age + k * 600) % 1200) / 1200;
        c.drawCircle(at, 10 + 28 * ph, strokePaint(1 - ph));
      }
    } else {
      c.drawCircle(at, 18, strokePaint(0.8));
    }
    c.drawCircle(at, 7, Paint()..color = color);
    c.drawCircle(at, 7, Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 2);
  }
}

/// A small label pill used by boxes and arrows.
void paintTag(Canvas c, String text, Offset anchor, Color color, double t, {bool above = true}) {
  final a = t.clamp(0.0, 1.0);
  final tp = TextPainter(
    text: TextSpan(
        text: text, style: TextStyle(color: Color.fromRGBO(255, 255, 255, a), fontSize: 14, fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 320);
  final box = Rect.fromLTWH(anchor.dx, above ? anchor.dy - tp.height - 8 : anchor.dy + 8, tp.width + 16, tp.height + 8);
  c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)), Paint()..color = color.withValues(alpha: 0.92 * a));
  tp.paint(c, box.topLeft + const Offset(8, 4));
  tp.dispose();
}

/// Records [shapes] once into a Picture. Inside a layer, so the pixel
/// eraser's clear only cuts through this layer.
ui.Picture recordShapes(List<Shape> shapes, Size size) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.saveLayer(Offset.zero & size, Paint());
  for (final s in shapes) {
    s.paint(c, size, 1);
  }
  c.restore();
  return rec.endRecording();
}

// ------------------------------------------------------------------ geometry

double distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.distanceSquared;
  if (l2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Quadratic curves through segment midpoints: smooth, and it passes close
/// to every sample.
Path smoothPath(List<Offset> p) {
  final path = Path()..moveTo(p.first.dx, p.first.dy);
  if (p.length < 3) {
    for (final o in p.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    return path;
  }
  for (var i = 1; i < p.length - 1; i++) {
    final mid = (p[i] + p[i + 1]) / 2;
    path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(p.last.dx, p.last.dy);
  return path;
}

/// Ramer–Douglas–Peucker: indices of the points worth keeping.
List<int> simplify(List<Offset> pts, double eps) {
  if (pts.length < 3) return List.generate(pts.length, (i) => i);
  final keep = List<bool>.filled(pts.length, false)
    ..[0] = true
    ..[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var best = 0.0, idx = -1;
    for (var i = s + 1; i < e; i++) {
      final d = distToSegment(pts[i], pts[s], pts[e]);
      if (d > best) {
        best = d;
        idx = i;
      }
    }
    if (idx >= 0 && best > eps) {
      keep[idx] = true;
      stack
        ..add((s, idx))
        ..add((idx, e));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) i];
}

/// One-Euro filter: strong smoothing when the pen moves slowly (kills
/// jitter), little when it moves fast (no lag).
class OneEuro {
  OneEuro({this.minCutoff = 1.2, this.beta = 0.012, this.dCutoff = 1.0});
  final double minCutoff, beta, dCutoff;
  Offset? _x;
  Offset _dx = Offset.zero;
  double? _t;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  Offset filter(Offset x, double tSec) {
    final prevT = _t, prevX = _x;
    _t = tSec;
    if (prevT == null || prevX == null) return _x = x;
    final dt = math.max(1e-3, tSec - prevT);
    _dx = Offset.lerp(_dx, (x - prevX) / dt, _alpha(dCutoff, dt))!;
    final cutoff = minCutoff + beta * _dx.distance;
    return _x = Offset.lerp(prevX, x, _alpha(cutoff, dt))!;
  }
}

// ------------------------------------------------------------------ store

sealed class Op {
  const Op();
}

class AddShapes extends Op {
  const AddShapes(this.shapes);
  final List<Shape> shapes;
}

/// Removed shapes with the index each had, in removal order.
class RemoveShapes extends Op {
  const RemoveShapes(this.removed);
  final List<(int, Shape)> removed;
}

class ClearLayer extends Op {
  const ClearLayer(this.removed);
  final List<Shape> removed;
}

class LayerState {
  final List<Shape> shapes = [];
  final List<Op> undo = [], redo = [];
  ui.Picture? cache;
  bool dirty = true;

  void reset() {
    shapes.clear();
    undo.clear();
    redo.clear();
  }
}

class AnnotationStore extends ChangeNotifier {
  final Map<Layer, LayerState> layers = {Layer.user: LayerState(), Layer.ai: LayerState()};

  /// The shape being drawn right now. Only the live painter listens to it,
  /// so moving the pen repaints one path, not the whole document.
  final ValueNotifier<Shape?> active = ValueNotifier(null);

  List<Shape> shapes(Layer l) => layers[l]!.shapes;
  bool canUndo(Layer l) => layers[l]!.undo.isNotEmpty;
  bool canRedo(Layer l) => layers[l]!.redo.isNotEmpty;
  bool get isEmpty => shapes(Layer.user).isEmpty && shapes(Layer.ai).isEmpty;

  void dispatch(Layer l, Op op) {
    final s = layers[l]!;
    _apply(s, op);
    s.undo.add(op);
    s.redo.clear();
    _changed(s);
  }

  void undo(Layer l) => _step(layers[l]!, back: true);
  void redo(Layer l) => _step(layers[l]!, back: false);

  void add(Layer l, Shape shape) => dispatch(l, AddShapes([shape]));

  void clear(Layer l) {
    final s = layers[l]!;
    if (s.shapes.isEmpty) return;
    dispatch(l, ClearLayer([...s.shapes]));
  }

  // ---- object eraser: shapes vanish as you drag; one undo brings them all back
  final List<(int, Shape)> _erased = [];

  void eraseAt(Layer l, Offset p, double r) {
    final s = layers[l]!;
    for (var i = s.shapes.length - 1; i >= 0; i--) {
      if (s.shapes[i].hitTest(p, r)) {
        _erased.add((i, s.shapes.removeAt(i)));
        _changed(s);
      }
    }
  }

  void commitErase(Layer l) {
    if (_erased.isEmpty) return;
    final s = layers[l]!;
    s.undo.add(RemoveShapes([..._erased]));
    s.redo.clear();
    _erased.clear();
    notifyListeners();
  }

  // ---- AI: shapes stream in one by one; Keep moves them into your layer
  void aiAdd(Shape shape) {
    final s = layers[Layer.ai]!;
    s.shapes.add(shape);
    _changed(s);
  }

  void keepAi() {
    final kept = [for (final x in shapes(Layer.ai)) ?x.keep()];
    dismissAi();
    if (kept.isNotEmpty) dispatch(Layer.user, AddShapes(kept));
  }

  void dismissAi() {
    final s = layers[Layer.ai]!;
    if (s.shapes.isEmpty) return;
    s.reset();
    _changed(s);
  }

  void _step(LayerState s, {required bool back}) {
    final from = back ? s.undo : s.redo, to = back ? s.redo : s.undo;
    if (from.isEmpty) return;
    final op = from.removeLast();
    back ? _revert(s, op) : _apply(s, op);
    to.add(op);
    _changed(s);
  }

  void _apply(LayerState s, Op op) {
    switch (op) {
      case AddShapes(:final shapes):
        s.shapes.addAll(shapes);
      case RemoveShapes(:final removed):
        final ids = {for (final (_, x) in removed) x.id};
        s.shapes.removeWhere((y) => ids.contains(y.id));
      case ClearLayer():
        s.shapes.clear();
    }
  }

  void _revert(LayerState s, Op op) {
    switch (op) {
      case AddShapes(:final shapes):
        final ids = {for (final x in shapes) x.id};
        s.shapes.removeWhere((y) => ids.contains(y.id));
      case RemoveShapes(:final removed):
        for (final (i, x) in removed.reversed) {
          s.shapes.insert(math.min(i, s.shapes.length), x);
        }
      case ClearLayer(:final removed):
        s.shapes
          ..clear()
          ..addAll(removed);
    }
  }

  void _changed(LayerState s) {
    s.dirty = true;
    notifyListeners();
  }

  /// Empties both layers, history included (closing the overlay).
  void reset() {
    _erased.clear();
    active.value = null;
    for (final s in layers.values) {
      s.reset();
      s.dirty = true;
    }
    notifyListeners();
  }

  /// Your annotations, for the AI's context (overlay coordinates).
  List<Map<String, dynamic>> describeUser() =>
      [for (final x in shapes(Layer.user)) if (x is! EraseShape) x.describe()];

  @override
  void dispose() {
    for (final s in layers.values) {
      s.cache?.dispose();
    }
    active.dispose();
    super.dispose();
  }
}
