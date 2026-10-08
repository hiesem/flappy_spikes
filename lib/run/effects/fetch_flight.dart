import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/parts_config.dart';
import 'easing.dart';
import 'particle_pool.dart';

/// Paints the flying item centred at the origin at [scale] / [rotation].
typedef FetchArt = void Function(Canvas canvas, double scale, double rotation);

/// Parameters of a fetch flight.
class FetchSpec {
  const FetchSpec({
    this.grow = .14,
    this.growBy = .4,
    this.fly = .62,
    this.controlDx = -36,
    this.lift = 40,
    this.scaleFrom = 1,
    this.scaleTo = 1,
    this.rotFrom = 0,
    this.rotTo = 0,
    this.trail = true,
    this.trailJitter = 4,
    this.trailMin = 6,
    this.trailMax = 10,
    this.trailColors = const [PartsConfig.gold, PartsConfig.pink],
    this.straight = false,
    this.alphaTo = 1,
  });

  /// Grow phase (s) and the extra scale at its peak (ease-out-back).
  final double grow, growBy;

  /// Flight time (s), cubic in-out along a quadratic bezier.
  final double fly;

  /// Bezier control: x = start.x + [controlDx]; y = min(sy, ey) +
  /// 0.25 (sy − ey) − [lift].
  final double controlDx, lift;
  final double scaleFrom, scaleTo, rotFrom, rotTo;

  /// Block trail: one square every 0.03 s (± jitter, size range, life 0.4 s,
  /// alpha 1 − u², spin ± 3 rad/s), 50/50 [trailColors].
  final bool trail;
  final double trailJitter, trailMin, trailMax;
  final List<Color> trailColors;

  /// Straight linear flight (heart → indicator), no grow, no curve.
  final bool straight;
  final double alphaTo;

  double get total => (straight ? 0 : grow) + fly;

  /// §5.14 feather → tray (scale 1.47 → 0.82, 20° → 26°).
  static const FetchSpec feather = FetchSpec(
    scaleFrom: 1.05 * 1.4,
    scaleTo: .82,
    rotFrom: .35,
    rotTo: .45,
  );

  /// §5.15 puzzle piece → pill (scale 2.73 → 1, grow +0.3, control −30).
  static const FetchSpec puzzlePiece = FetchSpec(
    growBy: .3,
    controlDx: -30,
    scaleFrom: 2.1 * 1.3,
    scaleTo: 1,
    trailJitter: 5,
    trailMax: 11,
  );

  /// §5.2 heart → indicator: straight, 0.42 s, scale → 0.6, opacity → 0.9.
  static const FetchSpec heart = FetchSpec(
    fly: .42,
    straight: true,
    trail: false,
    scaleTo: .6,
    alphaTo: .9,
  );
}

/// The fetch flight (ARCH §3 "FetchFlight", §5.14 / §5.15 `flyPos`): a
/// touched pickup grows for 0.14 s, then flies on a quadratic curve (up and
/// back over the bird) into its HUD slot in 0.62 s, scaling and turning,
/// with a block trail behind; [onLand] fires on arrival (the slot punches,
/// rings, sparkles). Positions are in the coordinates of the component's
/// parent (normally the HUD / viewport).
class FetchFlight extends PositionComponent {
  FetchFlight({
    required this.from,
    required this.to,
    required this.art,
    this.spec = FetchSpec.feather,
    this.pool,
    this.onLand,
    math.Random? random,
    super.priority,
  }) : _r = random ?? math.Random();

  final Offset from, to;
  final FetchArt art;
  final FetchSpec spec;
  final ParticlePool? pool;
  final void Function()? onLand;
  final math.Random _r;

  double _t = 0;
  double _trailAcc = 0;
  bool _landed = false;

  double get time => _t;
  bool get landed => _landed;

  Offset get control => Offset(
    from.dx + spec.controlDx,
    math.min(from.dy, to.dy) + .25 * (from.dy - to.dy) - spec.lift,
  );

  /// (position, scale, rotation, alpha) at [t] seconds.
  (Offset, double, double, double) at(double t) {
    final g = spec.straight ? 0.0 : spec.grow;
    if (t < g) {
      final s = spec.scaleFrom * (1 + spec.growBy * Ease.outBack(t / g));
      return (from, s, spec.rotFrom, 1);
    }
    final u = ((t - g) / spec.fly).clamp(0.0, 1.0);
    if (spec.straight) {
      return (
        Offset.lerp(from, to, u)!,
        spec.scaleFrom + (spec.scaleTo - spec.scaleFrom) * u,
        spec.rotFrom,
        1 + (spec.alphaTo - 1) * u,
      );
    }
    final v = Ease.cubicInOut(u);
    final c = control;
    final a = 1 - v;
    final p = Offset(
      a * a * from.dx + 2 * a * v * c.dx + v * v * to.dx,
      a * a * from.dy + 2 * a * v * c.dy + v * v * to.dy,
    );
    // The grow ends at scaleFrom × (1 + growBy × eob(1)) = × (1 + growBy).
    final s0 = spec.scaleFrom * (1 + spec.growBy);
    return (
      p,
      s0 + (spec.scaleTo - s0) * v,
      spec.rotFrom + (spec.rotTo - spec.rotFrom) * v,
      1,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_landed) return;
    _t += dt;
    final (p, _, _, _) = at(_t);
    final pl = pool;
    if (spec.trail && pl != null && _t > (spec.straight ? 0 : spec.grow)) {
      _trailAcc += dt;
      while (_trailAcc >= .03) {
        _trailAcc -= .03;
        double u(double a, double b) => a + _r.nextDouble() * (b - a);
        pl.spawn(
          x: p.dx + u(-spec.trailJitter, spec.trailJitter),
          y: p.dy + u(-spec.trailJitter, spec.trailJitter),
          w: u(spec.trailMin, spec.trailMax),
          color: spec.trailColors[_r.nextInt(spec.trailColors.length)],
          life: .4,
          spin: u(-3, 3),
          fadePow: 2,
        );
      }
    }
    if (_t >= spec.total) {
      _landed = true;
      onLand?.call();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_landed) return;
    final (p, s, r, a) = at(_t);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    final layer = a < 1;
    if (layer) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    }
    art(canvas, s, r);
    if (layer) canvas.restore();
    canvas.restore();
  }
}
