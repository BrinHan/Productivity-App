import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Fillet ("ear") radius for a pill of height [h].
double notchEar(double h) => math.min(16.0, h * 0.3);

/// A pill that hangs from the top edge of the screen. The top edge is flat
/// and flush; at both ends it flares outward into a concave fillet (like the
/// MacBook notch). Total width is w + 2f; the body is x in [f, f + w].
///
/// With no ears ([f] 0) and a [top] radius, it is a free-standing rounded
/// rectangle instead (the unlock square).
Path notchPath(double w, double h, double f, double r, {double top = 0}) {
  f = math.min(f, h * 0.5);
  r = math.max(0.0, math.min(r, math.min(w / 2, h - f)));
  const k = 0.62; // a bit above 0.5523: a smoother, squircle-like curve
  final bw = w + 2 * f;
  if (f < 0.01 && top > 0) {
    final t = math.min(top, math.min(w / 2, h - r));
    return Path()
      ..moveTo(t, 0)
      ..lineTo(w - t, 0)
      ..cubicTo(w - t + k * t, 0, w, t - k * t, w, t)
      ..lineTo(w, h - r)
      ..cubicTo(w, h - r + k * r, w - r + k * r, h, w - r, h)
      ..lineTo(r, h)
      ..cubicTo(r - k * r, h, 0, h - r + k * r, 0, h - r)
      ..lineTo(0, t)
      ..cubicTo(0, t - k * t, t - k * t, 0, t, 0)
      ..close();
  }
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
  const NotchClipper(this.w, this.h, this.f, this.r, {this.top = 0});
  final double w, h, f, r, top;

  @override
  Path getClip(Size size) => notchPath(w, h, f, r, top: top);

  @override
  bool shouldReclip(NotchClipper o) => o.w != w || o.h != h || o.f != f || o.r != r || o.top != top;
}
