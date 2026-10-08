import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/comet_config.dart';
import '../config/parts_config.dart';
import '../director/plans.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The comet star kind (PRD-2 §3.8): the director's comet `GapItemPlan`
/// (attached to a comet hoop, 20 pt past its plane at the hoop centre;
/// §3.0.3 slot order 6) becomes a [CometStar]. Starting the boost is
/// `CometFeature` (items/comet.dart), reacting to `PickupCollected` — so a
/// pair's COMET gift (WP-3d) starts it by emitting the same event.
class CometStarKind extends PickupKind {
  @override
  ElementId get element => ElementId.comet;

  @override
  Pickup build(GapItemPlan p, RunContext c) => CometStar(p);
}

/// §5.6 the comet pickup: a 46 pt gold 4-point star with a white 2 pt
/// outline and an inner white star, a pink / gold comet tail to the right;
/// the star wobbles ±14° and pulses ±8 %, the whole pickup bobs ±4 pt.
/// Hit radius 18 pt (§3.0.3). It hangs in the opening of an upright, still
/// hoop, so flying through the hoop collects it.
class CometStar extends Pickup {
  CometStar(GapItemPlan p)
    : super(
        id: ElementId.comet,
        hitRadius: PickupRadii.comet,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(CometConfig.starSize),
      );

  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  /// The collection pop is the comet's (`CometRide`): it plays at the bird.
  @override
  void onCollect(RunContext c) => removeFromParent();

  @override
  void render(Canvas canvas) {
    final bob = CometConfig.starBob * math.sin(_t * CometConfig.starBobOmega);
    paintStar(canvas, Offset(size.x / 2, size.y / 2 + bob), t: _t);
  }

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xFFFFFFFF);

  /// §5.6 Draws the pickup centred on [c] at time [t] (s): tail, then the
  /// wobbling / pulsing star (`screen_comet2.html`, 46 pt box).
  static void paintStar(Canvas canvas, Offset c, {double t = 0}) {
    final k = CometConfig.starSize / 46;
    // Tail (does not wobble): pink 0.85 under gold 0.9.
    _fill.color = PartsConfig.pink.withValues(alpha: .85);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + 7 * k, c.dy - 9 * k)
        ..lineTo(c.dx + 73 * k, c.dy)
        ..lineTo(c.dx + 7 * k, c.dy + 9 * k)
        ..close(),
      _fill,
    );
    _fill.color = PartsConfig.gold.withValues(alpha: .9);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + 7 * k, c.dy - 5 * k)
        ..lineTo(c.dx + 49 * k, c.dy)
        ..lineTo(c.dx + 7 * k, c.dy + 5 * k)
        ..close(),
      _fill,
    );
    final wobble =
        CometConfig.starWobbleDeg *
        math.pi /
        180 *
        math.sin(t * CometConfig.starWobbleOmega);
    final pulse =
        1 + CometConfig.starPulse * math.sin(t * CometConfig.starPulseOmega);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(wobble)
      ..scale(pulse * k);
    final outer = _star(21, 6);
    _fill.color = PartsConfig.gold;
    canvas.drawPath(outer, _fill);
    _stroke.strokeWidth = CometConfig.starOutline / k;
    canvas.drawPath(outer, _stroke);
    _fill.color = const Color(0xE6FFFFFF);
    canvas
      ..drawPath(_star(11, 3), _fill)
      ..restore();
  }

  /// A 4-point star centred on the origin: tips at [r], waist corners at
  /// (±[w], ±[w]) (the mock's polygon, e.g. 21 / 6 for the 46 pt star).
  static Path _star(double r, double w) => Path()
    ..moveTo(0, -r)
    ..lineTo(w, -w)
    ..lineTo(r, 0)
    ..lineTo(w, w)
    ..lineTo(0, r)
    ..lineTo(-w, w)
    ..lineTo(-r, 0)
    ..lineTo(-w, -w)
    ..close();
}
