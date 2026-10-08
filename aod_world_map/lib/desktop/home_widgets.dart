part of 'home_page.dart';

/// Hover fill plus a small press-down. No Material ink.
class _Tap extends StatefulWidget {
  const _Tap({
    required this.t,
    required this.onTap,
    required this.child,
    this.radius = _rSm,
    this.selected = false,
  });
  final _T t;
  final VoidCallback? onTap;
  final Widget child;
  final double radius;
  final bool selected;

  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapUp: on ? (_) => setState(() => _down = false) : null,
        onTapCancel: on ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              color: widget.selected || (_hover && on) ? widget.t.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(this.t, this.icon, this.tip, this.onTap, {this.size = 18});
  final _T t;
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: _Tap(
          t: t,
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: size, color: t.sub)),
        ),
      );
}

/// shadcn-style button. Default is the neutral foreground fill, [primary]
/// is the same as shadcn's default variant; without it you get the outline
/// variant; [ghost] drops the border. Keyboard focus shows a ring with a gap.
class _Btn extends StatefulWidget {
  const _Btn(
    this.t,
    this.label,
    this.onTap, {
    this.primary = false,
    this.ghost = false,
    this.icon,
    this.compact = false,
    this.fill = false,
  });
  final _T t;
  final String label;
  final VoidCallback? onTap;
  final bool primary, ghost, compact, fill;
  final IconData? icon;

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _hover = false, _down = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final on = widget.onTap != null;
    final primary = widget.primary;
    final fg = primary ? t.onAccent : t.text;
    final bg = primary
        ? (_hover && on ? Color.lerp(t.accent, Colors.black, 0.1)! : t.accent)
        : (_hover && on ? t.raised : Colors.transparent);
    final border = primary || widget.ghost ? Colors.transparent : t.line;
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: FocusableActionDetector(
        enabled: on,
        mouseCursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: on ? (_) => setState(() => _down = true) : null,
          onTapUp: on ? (_) => setState(() => _down = false) : null,
          onTapCancel: on ? () => setState(() => _down = false) : null,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.98 : 1,
            duration: const Duration(milliseconds: 90),
            child: Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: widget.fill ? double.infinity : null,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 12 : 16,
                  vertical: widget.compact ? 8 : 11,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(_rSm),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 16, color: fg),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label, softWrap: false, style: _ts(fg, widget.compact ? 13 : 14, w: FontWeight.w600)),
                  ],
                ),
              ),
              Positioned(
                left: -4,
                top: -4,
                right: -4,
                bottom: -4,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_rSm + 4),
                      border: Border.all(color: _focus ? t.focus : Colors.transparent, width: 2),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Toggle group with a sliding pill. Fixed segment width so the pill can
/// glide between segments with the same easing the checkbox uses.
class _Seg extends StatelessWidget {
  const _Seg(this.t, this.labels, this.index, this.onChanged);
  final _T t;
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  static const _w = 74.0, _h = 30.0;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(_rSm)),
        child: SizedBox(
          width: _w * labels.length,
          height: _h,
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300), // a tap carries no momentum: settle, don't overshoot
              curve: Curves.easeOutCubic,
              left: _w * index,
              top: 0,
              width: _w,
              height: _h,
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(_rSm - 2),
                  border: Border.all(color: t.line),
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < labels.length; i++)
                SizedBox(
                  width: _w,
                  height: _h,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: DefaultTextStyle.of(context).style.merge(_ts(i == index ? t.text : t.sub, 13, w: FontWeight.w600)),
                          child: Text(labels[i], softWrap: false),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      );
}

/// Animated checkbox: square box, foreground fill when checked, tick drawn
/// stroke by stroke. Ported from the supplied React component.
/// A tag as a soft pastel pill, the way Notion shows select options.
class _TagChip extends StatelessWidget {
  const _TagChip(this.t, this.tag);
  final _T t;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = t.tag(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(4)),
      child: Text(tag, style: _ts(c.fg, 12, h: 1.35)),
    );
  }
}

/// Shown on a task that was carried over from an earlier day.
class _SlipChip extends StatelessWidget {
  const _SlipChip(this.t, this.count);
  final _T t;
  final int count;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: count == 1 ? 'Carried over once' : 'Carried over $count times',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: t.warn.withValues(alpha: t.dark ? 0.18 : 0.10), borderRadius: BorderRadius.circular(4)),
          child: Text(count == 1 ? 'slipped' : 'slipped $count×', style: _ts(t.warn, 12, h: 1.35)),
        ),
      );
}

class _RepeatChip extends StatelessWidget {
  const _RepeatChip(this.t, this.rule);
  final _T t;
  final String rule;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: Repeat.label(rule),
    child: Semantics(
      label: Repeat.label(rule),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(Icons.repeat_rounded, size: 14, color: t.sub),
      ),
    ),
  );
}

class _Check extends StatefulWidget {
  const _Check(this.t, this.done, this.onTap, {this.size = 18});
  final _T t;
  final bool done;
  final VoidCallback onTap;
  final double size;

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t, s = widget.size;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: s,
            height: s,
            decoration: BoxDecoration(
              color: widget.done ? t.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6 * s / 18),
              border: Border.all(
                color: widget.done ? Colors.transparent : t.sub.withValues(alpha: _hover ? 0.6 : 0.4),
                width: 1.5,
              ),
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: widget.done ? 1 : 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (_, v, _) => CustomPaint(painter: _TickPainter(v, t.onAccent)),
            ),
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final k = size.width / 20;
    final path = Path()
      ..moveTo(5 * k, 10.5 * k)
      ..lineTo(8.182 * k, 14 * k)
      ..lineTo(15 * k, 6 * k);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = color;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter o) => o.progress != progress || o.color != color;
}

/// Title text whose strikethrough line draws across when [done] turns true.
class _StrikeText extends StatelessWidget {
  const _StrikeText(this.t, this.text, this.done, {this.size = 14, this.w = FontWeight.w500, this.h});
  final _T t;
  final String text;
  final bool done;
  final double size;
  final FontWeight w;
  final double? h;

  @override
  Widget build(BuildContext context) {
    final style = _ts(done ? t.sub : t.text, size, w: w, h: h);
    final measure = DefaultTextStyle.of(context).style.merge(_ts(t.text, size, w: w, h: h));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: done ? 1 : 0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (_, p, _) => LayoutBuilder(
        builder: (context, c) => CustomPaint(
          foregroundPainter: _StrikePainter(text, measure, c.maxWidth, p, t.sub),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: DefaultTextStyle.of(context).style.merge(style),
            child: Text(text),
          ),
        ),
      ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter(this.text, this.style, this.maxWidth, this.progress, this.color);
  final String text;
  final TextStyle style;
  final double maxWidth, progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
      ..layout(maxWidth: maxWidth);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final m in tp.computeLineMetrics()) {
      final y = m.baseline - m.ascent * 0.32;
      canvas.drawLine(Offset(m.left, y), Offset(m.left + m.width * progress, y), paint);
    }
  }

  @override
  bool shouldRepaint(_StrikePainter o) => true;
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.t, this.on, this.onChanged);
  final _T t;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!on),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: on ? t.text : t.raised,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: on ? Colors.transparent : t.line),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: on ? t.bg : t.sub),
              ),
            ),
          ),
        ),
      );
}

/// Thin progress line. Animates when the value changes.
class _Bar extends StatelessWidget {
  const _Bar(this.t, this.value, {this.warn = false, this.height = 4});
  final _T t;
  final double value, height;
  final bool warn;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: value.clamp(0.0, 1.0).toDouble()),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: t.line)),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: ColoredBox(color: warn ? t.warn : t.accent),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// The planner's standard surface: hairline border, no shadow. Screens pick
/// their own padding, so it stays a parameter rather than one house value.
class _Card extends StatelessWidget {
  const _Card(this.t, {required this.padding, required this.child, this.fill = true});
  final _T t;
  final double padding;
  final bool fill;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: fill ? double.infinity : null,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(_rLg),
          border: Border.all(color: t.line),
        ),
        child: child,
      );
}

class _Hair extends StatelessWidget {
  const _Hair(this.t, {this.color});
  final _T t;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color ?? t.line);
}

class _Empty extends StatelessWidget {
  const _Empty(this.t, this.icon, this.title, this.body);
  final _T t;
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 28, color: t.faint),
            const SizedBox(height: 10),
            Text(title, style: _ts(t.text, 14, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.center, style: _ts(t.sub, 13, h: 1.4)),
          ]),
        ),
      );
}

OutlineInputBorder _ob(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_rSm),
      borderSide: BorderSide(color: c, width: w),
    );

/// shadcn-style input: page background fill, thin border, bolder grey on focus.
InputDecoration _deco(_T t, String hint, {Widget? prefix, Widget? suffix}) => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: t.bg,
      hintText: hint,
      hintStyle: _ts(t.sub, 14),
      prefixIcon: prefix,
      prefixIconConstraints: const BoxConstraints(minWidth: 38),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: _ob(t.line),
      enabledBorder: _ob(t.line),
      focusedBorder: _ob(t.focus, 1.5),
    );

/// Label above the input, never a placeholder standing in for a label.
class _Labeled extends StatelessWidget {
  const _Labeled(
    this.t,
    this.label,
    this.ctl, {
    this.hint = '',
    this.obscure = false,
    this.onChanged,
    this.autofocus = false,
    this.onSubmitted,
  });
  final _T t;
  final String label, hint;
  final TextEditingController ctl;
  final bool obscure, autofocus;
  final VoidCallback? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _ts(t.text, 14, w: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: ctl,
          obscureText: obscure,
          autofocus: autofocus,
          style: _ts(t.text, 14),
          cursorColor: t.focus,
          onChanged: (_) => onChanged?.call(),
          onSubmitted: onSubmitted,
          decoration: _deco(t, hint),
        ),
      ]);
}

/// Page frame for the full-width views: left aligned title, body below.
class _Page extends StatelessWidget {
  const _Page({
    required this.t,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final _T t;
  final String title, subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 34, 40, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _ts(t.text, 30, w: FontWeight.w700, ls: -0.8, h: 1.1)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(subtitle, style: _ts(t.sub, 14, h: 1.45)),
                ),
              ]),
            ),
            ?trailing,
          ]),
          const SizedBox(height: 28),
          Expanded(child: child),
        ]),
      );
}
