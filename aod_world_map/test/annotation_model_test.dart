import 'dart:ui';

import 'package:aod_world_map/desktop/annotate/annotation_model.dart';
import 'package:flutter_test/flutter_test.dart';

StrokeShape _stroke(List<Offset> pts) => StrokeShape(color: const Color(0xFFFF0000), points: pts);

void main() {
  group('AnnotationStore', () {
    test('undo and redo add and remove shapes', () {
      final s = AnnotationStore();
      final a = _stroke(const [Offset(0, 0), Offset(10, 10)]);
      final b = _stroke(const [Offset(50, 50), Offset(60, 60)]);
      s.add(Layer.user, a);
      s.add(Layer.user, b);
      expect(s.shapes(Layer.user), [a, b]);

      s.undo(Layer.user);
      expect(s.shapes(Layer.user), [a]);
      s.redo(Layer.user);
      expect(s.shapes(Layer.user), [a, b]);

      // A new edit drops the redo history.
      s.undo(Layer.user);
      s.add(Layer.user, _stroke(const [Offset(1, 1)]));
      expect(s.canRedo(Layer.user), isFalse);
    });

    test('object eraser removes hit shapes and one undo restores them in order', () {
      final s = AnnotationStore();
      final a = _stroke(const [Offset(0, 0), Offset(100, 0)]);
      final b = _stroke(const [Offset(0, 50), Offset(100, 50)]);
      final c = _stroke(const [Offset(0, 100), Offset(100, 100)]);
      for (final x in [a, b, c]) {
        s.add(Layer.user, x);
      }
      s.eraseAt(Layer.user, const Offset(50, 1), 4); // a
      s.eraseAt(Layer.user, const Offset(50, 99), 4); // c
      s.eraseAt(Layer.user, const Offset(50, 25), 4); // nothing
      s.commitErase(Layer.user);
      expect(s.shapes(Layer.user), [b]);

      s.undo(Layer.user);
      expect(s.shapes(Layer.user), [a, b, c]);
      s.redo(Layer.user);
      expect(s.shapes(Layer.user), [b]);
    });

    test('clear all is one undoable step', () {
      final s = AnnotationStore();
      s.add(Layer.user, _stroke(const [Offset(0, 0)]));
      s.add(Layer.user, _stroke(const [Offset(5, 5)]));
      s.clear(Layer.user);
      expect(s.shapes(Layer.user), isEmpty);
      s.undo(Layer.user);
      expect(s.shapes(Layer.user), hasLength(2));
    });

    test('AI marks never land in the user layer until kept', () {
      final s = AnnotationStore();
      s.add(Layer.user, _stroke(const [Offset(0, 0)]));
      s.aiAdd(RectShape(color: kAiColor, rect: const Rect.fromLTWH(10, 10, 50, 20), label: 'Save'));
      s.aiAdd(PulseShape(at: const Offset(30, 30)));
      expect(s.shapes(Layer.user), hasLength(1));
      expect(s.shapes(Layer.ai), hasLength(2));

      s.keepAi();
      // The box is kept; the pulse is only a pointer and goes away.
      expect(s.shapes(Layer.ai), isEmpty);
      expect(s.shapes(Layer.user), hasLength(2));
      expect(s.shapes(Layer.user).last, isA<RectShape>());

      // Keeping is a single undo step.
      s.undo(Layer.user);
      expect(s.shapes(Layer.user), hasLength(1));
    });

    test('dismiss clears only the AI layer', () {
      final s = AnnotationStore();
      s.add(Layer.user, _stroke(const [Offset(0, 0)]));
      s.aiAdd(SpotlightShape(rect: const Rect.fromLTWH(0, 0, 10, 10)));
      s.dismissAi();
      expect(s.shapes(Layer.ai), isEmpty);
      expect(s.shapes(Layer.user), hasLength(1));
    });

    test('pixel eraser strokes are not described to the AI', () {
      final s = AnnotationStore();
      s.add(Layer.user, _stroke(const [Offset(0, 0), Offset(10, 0)]));
      s.add(Layer.user, EraseShape(points: const [Offset(5, 0)], radius: 4));
      expect(s.describeUser(), hasLength(1));
    });
  });

  group('hit testing', () {
    test('rectangle outline hits on the edge, not the inside', () {
      final r = RectShape(color: const Color(0xFF000000), width: 2, rect: const Rect.fromLTWH(0, 0, 100, 100));
      expect(r.hitTest(const Offset(0, 50), 3), isTrue);
      expect(r.hitTest(const Offset(50, 50), 3), isFalse);
    });

    test('ellipse outline hits near the curve', () {
      final e = RectShape(
          color: const Color(0xFF000000), width: 2, rect: const Rect.fromLTWH(0, 0, 100, 100), ellipse: true);
      expect(e.hitTest(const Offset(100, 50), 3), isTrue);
      expect(e.hitTest(const Offset(50, 50), 3), isFalse);
    });
  });

  group('geometry', () {
    test('simplify keeps the ends and drops collinear points', () {
      final pts = [for (var i = 0; i <= 10; i++) Offset(i.toDouble(), 0)];
      expect(simplify(pts, 0.4), [0, 10]);
    });

    test('simplify keeps a corner', () {
      final pts = [
        for (var i = 0; i <= 10; i++) Offset(i.toDouble(), 0),
        for (var i = 1; i <= 10; i++) Offset(10, i.toDouble()),
      ];
      expect(simplify(pts, 0.4), [0, 10, 20]);
    });

    test('one-euro filter passes the first sample and smooths jitter', () {
      final f = OneEuro();
      expect(f.filter(const Offset(10, 10), 0), const Offset(10, 10));
      // A 2px jitter while barely moving is mostly filtered out.
      final out = f.filter(const Offset(12, 10), 1 / 120);
      expect(out.dx, lessThan(11));
    });

    test('distance to segment', () {
      expect(distToSegment(const Offset(5, 3), Offset.zero, const Offset(10, 0)), 3);
      expect(distToSegment(const Offset(-4, 3), Offset.zero, const Offset(10, 0)), 5);
    });
  });
}
