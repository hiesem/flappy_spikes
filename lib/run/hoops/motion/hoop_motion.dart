import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../config/layout_config.dart';
import '../../director/plans.dart';
import '../hoop.dart';

/// §3.11 A moving ring's motion (ARCH §1.5, WP-1b). Pure functions of the
/// run clock: [poseAt] gives the offset from the ring's home position, the
/// extra angle and the velocity at time `t`, so the motion is deterministic,
/// pauses with `runClock` (pause, revive, tumble) and slows with the
/// Hourglass, and the pass test sees the ring's actual position and angle at
/// the moment of crossing (§3.11 passing rule).
///
/// Types (prototype `hoopStep`):
/// - [RailMotion]: vertical slide (axis ≤ ±25° off vertical), horizontal
///   slide (axis 90°) and diagonal slides (±52° off vertical = ±38° off
///   horizontal) — a constant-speed ping-pong along the axis.
/// - [SwingMotion]: hangs from a rope whose pivot is above the top spikes,
///   ±15°, period 1.8 s; the ring stays in line with the rope.
/// - [OrbitMotion]: an ellipse around the home position, the angle
///   changing ±22° along the path.
/// - [RockMotion]: stays in place and rocks ±15°, period 3 s.
abstract class HoopMotion implements HoopMotionDriver {
  HoopMotion(this.spec);

  /// Builds the motion the director rolled.
  factory HoopMotion.fromSpec(MotionSpec spec) => switch (spec.type) {
    MotionType.rail ||
    MotionType.horizontal ||
    MotionType.diagonal => RailMotion(spec),
    MotionType.swing => SwingMotion(spec),
    MotionType.orbit => OrbitMotion(spec),
    MotionType.rock => RockMotion(spec),
  };

  final MotionSpec spec;

  @override
  final Vector2 offset = Vector2.zero();
  @override
  double angleOffset = 0;
  @override
  final Vector2 velocity = Vector2.zero();

  /// Degrees per second of [angleOffset] (rim-end velocity of a rocking /
  /// swinging ring, for WP-1a's rim collision if it wants it).
  double angularVelocity = 0;

  /// Sets [offset], [angleOffset], [velocity] and [angularVelocity] for run
  /// time [t] (s).
  void poseAt(double t);

  /// The run time of the last [update].
  double time = 0;

  /// §3.11 Moves [h] to its pose at run time [t]: position = home + offset,
  /// angle = tilt + angle offset (radians). The front half follows at once
  /// (the hoop layers update before the run controller).
  @override
  void update(Hoop h, double t) {
    time = t;
    poseAt(t);
    h.position
      ..setFrom(h.basePosition)
      ..add(offset);
    h.angle = h.tilt * math.pi / 180 + angleOffset;
    h.front
      ..position.setFrom(h.position)
      ..angle = h.angle;
  }

  /// The ring centre's offset from home at run time [t] (a copy; tests and
  /// look-ahead). Leaves the current pose untouched.
  Vector2 offsetAt(double t) {
    final o = offset.clone(), v = velocity.clone();
    final a = angleOffset, w = angularVelocity;
    poseAt(t);
    final out = offset.clone();
    offset.setFrom(o);
    velocity.setFrom(v);
    angleOffset = a;
    angularVelocity = w;
    return out;
  }

  /// The largest distance of the path from home along x / y (pt) — the
  /// guide extents and the band checks.
  (double, double) get extent;
}

/// §3.11 Vertical / horizontal / diagonal slide: constant speed along the
/// axis (0° = vertical, 90° = horizontal, positive leans the far end right),
/// ±[MotionSpec.halfTravel], turning round at the ends. One cycle lasts
/// 4 × halfTravel / speed; [MotionSpec.phase] is the start point (0..1).
class RailMotion extends HoopMotion {
  RailMotion(super.spec);

  double get _axis => spec.axisDeg * math.pi / 180;

  /// The unit vector along the axis (screen coordinates, y down).
  Vector2 get axis => Vector2(math.sin(_axis), math.cos(_axis));

  /// Seconds per full back-and-forth.
  double get period =>
      spec.speed <= 0 ? double.infinity : 4 * spec.halfTravel / spec.speed;

  /// Position along the axis in −1..1 and its direction at [t].
  (double, double) _tri(double t) {
    final p = period;
    if (!p.isFinite) return (0, 0);
    var u = (t / p + spec.phase) % 1;
    if (u < 0) u += 1;
    return u < 0.5 ? (4 * u - 1, 1) : (3 - 4 * u, -1);
  }

  @override
  void poseAt(double t) {
    final (tri, dir) = _tri(t);
    final a = axis;
    offset.setValues(a.x * spec.halfTravel * tri, a.y * spec.halfTravel * tri);
    velocity.setValues(a.x * spec.speed * dir, a.y * spec.speed * dir);
    angleOffset = 0;
    angularVelocity = 0;
  }

  @override
  (double, double) get extent {
    final a = axis;
    return (a.x.abs() * spec.halfTravel, a.y.abs() * spec.halfTravel);
  }
}

/// §3.11 Swing: the ring hangs from a rope of length [MotionSpec.rope] whose
/// pivot is straight above the home position (above the top spikes); the
/// rope swings ±[MotionSpec.amplitudeDeg] with [MotionSpec.period]; the ring
/// stays in line with the rope.
class SwingMotion extends HoopMotion {
  SwingMotion(super.spec);

  double get _amp => spec.amplitudeDeg * math.pi / 180;
  double get _omega => spec.period <= 0 ? 0 : 2 * math.pi / spec.period;

  /// The rope angle at [t] (radians; positive = ring swung right).
  double ropeAngle(double t) => _amp * math.sin(t * _omega + spec.phase);

  /// The pivot relative to home (straight above, rope length up).
  Vector2 get pivot => Vector2(0, -spec.rope);

  @override
  void poseAt(double t) {
    final l = spec.rope;
    final th = ropeAngle(t);
    final dth = _amp * _omega * math.cos(t * _omega + spec.phase);
    offset.setValues(math.sin(th) * l, -l + math.cos(th) * l);
    velocity.setValues(math.cos(th) * l * dth, -math.sin(th) * l * dth);
    // In line with the rope: swung right → the top leans left.
    angleOffset = -th;
    angularVelocity = -dth * 180 / math.pi;
  }

  @override
  (double, double) get extent =>
      (math.sin(_amp) * spec.rope, (1 - math.cos(_amp)) * spec.rope);
}

/// §3.11 Orbit: an ellipse [MotionSpec.rx] × [MotionSpec.ry] around home at
/// [MotionSpec.omega] rad/s (clockwise on screen), the ring's angle
/// changing ±22° along the path.
class OrbitMotion extends HoopMotion {
  OrbitMotion(super.spec);

  static const double _tilt = LayoutConfig.orbitTiltDeg * math.pi / 180;

  @override
  void poseAt(double t) {
    final th = t * spec.omega + spec.phase;
    final c = math.cos(th), s = math.sin(th);
    offset.setValues(c * spec.rx, s * spec.ry);
    velocity.setValues(-s * spec.rx * spec.omega, c * spec.ry * spec.omega);
    angleOffset = _tilt * s;
    angularVelocity = _tilt * c * spec.omega * 180 / math.pi;
  }

  @override
  (double, double) get extent => (spec.rx, spec.ry);
}

/// §3.11 Rock: stays in place and rocks ±[MotionSpec.amplitudeDeg] with
/// [MotionSpec.period].
class RockMotion extends HoopMotion {
  RockMotion(super.spec);

  @override
  void poseAt(double t) {
    final amp = spec.amplitudeDeg * math.pi / 180;
    final w = spec.period <= 0 ? 0.0 : 2 * math.pi / spec.period;
    offset.setZero();
    velocity.setZero();
    angleOffset = amp * math.sin(t * w + spec.phase);
    angularVelocity = amp * w * math.cos(t * w + spec.phase) * 180 / math.pi;
  }

  @override
  (double, double) get extent => (0, 0);
}
