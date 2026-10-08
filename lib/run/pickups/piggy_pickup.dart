import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/piggy_config.dart';
import '../director/plans.dart';
import '../effects/collect_art.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The Piggy Bank pickup kind (PRD-2 §3.28): the director's piggy
/// `GapItemPlan` (§3.0.3: gap 12, weight 10, ≥ 30 gaps apart, mid-gap on the
/// flight line) becomes a [PiggyPickup]. What it *does* (the bank, the 20
/// coins, the ×2 pay-out) is `PiggyFeature` (items/piggy.dart), reacting to
/// `PickupCollected`.
class PiggyPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.piggy;

  @override
  Pickup build(GapItemPlan p, RunContext c) => PiggyPickup(p);
}

/// §5.27 the floating piggy: the [PiggyArt] pig at 1.25× with a soft pink
/// halo (r 26, α 0.5), bobbing ±3 pt at 3 rad/s. Hit radius 18 pt
/// (§3.0.3). Nothing else happens here — the feature reacts to
/// `PickupCollected`.
class PiggyPickup extends Pickup {
  PiggyPickup(GapItemPlan p)
    : super(
        id: ElementId.piggy,
        hitRadius: PickupRadii.piggy,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(2 * PiggyConfig.bodyRx * PiggyConfig.pickupScale),
      );

  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void onCollect(RunContext c) => removeFromParent();

  @override
  void render(Canvas canvas) {
    final bob = math.sin(_t * PiggyConfig.bobOmega) * PiggyConfig.bobAmp;
    final centre = Offset(size.x / 2, size.y / 2 + bob);
    CollectArt.halo(
      canvas,
      centre,
      PiggyConfig.haloR,
      PiggyConfig.haloColor,
      PiggyConfig.haloAlpha,
    );
    PiggyArt.paint(canvas, centre, PiggyConfig.pickupScale);
  }
}

/// §5.27 the pig art (the mock's `pig()`): flat pink `#FF8AC4` body (rx 13,
/// ry 10) with an ear, snout `#FF6FB0`, legs `#E05A99`, nostrils `#B0306E`,
/// eye `#3E1028`, a coin slot and a curly tail. Used by the pickup (1.25)
/// and the HUD badge (1.4). Centred at [centre], one art unit = [scale] pt.
abstract final class PiggyArt {
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = PiggyConfig.snout;

  static void paint(Canvas canvas, Offset centre, double scale) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale, scale);
    _fill.color = PiggyConfig.legs;
    canvas
      ..drawRect(const Rect.fromLTWH(-8, 6, 4, 6), _fill)
      ..drawRect(const Rect.fromLTWH(4, 6, 4, 6), _fill);
    _fill.color = PiggyConfig.body;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 2 * PiggyConfig.bodyRx,
        height: 2 * PiggyConfig.bodyRy,
      ),
      _fill,
    );
    CollectArt.triangle(canvas, const [
      Offset(-7, -8),
      Offset(-2, -15),
      Offset(0, -7),
    ], PiggyConfig.body);
    _fill.color = PiggyConfig.snout;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-12, 1), width: 8, height: 9),
      _fill,
    );
    _fill.color = PiggyConfig.nostril;
    canvas
      ..drawRect(const Rect.fromLTWH(-13.5, 0, 1.2, 2), _fill)
      ..drawRect(const Rect.fromLTWH(-11.2, 0, 1.2, 2), _fill);
    _fill.color = PiggyConfig.eye;
    canvas
      ..drawCircle(const Offset(-6, -3), 1.5, _fill)
      ..drawRect(const Rect.fromLTWH(-3, -10, 7, 1.8), _fill);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(14, -2), radius: 3),
      math.pi * .7,
      math.pi * 1.5,
      false,
      _stroke,
    );
    canvas.restore();
  }
}
