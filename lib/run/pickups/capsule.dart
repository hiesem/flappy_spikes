import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/capsule_config.dart';
import '../director/plans.dart';
import '../effects/pickup_touch_fx.dart';
import '../elements.dart';
import '../items/timed_powerup.dart';
import '../run_context.dart';
import '../run_state.dart';
import 'pickup.dart';

/// The powerup capsule kind (PRD-2 §3.30–3.32): the director's capsule
/// `GapItemPlan` (§3.0.3: gap item from gap 10, weight 20, ≥ 20 gaps apart,
/// mid-gap on the line between the two hoops, never while a timed powerup
/// or a ride runs; type Hourglass 35 / Mini Bird 35 / Coin Frenzy 30 in
/// `plan.extra`) becomes a [CapsulePickup]. Starting the powerup is
/// `TimedPowerupSlot` (items/timed_powerup.dart), reacting to
/// `PickupCollected`.
class CapsulePickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.capsule;

  @override
  Pickup build(GapItemPlan p, RunContext c) => CapsulePickup(p);
}

/// §5.29 one capsule: a 34 pt rounded square (r 8) in the powerup colour
/// with a darker lower band and the white icon, bobbing ±3 pt inside a
/// pulsing 25 pt ring; a touch bursts it (18 squares in its colour and
/// white, `PickupTouchSpec.capsule`). Hit radius 18 (§3.0.3).
class CapsulePickup extends Pickup {
  CapsulePickup(GapItemPlan p)
    : type = TimedPowerupInfo.fromCapsule(
        p.extra is CapsuleType
            ? p.extra! as CapsuleType
            : CapsuleType.hourglass,
      ),
      super(
        id: ElementId.capsule,
        hitRadius: PickupRadii.capsule,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(2 * CapsuleConfig.ringRadius),
      );

  /// The powerup inside.
  final TimedPowerup type;

  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void onCollect(RunContext c) {
    PickupTouchFx.emitSquares(
      c.run.particles,
      Offset(position.x, position.y),
      PickupTouchSpec.capsule.withBodyColor(type.color),
      c.cosmetic,
    );
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final bob = CapsuleConfig.bob * math.sin(_t * CapsuleConfig.bobOmega);
    CapsuleArt.paintCapsule(
      canvas,
      Offset(size.x / 2, size.y / 2 + bob),
      type,
      _t,
    );
  }
}

/// The capsule and its three icons (§5.29–5.31), shared by the capsule
/// pickup and the HUD timer pill. Drawn in the lab's 1 pt units, centred on
/// the origin.
abstract final class CapsuleArt {
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  static const Color _white = Color(0xFFFFFFFF);

  /// §5.29 the capsule at [centre]: pulsing ring, body, lower band, icon.
  static void paintCapsule(
    Canvas canvas,
    Offset centre,
    TimedPowerup type,
    double t,
  ) {
    final pulse = math.sin(t * CapsuleConfig.pulseOmega);
    final s = 1 + CapsuleConfig.pulseScale * pulse;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(s);
    final col = type.color;
    final a = (CapsuleConfig.ringAlpha + CapsuleConfig.ringAlphaSwing * pulse)
        .clamp(0.0, 1.0);
    _stroke
      ..strokeWidth = CapsuleConfig.ringStroke
      ..color = col.withValues(alpha: a);
    canvas.drawCircle(Offset.zero, CapsuleConfig.ringRadius, _stroke);
    const h = CapsuleConfig.size / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(
        -h,
        -h,
        h,
        h,
        const Radius.circular(CapsuleConfig.radius),
      ),
      _fill..color = col,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        -h,
        CapsuleConfig.bandTop,
        h,
        CapsuleConfig.bandTop + CapsuleConfig.bandHeight,
        const Radius.circular(6),
      ),
      _fill..color = CapsuleConfig.band,
    );
    paintIcon(canvas, type, t);
    canvas.restore();
  }

  /// The white icon of [type] centred on the origin (≈ 24 pt tall).
  static void paintIcon(Canvas canvas, TimedPowerup type, double t) {
    switch (type) {
      case TimedPowerup.hourglass:
        _hourglass(canvas);
      case TimedPowerup.mini:
        _potion(canvas, t);
      case TimedPowerup.frenzy:
      case TimedPowerup.comet:
        _coins(canvas);
    }
  }

  static Path _poly(List<(double, double)> pts) {
    final p = Path()..moveTo(pts.first.$1, pts.first.$2);
    for (final q in pts.skip(1)) {
      p.lineTo(q.$1, q.$2);
    }
    return p..close();
  }

  /// §5.29 a white hourglass: two bars and the glass, a blue sand heap.
  static void _hourglass(Canvas canvas) {
    _fill.color = _white;
    canvas
      ..drawRect(const Rect.fromLTWH(-9, -12, 18, 3), _fill)
      ..drawRect(const Rect.fromLTWH(-9, 9, 18, 3), _fill)
      ..drawPath(
        _poly(const [(-7, -9), (7, -9), (1, 0), (7, 9), (-7, 9), (-1, 0)]),
        _fill,
      )
      ..drawPath(
        _poly(const [(-4, 7), (4, 7), (0, 2)]),
        _fill..color = CapsuleConfig.hourglass,
      );
  }

  /// §5.30 the shrink potion: a round white-outlined flask with a cork,
  /// magic-purple liquid with a wavy surface and white bubbles, and our
  /// pink bird on the label.
  static void _potion(Canvas canvas, double t) {
    canvas.save();
    canvas.scale(1.18);
    // Glass and liquid, clipped to the bulb.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: const Offset(0, 4), radius: 9.5)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-10, -6, 20, 20),
      _fill..color = const Color(0x4DFFFFFF),
    );
    final liquid = Path()..moveTo(-10, 2);
    for (var x = -10.0; x <= 10; x += 2) {
      liquid.lineTo(x, 2 + math.sin(x * .9 + t * 1000 / 180) * 1.2);
    }
    liquid
      ..lineTo(10, 14)
      ..lineTo(-10, 14)
      ..close();
    canvas.drawPath(liquid, _fill..color = CapsuleConfig.potionPurple);
    _fill.color = _white;
    for (final (x, y, r) in const [
      (-4.0, 8.0, 1.4),
      (3.0, 10.0, 1.1),
      (5.0, 5.0, .9),
    ]) {
      canvas.drawCircle(Offset(x, y), r, _fill);
    }
    canvas.restore();
    // The flask outline: the bulb with a neck gap, the neck.
    final outline = Path()
      ..addArc(
        Rect.fromCircle(center: const Offset(0, 4), radius: 9.5),
        -math.pi / 2 + .42,
        2 * math.pi - .84,
      )
      ..lineTo(-3.5, -11)
      ..lineTo(3.5, -11)
      ..close();
    canvas.drawPath(
      outline,
      _stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = _white,
    );
    _stroke.strokeJoin = StrokeJoin.miter;
    // Cork.
    canvas.drawRect(
      const Rect.fromLTWH(-4.5, -15, 9, 4.5),
      _fill..color = const Color(0xFFE8C08A),
    );
    // Our pink bird on the label.
    canvas
      ..drawRect(
        const Rect.fromLTWH(-2.6, 4, 5, 5),
        _fill..color = const Color(0xFFEC008C),
      )
      ..drawPath(
        _poly(const [(2.4, 5.4), (4.6, 6.5), (2.4, 7.6)]),
        _fill..color = const Color(0xFFFFB529),
      )
      ..drawPath(
        _poly(const [(-2.6, 5), (-4.6, 4), (-4.6, 6.6)]),
        _fill..color = const Color(0xFFC2185B),
      );
    // Glass highlight.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(-3, 1), radius: 5),
      math.pi * 1.1,
      math.pi * .35,
      false,
      _stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xD9FFFFFF),
    );
    canvas.restore();
  }

  /// §5.31 three stacked coins (white discs with a gold inner ring).
  static void _coins(Canvas canvas) {
    for (final (dx, dy) in const [(-5.0, 4.0), (5.0, 4.0), (0.0, -4.0)]) {
      canvas.drawCircle(Offset(dx, dy), 7, _fill..color = _white);
      canvas.drawCircle(
        Offset(dx, dy),
        4.2,
        _stroke
          ..strokeWidth = 1.8
          ..color = CapsuleConfig.frenzy,
      );
    }
  }
}
