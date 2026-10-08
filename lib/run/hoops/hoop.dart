import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../director/plans.dart';
import 'hoop_kind.dart';

/// A moving-ring driver (WP-1b's `HoopMotion` implements it).
abstract interface class HoopMotionDriver {
  void update(Hoop h, double t);
  Vector2 get offset;
  double get angleOffset;
  Vector2 get velocity;
}

/// One hoop slot in track coordinates (PRD-2 §7: one `Hoop` component with
/// a kind and ring offsets). WP-0b skeleton; WP-1a fills the frame / pass
/// logic. The hoop itself lives in `RunLayers.back` and draws the back half;
/// [front] lives in `RunLayers.front` and draws the front half over the
/// bird (master #3).
class Hoop extends PositionComponent {
  Hoop({required this.plan, required this.kind})
    : opening = plan.opening,
      tilt = plan.tiltDeg,
      rings = List.of(plan.ringOffsets),
      super(
        position: Vector2(plan.trackX, plan.centreY),
        angle: plan.tiltDeg * math.pi / 180,
        anchor: Anchor.center,
      ) {
    front = HoopFrontLayer(this);
  }

  final SlotPlan plan;
  final HoopKind kind;
  double opening;

  /// Degrees (positive = top leans right).
  double tilt;

  /// Ring offsets along the hoop's local y (pairs: two).
  final List<double> rings;
  HoopMotionDriver? motion;

  /// The base position (motion offsets are added to it).
  late final Vector2 basePosition = Vector2(plan.trackX, plan.centreY);

  /// A rim was touched (that pass is not perfect).
  bool touched = false;

  /// Each hoop resolves once (§3.0.4 5).
  bool resolved = false;

  /// Switch rings start closed (§3.20).
  bool open = true;
  int? takenRing;

  /// Announced on screen (ElementSpawned / met).
  bool announced = false;

  late final HoopFrontLayer front;

  /// Track x of the plane.
  double get planeX => position.x;

  void resolvePass(int ring) {
    resolved = true;
    takenRing = ring;
  }

  void resolveMiss() => resolved = true;

  /// Keeps [front] in step and removes both halves.
  void removeFromRun() {
    front.removeFromParent();
    removeFromParent();
  }

  @override
  void update(double dt) {
    super.update(dt);
    front
      ..position.setFrom(position)
      ..angle = angle;
  }
}

/// The front half of a [Hoop] (drawn over the bird). Kinds add children or
/// set [paintFront].
class HoopFrontLayer extends PositionComponent {
  HoopFrontLayer(this.hoop)
    : super(position: hoop.position.clone(), anchor: Anchor.center);
  final Hoop hoop;
  void Function(Canvas canvas)? paintFront;

  @override
  void render(Canvas canvas) => paintFront?.call(canvas);
}
