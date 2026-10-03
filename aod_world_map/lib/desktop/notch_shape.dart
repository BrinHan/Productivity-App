import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Fillet ("ear") radius for a pill of height [h].
double notchEar(double h) => math.min(16.0, h * 0.3);

/// A pill that hangs from the top edge of the screen. The top edge is flat
/// and flush; at both ends it flares outward into a concave fillet (like the
/// MacBook notch). Total width is w + 2f; the body is x in [f, f + w].
Path notchPath(double w, double h, double f, double r) {
  f = math.min(f, h * 0.5);
  r = math.max(0.0, math.min(r, math.min(w / 2, h - f)));
  const k = 0.62; // a bit above 0.5523: a smoother, squircle-like curve
  final bw = w + 2 * f;
  return Path()
    ..moveTo(0, 0)
    ..lineTo(bw, 0)
    ..cubicTo(bw - k * f, 0, bw - f, f - k * f, bw - f, f)
    ..lineTo(bw - f, h - r)
    ..cubicTo(bw - f, h - r + k * r, bw - f - r + k * r, h, bw - f - r, h)
    ..lineTo(f + r, h)
    ..cubicTo(f + r - k * r, h, f, h - r + k * r, f, h - r)
    ..lineTo(f, f)
    ..cubicTo(f, f - k * f, k * f, 0, 0, 0)
    ..close();
}

class NotchClipper extends CustomClipper<Path> {
  const NotchClipper(this.w, this.h, this.f, this.r);
  final double w, h, f, r;

  @override
  Path getClip(Size size) => notchPath(w, h, f, r);

  @override
  bool shouldReclip(NotchClipper o) => o.w != w || o.h != h || o.f != f || o.r != r;
}
