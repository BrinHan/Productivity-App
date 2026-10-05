import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'island_controller.dart' show AudioBands;

const islandFontFallback = ['SF Pro Display', 'Segoe UI', 'Roboto'];

const kPipColors = <Color>[
  Color(0xFFF4EFE6), // soft white (default)
  Color(0xFFFFC9D6),
  Color(0xFFB8F0D0),
  Color(0xFFBDE0FF),
  Color(0xFFFFE9A8),
  Color(0xFFFF8A80),
];

/// Hover + press feedback without Material ink (ink would paint behind the pill).
class IslandPressable extends StatefulWidget {
  const IslandPressable({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<IslandPressable> createState() => _IslandPressableState();
}

class _IslandPressableState extends State<IslandPressable> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.93 : (_hover ? 1.04 : 1.0),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}

/// Album art from the file the media-session helper wrote, or a placeholder.
class IslandArt extends StatelessWidget {
  const IslandArt({super.key, required this.path, required this.size, this.radius = 12});
  final String? path;
  final double size, radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6A88), Color(0xFFFF99AC), Color(0xFFFFC371)],
        ),
      ),
      child: Icon(Icons.music_note, color: Colors.white, size: size * 0.5),
    );
    final p = path;
    if (p == null || p.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(p),
        key: ValueKey(p), // a new file per track, so no stale cache
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 240,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// Scrolls long text in a loop with faded edges; short text stays still.
class IslandMarquee extends StatefulWidget {
  const IslandMarquee({super.key, required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<IslandMarquee> createState() => _IslandMarqueeState();
}

class _IslandMarqueeState extends State<IslandMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cons) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final tw = tp.width;
        if (tw <= cons.maxWidth) return Text(widget.text, style: widget.style, maxLines: 1);

        const gap = 36.0;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.08, 0.92, 1],
          ).createShader(r),
          child: ClipRect(
            child: SizedBox(
              height: tp.height,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(-_c.value * (tw + gap), 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.text, style: widget.style, maxLines: 1),
                        const SizedBox(width: gap),
                        Text(widget.text, style: widget.style, maxLines: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
}

/// Five bars, low end on the left to treble on the right, following what the
/// speakers play (see [AudioBands]). A bar jumps up on a hit and falls back
/// more gently, like a VU meter. Without measured audio (the PowerShell
/// fallback) the bars just bounce; with nothing playing they lie flat.
class IslandWaveform extends StatefulWidget {
  const IslandWaveform({super.key, required this.active, this.bands});
  final bool active;
  final AudioBands? bands;

  @override
  State<IslandWaveform> createState() => _IslandWaveformState();
}

class _IslandWaveformState extends State<IslandWaveform> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final List<double> _lv = List.filled(5, 0.0);
  Duration _last = Duration.zero;
  double _t = 0;

  static const _cycles = [1, 2, 3, 2, 1];

  @override
  void initState() {
    super.initState();
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(IslandWaveform old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = e;
    _t += dt;
    final b = widget.bands;
    final measured = b != null && b.supported;
    var settled = true;
    for (var i = 0; i < 5; i++) {
      final double target;
      if (!widget.active) {
        target = 0;
      } else if (measured) {
        target = b.live ? b.values[i] : 0;
      } else {
        target = math.sin(2 * math.pi * _cycles[i] * _t / 1.2 + i * 1.3).abs();
      }
      // Snap up on a hit, fall back gently.
      final rate = target > _lv[i] ? 32.0 : 9.0;
      _lv[i] += (target - _lv[i]) * (1 - math.exp(-rate * dt));
      if (target > 0 || _lv[i] > 0.002) settled = false;
    }
    if (!widget.active && settled) _ticker.stop();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 30,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(
            5,
            (i) => Container(
              width: 3.5,
              height: 5 + 23 * _lv[i],
              decoration: BoxDecoration(
                color: widget.active ? const Color(0xFF30D158) : const Color(0x55FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
}
