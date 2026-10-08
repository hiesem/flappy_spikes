import 'dart:math' as math;

import 'package:flame/components.dart';

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
