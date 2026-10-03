import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'island_controller.dart';
import 'island_pages.dart';
import 'island_widgets.dart';
import 'notch_shape.dart';
import 'height_fade.dart';
import 'pip.dart';
import 'spring.dart';

/// Transparent screen used while the app is in island mode.
class IslandScreen extends StatelessWidget {
  const IslandScreen({super.key, required this.island, this.onShortcut});
  final IslandController island;
  final void Function(IslandShortcut)? onShortcut;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
              island.close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Align(
            alignment: Alignment.topCenter, // flush with the top of the screen
            child: DynamicIsland(controller: island, onShortcut: onShortcut, publishGeometry: true),
          ),
        ),
      );
}

class DynamicIsland extends StatefulWidget {
  const DynamicIsland({
    super.key,
    required this.controller,
    this.showWhenHidden = false,
    this.onShortcut,
    this.publishGeometry = false,
  });
  final IslandController controller;
  final bool showWhenHidden;
  final void Function(IslandShortcut)? onShortcut;
  final bool publishGeometry;

  @override
  State<DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends State<DynamicIsland> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  late IslandState _shown = _effective;
  late final Spring _w = Spring(_sizeFor(_shown).width);
  late final Spring _h = Spring(_sizeFor(_shown).height);
  late final Spring _dy = Spring(_dyFor(_shown));

  IslandState get _effective {
    final s = widget.controller.state;
    return (s == IslandState.hidden && widget.showWhenHidden) ? IslandState.idle : s;
  }

  Size _sizeFor(IslandState s) {
    final c = widget.controller;
    final idle = c.idleSize;
    if (s == IslandState.hidden) return Size(idle.width * 0.42, 0);
    switch (s) {
      case IslandState.open:
        return openSizeFor(c.page);
      case IslandState.call:
        return Size(math.max(400, idle.width + 60), math.max(84, idle.height + 16));
      case IslandState.music:
        return Size(math.max(330, idle.width + 40), math.max(68, idle.height + 8));
      case IslandState.success:
        return const Size(86, 86);
      case IslandState.notch:
        return const Size(112, 20);
      case IslandState.idle:
      case IslandState.hidden:
        return idle;
    }
  }

  double _dyFor(IslandState s) =>
      0.0;

  PipSpot get _pipSpot {
    if (_shown == IslandState.idle) return PipSpot.idle;
    if (_shown == IslandState.open && widget.controller.page == IslandPage.home) {
      return PipSpot.seat;
    }
    return PipSpot.hidden;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(DynamicIsland old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _ticker.dispose();
    super.dispose();
  }

  void _onChange() {
    final next = _effective;
    final prev = _shown;
    _shown = next;
    final ns = _sizeFor(next);
    _w.target = ns.width;
    _h.target = ns.height;
    _dy.target = _dyFor(next);

    if (next != prev) {
      final ps = _sizeFor(prev);
      final from = prev != IslandState.hidden && prev != IslandState.notch;
      if (from && next != IslandState.hidden) {
        if (ns.width > ps.width) {
          _h.velocity -= 120;
          _w.velocity += 60;
        } else if (ns.width < ps.width) {
          _h.velocity += 100;
          _w.velocity -= 40;
        }
      }
      if (next == IslandState.success) {
        _w.velocity += 160;
        _h.velocity += 160;
      }
    }
    if (!_ticker.isActive && !(_w.settled && _h.settled && _dy.settled)) {
      _last = Duration.zero;
      _ticker.start();
    }
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;
    _w.step(dt);
    _h.step(dt);
    _dy.step(dt);
    if (widget.publishGeometry) {
      widget.controller.pillSize = Size(_w.value, _h.value);
      widget.controller.pillDy = _dy.value;
    }
    if (_w.settled && _h.settled && _dy.settled) _ticker.stop();
    setState(() {});
  }

  void _onPillTap() {
    final c = widget.controller;
    if (_shown == IslandState.idle || _shown == IslandState.notch) {
      c.open(IslandPage.home);
    } else if (_shown == IslandState.music) {
      c.open(IslandPage.music);
    }
  }

  Widget _content(IslandState s) {
    final c = widget.controller;
    switch (s) {
      case IslandState.hidden:
      case IslandState.notch:
      case IslandState.idle: // Pip is drawn by the PipActor overlay
        return const SizedBox.shrink();
      case IslandState.open:
        return IslandOpenContent(c: c, onShortcut: widget.onShortcut);
      case IslandState.call:
        return _CallContent(onAccept: c.accept, onDecline: c.decline);
      case IslandState.music:
        final np = c.nowPlaying;
        return _MusicContent(
          title: np == null ? 'Nothing playing' : (np.title.isEmpty ? 'Unknown track' : np.title),
          artist: np == null
              ? 'Play something in any app'
              : (np.artist.isEmpty ? 'Unknown artist' : np.artist),
          playing: np?.playing ?? false,
          art: np?.art,
        );
      case IslandState.success:
        return const _SuccessContent();
    }
  }

  Rect _idleBox(double w, double h, double f) {
    final side = widget.controller.idleSize.height * 1.1;
    return Rect.fromCenter(center: Offset(f + w / 2, h / 2), width: side, height: side);
  }

  Rect _seatBox(double w, double h, double f) {
    const cs = kOpenHome;
    final origin = Offset(f + (w - cs.width) / 2, (h - cs.height) / 2);
    return Rect.fromCenter(
      center: homeSeatCenter(cs) + origin,
      width: kSeatW,
      height: kSeatW,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = math.max(_w.value, 24.0), h = math.max(_h.value, 18.0);
    final f = notchEar(h);
    final r = math.min(h * 0.5, 34.0);
    final size = _sizeFor(_shown);

    return Transform.translate(
      offset: Offset(0, _dy.value),
      child: SizedBox(
        width: w + 2 * f,
        height: h,
        child: ClipPath(
          clipper: NotchClipper(w, h, f, r),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onPillTap,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(children: [
                Positioned(
                  left: f,
                  top: 0,
                  width: w,
                  height: h,
                  child: OverflowBox(
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Inter',
                        fontFamilyFallback: islandFontFallback,
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        reverseDuration: const Duration(milliseconds: 140),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim.drive(CurveTween(curve: const Interval(0.45, 1.0))),
                          child: child,
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_shown),
                          child: SizedBox(
                            width: size.width,
                            height: size.height,
                            child: _content(_shown),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: PipActor(
                    c: widget.controller,
                    spot: _pipSpot,
                    idleBox: _idleBox(w, h, f),
                    seatBox: _seatBox(w, h, f),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- compact states

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.color, required this.icon, required this.onTap});
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IslandPressable(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}

class _CallContent extends StatelessWidget {
  const _CallContent({required this.onAccept, required this.onDecline});
  final VoidCallback onAccept, onDecline;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7F7FD5), Color(0xFF86A8E7), Color(0xFF91EAE4)],
                ),
              ),
              child: const Text('AJ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alex Johnson',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Incoming call…', style: TextStyle(fontSize: 13, color: Color(0x99FFFFFF))),
                ],
              ),
            ),
            _RoundButton(color: const Color(0xFFFF453A), icon: Icons.call_end, onTap: onDecline),
            const SizedBox(width: 12),
            _RoundButton(color: const Color(0xFF30D158), icon: Icons.call, onTap: onAccept),
          ],
        ),
      );
}

class _MusicContent extends StatelessWidget {
  const _MusicContent({
    required this.title,
    required this.artist,
    required this.playing,
    required this.art,
  });
  final String title, artist;
  final bool playing;
  final String? art;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            IslandArt(path: art, size: 44, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IslandMarquee(
                    text: title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontFamilyFallback: islandFontFallback,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IslandWaveform(active: playing),
          ],
        ),
      );
}

class _SuccessContent extends StatefulWidget {
  const _SuccessContent();

  @override
  State<_SuccessContent> createState() => _SuccessContentState();
}

class _SuccessContentState extends State<_SuccessContent> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _FaceCheckPainter(_c), size: Size.infinite);
}

class _FaceCheckPainter extends CustomPainter {
  _FaceCheckPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;
  static const _green = Color(0xFF30D158);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final c = size.center(Offset.zero);
    final q = Curves.easeOutCubic.transform(((t - 0.42) / 0.28).clamp(0.0, 1.0));
    const half = 19.0, arm = 9.0;

    if (q < 1) {
      final frame = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: 1 - q);
      for (final s in const [
        [-1.0, -1.0],
        [1.0, -1.0],
        [1.0, 1.0],
        [-1.0, 1.0],
      ]) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + s[0] * half, c.dy + s[1] * (half - arm))
            ..lineTo(c.dx + s[0] * half, c.dy + s[1] * half)
            ..lineTo(c.dx + s[0] * (half - arm), c.dy + s[1] * half),
          frame,
        );
      }
      final y = c.dy + (half - 5) * math.sin(t / 0.42 * 2 * math.pi * 1.25);
      canvas.drawLine(
        Offset(c.dx - 13, y),
        Offset(c.dx + 13, y),
        frame
          ..strokeWidth = 2
          ..color = _green.withValues(alpha: 1 - q),
      );
    }

    if (q > 0) {
      final tick = Path()
        ..moveTo(c.dx - 13, c.dy + 1)
        ..lineTo(c.dx - 4, c.dy + 10)
        ..lineTo(c.dx + 14, c.dy - 10);
      final m = tick.computeMetrics().first;
      canvas.drawPath(
        m.extractPath(0, m.length * q),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..color = _green,
      );
    }
  }

  @override
  bool shouldRepaint(_FaceCheckPainter old) => false;
}
