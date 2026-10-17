import 'dart:math' as math;

import 'package:flame/components.dart';

import '../config/physics_config.dart';
import '../config/run_config.dart';

/// §3.0.5 death physics — the momentum tumble (prototype `kill` +
/// `deathStep`), a pure plain-math integrator in track coordinates. The run
/// drives the bird body kinematically from [position] / [angle] and the
/// world from [camX].
///
/// - The camera and scroll ease to a stop over 0.4 s.
/// - The bird keeps its velocity, + 180 pt/s along the contact [normal]
///   (a plain miss: vy − 140), and spins at clamp(vx / 25 + impact, ±12).
/// - Gravity 1250 and air drag −40 %/s on the forward speed; a top-strip hit
///   bounces it down (0.3).
/// - It bounces on the floor tooth line (0.3, forward × 0.6, spin × −0.6)
///   while landing faster than 140 pt/s, then rests: slides to a stop and
///   settles flat (belly or back, whichever is nearer).
/// - It never leaves the screen sideways (24 pt left, 30 pt right, × −0.3).
///
/// No collisions with hoops, rims or pickups while tumbling.
class DeathTumble {
  DeathTumble({
    required Vector2 position,
    required Vector2 velocity,
    Vector2? normal,
    required this.camX,
    required double camSpeed,
    required this.top,
    required this.floor,
    this.radius = RunConfig.birdRadius,
    this.angle = 0,
    this.viewWidth = RunConfig.worldWidth,
    this.viewLeft = 0,
  }) : position = position.clone(),
       velocity = velocity.clone(),
       camSpeed = math.max(0, camSpeed),
       _camSpeed0 = math.max(0, camSpeed) {
    final n = normal;
    if (n != null) {
      this.velocity.addScaled(n, PhysicsConfig.deathKnock);
    } else {
      this.velocity.y -= PhysicsConfig.missPop;
    }
    final impact = n != null
        ? -n.y * PhysicsConfig.spinImpact
        : PhysicsConfig.spinMiss;
    spin = (this.velocity.x / PhysicsConfig.spinPerSpeed + impact).clamp(
      -PhysicsConfig.maxSpin,
      PhysicsConfig.maxSpin,
    );
  }

  /// Bird centre (track x, screen y).
  final Vector2 position;
  final Vector2 velocity;

  /// The world camera (track x of the screen's left edge).
  double camX;

  /// The camera's speed (eases to 0 over 0.4 s).
  double camSpeed;
  final double _camSpeed0;

  /// The current tooth lines (squeeze-aware; the run updates them).
  double top, floor;
  final double radius;

  /// Screen width (the edge rule).
  final double viewWidth;

  /// WP-TAB: the screen's left edge (screen x; −extra on a wide screen).
  final double viewLeft;

  /// Radians (positive = clockwise).
  double angle;

  /// rad/s.
  late double spin;

  bool resting = false;
  int bounces = 0;
  double time = 0;

  /// Called at each floor landing (bounce or the final landing) with the
  /// contact point (dust / feather puff).
  void Function(Vector2 at)? onLand;

  /// §3.0.5 resting line: tooth tips − r + 2.
  double get restY => floor - radius + PhysicsConfig.restInset;

  /// Screen x of the bird.
  double get screenPosition => position.x - camX;

  void step(double dt) {
    if (dt <= 0) return;
    time += dt;
    if (_camSpeed0 > 0) {
      camSpeed = math.max(
        0,
        camSpeed - _camSpeed0 / PhysicsConfig.worldStopSeconds * dt,
      );
      camX += camSpeed * dt;
    }
    final rest = restY;
    if (!resting) {
      velocity.y += RunConfig.gravity * dt;
      velocity.x *= 1 - PhysicsConfig.airDrag * dt;
      position.addScaled(velocity, dt);
      angle += spin * dt;
      if (position.y - radius < top && velocity.y < 0) {
        position.y = top + radius;
        velocity.y *= -PhysicsConfig.topRestitution;
        spin *= -PhysicsConfig.bounceSpin;
      }
      if (position.y >= rest && velocity.y > 0) {
        position.y = rest;
        onLand?.call(Vector2(position.x, floor));
        if (velocity.y > PhysicsConfig.bounceMinSpeed) {
          bounces++;
          velocity.y *= -PhysicsConfig.floorRestitution;
          velocity.x *= PhysicsConfig.bounceForward;
          spin *= -PhysicsConfig.bounceSpin;
        } else {
          velocity.y = 0;
          resting = true;
        }
      }
    } else {
      velocity.x *= math.max(0, 1 - PhysicsConfig.slideFriction * dt);
      position.x += velocity.x * dt;
      position.y = rest;
      spin *= math.max(0, 1 - PhysicsConfig.spinDamp * dt);
      angle += spin * dt;
      final flat = (angle / math.pi).roundToDouble() * math.pi;
      angle += (flat - angle) * math.min(1, PhysicsConfig.settleRate * dt);
    }
    final x = position.x - camX;
    final right = viewWidth - PhysicsConfig.edgeRight;
    if (x > right) {
      position.x -= x - right;
      velocity.x = -velocity.x.abs() * PhysicsConfig.edgeRestitution;
    }
    if (x < viewLeft + PhysicsConfig.edgeLeft) {
      position.x += viewLeft + PhysicsConfig.edgeLeft - x;
      velocity.x = velocity.x.abs() * PhysicsConfig.edgeRestitution;
    }
  }

  // region WP-3d — themed death moments (PRD-2 §3.0.5)
  /// Only the world's 0.4 s ease to a stop, while a themed death holds the
  /// bird (Live Wire, Frost Ring, Black Hole); the bird starts its tumble
  /// with its momentum once the moment is over.
  void stepCamera(double dt) {
    if (dt <= 0 || _camSpeed0 <= 0) return;
    camSpeed = math.max(
      0,
      camSpeed - _camSpeed0 / PhysicsConfig.worldStopSeconds * dt,
    );
    camX += camSpeed * dt;
  }
  // endregion WP-3d

  /// Lying flat: resting and the angle settled to a multiple of π.
  bool get settledFlat {
    if (!resting) return false;
    final flat = (angle / math.pi).roundToDouble() * math.pi;
    return (angle - flat).abs() < 0.02;
  }
}
