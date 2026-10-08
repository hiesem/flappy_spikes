import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/lives_config.dart';
import '../director/plans.dart';
import '../effects/life_icons.dart';
import '../effects/pickup_touch_fx.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The shield pickup kind (PRD-2 §3.7): the director's shield `GapItemPlan`
/// (§3.0.3: from gap 12, max one per run, mid-gap 0.1–0.4 band off the
/// line, never while shielded) becomes a [ShieldPickup]. Arming the shield
/// is `ShieldFeature` (items/shield.dart), reacting to `PickupCollected`.
class ShieldPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.shield;

  @override
  Pickup build(GapItemPlan p, RunContext c) => ShieldPickup(p);
}

/// §5.5 shield pickup: the shield icon ([LifeIcons.paintShield], 38 pt)
/// floating with a gentle ±3 pt wobble. Hit radius 18 pt (§3.0.3). A touch
/// plays the shared [PickupTouchFx] (`PickupTouchSpec.shield`: the gold
/// ring burst the circle forms with) and removes it.
class ShieldPickup extends Pickup {
  ShieldPickup(GapItemPlan p)
    : super(
        id: ElementId.shield,
        hitRadius: PickupRadii.shield,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2(
          LivesConfig.shieldPickupWidth,
          LivesConfig.shieldPickupWidth * 1.1,
        ),
      );

  static final _touch = PickupTouchFx.newPool();

  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void onCollect(RunContext c) {
    c.layers.fx.add(
      _touch.obtain().play(
        Offset(position.x, position.y),
        PickupTouchSpec.shield,
      ),
    );
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final bob =
        LivesConfig.shieldPickupBob *
        math.sin(_t * LivesConfig.shieldPickupBobOmega);
    LifeIcons.paintShield(
      canvas,
      Offset(size.x / 2, size.y / 2 + bob),
      LivesConfig.shieldPickupWidth,
    );
  }
}
