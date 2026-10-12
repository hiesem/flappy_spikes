import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../director/plans.dart';
import '../effects/clear_fade.dart';
import '../physics/hoop_frame.dart';
import 'hoop_kind.dart';
import 'ring_painter.dart';

/// A moving-ring driver (WP-1b's `HoopMotion` implements it).
abstract interface class HoopMotionDriver {
  void update(Hoop h, double t);
  Vector2 get offset;
  double get angleOffset;
  Vector2 get velocity;

  /// Degrees per second of [angleOffset] (§3.11 rock / swing / orbit).
  double get angularVelocity;
}

/// One hoop slot in track coordinates (PRD-2 §7: one `Hoop` component with
/// a kind and ring offsets). WP-0b skeleton; WP-1a fills the frame / pass
/// logic. The hoop itself lives in `RunLayers.back` and draws the back half;
/// [front] lives in `RunLayers.front` and draws the front half over the
/// bird (master #3).
class Hoop extends PositionComponent with ClearFade {
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

  /// PRD-2.2 §30.2 (for §11): at a plane-crossing pass, the bird centre's
  /// local y minus the passed ring's offset, measured in the ring's own
  /// moving frame at the crossing (`PlaneEvent.offset`). Null until then,
  /// and for passes without a crossing (ride passes).
  double? passOffset;

  /// Switch rings start closed (§3.20).
  bool open = true;
  int? takenRing;

  /// Announced on screen (ElementSpawned / met).
  bool announced = false;

  late final HoopFrontLayer front;

  /// Track x of the plane.
  double get planeX => position.x;

  // region WP-1a — frame, look, back painter (PRD-2 §3.0.4, §3.1, §5.13)
  /// How the ring is drawn right now (master #3 parameters): colour
  /// override (tier / Big Hoops / miss flash), stroke, dash, glow. Kinds'
  /// painters read it; the miss flash and later the tier look write it.
  final HoopLook look = HoopLook();

  /// Paints the back half (behind the bird), in hoop-local coordinates.
  void Function(Canvas canvas)? paintBack;

  /// The tilt in radians (plan tilt; motion adds its angle offset).
  double get tiltRad => tilt * math.pi / 180;

  /// §3.0.4 the hoop's world transform now: centre (base + motion offset),
  /// tilt (+ motion angle), ring offsets, opening, the kind's rim radius
  /// and the motion velocity.
  HoopFrame frame() {
    final m = motion;
    return HoopFrame(
      centre: m == null ? basePosition.clone() : basePosition + m.offset,
      tilt: tiltRad + (m?.angleOffset ?? 0),
      rings: rings,
      opening: opening,
      rimR: kind.rimRadius(this),
      velocity: m?.velocity.clone(),
      angularVelocity: (m?.angularVelocity ?? 0) * math.pi / 180,
    );
  }

  /// Advances the motion to runClock [t] and moves both halves with it.
  void syncMotion(double t) {
    final m = motion;
    if (m == null) return;
    m.update(this, t);
    position.setFrom(basePosition + m.offset);
    angle = tiltRad + m.angleOffset;
    front
      ..position.setFrom(position)
      ..angle = angle;
  }

  @override
  void render(Canvas canvas) {
    final paint = paintBack;
    if (paint != null) paintFaded(canvas, paint);
  }
  // endregion WP-1a

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

// region WP-1a — ring look (master #3 parameters)
/// The mutable drawing parameters of a hoop's rings (master #3,
/// [RingPainter.paintHalf]): null colours = the equipped hoop skin.
class HoopLook {
  RingColors? colors;
  double strokeWidth = RingPainter.stroke;
  List<double>? dash;
  Color? glow;
  double glowBlur = 24;
  double opacity = 1;

  /// Missed: the streak tier look stays off (§5.13).
  bool missed = false;
}
// endregion WP-1a

/// The front half of a [Hoop] (drawn over the bird). Kinds add children or
/// set [paintFront].
class HoopFrontLayer extends PositionComponent with ClearFade {
  HoopFrontLayer(this.hoop)
    : super(position: hoop.position.clone(), anchor: Anchor.center);
  final Hoop hoop;
  void Function(Canvas canvas)? paintFront;

  @override
  void render(Canvas canvas) {
    final paint = paintFront;
    if (paint != null) paintFaded(canvas, paint);
  }
}
