part of 'home_page.dart';

class _FocusView extends StatelessWidget {
  const _FocusView({required this.t, required this.p});
  final _T t;
  final PlannerModel p;

  @override
  Widget build(BuildContext context) {
    final open = p.forDay(DateTime.now()).where((x) => !x.done).toList();
    final left = p.focusSeconds;
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');
    final progress = p.focusTotal == 0 ? 0.0 : 1 - left / p.focusTotal;
    final selected = open.contains(p.focusTask) ? p.focusTask : null;

    return _Page(
      t: t,
      title: 'Focus',
      subtitle: 'One task, one timer.',
      child: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(alignment: Alignment.center, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: progress),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => CustomPaint(
                    size: const Size(260, 260),
                    painter: _RingPainter(v, t.line, t.accent),
                  ),
                ),
                Text('$mm:$ss', style: _ts(t.text, 60, w: FontWeight.w300, ls: -2.5, tab: true)),
              ]),
            ),
            const SizedBox(height: 26),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: PopupMenuButton<Task?>(
                enabled: open.isNotEmpty,
                tooltip: 'Choose a task',
                color: t.surface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_rSm + 2),
                  side: BorderSide(color: t.line),
                ),
                onSelected: p.pickFocusTask,
                itemBuilder: (_) => [
                  for (final x in open)
                    PopupMenuItem<Task?>(value: x, height: 38, child: Text(x.title, style: _ts(t.text, 13))),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(_rSm),
                    border: Border.all(color: t.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.task_alt_rounded, size: 16, color: t.sub),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        selected?.title ?? (open.isEmpty ? 'No open tasks today' : 'Choose a task'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _ts(selected == null ? t.sub : t.text, 13, w: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more_rounded, size: 18, color: t.sub),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Btn(t, p.focusRunning ? 'Pause' : 'Start', p.focusRunning ? p.pauseFocus : p.startFocus,
                  primary: true, icon: p.focusRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
              _Btn(t, 'Reset', p.resetFocus, icon: Icons.restart_alt_rounded),
              _Seg(t, const ['25 min', '50 min'], p.focusTotal == 50 * 60 ? 1 : 0,
                  (i) => p.setFocusMinutes(i == 0 ? 25 : 50)),
              if (selected != null)
                _Btn(t, 'Complete task', () {
                  p.toggle(selected);
                  p.pickFocusTask(null);
                }, icon: Icons.check_rounded),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.track, this.color);
  final double progress;
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -1.5707963,
        6.2831853 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress || o.track != track || o.color != color;
}
