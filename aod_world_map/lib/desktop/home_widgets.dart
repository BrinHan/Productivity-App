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

class _Btn extends StatefulWidget {
  const _Btn(this.t, this.label, this.onTap, {this.primary = false, this.icon, this.compact = false});
  final _T t;
  final String label;
  final VoidCallback? onTap;
  final bool primary, compact;
  final IconData? icon;

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final on = widget.onTap != null;
    final fg = widget.primary ? t.onAccent : t.text;
    final bg = widget.primary
        ? (_hover && on ? Color.lerp(t.accent, t.text, 0.12)! : t.accent)
        : (_hover && on ? t.raised : t.surface);
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: MouseRegion(
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
              duration: const Duration(milliseconds: 140),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 16,
                vertical: widget.compact ? 7 : 10,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(_rSm),
                border: Border.all(color: widget.primary ? Colors.transparent : t.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(widget.label, softWrap: false, style: _ts(fg, 13, w: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(this.t, this.labels, this.index, this.onChanged);
  final _T t;
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(_rSm)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == index ? t.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(_rSm - 3),
                    border: Border.all(color: i == index ? t.line : Colors.transparent),
                  ),
                  child: Text(labels[i],
                      softWrap: false,
                      style: _ts(i == index ? t.text : t.sub, 12.5, w: FontWeight.w600)),
                ),
              ),
            ),
        ]),
      );
}

class _Check extends StatelessWidget {
  const _Check(this.t, this.done, this.onTap, {this.size = 20});
  final _T t;
  final bool done;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? t.accent : Colors.transparent,
                border: Border.all(color: done ? t.accent : t.faint, width: 1.5),
              ),
              child: done ? Icon(Icons.check_rounded, size: size - 6, color: t.onAccent) : null,
            ),
          ),
        ),
      );
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
            duration: const Duration(milliseconds: 160),
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: on ? t.accent : t.raised,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: on ? t.accent : t.line),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: on ? t.onAccent : t.sub),
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
        builder: (_, v, __) => ClipRRect(
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

class _Hair extends StatelessWidget {
  const _Hair(this.t);
  final _T t;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: t.line);
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

InputDecoration _deco(_T t, String hint, {Widget? prefix, Widget? suffix}) => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: t.surface,
      hintText: hint,
      hintStyle: _ts(t.sub, 13),
      prefixIcon: prefix,
      prefixIconConstraints: const BoxConstraints(minWidth: 38),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: _ob(t.line),
      enabledBorder: _ob(t.line),
      focusedBorder: _ob(t.accent, 1.5),
    );

/// Label above the input, never a placeholder standing in for a label.
class _Labeled extends StatelessWidget {
  const _Labeled(this.t, this.label, this.ctl, {this.hint = '', this.obscure = false, this.onChanged});
  final _T t;
  final String label, hint;
  final TextEditingController ctl;
  final bool obscure;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _ts(t.text, 12.5, w: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctl,
          obscureText: obscure,
          style: _ts(t.text, 13),
          cursorColor: t.accent,
          onChanged: (_) => onChanged?.call(),
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
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 28),
          Expanded(child: child),
        ]),
      );
}
