import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Pip's mood and physics. Plain data, stepped once per frame.
class PipModel {
  double t = 0;
  Offset gaze = Offset.zero, gazeTarget = Offset.zero;
  double hover = 0; // 0..1, eased
  bool hovering = false;
  double _hoverFor = 0;
  double squish = 0, _squishV = 0; // spring: + = squashed
  double annoyed = 0, dizzy = 0, hearts = 0, wave = 0; // seconds left
  final List<double> _clicks = [];

  void startWave() => wave = 1.5;

  void click() {
    _clicks.removeWhere((c) => t - c > 1.0);
    _clicks.add(t);
    _squishV += 5;
    hearts = 0;
    if (_clicks.length >= 3) {
      dizzy = 3.2;
      annoyed = 0;
      _clicks.clear();
    } else if (dizzy <= 0) {
      annoyed = 1.1;
    }
  }

  void step(double dt) {
    t += dt;
    gaze = Offset.lerp(gaze, gazeTarget, 1 - math.exp(-dt * 12))!;
    hover += ((hovering ? 1.0 : 0.0) - hover) * (1 - math.exp(-dt * 10));
    if (hovering) {
      _hoverFor += dt;
      if (_hoverFor > 2.0 && hearts <= 0 && annoyed <= 0 && dizzy <= 0) {
        hearts = 2.6; // resting on Pip for 2 seconds -> hearts
        _hoverFor = -1e6;
      }
    } else {
      _hoverFor = 0;
    }
    const n = 4;
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      final a = -190 * squish - 11 * _squishV;
      _squishV += a * h;
      squish += _squishV * h;
    }
    annoyed = math.max(0.0, annoyed - dt);
    dizzy = math.max(0.0, dizzy - dt);
    hearts = math.max(0.0, hearts - dt);
    wave = math.max(0.0, wave - dt);
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Pip, drawn in code: a bean body with a sprout, stubby arms and feet.
class PipView extends StatefulWidget {
  const PipView({
    super.key,
    required this.gaze,
    required this.color,
    this.interactive = true,
    this.wave = false,
  });
  final ValueListenable<Offset> gaze;
  final Color color;
  final bool interactive; // hover + click reactions
  final bool wave; // wave hello when it appears

  @override
  State<PipView> createState() => _PipViewState();
}

class _PipViewState extends State<PipView> with SingleTickerProviderStateMixin {
  final PipModel _m = PipModel();
  final _Repaint _repaint = _Repaint();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.wave) _m.startWave();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onTick(Duration e) {
    var dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;
    _m.gazeTarget = widget.gaze.value;
    _m.step(dt);
    _repaint.ping();
  }

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      painter: PipPainter(_m, _repaint, widget.color),
      size: Size.infinite,
    );
    if (!widget.interactive) return paint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _m.hovering = true,
      onExit: (_) => _m.hovering = false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _m.click,
        child: paint,
      ),
    );
  }
}

class PipPainter extends CustomPainter {
  PipPainter(this.m, Listenable repaint, this.color) : super(repaint: repaint);
  final PipModel m;
  final Color color;

  static const _ink = Color(0xFF17171C);

  double _blink(double t) {
    double pulse(double period, double offset) {
      final x = (t + offset) % period;
      const d = 0.16;
      return x > d ? 0.0 : math.sin(x / d * math.pi);
    }

    return math.max(pulse(4.3, 0), pulse(6.7, 2.1));
  }

  void _arm(Canvas c, Offset s, double angle, double bs, Paint p) {
    c.save();
    c.translate(s.dx, s.dy);
    c.rotate(angle);
    c.drawRRect(
      RRect.fromLTRBR(-bs * 0.05, 0, bs * 0.05, bs * 0.22, Radius.circular(bs * 0.05)),
      p,
    );
    c.restore();
  }

  void _heart(Canvas c, Offset o, double s, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(o.dx, o.dy + s * 0.9)
        ..cubicTo(o.dx - s * 1.5, o.dy - s * 0.1, o.dx - s * 0.7, o.dy - s * 1.2, o.dx, o.dy - s * 0.4)
        ..cubicTo(o.dx + s * 0.7, o.dy - s * 1.2, o.dx + s * 1.5, o.dy - s * 0.1, o.dx, o.dy + s * 0.9),
      p,
    );
  }

  void _spiral(Canvas c, Offset o, double r, double rot, Paint p) {
    final path = Path();
    for (var i = 0; i <= 40; i++) {
      final a = rot + i * 0.45;
      final rr = r * i / 40;
      final pt = Offset(o.dx + math.cos(a) * rr, o.dy + math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = m.t;
    final bs = size.height * 0.66;
    final cx = size.width / 2;
    final baseY = size.height / 2 + bs * 0.62;
    final ink = Paint()
      ..color = _ink
      ..isAntiAlias = true;

    final breathe = math.sin(t * 2 * math.pi / 3.4);
    final sq = m.squish.clamp(-0.4, 0.8).toDouble();
    final sx = 1 + 0.22 * sq - 0.015 * breathe;
    final sy = 1 - 0.30 * sq + 0.03 * breathe;
    final rot = (m.dizzy > 0 ? math.sin(t * 9) * 0.12 : 0.0) + m.gaze.dx * 0.05;

    canvas.save();
    canvas.translate(cx + m.gaze.dx * bs * 0.03, baseY);
    canvas.rotate(rot);
    canvas.scale(sx, sy);

    final bw = bs * 0.80, bh = bs * 0.78;
    final bottom = -bs * 0.10, top = bottom - bh;
    final bodyPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    final partPaint = Paint()
      ..color = Color.lerp(color, Colors.black, 0.18)!
      ..isAntiAlias = true;

    // feet
    for (final sgn in const [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(sgn * bw * 0.20, bottom + bs * 0.02),
          width: bs * 0.20,
          height: bs * 0.11,
        ),
        partPaint,
      );
    }
    // arms (the right one waves)
    _arm(canvas, Offset(-bw / 2 + bs * 0.02, top + bh * 0.52),
        0.35 + (m.dizzy > 0 ? math.sin(t * 9) * 0.3 : 0.0), bs, partPaint);
    _arm(canvas, Offset(bw / 2 - bs * 0.02, top + bh * 0.52),
        m.wave > 0 ? -2.3 + math.sin(t * 16) * 0.35 : -0.35, bs, partPaint);

    // body + soft highlight
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        -bw / 2, top, bw / 2, bottom,
        topLeft: Radius.circular(bw * 0.5),
        topRight: Radius.circular(bw * 0.5),
        bottomLeft: Radius.circular(bw * 0.28),
        bottomRight: Radius.circular(bw * 0.28),
      ),
      bodyPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-bw * 0.18, top + bh * 0.16),
        width: bw * 0.28,
        height: bh * 0.12,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // sprout: sways, perks up on hover, droops when annoyed
    final sway = math.sin(t * 1.7) * 0.12 + m.gaze.dx * 0.2;
    final perk = 1 + 0.25 * m.hover;
    final droop = m.annoyed > 0 ? 0.6 : 0.0;
    final len = bs * 0.16 * perk;
    canvas.save();
    canvas.translate(0, top + bh * 0.02);
    canvas.rotate(sway);
    canvas.drawLine(
      Offset.zero,
      Offset(0, -len),
      Paint()
        ..color = const Color(0xFF3FA85F)
        ..strokeWidth = bs * 0.035
        ..strokeCap = StrokeCap.round,
    );
    for (final sgn in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(0, -len);
      canvas.rotate(sgn * (0.75 - 0.35 * droop));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, -bs * 0.07), width: bs * 0.10, height: bs * 0.17),
        Paint()..color = const Color(0xFF5CCB7A),
      );
      canvas.restore();
    }
    canvas.restore();

    // face
    final ey = top + bh * 0.46;
    final ex = bw * 0.20;
    final r = bs * 0.062 * (1 + 0.30 * m.hover);
    final blink = _blink(t);
    final hf = (1 - 0.9 * blink) * (m.annoyed > 0 ? 0.62 : 1.0);
    final gx = m.gaze.dx * bs * 0.055, gy = m.gaze.dy * bs * 0.04;

    if (m.dizzy > 0) {
      final sp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bs * 0.025
        ..strokeCap = StrokeCap.round
        ..color = _ink;
      _spiral(canvas, Offset(-ex, ey), r * 1.5, t * 8, sp);
      _spiral(canvas, Offset(ex, ey), r * 1.5, -t * 8, sp);
    } else {
      for (final sgn in const [-1.0, 1.0]) {
        final c = Offset(sgn * ex + gx, ey + gy);
        canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 2 * hf), ink);
        if (blink < 0.5) {
          canvas.drawCircle(
            c + Offset(-r * 0.3, -r * 0.3 * hf),
            r * 0.28,
            Paint()..color = Colors.white.withValues(alpha: 0.9),
          );
        }
      }
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bs * 0.03
      ..strokeCap = StrokeCap.round
      ..color = _ink;

    if (m.annoyed > 0 && m.dizzy <= 0) {
      for (final sgn in const [-1.0, 1.0]) {
        final c0 = sgn * ex + gx;
        canvas.drawLine(
          Offset(c0 - sgn * r * 1.5, ey - r * 1.0), // inner end, lower
          Offset(c0 + sgn * r * 1.4, ey - r * 1.9), // outer end, higher
          line,
        );
      }
    }

    // mouth
    final my = ey + bw * 0.24;
    if (m.dizzy > 0) {
      final path = Path();
      for (var i = 0; i <= 12; i++) {
        final x = -bs * 0.09 + i * (bs * 0.18 / 12);
        final y = my + math.sin(i * 1.2 + t * 8) * bs * 0.02;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, line);
    } else if (m.annoyed > 0) {
      canvas.drawLine(Offset(-bs * 0.07, my + bs * 0.01), Offset(bs * 0.07, my - bs * 0.01), line);
    } else if (m.hearts > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(-bs * 0.09, my - bs * 0.01)
          ..quadraticBezierTo(0, my + bs * 0.14, bs * 0.09, my - bs * 0.01)
          ..close(),
        ink,
      );
      for (final sgn in const [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(sgn * ex * 1.5, ey + r * 2.3),
            width: bs * 0.12,
            height: bs * 0.07,
          ),
          Paint()..color = const Color(0xFFFF5C7A).withValues(alpha: 0.35),
        );
      }
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-bs * 0.07, my)
          ..quadraticBezierTo(0, my + bs * 0.06 * (1 + 0.6 * m.hover), bs * 0.07, my),
        line,
      );
    }
    canvas.restore();

    // hearts float up
    if (m.hearts > 0) {
      final life = 2.6 - m.hearts;
      for (var i = 0; i < 3; i++) {
        final pp = (life - i * 0.35) / 1.6;
        if (pp < 0 || pp > 1) continue;
        _heart(
          canvas,
          Offset(cx + (i - 1) * bs * 0.26 + math.sin(pp * 5 + i) * bs * 0.05,
              baseY - bs * 1.0 - pp * bs * 0.55),
          bs * 0.085 * (0.7 + 0.3 * pp),
          Paint()..color = const Color(0xFFFF5C7A).withValues(alpha: 1 - pp),
        );
      }
    }
  }

  @override
  bool shouldRepaint(PipPainter old) => old.color != color;
}
