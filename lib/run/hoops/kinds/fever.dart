import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../config/fever_config.dart';
import '../../config/run_config.dart';
import '../../effects/particle_pool.dart';
import '../../effects/run_shake.dart';
import '../../effects/shock_ring.dart';
import '../../run_context.dart';
import '../hoop.dart';
import '../hoop_kind.dart';
import '../ring_painter.dart';
import 'normal.dart';

/// The glowing ring (FEVER), design "Gate Nova" (PRD-2 §3.19, §5.18; mock
/// `screen_fever_gatenova_A.html`, preset `full`).
///
/// In the normal hoop sequence it replaces a normal hoop: same opening,
/// rim bounce, spacing and max jump; never tilted or moving (the director
/// places it). Fixed colours (not stage-tinted, no tier look), two render
/// layers like every ring.
///
/// A **perfect** pass (no rim touch) is the FEVER pass: the streak sets
/// max(5, streak + 1) (`StreakFeature`), the bird catches fire and the
/// FEVER! banner shows (`FeverFeature`), and this kind plays the ring's pass
/// effect — three expanding rings of light (gold, white, orange, 0.09 s
/// apart), ≈ 26 plasma flames from the rim, the beam / halo flare, a warm
/// screen flash (≈ 0.3 s), a 6 pt shake — with the FEVER sound on top of
/// `perfect_3`. A pass with a rim touch is a normal pass: no FEVER, no fire
/// (Q50). Score and coins are unchanged (+1, +2 perfect).
class FeverHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.fever;

  @override
  bool get usesTierLook => false;

  static final Expando<FeverRingState> _states = Expando('fever');

  /// The ring state of [h] (tests).
  static FeverRingState? stateOf(Hoop h) => _states[h];

  @override
  void buildVisual(Hoop h, RunContext c) {
    final state = FeverRingState(h, c);
    _states[h] = state;
    h.add(state);
    void paint(Canvas canvas, {required bool front}) =>
        FeverRingPainter.paint(
          canvas,
          h.opening,
          state.t,
          state.seed,
          state.flare,
          front: front,
        );
    h.paintBack = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: false);
        return;
      }
      if (h.rewardStripped) {
        // PRD-2.2 §27.3 the plasma fades, the ring stays plain.
        NormalHoopKind.paintStripped(
          canvas,
          h,
          c,
          front: false,
          reward: () => paint(canvas, front: false),
        );
        return;
      }
      paint(canvas, front: false);
    };
    h.front.paintFront = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: true);
        return;
      }
      if (h.rewardStripped) {
        NormalHoopKind.paintStripped(
          canvas,
          h,
          c,
          front: true,
          reward: () => paint(canvas, front: true),
        );
        return;
      }
      paint(canvas, front: true);
    };
  }

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    if (!p.perfect) return; // Q50: a rim touch is a normal pass
    if (h.rewardStripped) return; // PRD-2.2 §27.3 a plain ring now
    _states[h]?.flare = 1;
    c.sfx(Sfx.feverPass);
    final f = h.frame();
    final at = f.toWorld(Vector2(0, h.rings.first));
    final ry = RingPainter.ryFor(h.opening);
    for (var k = 0; k < FeverConfig.passRingColors.length; k++) {
      final col = FeverConfig.passRingColors[k];
      c.layers.fx.add(
        ShockRing()..play(
          Offset(at.x, at.y),
          rx: 20,
          ry: ry,
          color: col,
          length: FeverConfig.passRingLife,
          scaleFrom: 1,
          scaleTo: 1,
          strokeFrom: 7,
          strokeTo: 1,
          grow: FeverConfig.passRingGrow,
          glowBlur: 12,
          delay: k * FeverConfig.passRingGap,
        ),
      );
    }
    final r = c.cosmetic;
    for (var i = 0; i < FeverConfig.passBurst; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final v = FeverConfig.passBurstSpeed * (.6 + r.nextDouble() * .7);
      final s = 4 + r.nextDouble() * 4;
      c.run.particles.spawn(
        shape: ParticleShape.flame,
        x: at.x + math.cos(a) * 14,
        y: at.y + math.sin(a) * ry,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 2 * s,
        color: FeverConfig.firePalette.first,
        ramp: FeverConfig.firePalette,
        life: .7,
        alpha0: 1,
        alpha1: 0,
        fadePow: 2,
      );
    }
    final world = c.game.world;
    world.add(FeverFlash(Vector2(RunConfig.worldWidth, c.viewHeight)));
    world.add(FeverShake(c));
  }
}

/// Per-ring clock, flare and ambient sparkles / embers (world time).
class FeverRingState extends Component {
  FeverRingState(this.hoop, this.c) : seed = c.cosmetic.nextInt(100);

  final Hoop hoop;
  final RunContext c;
  final int seed;
  double t = 0;

  /// The pass flare (1 → 0 at 2 /s).
  double flare = 0;

  double _sparkAcc = 0, _emberAcc = 0;

  @override
  void update(double dt) {
    t += dt;
    if (flare > 0) flare = math.max(0, flare - dt * FeverConfig.flareDecay);
    if (hoop.look.missed) return;
    if (hoop.rewardStripped) return; // PRD-2.2 §27.3 no more sparks
    final x = hoop.planeX - c.s.camX;
    if (x < -60 || x > RunConfig.worldWidth + 60) return;
    final ry = RingPainter.ryFor(hoop.opening);
    final d = FeverRingPainter.decorScaleFor(hoop.opening); // PRD-2.2 §25
    final at = hoop.frame().toWorld(Vector2(0, hoop.rings.first));
    final r = c.cosmetic;
    _sparkAcc += dt * FeverConfig.sparksPerSecond;
    while (_sparkAcc >= 1) {
      _sparkAcc -= 1;
      c.run.particles.spawn(
        shape: ParticleShape.twinkle,
        x: at.x - 8 * d,
        y: at.y + (r.nextDouble() - .5) * ry * 1.6,
        vx: -30 - r.nextDouble() * 40,
        vy: (r.nextDouble() - .5) * 10,
        w: (5 + r.nextDouble() * 5) * d,
        color: r.nextBool() ? const Color(0xFFFFF59D) : const Color(0xFFFFFFFF),
        life: .9,
      );
    }
    _emberAcc += dt * FeverConfig.embersPerSecond;
    while (_emberAcc >= 1) {
      _emberAcc -= 1;
      final a = r.nextDouble() * 2 * math.pi;
      final (ex, ey) = FeverRingPainter.ellPt(ry, a, 5 * d);
      c.run.particles.spawn(
        shape: ParticleShape.circle,
        x: at.x + ex,
        y: at.y + ey,
        vx: math.cos(a) * 40,
        vy: math.sin(a) * 40,
        w: 4 * d,
        color: r.nextBool() ? const Color(0xFFFFD54A) : const Color(0xFFFF6D00),
        life: .5,
      );
    }
  }
}

/// The §5.18 Gate Nova ring in hoop-local coordinates (centre at 0, 0):
/// halo, light beam with streaks, plasma loops, the red rim on its dark-red
/// glowing outline, the boiling plasma beads and the inner gold ring.
abstract final class FeverRingPainter {
  static const double rx = RingPainter.rx;

  /// PRD-2.2 §25 The decoration scale of a FEVER ring with [opening]:
  /// `ry / ryDesign` (designed at 118 pt). The halo, beam, streaks, plasma
  /// loops, sparkles and embers are multiplied by it; the rim, outline,
  /// beads and inner gold ring are not.
  static double decorScaleFor(double opening) =>
      RingPainter.ryFor(opening) / FeverConfig.ryDesign;

  /// PRD-2.2 §25 The vertical half extent (pt from the centre) of the
  /// decoration's outer bounds (the halo, the widest part; flare 0) for a
  /// ring with [opening].
  static double decorExtent(double opening) =>
      RingPainter.ryFor(opening) +
      FeverConfig.haloExtra * decorScaleFor(opening);

  /// The mock's deterministic `rnd(n)` (cosmetic only).
  static double rnd(num n) {
    final v = math.sin(n * 12.9898 + 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  /// A point on the ring ellipse at angle [a], [o] pt outside it.
  static (double, double) ellPt(double ry, double a, [double o = 0]) =>
      ((rx + o) * math.cos(a), (ry + o) * math.sin(a));

  static bool _isFront(double a) => math.cos(a) < 0;

  static final Paint _p = Paint();

  static Path _half(double rxx, double ryy, {required bool front}) =>
      Path()..addArc(
        Rect.fromCenter(center: Offset.zero, width: 2 * rxx, height: 2 * ryy),
        front ? math.pi / 2 : -math.pi / 2,
        math.pi,
      );

  /// Paints one layer: the back layer is aura (behind) + ring, the front
  /// layer ring + aura (front loops), as in the mock.
  static void paint(
    Canvas canvas,
    double opening,
    double t,
    int seed,
    double flare, {
    required bool front,
  }) {
    final ry = RingPainter.ryFor(opening);
    final d = decorScaleFor(opening); // PRD-2.2 §25
    if (!front) {
      _aura(canvas, ry, d, t, seed, flare, front: false);
      _ring(canvas, ry, t, seed, front: false);
    } else {
      _ring(canvas, ry, t, seed, front: true);
      _aura(canvas, ry, d, t, seed, flare, front: true);
    }
  }

  static void _aura(
    Canvas canvas,
    double ry,
    double d,
    double t,
    int seed,
    double fl, {
    required bool front,
  }) {
    if (!front) {
      // Warm halo (ring + 44 pt).
      final hr = ry + FeverConfig.haloExtra * d;
      final ha = (FeverConfig.haloAlpha + .25 * fl).clamp(0.0, 1.0);
      _p
        ..style = PaintingStyle.fill
        ..maskFilter = null
        ..shader = Gradient.radial(Offset.zero, hr, [
          Color.fromRGBO(255, 150, 30, ha),
          const Color.fromRGBO(255, 150, 30, 0),
        ]);
      canvas.drawRect(Rect.fromCircle(center: Offset.zero, radius: hr), _p);
      // The light beam toward the bird with drifting streaks.
      final len = FeverConfig.beamLength * (1 + .35 * fl) * d;
      final ba = FeverConfig.beamAlpha;
      _p.shader = Gradient.linear(
        Offset.zero,
        Offset(-len, 0),
        [
          Color.fromRGBO(255, 226, 90, (ba + .25 * fl).clamp(0.0, 1.0)),
          Color.fromRGBO(255, 240, 150, ba * .4),
          const Color.fromRGBO(255, 240, 150, 0),
        ],
        const [0, .6, 1],
      );
      final sp = FeverConfig.beamSpread * d;
      canvas.drawPath(
        Path()
          ..moveTo(0, -ry + 5)
          ..lineTo(-len, -ry - sp)
          ..lineTo(-len, ry + sp)
          ..lineTo(0, ry - 5)
          ..close(),
        _p,
      );
      _p.shader = null;
      _p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * d
        ..strokeCap = StrokeCap.butt;
      for (var i = 0; i < FeverConfig.beamStreaks; i++) {
        final u = (t * .7 + i / FeverConfig.beamStreaks) % 1;
        final y = (rnd(i * 3 + seed) - .5) * ry * 1.6;
        final x = -6 * d - u * len;
        _p.color = Color.fromRGBO(255, 255, 255, .75 * (1 - u));
        canvas.drawLine(
          Offset(x, y),
          Offset(x - (12 + 8 * rnd(i)) * d, y),
          _p,
        );
      }
    }
    // Plasma loops rising off the rim (prominences).
    for (var k = 0; k < FeverConfig.loops; k++) {
      final ph =
          (t * FeverConfig.loopSpeed + k / FeverConfig.loops + seed * .01) % 1;
      final a0 = k * 2.4 + seed + .3;
      const span = .45;
      final am = a0 + span / 2;
      if (_isFront(am) != front) continue;
      final rise = math.sin(ph * math.pi);
      if (rise <= .01) continue;
      final (x0, y0) = ellPt(ry, a0, 3 * d);
      final (x1, y1) = ellPt(ry, a0 + span, 3 * d);
      final (mx, my) = ellPt(ry, am, (10 + FeverConfig.loopHeight * rise) * d);
      final path = Path()
        ..moveTo(x0, y0)
        ..quadraticBezierTo(mx, my, x1, y1);
      _p
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = FeverConfig.loopWidth * d
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          FeverConfig.glowBlur / 2 * d,
        )
        ..color = const Color(0xFFFF3D00).withValues(alpha: .85 * rise);
      canvas.drawPath(path, _p);
      _p
        ..maskFilter = null
        ..color = FeverConfig.loopColor.withValues(alpha: .85 * rise);
      canvas.drawPath(path, _p);
      _p
        ..strokeWidth = math.max(1, FeverConfig.loopWidth / 3 * d)
        ..color = FeverConfig.loopCore.withValues(alpha: rise);
      canvas.drawPath(path, _p);
    }
  }

  static void _ring(
    Canvas canvas,
    double ry,
    double t,
    int seed, {
    required bool front,
  }) {
    final half = _half(rx, ry, front: front);
    _p
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Orange glow + dark-red outline.
    _p
      ..strokeWidth = FeverConfig.outlineWidth
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        FeverConfig.glowBlur / 2,
      )
      ..color = FeverConfig.glowColor;
    canvas.drawPath(half, _p);
    _p
      ..maskFilter = null
      ..color = FeverConfig.outline;
    canvas.drawPath(half, _p);
    _p
      ..strokeWidth = FeverConfig.rimWidth
      ..color = front ? FeverConfig.rimFront : FeverConfig.rimBack;
    canvas.drawPath(half, _p);
    // Boiling plasma beads riding the red rim (re-rolled 12 × per second).
    final a0 = front ? math.pi / 2 : -math.pi / 2;
    final fr = (t * FeverConfig.beadRerollPerSecond).floor();
    _p.style = PaintingStyle.fill;
    final n = FeverConfig.beads;
    for (var i = 0; i < n; i++) {
      final a = a0 + math.pi * (i + .5) / n;
      final (x, y) = ellPt(ry, a, (rnd(i + fr * 3 + seed) - .5) * 2);
      final r = FeverConfig.beadRadius * (.55 + .6 * rnd(i * 7 + fr + seed));
      final col =
          FeverConfig.beadColors[(i + fr) % FeverConfig.beadColors.length];
      _p.color = col.withValues(alpha: front ? 1 : .65);
      canvas.drawCircle(Offset(x, y), r, _p);
    }
    // The glowing inner gold ring (the Sun Gate).
    final pul = .6 + .4 * math.sin(t * 4);
    final inset = FeverConfig.rimWidth / 2 + 1.5;
    final inner = _half(rx - inset, ry - inset, front: front);
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = FeverConfig.innerWidth
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        (FeverConfig.innerGlowMin + FeverConfig.innerGlowPulse * pul) / 2,
      )
      ..color = const Color(0xFFFFD54A);
    canvas.drawPath(inner, _p);
    _p
      ..maskFilter = null
      ..color = FeverConfig.innerRing;
    canvas.drawPath(inner, _p);
  }
}

/// §5.18 the warm screen flash of the FEVER pass (≈ 0.3 s), over the world.
class FeverFlash extends PositionComponent {
  FeverFlash(Vector2 screen) : super(size: screen, priority: 16);

  double level = FeverConfig.passFlash;

  @override
  void update(double dt) {
    level -= dt * FeverConfig.passFlashDecay;
    if (level <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (level <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(-20, -20, size.x + 40, size.y + 40),
      Paint()..color = FeverConfig.flashColor.withValues(alpha: level * .55),
    );
  }
}

/// §5.18 the small (6 pt) shake of the FEVER pass on the world camera
/// (the HUD in the viewport stays still). Applies the [RunShake] offset as a
/// delta, so it composes with other shakes, and puts the camera back when
/// done.
class FeverShake extends Component {
  FeverShake(this.c) : _shake = RunShake(random: c.cosmetic)..feverPass();

  final RunContext c;
  final RunShake _shake;
  Offset _applied = Offset.zero;

  @override
  void update(double dt) {
    _shake.update(dt);
    final o = _shake.offset;
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position + Vector2(o.dx - _applied.dx, o.dy - _applied.dy);
    _applied = o;
    if (!_shake.active) removeFromParent();
  }

  @override
  void onRemove() {
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position - Vector2(_applied.dx, _applied.dy);
    _applied = Offset.zero;
    super.onRemove();
  }
}
