import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'aod_palette.dart';

/// Liquid wave rising inside a circle, with cycling status text.
class LiquidWaveLoader extends StatefulWidget {
  const LiquidWaveLoader({
    super.key,
    required this.palette,
    this.size = 150,
    this.messages = const [
      'Finding your location ...',
      'Loading the map ...',
      'Checking the time ...',
    ],
  });

  final AodPalette palette;
  final double size;
  final List<String> messages;

  @override
  State<LiquidWaveLoader> createState() => _LiquidWaveLoaderState();
}

class _LiquidWaveLoaderState extends State<LiquidWaveLoader>
    with TickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  late final AnimationController _riseCtl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..forward();
  late final Animation<double> _rise = CurvedAnimation(
    parent: _riseCtl,
    curve: Curves.easeOut,
  );
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    if (widget.messages.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() => _i = (_i + 1) % widget.messages.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wave.dispose();
    _riseCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _WavePainter(_wave, _rise, p.text, p.night),
            ),
          ),
          const SizedBox(height: 24),
          if (widget.messages.isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                widget.messages[_i],
                key: ValueKey(_i),
                style: TextStyle(
                  color: p.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.phase, this.rise, this.color, this.bg)
    : super(repaint: Listenable.merge([phase, rise]));

  final Animation<double> phase, rise;
  final Color color, bg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = bg);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    // Keep the water level relative to the circle, so the rise fills the
    // indicator instead of being compressed into the lower half.
    final level = c.dy + r * (1 - 1.7 * rise.value);
    final amp = r * 0.10;

    void wave(double shift, double alpha) {
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 2) {
        path.lineTo(
          x,
          level + math.sin(x / size.width * 2 * math.pi * 1.5 + shift) * amp,
        );
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
    }

    wave(phase.value * 2 * math.pi, 0.4);
    wave(-phase.value * 2 * math.pi * 1.3 + 1.0, 1.0);
    canvas.restore();

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.025)
        ..color = color.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase ||
      old.rise != rise ||
      old.color != color ||
      old.bg != bg;
}
