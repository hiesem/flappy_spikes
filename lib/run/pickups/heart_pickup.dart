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

/// The heart pickup kind (PRD-2 §3.3): the director's heart `GapItemPlan`
/// (§3.0.3: gap 3, then every 17–27 gaps, mid-gap, on the line or 0.1–0.4
/// band off it) becomes a [HeartPickup]. What a heart *does* (count, extra
/// life, sound, fetch flight) is `ExtraLifeFeature` (items/extra_life.dart),
/// reacting to `PickupCollected`.
class HeartPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.heart;

  @override
  Pickup build(GapItemPlan p, RunContext c) => HeartPickup(p);
}

/// §5.2 heart pickup (approved 1b, no glow): a 32 pt `#FF3B5C` heart with a
/// white outline and a gentle scale pulse 1.0 ↔ 1.14 (1 s loop). Hit radius
/// = the §3.0.3 heart radius (16 pt). A touch plays the shared
/// [PickupTouchFx] (`PickupTouchSpec.heart`: one gold ring) and removes it.
class HeartPickup extends Pickup {
  HeartPickup(GapItemPlan p)
    : super(
        id: ElementId.heart,
        hitRadius: PickupRadii.heart,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(LivesConfig.heartPickupSize),
      );

  static final _touch = PickupTouchFx.newPool();

  double _t = 0;

  /// §5.2 pulse scale at [t] s (1.0 → 1.14 → 1.0 per period, eased).
  static double pulseAt(double t) {
    final u = (t / LivesConfig.heartPulsePeriod) % 1;
    return 1 +
        (LivesConfig.heartPulseScale - 1) *
            (.5 - .5 * math.cos(2 * math.pi * u));
  }

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
        PickupTouchSpec.heart,
      ),
    );
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    LifeIcons.paintHeart(
      canvas,
      Offset(size.x / 2, size.y / 2),
      LivesConfig.heartPickupSize * pulseAt(_t),
      outline: LivesConfig.heartOutline,
    );
  }
}
