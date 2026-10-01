
import 'package:flutter/material.dart';

/// Day/night switch: sun slides into a moon, clouds drop away, stars appear.
/// `isNight == true` means dark mode. [em] sets the size (width = 5.625 em).
class SkyToggle extends StatefulWidget {
  const SkyToggle({
    super.key,
    required this.isNight,
    required this.onChanged,
    this.em = 12,
  });

  final bool isNight;
  final ValueChanged<bool> onChanged;
  final double em;

  @override
  State<SkyToggle> createState() => _SkyToggleState();
}

class _SkyToggleState extends State<SkyToggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.isNight ? 1 : 0,
  );

  @override
  void didUpdateWidget(SkyToggle old) {
    super.didUpdateWidget(old);
    if (old.isNight != widget.isNight) {
      widget.isNight ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final em = widget.em;
    return Semantics(
      button: true,
      toggled: widget.isNight,
      label: 'Dark mode',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onChanged(!widget.isNight),
          child: SizedBox(
            width: 5.625 * em,
            height: 2.5 * em,
            child: CustomPaint(painter: _SkyPainter(_c, em)),
          ),
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.ctrl, this.em) : super(repaint: ctrl);

  final AnimationController ctrl;
  final double em;

  // Same easing curves as the original CSS (they overshoot slightly = springy).
  static const _body = Cubic(0, -0.02, 0.4, 1.25);
  static const _knob = Cubic(0, -0.02, 0.35, 1.17);

  static const _lightBg = Color(0xFF3D7EAE), _nightBg = Color(0xFF1D1F2C);
  static const _sun = Color(0xFFECCA2F), _moon = Color(0xFFC4C9D1), _spot = Color(0xFF959DB1);
  static const _cloud = Color(0xFFF3FDFF), _backCloud = Color(0xFFAACADF);

  // dx, dy, front(1)/back(0), spread  — in em, relative to the base cloud.
  static const _cloudPuffs = <List<double>>[
    [0.937, 0.312, 1, 0],
    [-0.312, -0.312, 0, 0],
    [1.437, 0.375, 1, 0],
    [0.5, -0.125, 0, 0],
    [2.187, 0, 1, 0],
    [1.25, -0.062, 0, 0],
    [2.937, 0.312, 1, 0],
    [2, -0.312, 0, 0],
    [3.625, -0.062, 1, 0],
    [2.625, 0, 0, 0],
    [4.5, -0.312, 1, 0],
    [3.375, -0.437, 0, 0],
    [4.625, -1.75, 1, 0.437],
    [4, -0.625, 0, 0],
    [4.125, -2.125, 0, 0.437],
  ];

  // Star centres in the original 144x55 SVG space.
  static const _stars = <List<double>>[
    [137.5, 4.3], [35, 23.4], [4, 36.4], [58, 25.4], [85, 25.4], [140, 36.4], [103, 50.4],
  ];

  static const _w = 5.625, _h = 2.5, _kr = 1.0625; // _kr = sun/moon radius

  @override
  void paint(Canvas canvas, Size size) {
    final v = ctrl.value;
    final t = _body.transform(v);
    final k = _knob.transform(v);
    final tc = t.clamp(0.0, 1.0).toDouble();

    canvas.save();
    canvas.scale(em);

    final pill = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, _w, _h), const Radius.circular(_h / 2));
    canvas.drawRRect(pill, Paint()..color = Color.lerp(_lightBg, _nightBg, tc)!);

    canvas.save();
    canvas.clipRRect(pill);

    // Stars slide in from above.
    const s = 2.75 / 144 * 1.0;
    final starCy = -1.975 + (1.25 + 1.975) * t;
    final starTop = starCy - 55 * s / 2;
    final starPaint = Paint()..color = Colors.white;
    for (final st in _stars) {
      _star(canvas, 0.312 + st[0] * s, starTop + st[1] * s, 4.3 * s * 1.8, starPaint);
    }

    // Clouds drop away.
    final bx = 0.937, by = 2.5 + 3.4375 * t;
    for (var i = _cloudPuffs.length - 1; i >= 0; i--) {
      final p = _cloudPuffs[i];
      canvas.drawCircle(
        Offset(bx + p[0], by + p[1]),
        0.625 + p[3],
        Paint()..color = p[2] == 1 ? _cloud : _backCloud,
      );
    }
    canvas.drawCircle(Offset(bx, by), 0.625, Paint()..color = _cloud);

    // Translucent rings behind the knob.
    final cx = 1.25 + ((_w - 1.25) - 1.25) * k;
    final cy = _h / 2;
    final ring = Paint()..color = Colors.white.withValues(alpha: 0.1);
    for (final r in const [2.9375, 2.3125, 1.6875, 1.6875]) {
      canvas.drawCircle(Offset(cx, cy), r, ring);
    }

    // Sun (with soft drop shadow).
    final c = Offset(cx, cy);
    canvas.drawCircle(
      c.translate(0.06, 0.12),
      _kr,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.1),
    );
    canvas.drawCircle(c, _kr, Paint()..color = _sun);

    // Moon slides in from the right, clipped to the sun's disc.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: _kr)));
    final mc = Offset(cx + (1 - k) * 2 * _kr, cy);
    canvas.drawCircle(mc, _kr, Paint()..color = _moon);
    final left = mc.dx - _kr, top = mc.dy - _kr;
    for (final sp in const [
      [0.812, 0.312, 0.25],
      [1.375, 0.937, 0.375],
      [0.312, 0.75, 0.75],
    ]) {
      canvas.drawCircle(
        Offset(left + sp[0] + sp[2] / 2, top + sp[1] + sp[2] / 2),
        sp[2] / 2,
        Paint()..color = _spot,
      );
    }
    canvas.restore();

    canvas.restore(); // pill clip

    // Soft inner edge.
    canvas.drawRRect(
      pill.deflate(0.03),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.restore();
  }

  void _star(Canvas c, double cx, double cy, double r, Paint p) {
    final q = r * 0.22;
    c.drawPath(
      Path()
        ..moveTo(cx, cy - r)
        ..quadraticBezierTo(cx + q, cy - q, cx + r, cy)
        ..quadraticBezierTo(cx + q, cy + q, cx, cy + r)
        ..quadraticBezierTo(cx - q, cy + q, cx - r, cy)
        ..quadraticBezierTo(cx - q, cy - q, cx, cy - r)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.em != em || old.ctrl != ctrl;
}
