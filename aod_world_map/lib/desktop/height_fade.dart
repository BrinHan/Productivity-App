import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The island's black surface. It fades toward the bottom, and the taller the
/// island is, the more it fades. No fade at or below [_fullAt] (home page).
class HeightFade extends StatelessWidget {
  const HeightFade({super.key, required this.height, required this.child});
  final double height;
  final Widget child;

  static const double _fullAt = 156, _maxAt = 440, _minAlpha = 0.55, _keep = 120;

  /// Opacity at the very bottom for an island this tall (1 = opaque).
  static double bottomAlpha(double h) {
    final t = ((h - _fullAt) / (_maxAt - _fullAt)).clamp(0.0, 1.0);
    final s = t * t * (3 - 2 * t); // smoothstep
    return 1 - (1 - _minAlpha) * s;
  }

  @override
  Widget build(BuildContext context) {
    final a = bottomAlpha(height);
    final start = (_keep / math.max(height, 1.0)).clamp(0.0, 1.0);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.white.withValues(alpha: a)],
        stops: [0.0, start, 1.0],
      ).createShader(r),
      child: ColoredBox(color: Colors.black, child: child),
    );
  }
}
