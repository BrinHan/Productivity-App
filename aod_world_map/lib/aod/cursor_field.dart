import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Pointer state shared between the widget (writes) and the painter (reads).
/// `pos` eases toward `target`; `strength` fades 0..1 as the pointer
/// enters/leaves, so the dots glide away and back instead of snapping.
class CursorField extends ChangeNotifier {
  Offset target = Offset.zero;
  Offset pos = Offset.zero;
  double strength = 0;
  bool active = false;
  bool _seeded = false;

  void move(Offset p) {
    target = p;
    if (!_seeded || strength < 0.01) {
      pos = p; // appear in place rather than sliding in from the corner
      _seeded = true;
    }
    active = true;
  }

  void leave() => active = false;

  /// Advances the easing by [dt] seconds. Returns true while still animating.
  bool step(double dt) {
    final kp = 1 - math.exp(-dt * 22);
    final ks = 1 - math.exp(-dt * 9);
    pos = Offset.lerp(pos, target, kp)!;
    strength += ((active ? 1.0 : 0.0) - strength) * ks;
    if (active && strength > 0.997) strength = 1;
    if (!active && strength < 0.003) strength = 0;
    notifyListeners();
    final posSettled = (target - pos).distance < 0.2;
    final strSettled = active ? strength == 1 : strength == 0;
    return !(posSettled && strSettled);
  }
}
