import 'package:flame/components.dart';

import '../director/plans.dart';
import '../elements.dart';
import '../run_context.dart';

/// §3.0.3 pickup hit radii (pt): touched when the distance from the bird
/// centre to the pickup centre minus the bird radius (× 0.52 as Mini Bird)
/// is ≤ the radius.
abstract final class PickupRadii {
  /// §3.0.3 Heart.
  static const double heart = 16;

  /// §3.0.3 Shield.
  static const double shield = 18;

  /// §3.0.3 Golden feather.
  static const double feather = 18;

  /// §3.0.3 Puzzle piece.
  static const double puzzlePiece = 22;

  /// §3.0.3 Switch.
  static const double switchPickup = 18;

  /// §3.0.3 Comet star.
  static const double comet = 18;

  /// §3.0.3 Egg.
  static const double egg = 16;

  /// §3.0.3 Piggy Bank.
  static const double piggy = 18;

  /// §3.0.3 Firefly Jar.
  static const double jar = 18;

  /// §3.0.3 Powerup capsule.
  static const double capsule = 18;

  /// §3.0.3 Piggy coin.
  static const double piggyCoin = 10;

  /// §3.0.3 Star (Star Trail).
  static const double star = 10;

  /// §3.0.3 Firefly.
  static const double firefly = 16;

  static double? forElement(ElementId e) => switch (e) {
    ElementId.heart => heart,
    ElementId.shield => shield,
    ElementId.feather => feather,
    ElementId.puzzlePiece => puzzlePiece,
    ElementId.switchRing => switchPickup,
    ElementId.comet => comet,
    ElementId.egg => egg,
    ElementId.piggy => piggy,
    ElementId.jar => jar,
    ElementId.capsule ||
    ElementId.hourglass ||
    ElementId.miniBird ||
    ElementId.coinFrenzy => capsule,
    ElementId.piggyCoins => piggyCoin,
    ElementId.starTrail => star,
    ElementId.fireflySwarm => firefly,
    _ => null,
  };
}

/// Base of every in-run pickup, in track coordinates (ARCH §1.6). WP-0c's
/// `PickupTouchFx` is the shared touch effect.
abstract class Pickup extends PositionComponent {
  Pickup({
    required this.id,
    required this.hitRadius,
    this.plan,
    super.position,
    super.size,
    super.anchor = Anchor.center,
  });

  final ElementId id;
  final double hitRadius;
  final GapItemPlan? plan;
  bool collected = false;

  /// Passed the bird uncaught (resolved once).
  bool escaped = false;

  /// Announced on screen (ElementSpawned / met).
  bool announced = false;

  /// §3.0.3 hit test against a bird at [birdTrack] with radius [birdR].
  bool touches(Vector2 birdTrack, double birdR) =>
      !collected && birdTrack.distanceTo(position) - birdR <= hitRadius;

  /// Fully behind a bird at [birdTrackX] (it can no longer be caught).
  bool isPast(double birdTrackX, double birdR) =>
      position.x + hitRadius < birdTrackX - birdR;

  void onCollect(RunContext c);
  void onPassedUncaught(RunContext c) {}
}

/// Builds a pickup from a gap-item plan (ARCH §1.6).
abstract class PickupKind {
  ElementId get element;
  Pickup build(GapItemPlan p, RunContext c);
}
