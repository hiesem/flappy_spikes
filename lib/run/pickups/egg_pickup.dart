import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/egg_config.dart';
import '../director/plans.dart';
import '../effects/collect_art.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The egg pickup kind (PRD-2 §3.27): the director's egg `GapItemPlan`
/// (§3.0.3: gap 10, weight 12, ≥ 15 gaps apart, mid-gap on the flight line)
/// becomes an [EggPickup]. What it *does* (egg on the bird, cracks per ring,
/// the chick) is `EggFeature` (items/egg.dart), reacting to
/// `PickupCollected`.
class EggPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.egg;

  @override
  Pickup build(GapItemPlan p, RunContext c) => EggPickup(p);
}

/// §5.26 the floating egg: a cream `#FFF3D6` 8 × 10 oval at 1.3× with three
/// tan speckles and a warm halo (r 22, α 0.6), bobbing ±3 pt at 3 rad/s.
/// Hit radius 16 pt (§3.0.3). Nothing else happens here — the feature
/// reacts to `PickupCollected(egg)`.
class EggPickup extends Pickup {
  EggPickup(GapItemPlan p)
    : super(
        id: ElementId.egg,
        hitRadius: PickupRadii.egg,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(2 * EggConfig.ovalRx * EggConfig.pickupScale),
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
    final bob = math.sin(_t * EggConfig.bobOmega) * EggConfig.bobAmp;
    final c = Offset(size.x / 2, size.y / 2 + bob);
    CollectArt.halo(
      canvas,
      c,
      EggConfig.haloR,
      EggConfig.haloColor,
      EggConfig.haloAlpha,
    );
    EggArt.paint(canvas, c, scale: EggConfig.pickupScale);
  }
}

/// §5.26 the egg's art (the mocks' `eggShape`): a cream oval with three tan
/// speckles and one zig-zag crack line per ring already passed. Used by the
/// pickup (scale 1.3), the bird's back (scale 1) and the HUD.
abstract final class EggArt {
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = EggConfig.crackWidth
    ..strokeJoin = StrokeJoin.round
    ..color = EggConfig.crackColor;

  /// Draws the egg centred at [centre] at [scale] with [cracks] crack lines.
  static void paint(
    Canvas canvas,
    Offset centre, {
    double scale = 1,
    int cracks = 0,
  }) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale, scale);
    _fill.color = EggConfig.oval;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 2 * EggConfig.ovalRx,
        height: 2 * EggConfig.ovalRy,
      ),
      _fill,
    );
    _fill.color = EggConfig.speckle;
    for (final s in EggConfig.speckles) {
      canvas.drawCircle(s, EggConfig.speckleR, _fill);
    }
    for (var i = 0; i < cracks.clamp(0, EggConfig.rings); i++) {
      final yy = EggConfig.crackStartY + i * EggConfig.crackStep;
      canvas.drawPath(
        Path()
          ..moveTo(-5, yy)
          ..lineTo(-2, yy + 2)
          ..lineTo(1, yy - 1)
          ..lineTo(4, yy + 2),
        _stroke,
      );
    }
    canvas.restore();
  }
}
