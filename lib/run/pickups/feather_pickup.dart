import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/feather_config.dart';
import '../director/plans.dart';
import '../effects/particle_pool.dart';
import '../effects/pickup_touch_fx.dart';
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The golden feather kind (PRD-2 §3.15): the director's feather
/// `GapItemPlan` (§3.0.3: once per run in the gap after hoop 3–12, 0.65 ×
/// spacing after the hoop, 64–200 pt above its centre, only while fewer
/// than 3 feathers are held) becomes a [FeatherPickup]. What a feather
/// *does* (count, tray, sounds) is `FeathersFeature` (items/feathers.dart),
/// reacting to `PickupCollected`.
class FeatherPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.feather;

  @override
  Pickup build(GapItemPlan p, RunContext c) {
    c.s.featherSpawned = true;
    return FeatherPickup(p, c);
  }
}

/// §5.14 the golden feather in the field: bobs, pulses and sways, with a
/// small twinkle every 0.28 s on a 24 pt radius (in the run's world pool,
/// so the twinkles scroll with the world). A touch plays the shared
/// [PickupTouchFx] (`PickupTouchSpec.feather`) and removes it — the fetch
/// flight into the tray is the feature's. Hit radius 18 (§3.0.3).
class FeatherPickup extends Pickup {
  FeatherPickup(GapItemPlan p, this.c)
    : super(
        id: ElementId.feather,
        hitRadius: PickupRadii.feather,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2(48, 56),
      );

  final RunContext c;

  static final _touch = PickupTouchFx.newPool();

  double _t = 0;
  double _spark = 0;

  /// §5.14 idle pose at [t]: (dx, dy, scale, rotation).
  static (double, double, double, double) poseAt(double t) {
    const tau = 2 * math.pi;
    final bob = FeatherConfig.bob * math.sin(t * tau * FeatherConfig.bobHz);
    final s = FeatherConfig.pickupScale *
        (1 + FeatherConfig.pulse * math.sin(t * tau * FeatherConfig.pulseHz));
    final r = FeatherConfig.pickupTilt +
        FeatherConfig.sway * math.sin(t * tau * FeatherConfig.swayHz);
    final dx =
        FeatherConfig.drift * math.sin(t * tau * FeatherConfig.swayHz + 1);
    return (dx, bob, s, r);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _spark -= dt;
    if (_spark <= 0 && !collected) {
      _spark = FeatherConfig.twinkleEvery;
      final r = c.cosmetic;
      final a = r.nextDouble() * math.pi * 2;
      final size = FeatherConfig.twinkleMin +
          r.nextDouble() * (FeatherConfig.twinkleMax - FeatherConfig.twinkleMin);
      c.run.particles.spawn(
        shape: ParticleShape.twinkle,
        x: position.x + math.cos(a) * FeatherConfig.twinkleRadius,
        y: position.y + math.sin(a) * FeatherConfig.twinkleRadius,
        w: size * 2.8,
        color: r.nextBool() ? const Color(0xFFFFFFFF) : FeatherConfig.paleGold,
        life: FeatherConfig.twinkleLife,
        spin: 3,
      );
    }
  }

  @override
  void onCollect(RunContext c) {
    c.layers.fx.add(
      _touch.obtain().play(
        Offset(position.x, position.y),
        PickupTouchSpec.feather,
        pool: c.run.particles,
        random: c.cosmetic,
      ),
    );
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final (dx, dy, s, r) = poseAt(_t);
    canvas.save();
    canvas.translate(size.x / 2 + dx, size.y / 2 + dy);
    canvas.rotate(r);
    canvas.scale(s);
    FeatherArt.paint(canvas);
    canvas.restore();
  }
}

/// The approved golden feather (§5.14; `collect.js ART.feather`), drawn in
/// its 1-unit art box centred on the origin (≈ 20 × 44 incl. the quill):
/// vane `#FFB529` with the right half `#F09A0A`, four white notch strokes,
/// a pink quill extending below the vane and a white outline. Used by the
/// pickup, its fetch flight, the tray and the balloon bonus screen.
abstract final class FeatherArt {
  static final Path _vane = Path()
    ..moveTo(0, -19)
    ..cubicTo(9, -12, 10, 6, 2, 15)
    ..lineTo(0, 17)
    ..lineTo(-2, 15)
    ..cubicTo(-8, 6, -7, -12, 0, -19)
    ..close();
  static final Path _right = Path()
    ..moveTo(0, -19)
    ..cubicTo(9, -12, 10, 6, 2, 15)
    ..lineTo(0, 17)
    ..close();
  static final Path _notches = Path()
    ..moveTo(4, -5)
    ..lineTo(8.5, -8.5)
    ..moveTo(5, 3)
    ..lineTo(9, 0)
    ..moveTo(-3, -1)
    ..lineTo(-6.5, -4.5)
    ..moveTo(-3, 8)
    ..lineTo(-6, 5);
  static final Path _quill = Path()
    ..moveTo(0, 23)
    ..lineTo(0, -14);
  static final Path _innerQuill = Path()
    ..moveTo(0, 17)
    ..lineTo(0, -14);

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Paints the feather; [ghost] = a flat silhouette in that colour (an
  /// empty slot); [outline] = the white outline per side (pt in art units).
  static void paint(
    Canvas canvas, {
    Color? ghost,
    double outline = FeatherConfig.outline,
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
      );
    }
    if (ghost != null) {
      canvas.drawPath(_quill, _stroke
        ..color = ghost
        ..strokeWidth = 2.6);
      canvas.drawPath(_vane, _fill..color = ghost);
    } else {
      const white = Color(0xFFFFFFFF);
      if (outline > 0) {
        canvas.drawPath(_quill, _stroke
          ..color = white
          ..strokeWidth = 2.6 + 2 * outline);
        canvas.drawPath(_vane, _stroke
          ..color = white
          ..strokeWidth = 2 * outline);
      }
      canvas.drawPath(_quill, _stroke
        ..color = FeatherConfig.quill
        ..strokeWidth = 2.6);
      canvas.drawPath(_vane, _fill..color = FeatherConfig.vane);
      canvas.drawPath(_right, _fill..color = FeatherConfig.vaneRight);
      canvas.drawPath(_notches, _stroke
        ..color = white
        ..strokeWidth = 1.6);
      canvas.drawPath(_innerQuill, _stroke
        ..color = FeatherConfig.quill
        ..strokeWidth = 2.2);
    }
    if (layer) canvas.restore();
  }

  /// [paint] at [at], [scale], [rotation].
  static void paintAt(
    Canvas canvas,
    Offset at,
    double scale,
    double rotation, {
    Color? ghost,
    double outline = FeatherConfig.outline,
    double opacity = 1,
  }) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotation);
    canvas.scale(scale);
    paint(canvas, ghost: ghost, outline: outline, opacity: opacity);
    canvas.restore();
  }
}
