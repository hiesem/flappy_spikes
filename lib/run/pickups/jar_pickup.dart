import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/jar_config.dart';
import '../director/plans.dart';
import '../effects/collect_art.dart';
import '../effects/particle_pool.dart' show ParticleShape;
import '../elements.dart';
import '../run_context.dart';
import 'pickup.dart';

/// The Firefly Jar pickup kind (PRD-2 §3.29): the director's jar
/// `GapItemPlan` (§3.0.3: gap 15, weight 10, ≥ 30 gaps apart, mid-gap on the
/// flight line) becomes a [JarPickup]. What it *does* (the jar, the swarms,
/// the +25) is `JarFeature` (items/jar.dart), reacting to `PickupCollected`.
class JarPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.jar;

  @override
  Pickup build(GapItemPlan p, RunContext c) => JarPickup(p, c);
}

/// §5.28 the animated floating jar: it bobs ±5 pt (2.6 rad/s) and sways
/// ±0.12 rad (2 rad/s), its glow pulses (halo r 34 + 6·pul, α 0.45 + 0.3·pul),
/// ten soft light rays turn at 0.6 rad/s, four fireflies blink and drift up
/// inside, and tiny sparks float off it. Hit radius 18 pt (§3.0.3). Nothing
/// else happens here — the feature reacts to `PickupCollected`.
class JarPickup extends Pickup {
  JarPickup(GapItemPlan p, this.c)
    : super(
        id: ElementId.jar,
        hitRadius: PickupRadii.jar,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(2 * JarConfig.glassHalfW * 2),
      );

  final RunContext c;

  double _t = 0;
  double _sparkIn = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    // §5.28 tiny sparks float off the jar (~10/s).
    _sparkIn -= dt;
    while (_sparkIn <= 0) {
      _sparkIn += 1 / JarConfig.sparkRate;
      final r = c.cosmetic;
      c.run.particles.spawn(
        shape: ParticleShape.circle,
        x: position.x + (r.nextDouble() - .5) * JarConfig.sparkSpread,
        y: position.y + (r.nextDouble() - .5) * JarConfig.sparkSpread,
        vx: (r.nextDouble() - .5) * 20,
        vy: -25 - r.nextDouble() * 25,
        w: JarConfig.sparkSizeMin +
            r.nextDouble() * (JarConfig.sparkSizeMax - JarConfig.sparkSizeMin),
        color: JarConfig.awayColor,
        life: JarConfig.sparkLife,
      );
    }
  }

  @override
  void onCollect(RunContext c) => removeFromParent();

  @override
  void render(Canvas canvas) {
    final bob = math.sin(_t * JarConfig.bobOmega) * JarConfig.bobAmp;
    final centre = Offset(size.x / 2, size.y / 2 + bob);
    final pul = .5 + .5 * math.sin(_t * JarConfig.haloPulseOmega);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(math.sin(_t * JarConfig.swayOmega) * JarConfig.swayAmp);
    // §5.28 ten soft light rays (36 + 8·sin(3t + i) pt, 0.6 rad/s).
    for (var i = 0; i < JarConfig.rays; i++) {
      final a = i / JarConfig.rays * 2 * math.pi + _t * JarConfig.rayOmega;
      final len =
          JarConfig.rayLength + JarConfig.rayPulse * math.sin(_t * 3 + i);
      final dir = Offset(math.cos(a), math.sin(a));
      final p = Path()
        ..moveTo(0, 0)
        ..lineTo(
          math.cos(a - JarConfig.raySpread) * len,
          math.sin(a - JarConfig.raySpread) * len,
        )
        ..lineTo(
          math.cos(a + JarConfig.raySpread) * len,
          math.sin(a + JarConfig.raySpread) * len,
        )
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..shader = Gradient.linear(Offset.zero, dir * len, [
            JarConfig.rayColor.withValues(alpha: .55 + .3 * pul),
            JarConfig.rayColorEnd.withValues(alpha: 0),
          ]),
      );
    }
    CollectArt.halo(
      canvas,
      Offset.zero,
      JarConfig.haloR + JarConfig.haloPulse * pul,
      JarConfig.haloColor,
      JarConfig.haloAlpha + JarConfig.haloAlphaPulse * pul,
    );
    JarArt.paint(canvas, Offset.zero, JarConfig.pickupScale, fill: .25 + .1 * pul);
    // §5.28 four blinkng fireflies drifting up inside the glass.
    for (var k = 0; k < JarConfig.innerFlies; k++) {
      final fx =
          math.sin(_t * JarConfig.innerSwayOmega + k * JarConfig.innerSwayPhase) *
              JarConfig.innerSway;
      final fy = JarConfig.innerRiseTop -
          ((_t * JarConfig.innerRiseRate + k * JarConfig.innerRiseStep) % 1) *
              JarConfig.innerRiseSpan;
      final bl =
          .5 + .5 * math.sin(_t * JarConfig.innerBlinkOmega + k * JarConfig.innerBlinkPhase);
      CollectArt.halo(
        canvas,
        Offset(fx, fy),
        JarConfig.innerHaloR,
        JarConfig.awayColor,
        .9 * bl,
      );
      final dot = Paint()..color = JarConfig.innerDot;
      canvas.drawCircle(Offset(fx, fy), JarConfig.innerDotR, dot);
    }
    canvas.restore();
  }
}

/// §5.28 the glass jar (the mocks' `jarIcon`): pale blue glass
/// `rgba(200,240,255,.45)` with a grey `rgba(120,140,150,.95)` 2 pt outline,
/// a brown `#8D6E3F` lid, and lime glow fill rising with [fill] (0..1).
/// Used by the pickup (1.05) and the HUD badge (0.95).
abstract final class JarArt {
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = JarConfig.glassStrokeWidth
    ..color = JarConfig.glassStroke;

  /// The glass body path in jar units (x ±12, top −14, bottom 17, corners 4).
  static Path body() {
    const w = JarConfig.glassHalfW;
    const c = JarConfig.glassCorner;
    return Path()
      ..moveTo(-w, JarConfig.glassTop)
      ..lineTo(-w, JarConfig.glassBottom - c)
      ..quadraticBezierTo(-w, JarConfig.glassBottom, -w + c, JarConfig.glassBottom)
      ..lineTo(w - c, JarConfig.glassBottom)
      ..quadraticBezierTo(w, JarConfig.glassBottom, w, JarConfig.glassBottom - c)
      ..lineTo(w, JarConfig.glassTop)
      ..close();
  }

  static void paint(Canvas canvas, Offset centre, double scale, {double fill = 0}) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale, scale);
    final path = body();
    _fill.color = JarConfig.glass;
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
    _fill.color = JarConfig.lid;
    canvas.drawRect(
      const Rect.fromLTWH(
        -JarConfig.lidW / 2,
        JarConfig.lidY,
        JarConfig.lidW,
        JarConfig.lidH,
      ),
      _fill,
    );
    if (fill > 0) {
      _fill.color = JarConfig.glow;
      canvas
        ..save()
        ..clipPath(path)
        ..drawRect(
          Rect.fromLTWH(
            -JarConfig.glassHalfW,
            JarConfig.glassBottom - 30 * fill.clamp(0.0, 1.0),
            JarConfig.glassHalfW * 2,
            30 * fill.clamp(0.0, 1.0),
          ),
          _fill,
        )
        ..restore();
    }
    canvas.restore();
  }
}
