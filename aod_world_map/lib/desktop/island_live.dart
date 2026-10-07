import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'island_controller.dart';
import 'island_widgets.dart';
import 'planner_model.dart';

const _focusColor = Color(0xFFFF9F0A);
const _doneColor = Color(0xFF30D158);
const _dim = Color(0x99FFFFFF);

/// The pill while a focus session runs: the task, the time left, and
/// pause, done and stop. It follows the planner, which ticks every second
/// while the timer runs, so this redraws on its own.
class IslandFocusContent extends StatelessWidget {
  const IslandFocusContent({super.key, required this.planner});
  final PlannerModel planner;

  Widget _round(IconData icon, String tip, VoidCallback onTap, {Color color = const Color(0x24FFFFFF)}) => Tooltip(
        message: tip,
        child: IslandPressable(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: planner,
        builder: (context, _) {
          final p = planner;
          final left = p.focusSeconds;
          final finished = p.focusFinished, running = p.focusRunning;
          final progress = p.focusTotal == 0 ? 0.0 : 1 - left / p.focusTotal;
          final title = p.focusTask?.title ?? 'Focus';
          final mm = (left ~/ 60).toString().padLeft(2, '0');
          final ss = (left % 60).toString().padLeft(2, '0');
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              // The ring is the play / pause button.
              Tooltip(
                message: finished ? 'Start again' : (running ? 'Pause' : 'Resume'),
                child: IslandPressable(
                  onTap: running ? p.pauseFocus : p.startFocus,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CustomPaint(
                      painter: _RingPainter(finished ? 1 : progress, finished ? _doneColor : _focusColor),
                      child: Icon(
                        finished ? Icons.replay_rounded : (running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IslandMarquee(
                      text: title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamilyFallback: islandFontFallback,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(finished ? 'Time\'s up' : (running ? 'Focusing' : 'Paused'),
                        maxLines: 1,
                        style: TextStyle(fontSize: 11.5, color: finished ? _doneColor : _dim)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!finished)
                Text('$mm:$ss',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: running ? _focusColor : _dim,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              const SizedBox(width: 8),
              if (!running) ...[
                _round(Icons.close_rounded, 'Stop the session', p.resetFocus),
                const SizedBox(width: 6),
              ],
              _round(Icons.check_rounded, p.focusTask == null ? 'End the session' : 'Mark the task done',
                  p.completeFocus,
                  color: finished ? _doneColor : const Color(0x24FFFFFF)),
            ]),
          );
        },
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 2.5;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;
    canvas.drawCircle(c, r, stroke..color = const Color(0x33FFFFFF));
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        stroke
          ..color = color
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress || o.color != color;
}

/// After a call: the to-dos found in it, with "add them to today" or a
/// look at the note first.
class IslandActionsContent extends StatelessWidget {
  const IslandActionsContent({super.key, required this.c});
  final IslandController c;

  Widget _pill(String label, VoidCallback onTap, {required bool filled}) => IslandPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: filled ? Colors.white : const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.black : Colors.white,
              )),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final o = c.actionOffer;
    final n = o?.items.length ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.checklist_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$n to-do${n == 1 ? '' : 's'} from ${o?.note.app ?? 'your call'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(o == null || o.items.isEmpty ? '' : o.items.first,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _dim)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _pill('Review', c.reviewActions, filled: false),
        const SizedBox(width: 8),
        _pill('Add to today', c.acceptActions, filled: true),
      ]),
    );
  }
}
