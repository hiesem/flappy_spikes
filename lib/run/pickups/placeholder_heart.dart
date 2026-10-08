import 'dart:ui';

import 'package:flame/components.dart';

import '../director/plans.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

// ============================================================================
// PLACEHOLDER — WP-1b heart *placement* wiring only. WP-2a replaces this file
// (and the WP-1b region in `pickups/registry.dart`) with the real
// `heart_pickup.dart`: §5.2 art, collect → hearts / extra life (§3.3),
// `PickupTouchFx.heart`, `FetchFlight` to the HUD indicator, sound, rumble.
// ============================================================================

/// PLACEHOLDER heart kind (WP-1b): turns the director's heart `GapItemPlan`
/// (§3.0.3 / §3.3: gap 3, then every 17–27 gaps, mid-gap, on the line or
/// 0.1–0.4 band off it) into a component at the planned spot. No gameplay
/// effect: collecting it only removes it.
class PlaceholderHeartKind extends PickupKind {
  @override
  ElementId get element => ElementId.heart;

  @override
  Pickup build(GapItemPlan p, RunContext c) => PlaceholderHeartPickup(p);
}

/// PLACEHOLDER heart pickup (WP-1b; replaced by WP-2a). Drawn as a plain
/// see-through heart with a white outline — not the final §5.2 art. Hit
/// radius = the §3.0.3 heart radius (16 pt).
class PlaceholderHeartPickup extends Pickup {
  PlaceholderHeartPickup(GapItemPlan p)
    : super(
        id: ElementId.heart,
        hitRadius: PickupRadii.heart,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(2 * PickupRadii.heart),
      );

  static final Paint _fill = Paint()..color = const Color(0x99FF3D7F);
  static final Paint _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = const Color(0xFFFFFFFF);

  @override
  void onCollect(RunContext c) => removeFromParent();

  @override
  void render(Canvas canvas) {
    final r = PickupRadii.heart;
    final cx = size.x / 2, cy = size.y / 2;
    final path = Path()
      ..moveTo(cx, cy + r * 0.8)
      ..cubicTo(
        cx - r * 1.4,
        cy - r * 0.1,
        cx - r * 0.6,
        cy - r * 1.1,
        cx,
        cy - r * 0.4,
      )
      ..cubicTo(
        cx + r * 0.6,
        cy - r * 1.1,
        cx + r * 1.4,
        cy - r * 0.1,
        cx,
        cy + r * 0.8,
      )
      ..close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _edge);
  }
}
