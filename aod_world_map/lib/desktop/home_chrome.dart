part of 'home_page.dart';

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.t,
    required this.shell,
    required this.sidebarOpen,
    required this.onToggleSidebar,
    required this.notes,
    required this.onOpenNotes,
  });
  final _T t;
  final ShellController shell;
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final NotesService notes;
  final VoidCallback onOpenNotes;

  @override
  Widget build(BuildContext context) => DragToMoveArea(
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: t.side,
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(children: [
            _WinBtn(t, Icons.view_sidebar_outlined, sidebarOpen ? 'Hide sidebar (Ctrl+B)' : 'Show sidebar (Ctrl+B)',
                onToggleSidebar),
            if (notes.recording) ...[
              const SizedBox(width: 8),
              _RecPill(t: t, notes: notes, onTap: onOpenNotes),
            ],
            const Spacer(),
            _WinBtn(t, Icons.public, 'Screensaver map', shell.showMap),
            _WinBtn(t, Icons.picture_in_picture_alt_outlined, 'Shrink to island', () => shell.enterIsland()),
            const SizedBox(width: 8),
            _CaptionButtons(t: t, shell: shell),
          ]),
        ),
      );
}

/// Windows caption buttons: minimize, maximize / restore, close. Full bar
/// height, flush to the corner, red close on hover, like native windows.
class _CaptionButtons extends StatefulWidget {
  const _CaptionButtons({required this.t, required this.shell});
  final _T t;
  final ShellController shell;

  @override
  State<_CaptionButtons> createState() => _CaptionButtonsState();
}

class _CaptionButtonsState extends State<_CaptionButtons> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _max = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _max = true);

  @override
  void onWindowUnmaximize() => setState(() => _max = false);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _CaptionBtn(t: t, glyph: _Glyph.minimize, tip: 'Minimize', onTap: windowManager.minimize),
      _CaptionBtn(
        t: t,
        glyph: _max ? _Glyph.restore : _Glyph.maximize,
        tip: _max ? 'Restore down' : 'Maximize',
        onTap: widget.shell.toggleMaximize,
      ),
      _CaptionBtn(t: t, glyph: _Glyph.close, tip: 'Close', onTap: widget.shell.quit, danger: true),
    ]);
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionBtn extends StatefulWidget {
  const _CaptionBtn({required this.t, required this.glyph, required this.tip, required this.onTap, this.danger = false});
  final _T t;
  final _Glyph glyph;
  final String tip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_CaptionBtn> createState() => _CaptionBtnState();
}

class _CaptionBtnState extends State<_CaptionBtn> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final bg = widget.danger
        ? (_down ? const Color(0xFFF1707A) : (_hover ? const Color(0xFFE81123) : Colors.transparent))
        : (_down ? t.line : (_hover ? t.raised : Colors.transparent));
    final fg = widget.danger && (_hover || _down) ? Colors.white : t.text;
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Feedback on press; act on release, so dragging off cancels.
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: _hover ? 90 : 160),
            width: 46,
            height: 40,
            color: bg,
            child: CustomPaint(painter: _GlyphPainter(widget.glyph, fg)),
          ),
        ),
      ),
    );
  }
}

/// Thin 10 px caption glyphs, drawn rather than taken from an icon font so
/// they match the native ones.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = glyph == _Glyph.close;
    final c = size.center(Offset.zero);
    const s = 10.0, h = s / 2;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(Offset(c.dx - h, c.dy + 0.5), Offset(c.dx + h, c.dy + 0.5), paint);
      case _Glyph.maximize:
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: c + const Offset(0.5, 0.5), width: s - 1, height: s - 1),
                const Radius.circular(1.5)),
            paint);
      case _Glyph.restore:
        final front = Rect.fromLTWH(c.dx - h + 0.5, c.dy - h + 2.5, s - 3, s - 3);
        canvas.drawRRect(RRect.fromRectAndRadius(front, const Radius.circular(1.5)), paint);
        final back = Path()
          ..moveTo(c.dx - h + 2.5, c.dy - h + 2.5)
          ..lineTo(c.dx - h + 2.5, c.dy - h + 1.5)
          ..arcToPoint(Offset(c.dx - h + 4, c.dy - h + 0.5), radius: const Radius.circular(1.5))
          ..lineTo(c.dx + h - 1.5, c.dy - h + 0.5)
          ..arcToPoint(Offset(c.dx + h + 0.5, c.dy - h + 2), radius: const Radius.circular(1.5))
          ..lineTo(c.dx + h + 0.5, c.dy + h - 3.5)
          ..arcToPoint(Offset(c.dx + h - 1, c.dy + h - 2.5), radius: const Radius.circular(1.5))
          ..lineTo(c.dx + h - 2.5, c.dy + h - 2.5);
        canvas.drawPath(back, paint);
      case _Glyph.close:
        canvas.drawLine(Offset(c.dx - h, c.dy - h), Offset(c.dx + h, c.dy + h), paint);
        canvas.drawLine(Offset(c.dx + h, c.dy - h), Offset(c.dx - h, c.dy + h), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.glyph != glyph || o.color != color;
}

class _WinBtn extends StatelessWidget {
  const _WinBtn(this.t, this.icon, this.tip, this.onTap);
  final _T t;
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: _Tap(
          t: t,
          onTap: onTap,
          radius: 8,
          child: SizedBox(width: 36, height: 28, child: Icon(icon, size: 16, color: t.sub)),
        ),
      );
}
