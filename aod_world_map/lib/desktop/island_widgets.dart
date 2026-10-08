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
  const IslandPressable({super.key, required this.child, required this.onTap, this.label});
  final Widget child;
  final VoidCallback onTap;

  /// What a screen reader says for a button that is only an icon.
  final String? label;

  @override
  State<IslandPressable> createState() => _IslandPressableState();
}

class _IslandPressableState extends State<IslandPressable> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        onTap: widget.onTap,
        child: _pressable(),
      );

  Widget _pressable() => MouseRegion(
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
  // Runs only while the text is too long to fit; a ticker left running
  // would make the island redraw every frame for nothing.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  TextPainter? _tp;
  bool _scroll = false;

  TextPainter get _measured => _tp ??= TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  void didUpdateWidget(IslandMarquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _tp?.dispose();
      _tp = null;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _tp?.dispose();
    super.dispose();
  }

  void _setScrolling(bool v) {
    if (v == _scroll) return;
    _scroll = v;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll) {
        if (!_c.isAnimating) _c.repeat();
      } else {
        _c.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cons) {
        final tp = _measured;
        final tw = tp.width;
        _setScrolling(tw > cons.maxWidth);
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
                // The text is laid out and recorded once; frames only slide it.
                child: RepaintBoundary(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.text, style: widget.style, maxLines: 1),
                      const SizedBox(width: gap),
                      Text(widget.text, style: widget.style, maxLines: 1),
                    ],
                  ),
                ),
                builder: (_, row) => OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(-_c.value * (tw + gap), 0),
                    child: row,
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
  const IslandWaveform({super.key, required this.active, this.bands, this.color = const Color(0xFF30D158)});
  final bool active;
  final AudioBands? bands;

  /// The bars' colour while playing.
  final Color color;

  @override
  State<IslandWaveform> createState() => _IslandWaveformState();
}

class _IslandWaveformState extends State<IslandWaveform> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final List<double> _lv = List.filled(5, 0.0);
  final ValueNotifier<int> _frame = ValueNotifier(0); // bars repaint, nothing rebuilds
  Duration _last = Duration.zero;
  double _t = 0;

  /// How long the measured levels have been silent while playing.
  double _quiet = 0;

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
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = e;
    _t += dt;
    final b = widget.bands;
    // Playing but the PC hears nothing (e.g. Spotify playing on a phone):
    // after a moment, animate the bars instead of leaving them flat.
    final heard = b != null && b.supported && b.live && b.values.any((v) => v > 0.02);
    _quiet = heard ? 0 : _quiet + dt;
    final measured = b != null && b.supported && (heard || _quiet < 0.6);
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
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(size: const Size(32, 30), painter: _BarsPainter(this)),
      );
}

/// The five bars: 3.5 wide, spread across 32, centred vertically.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.s) : super(repaint: s._frame);
  final _IslandWaveformState s;

  @override
  void paint(Canvas canvas, Size size) {
    const bw = 3.5;
    final gap = (size.width - 5 * bw) / 4;
    final paint = Paint()..color = s.widget.active ? s.widget.color : const Color(0x55FFFFFF);
    for (var i = 0; i < 5; i++) {
      final h = 5 + 23 * s._lv[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (bw + gap), (size.height - h) / 2, bw, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.s != s || old.s.widget.active != s.widget.active || old.s.widget.color != s.widget.color;
}

/// A small tile in the colours of the app that is playing. Windows gives
/// only the app's id, so it is a coloured icon rather than the real logo.
class IslandAppBadge extends StatelessWidget {
  const IslandAppBadge({super.key, required this.app, this.size = 22});
  final String app;
  final double size;

  (Color, Color, IconData) get _look {
    final a = app.toLowerCase();
    if (a.contains('spotify')) return (const Color(0xFF1ED760), const Color(0xFF169C46), Icons.graphic_eq_rounded);
    if (a.contains('applemusic') || a.contains('itunes')) {
      return (const Color(0xFFFF5E73), const Color(0xFFFA233B), Icons.music_note_rounded);
    }
    if (a.contains('zunemusic') || a.contains('mediaplayer')) {
      return (const Color(0xFFFF7A45), const Color(0xFFE0451F), Icons.play_arrow_rounded);
    }
    if (a.contains('vlc')) return (const Color(0xFFFFA033), const Color(0xFFE07000), Icons.play_arrow_rounded);
    if (a.contains('chrome') || a.contains('msedge') || a.contains('firefox') || a.contains('brave') || a.contains('opera')) {
      return (const Color(0xFF5AA0FF), const Color(0xFF2A6FDB), Icons.language_rounded);
    }
    return (const Color(0xFF5A5A5E), const Color(0xFF3A3A3C), Icons.music_note_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final (top, bottom, icon) = _look;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.27),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
      ),
      child: Icon(icon, size: size * 0.64, color: Colors.white),
    );
  }
}
