import 'dart:math' as math;

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
  double pet = 0, petEnergy = 0;
  double sleep = 0, idleFor = 0;
  double fly = 0;
  bool flying = false;
  double _hoverFor = 0, _heartTimer = 0;
  final List<double> _clicks = [];
  final List<Heart> particles = [];
  final math.Random _rng = math.Random();

  void startWave() => wave = 1.6;
  void land() => _squishV += 7;

  void _wake() {
    if (sleep > 0.5) {
      startle = 0.8;
      _squishV -= 6;
    }
    idleFor = 0;
  }

  void hoverMove(Offset p, double dist) {
    if (!hovering) _wake();
    hovering = true;
    ptr = p;
    lastPtr = p;
    idleFor = 0;
    petEnergy = math.min(petEnergy + dist * 0.035, 2.0);
  }

  void leave() {
    hovering = false;
    ptr = null;
  }

  /// Pointer-down: reacts instantly (no waiting for release).
  void poke() {
    _wake();
    final last = _clicks.isEmpty ? -9.0 : _clicks.last;
    final dbl = t - last < 0.32;
    _clicks.removeWhere((c) => t - c > 1.0);
    _clicks.add(t);
    _squishV += 5;
    hearts = 0;
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

    // petting = moving the cursor back and forth over Pip
    petEnergy = math.max(0.0, petEnergy - dt * 1.4);
    final petting = hovering && petEnergy > 0.55;
    pet +=
        ((petting ? 1.0 : 0.0) - pet) * (1 - math.exp(-dt * (petting ? 9 : 4)));
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

    const n = 4;
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      final a = -190 * squish - 11 * _squishV;
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

  void _arm(Canvas c, Offset s, double angle, double bs, Paint p) {
    c.save();
    c.translate(s.dx, s.dy);
    c.rotate(angle);
    c.drawRRect(
      RRect.fromLTRBR(
        -bs * 0.05,
        0,
        bs * 0.05,
        bs * 0.22,
        Radius.circular(bs * 0.05),
      ),
      p,
    );
    c.restore();
  }

  void _heart(Canvas c, Offset o, double s, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(o.dx, o.dy + s * 0.9)
        ..cubicTo(
          o.dx - s * 1.5,
          o.dy - s * 0.1,
          o.dx - s * 0.7,
          o.dy - s * 1.2,
          o.dx,
          o.dy - s * 0.4,
        )
        ..cubicTo(
          o.dx + s * 0.7,
          o.dy - s * 1.2,
          o.dx + s * 1.5,
          o.dy - s * 0.1,
          o.dx,
          o.dy + s * 0.9,
        ),
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

  /// Squircle bean. The top is pushed in where the pointer presses.
  Path _body(
    double bw,
    double bh,
    double top,
    double bottom,
    double dent,
    double dentX,
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
      if (s < 0 && dent > 0) {
        final g = math.exp(-math.pow((x - dentX) / (bw * 0.30), 2).toDouble());
        y += dent * g * math.min(1.0, -s * 1.6);
        x *= 1 + 0.10 * dent / bh;
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
    final sq = m.squish.clamp(-0.4, 0.8).toDouble();
    final bw = bs * 0.80, bh = bs * 0.78;
    final bottom = -bs * 0.10, top = bottom - bh;

    // squishy head
    var dent = 0.0, dentX = 0.0;
    if (m.ptrOn > 0.01) {
      final px = m.lastPtr.dx * size.width - cx;
      final py = m.lastPtr.dy * size.height - baseY;
      final pen = ((py - top) / (bh * 0.35)).clamp(0.0, 1.0);
      final relax = 1 - ((py - top - bh * 0.55) / (bh * 0.30)).clamp(0.0, 1.0);
      final lateral = (1 - px.abs() / (bw * 0.75)).clamp(0.0, 1.0);
      dent = pen * relax * lateral * m.ptrOn * bh * 0.34;
      dentX = px;
    }
    final dr = dent / bh;
    double g(double x) =>
        math.exp(-math.pow((x - dentX) / (bw * 0.30), 2).toDouble());

    final ink = Paint()
      ..color = _ink
      ..isAntiAlias = true;
    final bodyPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
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
        math.sin(t * 17) * 0.06 * m.pet +
        (dent > 0 ? (dentX / bw) * 0.10 * m.ptrOn : 0.0);
    final sx =
        1 +
        0.22 * sq -
        0.015 * breathe +
        0.10 * dr +
        0.04 * m.pet * math.sin(t * 19);
    final sy = 1 - 0.30 * sq + 0.03 * breathe - 0.08 * dr;
    canvas.translate(cx + m.gaze.dx * bs * 0.03, baseY);
    canvas.rotate(rot);
    canvas.scale(sx, sy);

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

    // arms: relaxed, waving, happy, dizzy or flying
    var la = 0.35 + 0.75 * m.pet, ra = -(0.35 + 0.75 * m.pet);
    if (m.dizzy > 0) la += math.sin(t * 9) * 0.3;
    if (m.wave > 0) ra = -2.3 + math.sin(t * 16) * 0.35;
    if (m.fly > 0.02) {
      final fl = math.sin(t * 26) * 0.4;
      la += (2.4 + fl - la) * m.fly;
      ra += (-2.4 - fl - ra) * m.fly;
    }
    _arm(
      canvas,
      Offset(-bw / 2 + bs * 0.02, top + bh * 0.52),
      la,
      bs,
      partPaint,
    );
    _arm(
      canvas,
      Offset(bw / 2 - bs * 0.02, top + bh * 0.52),
      ra,
      bs,
      partPaint,
    );

    // body + highlight
    canvas.drawPath(_body(bw, bh, top, bottom, dent, dentX), bodyPaint);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-bw * 0.18, top + bh * 0.16 + dent * g(-bw * 0.18)),
        width: bw * 0.28,
        height: bh * 0.12,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // sprout
    final sway =
        math.sin(t * 1.7) * 0.12 +
        m.gaze.dx * 0.2 +
        math.sin(t * 22) * 0.10 * m.pet;
    final perk = 1 + 0.25 * m.hover + 0.35 * m.pet - 0.5 * sleep;
    final len = bs * 0.16 * perk;
    canvas.save();
    canvas.translate(0, top + bh * 0.02 + dent * g(0));
    canvas.rotate(sway + (m.annoyed > 0 ? 0.0 : 0.0));
    canvas.drawLine(
      Offset.zero,
      Offset(0, -len),
      Paint()
        ..color = _stem
        ..strokeWidth = bs * 0.035
        ..strokeCap = StrokeCap.round,
    );
    final droop = (m.annoyed > 0 ? 0.6 : 0.0) + sleep * 0.6;
    for (final sgn in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(0, -len);
      canvas.rotate(sgn * (0.75 - 0.35 * droop));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -bs * 0.07),
          width: bs * 0.10,
          height: bs * 0.17,
        ),
        Paint()..color = _leaf,
      );
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
    final openEye = (1 - math.max(m.pet, sleep)).clamp(0.0, 1.0);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bs * 0.03
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = _ink;

    if (m.dizzy > 0) {
      for (final sgn in const [-1.0, 1.0]) {
        final ey = ey0 + dent * 0.5 * g(sgn * ex);
        _spiral(canvas, Offset(sgn * ex, ey), r * 1.5, sgn * t * 8, line);
      }
    } else {
      for (final sgn in const [-1.0, 1.0]) {
        final ey = ey0 + dent * 0.5 * g(sgn * ex);
        final c0 = Offset(sgn * ex + gx, ey + gy);
        if (openEye > 0.02) {
          canvas.drawOval(
            Rect.fromCenter(
              center: c0,
              width: (r * 2).toDouble(),
              height: math.max(1.0, r * 2 * hf).toDouble(),
            ),
            Paint()..color = _ink.withValues(alpha: openEye.toDouble()),
          );
          if (blink < 0.5) {
            canvas.drawCircle(
              c0 + Offset(-r * 0.3, -r * 0.3 * hf),
              r * 0.28,
              Paint()..color = Colors.white.withValues(alpha: 0.9 * openEye),
            );
          }
        }
        if (m.pet > 0.02) {
          // happy ^ eyes while being petted
          canvas.drawPath(
            Path()
              ..moveTo(c0.dx - r * 1.2, c0.dy + r * 0.5)
              ..quadraticBezierTo(
                c0.dx,
                c0.dy - r * 1.5,
                c0.dx + r * 1.2,
                c0.dy + r * 0.5,
              ),
            line..color = _ink.withValues(alpha: m.pet),
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

    // blush
    final blush = math.max(
      math.max(m.pet * 0.55, m.hearts > 0 ? 0.35 : 0.0),
      m.hover * 0.12,
    );
    if (blush > 0.02) {
      for (final sgn in const [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(sgn * ex * 1.5, ey0 + r * 2.3),
            width: bs * 0.13,
            height: bs * 0.075,
          ),
          Paint()..color = _pink.withValues(alpha: blush),
        );
      }
    }

    // mouth
    final my = ey0 + bw * 0.24 + dent * 0.4 * g(0);
    if (m.dizzy > 0) {
      final path = Path();
      for (var i = 0; i <= 12; i++) {
        final x = -bs * 0.09 + i * (bs * 0.18 / 12);
        final y = my + math.sin(i * 1.2 + t * 8) * bs * 0.02;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, line);
    } else if (m.annoyed > 0) {
      canvas.drawLine(
        Offset(-bs * 0.07, my + bs * 0.01),
        Offset(bs * 0.07, my - bs * 0.01),
        line,
      );
    } else if (m.pet > 0.3 || m.hearts > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(-bs * 0.09, my - bs * 0.01)
          ..quadraticBezierTo(
            0,
            my + bs * 0.17 * (0.6 + 0.4 * m.pet),
            bs * 0.09,
            my - bs * 0.01,
          )
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
        Rect.fromCenter(
          center: Offset(0, my + bs * 0.02),
          width: bs * 0.08,
          height: bs * 0.10,
        ),
        ink,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-bs * 0.07, my)
          ..quadraticBezierTo(
            0,
            my + bs * 0.06 * (1 + 0.6 * m.hover),
            bs * 0.07,
            my,
          ),
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
      canvas.drawLine(
        Offset(bw * 0.58, top - bs * 0.14),
        Offset(bw * 0.58, top - bs * 0.02),
        p,
      );
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

  Rect get _box => _spot == PipSpot.seat ? widget.seatBox : widget.idleBox;

  @override
  void initState() {
    super.initState();
    _spot = widget.spot;
    _pos = _box.center;
    _scale = _box.height / _nominal;
    if (_spot != PipSpot.hidden) {
      _vis = 1;
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
    setState(() {});
  }

  Offset _n(Offset p) => Offset(p.dx / _nominal, p.dy / _nominal);

  @override
  Widget build(BuildContext context) {
    if (_vis < 0.01 && _spot == PipSpot.hidden) return const SizedBox.shrink();
    final s = _scale * _vis.clamp(0.0, 1.2);
    final interactive = _spot == PipSpot.seat && _ft < 0 && _vis > 0.6;

    Widget pip = SizedBox(
      width: _nominal,
      height: _nominal,
      child: CustomPaint(painter: PipPainter(_m, widget.c.pipColor)),
    );
    pip = interactive
        ? MouseRegion(
            cursor: SystemMouseCursors.grab,
            onEnter: (e) => _m.hoverMove(_n(e.localPosition), 0),
            onHover: (e) => _m.hoverMove(_n(e.localPosition), e.delta.distance),
            onExit: (_) => _m.leave(),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _m.poke(),
              child: pip,
            ),
          )
        : IgnorePointer(child: pip);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_trail.length > 1)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TrailPainter(List.of(_trail), widget.c.pipColor),
              ),
            ),
          ),
        Positioned(
          left: _pos.dx - _nominal / 2,
          top: _pos.dy - _nominal / 2,
          width: _nominal,
          height: _nominal,
          child: Transform.rotate(
            angle: _rot,
            child: Transform.scale(scale: s, child: pip),
          ),
        ),
      ],
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.pts, this.color);
  final List<Offset> pts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < pts.length; i++) {
      final f = i / pts.length;
      canvas.drawCircle(
        pts[i],
        2 + 5 * f,
        Paint()..color = color.withValues(alpha: 0.05 + 0.35 * f),
      );
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => true;
}
