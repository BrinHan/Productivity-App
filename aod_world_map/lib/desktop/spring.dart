import 'motion.dart';

/// Damped spring (mass 1). Retarget it any time: it continues from the live
/// value and velocity, so animations stay interruptible.
class Spring {
  Spring(this.value) : target = value;
  double value, target, velocity = 0;
  double stiffness = 120, damping = 14; // ratio ~0.64: bouncy

  void set(double k, double c) {
    stiffness = k;
    damping = c;
  }

  bool get settled => (value - target).abs() < 0.05 && velocity.abs() < 0.05;

  void step(double dt) {
    if (Motion.reduced) {
      // Animation effects are off in Windows: arrive without the bounce.
      value = target;
      velocity = 0;
      return;
    }
    final n = (dt / 0.004).ceil().clamp(1, 12).toInt();
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      velocity += (-stiffness * (value - target) - damping * velocity) * h;
      value += velocity * h;
    }
    if (settled) {
      value = target;
      velocity = 0;
    }
  }
}
