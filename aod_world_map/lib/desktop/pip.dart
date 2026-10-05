import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'island_controller.dart';

class Heart {
  Heart(this.x, this.vx, this.age);
  double x, vx, age;
  double y = 0;
}

/// Pip's mood + physics. Plain data, stepped once per frame.
class PipModel {
  double t = 0;
  Offset gaze = Offset.zero, gazeTarget = Offset.zero;
  bool hovering = false;
  double hover = 0;
  Offset? ptr; // pointer inside the Pip box, 0..1
  Offset lastPtr = const Offset(0.5, 0.5);
  double ptrOn = 0;
  double squish = 0, _squishV = 0;
  double annoyed = 0, dizzy = 0, wave = 0, startle = 0, flip = 0, hearts = 0;
  double pet = 0;
  double sleep = 0, idleFor = 0;
  double fly = 0;
  bool flying = false;
  double _hoverFor = 0, _heartTimer = 0;
  final List<double> _clicks = [];
  final List<Heart> particles = [];
  final math.Random _rng = math.Random();

  // ---- petting = rubbing the cursor back and forth over the head ----
  /// The head, in the 0..1 Pip box.
  static const Rect headZone = Rect.fromLTRB(0.24, 0.20, 0.76, 0.58);
  double? _lastX;
  double _dir = 0, _strokeLen = 0, _lastReversal = -9;
  final List<double> _reversals = [];

  void startWave() => wave = 1.6;
  void land() => _squishV += 5;

  void _wake() {
    if (sleep > 0.5) {
      startle = 0.8;
      _squishV -= 4;
    }
    idleFor = 0;
  }

  void _resetRub() {
    _lastX = null;
    _dir = 0;
    _strokeLen = 0;
  }

  void _rub(double x) {
    final last = _lastX;
    if (last == null) {
      _lastX = x;
      return;
    }
    final dx = x - last;
    if (dx.abs() < 0.006) return; // jitter: keep the anchor
    _lastX = x;
    final d = dx.sign;
    if (_dir == 0 || d == _dir) {
      _dir = d;
      _strokeLen += dx.abs();
    } else {
      // direction flipped: a full stroke counts only if it was long enough
      if (_strokeLen > 0.08) {
        _reversals.add(t);
        _lastReversal = t;
      }
      _dir = d;
      _strokeLen = dx.abs();
    }
  }

  void hoverMove(Offset p) {
    if (!hovering) _wake();
    hovering = true;
    ptr = p;
    lastPtr = p;
    idleFor = 0;
    if (headZone.contains(p) && annoyed <= 0 && dizzy <= 0) {
      _rub(p.dx);
    } else {
      _resetRub();
    }
  }

  void leave() {
    hovering = false;
    ptr = null;
    _resetRub();
    _reversals.clear();
  }

  /// Pointer-down: reacts instantly. A click cancels any petting mood so
  /// Pip is never happy and angry at once.
  void poke() {
    _wake();
    final last = _clicks.isEmpty ? -9.0 : _clicks.last;
    final dbl = t - last < 0.32;
    _clicks.removeWhere((c) => t - c > 1.0);
    _clicks.add(t);
    _squishV += 3.5;
    hearts = 0;
    pet = 0;
    particles.clear();
    _reversals.clear();
    _resetRub();
    if (_clicks.length >= 3) {
      dizzy = 3.2;
      annoyed = 0;
      flip = 0;
      _clicks.clear();
    } else if (dbl && _clicks.length == 2) {
      flip = 0.001; // backflip
      annoyed = 0;
    } else if (dizzy <= 0 && flip <= 0) {
      annoyed = 1.0;
    }
  }

  void step(double dt) {
    t += dt;
    idleFor += dt;
    final wander = idleFor > 6 && sleep < 0.5 && !hovering;
    final Offset want = hovering && ptr != null
        ? Offset((ptr!.dx - 0.5) * 2, (ptr!.dy - 0.5) * 2)
        : (wander
              ? Offset(math.sin(t * 0.55) * 0.55, math.sin(t * 0.8) * 0.2)
              : gazeTarget);
    gaze = Offset.lerp(gaze, want, 1 - math.exp(-dt * 10))!;

    hover += ((hovering ? 1.0 : 0.0) - hover) * (1 - math.exp(-dt * 10));
    ptrOn += ((ptr != null ? 1.0 : 0.0) - ptrOn) * (1 - math.exp(-dt * 14));
    fly += ((flying ? 1.0 : 0.0) - fly) * (1 - math.exp(-dt * 12));
    sleep +=
        ((idleFor > 18 && !hovering ? 1.0 : 0.0) - sleep) *
        (1 - math.exp(-dt * 1.6));

    // petting: at least 3 direction changes over the head within 1 s, and
    // the last one still fresh. Never while annoyed / dizzy / flipping.
    _reversals.removeWhere((r) => t - r > 1.0);
    final calm = annoyed <= 0 && dizzy <= 0 && flip <= 0;
    final petting =
        calm && hovering && _reversals.length >= 3 && t - _lastReversal < 0.45;
    pet +=
        ((petting ? 1.0 : 0.0) - pet) * (1 - math.exp(-dt * (petting ? 9 : 5)));
    if (!calm) pet = 0;

    if (pet > 0.4) {
      _heartTimer += dt;
      if (_heartTimer > 0.16) {
        _heartTimer = 0;
        particles.add(
          Heart(
            (_rng.nextDouble() - 0.5) * 0.7,
            (_rng.nextDouble() - 0.5) * 0.25,
            0,
          ),
        );
      }
    }
    for (final p in particles) {
      p.age += dt;
      if (p.age > 0) {
        p.y -= dt * 0.55;
        p.x += p.vx * dt;
      }
    }
    particles.removeWhere((p) => p.age > 1.1);

    // resting on Pip for 2 s -> blissful + hearts
    if (hovering) {
      _hoverFor += dt;
      if (_hoverFor > 2.0 &&
          hearts <= 0 &&
          annoyed <= 0 &&
          dizzy <= 0 &&
          pet < 0.3) {
        hearts = 2.6;
        _hoverFor = -1e6;
        for (var i = 0; i < 3; i++) {
          particles.add(Heart((i - 1) * 0.26, 0, -i * 0.3));
        }
      }
    } else {
      _hoverFor = 0;
    }

    // body spring (damped harder than before: less jelly)
    const n = 4;
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      final a = -200 * squish - 17 * _squishV;
      _squishV += a * h;
      squish += _squishV * h;
    }
    annoyed = math.max(0.0, annoyed - dt);
    dizzy = math.max(0.0, dizzy - dt);
    wave = math.max(0.0, wave - dt);
    hearts = math.max(0.0, hearts - dt);
    startle = math.max(0.0, startle - dt);
    if (flip > 0) {
      flip += dt / 0.75;
      if (flip >= 1) flip = 0;
    }
  }
}

class PipPainter extends CustomPainter {
  PipPainter(this.m, this.color);
  final PipModel m;
  final Color color;

  static const _ink = Color(0xFF17171C);
  static const _stem = Color(0xFF3FA85F),
      _leaf = Color(0xFF5CCB7A),
      _pink = Color(0xFFFF5C7A);

  double _blink(double t) {
    double pulse(double period, double offset) {
      final x = (t + offset) % period;
      const d = 0.16;
      return x > d ? 0.0 : math.sin(x / d * math.pi);
    }

    return math.max(pulse(4.3, 0), pulse(6.7, 2.1));
  }

  /// Arm with a round hand.
  void _arm(Canvas c, Offset s, double angle, double bs, Paint p) {
    c.save();
    c.translate(s.dx, s.dy);
    c.rotate(angle);
    c.drawRRect(
      RRect.fromLTRBR(-bs * 0.05, 0, bs * 0.05, bs * 0.24, Radius.circular(bs * 0.05)),
      p,
    );
    c.drawCircle(Offset(0, bs * 0.24), bs * 0.068, p);
    c.restore();
  }

  void _leafShape(Canvas c, double len, double wid, Paint fill, Paint vein) {
    c.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(wid, -len * 0.45, 0, -len)
        ..quadraticBezierTo(-wid, -len * 0.45, 0, 0),
      fill,
    );
    c.drawLine(Offset.zero, Offset(0, -len * 0.78), vein);
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

  void _z(Canvas c, Offset o, double s, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(o.dx - s, o.dy - s)
        ..lineTo(o.dx + s, o.dy - s)
        ..lineTo(o.dx - s, o.dy + s)
        ..lineTo(o.dx + s, o.dy + s),
      p,
    );
  }

  /// Squircle bean. Wherever the pointer presses, nearby outline points are
  /// pushed toward the centre (so it dents on any side, not just the top).
  Path _body(
    double bw,
    double bh,
    double top,
    double bottom,
    Offset press,
    double depth,
    double sigma,
  ) {
    final a = bw / 2, b = bh / 2, cy = (top + bottom) / 2;
    final path = Path();
    const n = 72;
    for (var i = 0; i < n; i++) {
      final th = 2 * math.pi * i / n;
      final c = math.cos(th), s = math.sin(th);
      final e = s < 0 ? 2.25 : 4.2; // rounder head, boxier base
      var x = a * c.sign * math.pow(c.abs(), 2 / e).toDouble();
      var y = cy + b * s.sign * math.pow(s.abs(), 2 / e).toDouble();
      if (depth > 0.01) {
        final dx = x - press.dx, dy = y - press.dy;
        final g = math.exp(-(dx * dx + dy * dy) / (sigma * sigma));
        final vx = -x, vy = cy - y;
        final vl = math.sqrt(vx * vx + vy * vy) + 1e-6;
        x += vx / vl * depth * g;
        y += vy / vl * depth * g;
      }
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = m.t;
    final bs = size.height * 0.66;
    final cx = size.width / 2;
    final baseY = size.height / 2 + bs * 0.62;
    final sleep = m.sleep;
    final breathe = math.sin(t * 2 * math.pi / (3.4 + 2.2 * sleep));
    final sq = m.squish.clamp(-0.3, 0.5).toDouble();
    final bw = bs * 0.80, bh = bs * 0.78;
    final bottom = -bs * 0.10, top = bottom - bh;
    final cyB = (top + bottom) / 2;

    // One mood at a time: annoyed / dizzy cancel the happy look completely.
    final calm = m.annoyed <= 0 && m.dizzy <= 0;
    final pet = calm ? m.pet : 0.0;
    final hearts = m.annoyed > 0 ? 0.0 : m.hearts;

    // Soft press: strongest where the pointer is, on any part of the body.
    var press = 0.0, depth = 0.0;
    var pp = Offset.zero;
    final sigma = bw * 0.34;
    if (m.ptrOn > 0.01) {
      pp = Offset(m.lastPtr.dx * size.width - cx, m.lastPtr.dy * size.height - baseY);
      final nx = pp.dx / (bw * 0.575), ny = (pp.dy - cyB) / (bh * 0.575);
      final nd = math.sqrt(nx * nx + ny * ny);
      final near = ((1.4 - nd) / 0.5).clamp(0.0, 1.0).toDouble();
      press = m.ptrOn * near;
      depth = press * bh * 0.11;
    }
    final dr = depth / bh;

    /// Interior features shift slightly away from the pointer.
    Offset push(Offset q) {
      if (depth <= 0.01) return Offset.zero;
      final dx = q.dx - pp.dx, dy = q.dy - pp.dy;
      final d2 = dx * dx + dy * dy;
      final g = math.exp(-d2 / (sigma * sigma));
      final d = math.sqrt(d2) + 1e-6;
      return Offset(dx / d, dy / d) * (depth * 0.3 * g);
    }

    final ink = Paint()
      ..color = _ink
      ..isAntiAlias = true;
    final bodyPaint = Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        Offset(0, top),
        Offset(0, bottom),
        [
          Color.lerp(color, Colors.white, 0.28)!,
          color,
          Color.lerp(color, Colors.black, 0.16)!,
        ],
        const [0.0, 0.45, 1.0],
      );
    final partPaint = Paint()
      ..color = Color.lerp(color, Colors.black, 0.18)!
      ..isAntiAlias = true;

    canvas.save();
    if (m.flip > 0) {
      final pivot = Offset(cx, baseY - bs * 0.45);
      final hop = math.sin(math.pi * m.flip) * bs * 0.55;
      canvas.translate(pivot.dx, pivot.dy - hop);
      canvas.rotate(Curves.easeInOut.transform(m.flip) * 2 * math.pi);
      canvas.translate(-pivot.dx, -pivot.dy);
    }
    final rot =
        (m.dizzy > 0 ? math.sin(t * 9) * 0.12 : 0.0) +
        m.gaze.dx * 0.05 +
        math.sin(t * 17) * 0.05 * pet -
        (pp.dx / bw).clamp(-0.6, 0.6).toDouble() * 0.08 * press;
    final sx = 1 + 0.16 * sq - 0.015 * breathe + 0.4 * dr + 0.03 * pet * math.sin(t * 19);
    final sy = 1 - 0.20 * sq + 0.03 * breathe - 0.3 * dr;
    canvas.translate(cx + m.gaze.dx * bs * 0.03, baseY);
    canvas.rotate(rot);
    canvas.scale(sx, sy);

    // feet
    for (final sgn in const [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(sgn * bw * 0.22, bottom + bs * 0.02),
          width: bs * 0.24,
          height: bs * 0.12,
        ),
        partPaint,
      );
    }

    // arms: relaxed, waving, happy, dizzy or flying
    var la = 0.35 + 0.75 * pet, ra = -(0.35 + 0.75 * pet);
    if (m.dizzy > 0) la += math.sin(t * 9) * 0.3;
    if (m.wave > 0) ra = -2.3 + math.sin(t * 16) * 0.35;
    if (m.fly > 0.02) {
      final fl = math.sin(t * 26) * 0.4;
      la += (2.4 + fl - la) * m.fly;
      ra += (-2.4 - fl - ra) * m.fly;
    }
    _arm(canvas, Offset(-bw / 2 + bs * 0.02, top + bh * 0.52), la, bs, partPaint);
    _arm(canvas, Offset(bw / 2 - bs * 0.02, top + bh * 0.52), ra, bs, partPaint);

    // body, soft rim, belly, highlight
    final body = _body(bw, bh, top, bottom, pp, depth, sigma);
    canvas.drawPath(body, bodyPaint);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bs * 0.016
        ..isAntiAlias = true
        ..color = Colors.black.withValues(alpha: 0.16),
    );
    final bellyC = Offset(0, bottom - bh * 0.27);
    canvas.drawOval(
      Rect.fromCenter(center: bellyC + push(bellyC), width: bw * 0.52, height: bh * 0.36),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    final hiC = Offset(-bw * 0.18, top + bh * 0.16);
    canvas.drawOval(
      Rect.fromCenter(center: hiC + push(hiC), width: bw * 0.28, height: bh * 0.12),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );

    // sprout
    final sway = math.sin(t * 1.7) * 0.12 + m.gaze.dx * 0.2 + math.sin(t * 22) * 0.10 * pet;
    final perk = 1 + 0.25 * m.hover + 0.35 * pet - 0.5 * sleep;
    final len = bs * 0.16 * perk;
    final sproutBase = Offset(0, top + bh * 0.02);
    canvas.save();
    canvas.translate(0, sproutBase.dy + push(sproutBase).dy);
    canvas.rotate(sway);
    canvas.drawLine(
      Offset.zero,
      Offset(0, -len),
      Paint()
        ..color = _stem
        ..strokeWidth = bs * 0.035
        ..strokeCap = StrokeCap.round,
    );
    final droop = (m.annoyed > 0 ? 0.6 : 0.0) + sleep * 0.6;
    final leafPaint = Paint()..color = _leaf;
    final vein = Paint()
      ..color = _stem.withValues(alpha: 0.7)
      ..strokeWidth = bs * 0.009
      ..strokeCap = StrokeCap.round;
    for (final sgn in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(0, -len);
      canvas.rotate(sgn * (0.75 - 0.35 * droop));
      _leafShape(canvas, bs * 0.19, bs * 0.075, leafPaint, vein);
      canvas.restore();
    }
    canvas.restore();

    // face
    final ey0 = top + bh * 0.46;
    final ex = bw * 0.20;
    final r = bs * 0.062 * (1 + 0.30 * m.hover + (m.startle > 0 ? 0.35 : 0.0));
    final blink = _blink(t) * (1 - sleep);
    final hf = (1 - 0.9 * blink) * (m.annoyed > 0 ? 0.62 : 1.0);
    final gx = m.gaze.dx * bs * 0.055, gy = m.gaze.dy * bs * 0.04;
    final openEye = (1 - math.max(pet, sleep)).clamp(0.0, 1.0).toDouble();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bs * 0.03
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = _ink;

    if (m.dizzy > 0) {
      for (final sgn in const [-1.0, 1.0]) {
        final base = Offset(sgn * ex, ey0);
        _spiral(canvas, base + push(base), r * 1.5, sgn * t * 8, line);
      }
    } else {
      for (final sgn in const [-1.0, 1.0]) {
        final base = Offset(sgn * ex, ey0);
        final c0 = base + push(base) + Offset(gx, gy);
        if (openEye > 0.02) {
          canvas.drawOval(
            Rect.fromCenter(
              center: c0,
              width: r * 2,
              height: math.max(1.0, r * 2 * hf),
            ),
            Paint()..color = _ink.withValues(alpha: openEye),
          );
          if (blink < 0.5) {
            canvas.drawCircle(
              c0 + Offset(-r * 0.3, -r * 0.3 * hf),
              r * 0.30,
              Paint()..color = Colors.white.withValues(alpha: 0.92 * openEye),
            );
            canvas.drawCircle(
              c0 + Offset(r * 0.32, r * 0.34 * hf),
              r * 0.14,
              Paint()..color = Colors.white.withValues(alpha: 0.6 * openEye),
            );
          }
        }
        if (pet > 0.02) {
          // happy ^ eyes while being petted
          canvas.drawPath(
            Path()
              ..moveTo(c0.dx - r * 1.2, c0.dy + r * 0.5)
              ..quadraticBezierTo(c0.dx, c0.dy - r * 1.5, c0.dx + r * 1.2, c0.dy + r * 0.5),
            line..color = _ink.withValues(alpha: pet),
          );
        }
        if (sleep > 0.02) {
          canvas.drawPath(
            Path()
              ..moveTo(c0.dx - r, c0.dy)
              ..quadraticBezierTo(c0.dx, c0.dy + r * 0.7, c0.dx + r, c0.dy),
            line..color = _ink.withValues(alpha: sleep),
          );
        }
        line.color = _ink;
      }
      if (m.annoyed > 0) {
        for (final sgn in const [-1.0, 1.0]) {
          final c0 = sgn * ex + gx;
          canvas.drawLine(
            Offset(c0 - sgn * r * 1.5, ey0 - r * 1.0),
            Offset(c0 + sgn * r * 1.4, ey0 - r * 1.9),
            line,
          );
        }
      }
    }

    // blush (always a hint; stronger when happy)
    final blush = math.max(
      math.max(pet * 0.55, hearts > 0 ? 0.35 : 0.0),
      math.max(m.hover * 0.2, 0.14),
    );
    final blushA = m.annoyed > 0 ? blush * 0.4 : blush;
    for (final sgn in const [-1.0, 1.0]) {
      final bc = Offset(sgn * ex * 1.5, ey0 + r * 2.3);
      canvas.drawOval(
        Rect.fromCenter(center: bc + push(bc), width: bs * 0.13, height: bs * 0.075),
        Paint()..color = _pink.withValues(alpha: blushA),
      );
    }

    // mouth
    var my = ey0 + bw * 0.24;
    my += push(Offset(0, my)).dy;
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
    } else if (pet > 0.3 || hearts > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(-bs * 0.09, my - bs * 0.01)
          ..quadraticBezierTo(0, my + bs * 0.17 * (0.6 + 0.4 * pet), bs * 0.09, my - bs * 0.01)
          ..close(),
        ink,
      );
    } else if (sleep > 0.4) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, my + bs * 0.02),
          width: bs * 0.06,
          height: bs * 0.05 * (1 + 0.4 * breathe),
        ),
        ink,
      );
    } else if (m.startle > 0) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, my + bs * 0.02), width: bs * 0.08, height: bs * 0.10),
        ink,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-bs * 0.07, my)
          ..quadraticBezierTo(0, my + bs * 0.06 * (1 + 0.6 * m.hover), bs * 0.07, my),
        line,
      );
    }

    // sleeping Z's and the startle "!"
    if (sleep > 0.3) {
      for (var i = 0; i < 2; i++) {
        final ph = ((t * 0.5 + i * 0.5) % 1.0);
        _z(
          canvas,
          Offset(bw * (0.38 + ph * 0.18), top - bs * (0.02 + ph * 0.28)),
          bs * (0.035 + 0.025 * ph),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = bs * 0.022
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: (sleep - 0.3) * (1 - ph)),
        );
      }
    }
    if (m.startle > 0) {
      final a = math.min(1.0, m.startle * 3);
      final p = Paint()
        ..color = _pink.withValues(alpha: a)
        ..strokeWidth = bs * 0.045
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(bw * 0.58, top - bs * 0.14), Offset(bw * 0.58, top - bs * 0.02), p);
      canvas.drawCircle(Offset(bw * 0.58, top + bs * 0.04), bs * 0.03, p);
    }
    canvas.restore();

    // hearts float up (not affected by the squish / flip)
    for (final p in m.particles) {
      if (p.age < 0) continue;
      final a = (1 - p.age / 1.1).clamp(0.0, 1.0);
      _heart(
        canvas,
        Offset(cx + p.x * bs, baseY - bs * 0.95 + p.y * bs),
        bs * 0.085 * (0.7 + 0.3 * a),
        Paint()..color = _pink.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(PipPainter old) => true;
}

enum PipSpot { hidden, idle, seat }

/// One Pip that lives across idle -> open: it flies a looping path between
/// its spots (and back along the same path), then lands with a squish.
class PipActor extends StatefulWidget {
  const PipActor({
    super.key,
    required this.c,
    required this.spot,
    required this.idleBox,
    required this.seatBox,
  });
  final IslandController c;
  final PipSpot spot;
  final Rect idleBox, seatBox; // island coordinates

  @override
  State<PipActor> createState() => _PipActorState();
}

class _PipActorState extends State<PipActor>
    with SingleTickerProviderStateMixin {
  static const _nominal = 78.0;
  final PipModel _m = PipModel();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  final math.Random _rng = math.Random();

  PipSpot _spot = PipSpot.hidden;
  Offset _pos = Offset.zero;
  double _scale = 1, _rot = 0, _vis = 0, _visV = 0;
  double _ft = -1, _dur = 1.2, _seed = 0, _fromScale = 1, _appear = 0;
  Offset _from = Offset.zero;
  final List<Offset> _trail = [];

  /// Bumped every tick: Pip and its trail repaint from it without the
  /// widget tree rebuilding. Only the hover/press area is a widget, and it
  /// rebuilds only when Pip becomes touchable or changes size.
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final _PipLayerPainter _painter = _PipLayerPainter(this);
  bool _interactive = false, _gone = true;
  double _hitScale = 0;

  double get _drawScale => _scale * _vis.clamp(0.0, 1.2);

  Rect get _box => _spot == PipSpot.seat ? widget.seatBox : widget.idleBox;

  @override
  void initState() {
    super.initState();
    _spot = widget.spot;
    _pos = _box.center;
    _scale = _box.height / _nominal;
    if (_spot != PipSpot.hidden) {
      _vis = 0;
      _appear = 0.16;
      _m.startWave();
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(PipActor old) {
    super.didUpdateWidget(old);
    final prev = _spot, next = widget.spot;
    if (prev == next) return;
    _spot = next;
    if (prev == PipSpot.idle && next == PipSpot.seat) {
      _startFlight(1.25);
    } else if (prev == PipSpot.seat && next == PipSpot.idle) {
      _startFlight(0.85); // same path, reversed
    } else if (prev == PipSpot.hidden) {
      _ft = -1;
      _pos = _box.center;
      _scale = _box.height / _nominal;
      _vis = 0;
      _visV = 0;
      _appear = 0.16;
      _m.startWave();
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _startFlight(double seconds) {
    _ft = 0;
    _from = _pos;
    _fromScale = _scale;
    _dur = seconds;
    _seed = _rng.nextDouble() * math.pi * 2;
    _m.flying = true;
    _trail.clear();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration e) {
    var dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    // appear / disappear spring
    _appear = math.max(0.0, _appear - dt);
    final vt = (_spot == PipSpot.hidden || _appear > 0) ? 0.0 : 1.0;
    _visV += (-170 * (_vis - vt) - 26 * _visV) * dt;
    _vis += _visV * dt;

    final tc = _box.center;
    final ts = _box.height / _nominal;
    var vx = 0.0;
    if (_ft >= 0) {
      _ft += dt / _dur;
      final t = _ft.clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(t);
      final env = math.sin(math.pi * t);
      final radius = math.min(widget.seatBox.height * 0.55, 40.0);
      final ang = 2 * math.pi * 1.4 * t + _seed;
      final loop = Offset(
        math.cos(ang) * radius * env * 1.6,
        math.sin(ang) * radius * env * 0.7,
      );
      final p = Offset.lerp(_from, tc, eased)! + loop;
      vx = (p.dx - _pos.dx) / dt;
      _pos = p;
      _scale = (_fromScale + (ts - _fromScale) * eased) * (1 + 0.18 * env);
      final roll =
          2 *
          math.pi *
          Curves.easeInOut.transform(((t - 0.15) / 0.6).clamp(0.0, 1.0));
      _rot = roll + (vx * 0.0012).clamp(-0.45, 0.45);
      _trail.add(_pos);
      if (_trail.length > 12) _trail.removeAt(0);
      if (_ft >= 1) {
        _ft = -1;
        _rot = 0;
        _m.flying = false;
        _m.land();
        _trail.clear();
      }
    } else {
      _pos = tc;
      _scale = ts;
      _rot = 0;
    }

    _m.gazeTarget = _ft >= 0
        ? Offset((vx / 400).clamp(-1.0, 1.0).toDouble(), 0)
        : widget.c.gaze.value;
    _m.step(dt);

    if (_spot == PipSpot.hidden && _vis < 0.01 && _ft < 0) {
      _vis = 0;
      _ticker.stop();
    }
    final interactive = _spot == PipSpot.seat && _ft < 0 && _vis > 0.6;
    final gone = _vis < 0.01 && _spot == PipSpot.hidden;
    if (interactive != _interactive ||
        gone != _gone ||
        (interactive && (_drawScale - _hitScale).abs() > 0.004)) {
      setState(() {});
    }
    _frame.value++;
  }

  Offset _n(Offset p) => Offset(p.dx / _nominal, p.dy / _nominal);

  @override
  Widget build(BuildContext context) {
    _gone = _vis < 0.01 && _spot == PipSpot.hidden;
    _interactive = _spot == PipSpot.seat && _ft < 0 && _vis > 0.6;
    if (_gone) return const SizedBox.shrink();
    _frame.value++; // the colour or boxes may have changed with the widget
    final layer = IgnorePointer(child: CustomPaint(painter: _painter, size: Size.infinite));
    if (!_interactive) return layer;

    // Seated: the same box Pip is drawn in, so hover lands where it did.
    _hitScale = _drawScale;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: layer),
        Positioned(
          left: _pos.dx - _nominal / 2,
          top: _pos.dy - _nominal / 2,
          width: _nominal,
          height: _nominal,
          child: Transform.rotate(
            angle: _rot,
            child: Transform.scale(
              scale: _hitScale,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                onEnter: (e) => _m.hoverMove(_n(e.localPosition)),
                onHover: (e) => _m.hoverMove(_n(e.localPosition)),
                onExit: (_) => _m.leave(),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _m.poke(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pip and its flight trail, drawn straight from the actor's state.
class _PipLayerPainter extends CustomPainter {
  _PipLayerPainter(this.a) : super(repaint: a._frame);
  final _PipActorState a;

  @override
  void paint(Canvas canvas, Size size) {
    final color = a.widget.c.pipColor;
    final pts = a._trail;
    if (pts.length > 1) {
      for (var i = 0; i < pts.length; i++) {
        final f = i / pts.length;
        canvas.drawCircle(pts[i], 2 + 5 * f, Paint()..color = color.withValues(alpha: 0.05 + 0.35 * f));
      }
    }
    if (a._vis < 0.01 && a._spot == PipSpot.hidden) return;
    const half = _PipActorState._nominal / 2;
    canvas.save();
    // Same as Transform.rotate + Transform.scale about the box centre.
    canvas.translate(a._pos.dx, a._pos.dy);
    canvas.rotate(a._rot);
    canvas.scale(a._drawScale);
    canvas.translate(-half, -half);
    PipPainter(a._m, color).paint(canvas, const Size.square(_PipActorState._nominal));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PipLayerPainter old) => old.a != a;
}
