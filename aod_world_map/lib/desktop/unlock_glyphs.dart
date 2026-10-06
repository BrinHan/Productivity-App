import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'unlock_watch.dart';

/// How long one unlock animation runs, recognition to checkmark.
const kUnlockAnimation = Duration(milliseconds: 2400);

/// The square island's welcome-back animation for [method], in the manner
/// of Apple's: Face ID turns the face as it scans, Touch ID fills the
/// fingerprint's ridges, a PIN springs the padlock. Each ends in a check.
class UnlockGlyph extends StatefulWidget {
  const UnlockGlyph({super.key, required this.method});
  final UnlockMethod method;

  @override
  State<UnlockGlyph> createState() => _UnlockGlyphState();
}

class _UnlockGlyphState extends State<UnlockGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kUnlockAnimation)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: switch (widget.method) {
          UnlockMethod.face => _FacePainter(_c),
          UnlockMethod.fingerprint => _FingerPainter(_c),
          UnlockMethod.pin => _PadlockPainter(_c),
        },
      );
}

const _green = Color(0xFF30D158);

/// 0..1 progress of [t] through the window [a]..[b].
double _span(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

Paint _stroke(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true
  ..color = c;

abstract class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  /// When the check starts and finishes drawing.
  double get checkFrom;
  double get checkTo;

  void glyph(Canvas canvas, double t);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    glyph(canvas, t);
    _check(canvas, _span(t, checkFrom, checkTo));
    canvas.restore();
  }

  /// The green tick: drawn on, with a small pop as it lands.
  void _check(Canvas canvas, double q) {
    if (q <= 0) return;
    final draw = Curves.easeOutCubic.transform(q);
    final pop = 1 + 0.12 * math.sin(math.pi * _span(q, 0.55, 1));
    final tick = Path()
      ..moveTo(-13, 1)
      ..lineTo(-4, 10)
      ..lineTo(14, -10);
    final m = tick.computeMetrics().first;
    canvas.save();
    canvas.scale(pop);
    canvas.drawPath(m.extractPath(0, m.length * draw), _stroke(_green, 5));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.anim != anim;
}

// ------------------------------------------------------------------ Face ID

/// Four rounded corner brackets around a simple face. While scanning, the
/// face turns from side to side inside the frame (its features slide and
/// narrow, like a head turning); on success they fold away into the check.
class _FacePainter extends _GlyphPainter {
  _FacePainter(super.anim);

  @override
  double get checkFrom => 0.56;
  @override
  double get checkTo => 0.8;

  @override
  void glyph(Canvas canvas, double t) {
    final appear = Curves.easeOutBack.transform(_span(t, 0, 0.12));
    final fold = Curves.easeInCubic.transform(_span(t, 0.5, 0.64));
    final frameFade = _span(t, 0.66, 0.84);
    if (frameFade >= 1) return;

    canvas.save();
    canvas.scale(0.82 + 0.18 * appear - 0.06 * fold);
    final white = Colors.white.withValues(alpha: appear.clamp(0.0, 1.0) * (1 - frameFade));

    // Corner brackets.
    const h = 21.0, arm = 11.0, r = 7.0;
    final frame = _stroke(white, 3);
    for (final (sx, sy) in const [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(sx * h, sy * (h - arm))
          ..lineTo(sx * h, sy * (h - r))
          ..quadraticBezierTo(sx * h, sy * h, sx * (h - r), sy * h)
          ..lineTo(sx * (h - arm), sy * h),
        frame,
      );
    }

    // The face, turning: one and a half looks left and right, settling.
    if (fold < 1) {
      final u = _span(t, 0.1, 0.5);
      final turn = math.sin(u * math.pi * 3) * math.pow(1 - u, 0.7);
      final dx = 5.0 * turn, narrow = 1 - 0.18 * turn.abs();
      final k = 1 - fold;
      final face = _stroke(white.withValues(alpha: white.a * k), 3);
      canvas.save();
      canvas.translate(dx * k, 0);
      canvas.scale(narrow * k, k);
      // Eyes.
      canvas.drawLine(const Offset(-7.5, -8), const Offset(-7.5, -3.5), face);
      canvas.drawLine(const Offset(7.5, -8), const Offset(7.5, -3.5), face);
      // Nose: down, then a short foot to the left.
      canvas.drawPath(
        Path()
          ..moveTo(1, -7)
          ..lineTo(1, 2.5)
          ..lineTo(-2, 2.5),
        face..strokeWidth = 2.6,
      );
      // Smile.
      canvas.drawPath(
        Path()
          ..moveTo(-8, 7.5)
          ..quadraticBezierTo(0, 13.5, 8, 7.5),
        face..strokeWidth = 3,
      );
      canvas.restore();
    }
    canvas.restore();
  }
}

// ------------------------------------------------------------------ Touch ID

/// A fingerprint of open ridges. They light up from the centre outwards in
/// Touch ID's red-to-pink, then the print gives way to the check.
class _FingerPainter extends _GlyphPainter {
  _FingerPainter(super.anim);

  @override
  double get checkFrom => 0.6;
  @override
  double get checkTo => 0.82;

  /// (radius, start degrees, sweep degrees), inner ridges first; 0 degrees
  /// points right and angles run clockwise (90 is straight down), so the
  /// ridges wrap down the sides and stay open at the bottom. A few are
  /// broken in two, as real prints are.
  static const _ridges = [
    (2.6, 170.0, 300.0),
    (6.0, 125.0, 290.0),
    (9.4, 115.0, 215.0),
    (9.4, 345.0, 80.0),
    (12.8, 125.0, 285.0),
    (16.2, 150.0, 140.0),
    (16.2, 305.0, 95.0),
    (19.6, 175.0, 190.0),
  ];

  static final _ink = ui.Gradient.linear(
    const Offset(0, -22),
    const Offset(0, 20),
    const [Color(0xFFFF2D55), Color(0xFFFF5E3A)],
  );

  @override
  void glyph(Canvas canvas, double t) {
    final appear = _span(t, 0, 0.1);
    final fill = _span(t, 0.08, 0.52);
    final leave = Curves.easeInCubic.transform(_span(t, 0.54, 0.68));
    if (leave >= 1) return;

    canvas.save();
    canvas.translate(0, 4);
    canvas.scale(0.9 + 0.1 * appear - 0.12 * leave);
    final base = _stroke(Colors.white.withValues(alpha: 0.22 * appear * (1 - leave)), 2.6);
    final ink = _stroke(Colors.white, 2.6)
      ..shader = _ink
      ..color = Colors.white.withValues(alpha: 1 - leave);

    for (var i = 0; i < _ridges.length; i++) {
      final (r, start, sweep) = _ridges[i];
      final path = Path()
        ..addArc(
          Rect.fromCenter(center: Offset.zero, width: r * 1.75, height: r * 2.15),
          start * math.pi / 180,
          sweep * math.pi / 180,
        );
      canvas.drawPath(path, base);
      // Inner ridges start first; each traces along its own length.
      final p = Curves.easeInOutCubic.transform(_span(fill, i * 0.07, i * 0.07 + 0.5));
      if (p > 0) {
        final m = path.computeMetrics().first;
        canvas.drawPath(m.extractPath(0, m.length * p), ink);
      }
    }
    canvas.restore();
  }
}

// ------------------------------------------------------------------ PIN

/// A padlock whose shackle lifts and swings open, then the check.
class _PadlockPainter extends _GlyphPainter {
  _PadlockPainter(super.anim);

  @override
  double get checkFrom => 0.5;
  @override
  double get checkTo => 0.74;

  @override
  void glyph(Canvas canvas, double t) {
    final appear = Curves.easeOutBack.transform(_span(t, 0, 0.12));
    final lift = Curves.easeOutBack.transform(_span(t, 0.14, 0.32));
    final swing = Curves.easeOutCubic.transform(_span(t, 0.26, 0.42));
    final leave = Curves.easeInCubic.transform(_span(t, 0.44, 0.56));
    if (leave >= 1) return;

    final white = Colors.white.withValues(alpha: appear.clamp(0.0, 1.0) * (1 - leave));
    canvas.save();
    canvas.scale(0.85 + 0.15 * appear - 0.1 * leave);

    // Shackle: rises, then swings open about its left leg.
    canvas.save();
    canvas.translate(-7, -2 - 5 * lift);
    canvas.rotate(-0.45 * swing);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(0, -6)
        ..arcToPoint(const Offset(14, -6), radius: const Radius.circular(7))
        ..lineTo(14, 0),
      _stroke(white, 3.2),
    );
    canvas.restore();

    // Body, with a keyhole.
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 7), width: 26, height: 19), const Radius.circular(5));
    canvas.drawRRect(body, Paint()..color = white);
    canvas.drawCircle(const Offset(0, 6), 2.4, Paint()..color = Colors.black.withValues(alpha: white.a));
    canvas.restore();
  }
}
