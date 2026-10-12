import 'dart:math' as math;

import 'package:flame/components.dart';

import '../config/physics_config.dart';
import '../config/run_config.dart';

/// The bird's collider in track coordinates (§3.0.1: r 14.75 × scale).
class BirdCircle {
  BirdCircle(this.c, [this.r = RunConfig.birdRadius]);

  /// Centre (track x, screen y).
  final Vector2 c;
  final double r;
}

/// A hoop's world transform at one moment (ARCH §1.4): centre, tilt, ring
/// offsets, opening, rim radius and velocity. Pure math; the run's physics
/// tests (§3.0.4) work in its local frame: x along the flight direction
/// (the plane is local x = 0), y along the ring.
class HoopFrame {
  HoopFrame({
    required this.centre,
    this.tilt = 0,
    this.rings = const [0],
    required this.opening,
    this.rimR = RunConfig.rimRadius,
    Vector2? velocity,
    this.angularVelocity = 0,
  }) : velocity = velocity ?? Vector2.zero();

  /// Track coordinates of the hoop centre.
  final Vector2 centre;

  /// Radians; positive = the top leans right (canvas rotation).
  final double tilt;

  /// Ring offsets along the local y (pairs: two).
  final List<double> rings;
  final double opening;
  final double rimR;

  /// The hoop's own velocity (moving rings; pt/s).
  final Vector2 velocity;

  /// The rate of [tilt] (rad/s; rocking / swinging / orbiting rings,
  /// §3.11). Rim ends move with it about [centre].
  final double angularVelocity;

  /// §3.0.4 2 The velocity of the rigid hoop at track point [p]: the centre
  /// velocity plus the rotation about the centre (ω × r, canvas rotation).
  Vector2 velocityAt(Vector2 p) {
    final rx = p.x - centre.x, ry = p.y - centre.y;
    return Vector2(
      velocity.x - angularVelocity * ry,
      velocity.y + angularVelocity * rx,
    );
  }

  /// §3.0.4 1 Distance from a ring's centre to its rim-end centres.
  double get reach => opening / 2 + rimR;

  double get _cos => math.cos(tilt);
  double get _sin => math.sin(tilt);

  /// Track → local.
  Vector2 toLocal(Vector2 p) {
    final dx = p.x - centre.x, dy = p.y - centre.y;
    final c = _cos, s = _sin;
    return Vector2(dx * c + dy * s, -dx * s + dy * c);
  }

  /// Local → track.
  Vector2 toWorld(Vector2 l) {
    final c = _cos, s = _sin;
    return Vector2(centre.x + l.x * c - l.y * s, centre.y + l.x * s + l.y * c);
  }

  /// §3.0.4 1 The rim-end centre of [ring] on [side] (−1 top, +1 bottom).
  Vector2 rimEnd(int ring, int side) =>
      toWorld(Vector2(0, rings[ring] + side * reach));

  /// PRD-2.2 §30.2 The pose between [a] (u = 0) and [b] (u = 1): centre,
  /// tilt, velocity and angular velocity interpolated; ring offsets, opening
  /// and rim radius are [b]'s. Pure.
  static HoopFrame lerp(HoopFrame a, HoopFrame b, double u) {
    if (u >= 1) return b;
    if (u <= 0 && identical(a.rings, b.rings) && a.opening == b.opening) {
      return a;
    }
    return HoopFrame(
      centre: a.centre + (b.centre - a.centre) * u,
      tilt: a.tilt + (b.tilt - a.tilt) * u,
      rings: b.rings,
      opening: b.opening,
      rimR: b.rimR,
      velocity: a.velocity + (b.velocity - a.velocity) * u,
      angularVelocity:
          a.angularVelocity + (b.angularVelocity - a.angularVelocity) * u,
    );
  }

  /// PRD-2.2 §30.2 How many sub-steps the step from pose [a] to pose [b]
  /// needs: [PhysicsConfig.sweepSubsteps] when the centre moves more than
  /// [PhysicsConfig.sweepSubstepThreshold] or the tilt change moves a rim
  /// end more than that; else 1 (still rings: always 1). Pure.
  static int substeps(HoopFrame a, HoopFrame b) {
    if (identical(a, b)) return 1;
    final move = (b.centre - a.centre).length;
    var far = 0.0;
    for (final o in b.rings) {
      far = math.max(far, o.abs());
    }
    final sweep = (b.tilt - a.tilt).abs() * (far + b.reach);
    return math.max(move, sweep) > PhysicsConfig.sweepSubstepThreshold
        ? PhysicsConfig.sweepSubsteps
        : 1;
  }

  /// PRD-2.2 §30.2 The sub-steps for the step from pose [a] to pose [b]
  /// with the bird going [prev] → [now]: [substeps], but only for a ring
  /// near the bird — 1 when both bird positions are farther from both
  /// poses' centres than the ring's size plus the bird and the step's
  /// motion (no crossing or rim contact is possible there). Pure.
  static int sweepSteps(
    HoopFrame a,
    HoopFrame b,
    BirdCircle prev,
    BirdCircle now,
  ) {
    if (identical(a, b)) return 1;
    var far = 0.0;
    for (final o in b.rings) {
      far = math.max(far, o.abs());
    }
    final size =
        far +
        b.reach +
        b.rimR +
        now.r +
        (b.centre - a.centre).length +
        (now.c - prev.c).length;
    final s2 = size * size;
    final near =
        (now.c - b.centre).length2 <= s2 || (prev.c - a.centre).length2 <= s2;
    return near ? substeps(a, b) : 1;
  }

  /// §3.0.4 5 The ring's rightmost point: centre x + |sin tilt| × (largest
  /// ring offset + opening/2 + 7) + 7.
  double get rightmostX {
    var far = 0.0;
    for (final o in rings) {
      far = math.max(far, o.abs());
    }
    return centre.x + _sin.abs() * (far + reach) + rimR;
  }
}
