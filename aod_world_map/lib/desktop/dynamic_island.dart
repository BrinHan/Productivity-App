import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'island_controller.dart';
import 'island_pages.dart';
import 'island_widgets.dart';
import 'pip.dart';

/// Damped spring. Defaults: mass 1, stiffness ("tension") 120, damping
/// ("friction") 14 -> damping ratio ~0.64, i.e. a visible bouncy overshoot.
class _Spring {
  _Spring(double v)
      : value = v,
        target = v;
  double value, target, velocity = 0;
  final double stiffness = 120, damping = 14, mass = 1;

  bool get settled => (value - target).abs() < 0.05 && velocity.abs() < 0.05;

  void step(double dt) {
    final n = (dt / 0.004).ceil().clamp(1, 12).toInt();
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      final a = (-stiffness * (value - target) - damping * velocity) / mass;
      velocity += a * h;
      value += velocity * h;
    }
    if (settled) {
      value = target;
      velocity = 0;
    }
  }
}

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
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DynamicIsland(
                controller: island,
                onShortcut: onShortcut,
                publishGeometry: true,
              ),
            ),
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

  /// Inline previews show the idle pill instead of hiding off-screen.
  final bool showWhenHidden;
  final void Function(IslandShortcut)? onShortcut;

  /// Only the real island window reports its live size to the controller.
  final bool publishGeometry;

  @override
  State<DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends State<DynamicIsland> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  late IslandState _shown = _effective;
  late final _Spring _w = _Spring(_sizeFor(_shown).width);
  late final _Spring _h = _Spring(_sizeFor(_shown).height);
  late final _Spring _dy = _Spring(_dyFor(_shown));

  IslandState get _effective {
    final s = widget.controller.state;
    return (s == IslandState.hidden && widget.showWhenHidden) ? IslandState.idle : s;
  }

  Size _sizeFor(IslandState s) {
    final c = widget.controller;
    final idle = c.idleSize;
    switch (s) {
      case IslandState.open:
        return c.page == IslandPage.settings ? const Size(500, 316) : const Size(500, 156);
      case IslandState.call:
        return Size(math.max(400, idle.width + 60), math.max(84, idle.height + 16));
      case IslandState.music:
        return Size(math.max(330, idle.width + 40), math.max(68, idle.height + 8));
      case IslandState.success:
        return const Size(86, 86);
      case IslandState.idle:
      case IslandState.hidden:
        return idle;
    }
  }

  double _dyFor(IslandState s) =>
      s == IslandState.hidden ? -(widget.controller.idleSize.height + 26) : 0.0;

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
      // Squash & stretch: widening flattens the pill for a beat, narrowing
      // makes it pop taller, success pops in every direction.
      final ps = _sizeFor(prev);
      if (prev != IslandState.hidden && next != IslandState.hidden) {
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
    if (_shown == IslandState.idle) {
      c.open(IslandPage.home);
    } else if (_shown == IslandState.music) {
      c.open(IslandPage.music);
    }
  }

  Widget _content(IslandState s) {
    final c = widget.controller;
    switch (s) {
      case IslandState.hidden:
        return const SizedBox.shrink();
      case IslandState.idle:
        return PipView(gaze: c.gaze, color: c.pipColor, interactive: false, wave: true);
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

  @override
  Widget build(BuildContext context) {
    final w = math.max(_w.value, 24.0), h = math.max(_h.value, 20.0);
    final r = math.min(math.min(w, h) * 0.6, 32.0);
    final size = _sizeFor(_shown);

    return Transform.translate(
      offset: Offset(0, _dy.value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onPillTap,
        child: Container(
          width: w,
          height: h,
          clipBehavior: Clip.antiAlias, // content can never leave the pill
          decoration: ShapeDecoration(
            color: Colors.black,
            shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(r)),
          ),
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
                // Old content leaves fast; new content waits for the morph.
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
                  Text('Incoming call…',
                      style: TextStyle(fontSize: 13, color: Color(0x99FFFFFF))),
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

/// Face-ID style scan, then a check mark that draws itself.
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
