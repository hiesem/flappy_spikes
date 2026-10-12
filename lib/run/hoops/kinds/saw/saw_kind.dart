import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/run_config.dart';
import '../../../config/saw_config.dart';
import '../../../director/plans.dart';
import '../../../effects/particle_pool.dart';
import '../../../mistakes.dart';
import '../../../physics/hoop_frame.dart';
import '../../../run_context.dart';
import '../../../run_state.dart';
import '../../hoop.dart';
import '../../hoop_kind.dart';
import '../../ring_painter.dart';
import '../normal.dart';
import 'black_hole.dart';
import 'frost_ring.dart';
import 'live_wire.dart';

/// One saw-ring design's art (PRD-2 §5.17): the two ring halves with their
/// aura, the ambient particles / sounds while it is on screen. The rules
/// (deadly rim, hitbox, opening) are the same for all three.
abstract class SawDesignArt {
  SawDesign get design;

  /// Behind the bird: back aura + back (right) half.
  void paintBack(Canvas canvas, SawRingState s);

  /// Over the bird: front (left) half + front aura (+ near-miss bolt).
  void paintFront(Canvas canvas, SawRingState s);

  /// Particles and approach sounds while on screen.
  void ambient(SawRingState s, double dt) {}

  static SawDesignArt of(SawDesign d) => switch (d) {
    SawDesign.liveWire => const LiveWireArt(),
    SawDesign.frostRing => const FrostRingArt(),
    SawDesign.blackHole => const BlackHoleArt(),
  };
}

/// Saw rings (PRD-2 §3.18, §5.17): a hoop whose **rim is deadly**. Each
/// spawn shows one of three designs (Live Wire, Frost Ring, Black Hole),
/// picked by the director (`SlotPlan.extra`, equal chance, never the same
/// twice in a row per run); all share the rules:
///
/// - the collider is the two rim-end circles at local (0, ±(opening/2 + r))
///   with r = 5 (Live Wire / Frost Ring) or 6 (Black Hole); any touch is a
///   mistake ([RimMode.deadly] → `MistakeCause.saw`), never a bounce;
///   decoration never kills;
/// - the opening is the normal hoop's (PRD-2.2 §25: the director adds
///   `RunConfig.sawExtraOpening`, now 0; PRD-2 had +28 pt), and the
///   decoration scales with the ring ([decorScaleFor]);
/// - a clean pass is an ordinary (always perfect) hoop: +1, coins, streak;
/// - rides (comet / portal) ignore its rim; Big Hoops grows it but it keeps
///   its own look (no gold, no tier look);
/// - Black Hole pulls the bird toward its rim within 34 pt (260 pt/s²,
///   570 at the inhale peak, 0.9 s every 3.4 s).
///
/// The death moments, the approach hums, the strip lensing and the
/// analytics live in `SawFeature` (saw_death.dart).
class SawHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.saw;

  @override
  bool get usesTierLook => false;

  static final Expando<SawRingState> _states = Expando('saw');

  /// The ring state of [h] (tests, the feature).
  static SawRingState? stateOf(Hoop h) => _states[h];

  /// The design of [h] (Live Wire when the plan carries none).
  static SawDesign designOf(Hoop h) {
    final e = h.plan.extra;
    return e is SawDesign ? e : SawDesign.liveWire;
  }

  @override
  RimMode rimMode(Hoop h, RunState s) =>
      s.ride != null ? RimMode.ignored : RimMode.deadly;

  @override
  double rimRadius(Hoop h) => SawConfig.rimRadius(designOf(h));

  @override
  ThemedDeath? themedDeath(Hoop h) => switch (designOf(h)) {
    SawDesign.liveWire => const ThemedDeath(
      'saw_live_wire',
      holdSeconds: SawConfig.wireHold,
    ),
    SawDesign.frostRing => const ThemedDeath(
      'saw_frost_ring',
      holdSeconds: SawConfig.frostHold,
    ),
    SawDesign.blackHole => const ThemedDeath(
      'saw_black_hole',
      holdSeconds: SawConfig.holeHold,
      noBody: true,
    ),
  };

  @override
  void onSpawn(Hoop h, RunContext c) {
    c.track('sawring_spawned', {'design': storageName(designOf(h))});
  }

  @override
  void buildVisual(Hoop h, RunContext c) {
    final art = SawDesignArt.of(designOf(h));
    final state = SawRingState(h, c, art);
    _states[h] = state;
    h.add(state);
    h.add(state.backPool);
    h.front.add(state.frontPool);
    h.paintBack = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: false);
        return;
      }
      art.paintBack(canvas, state);
    };
    h.front.paintFront = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: true);
        return;
      }
      art.paintFront(canvas, state);
    };
  }

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    c.track('sawring_passed', {'design': storageName(designOf(h))});
  }

  /// PRD-2.2 §25 The decoration scale of a saw ring with [opening]:
  /// `ry / ryDesign` (`RingPainter.ryFor`, designed at 146 pt). Every
  /// decoration size / offset (glow, swirl, ripples, sparks, crystals,
  /// stars / debris) is multiplied by it; the rim is not.
  static double decorScaleFor(double opening) =>
      RingPainter.ryFor(opening) / SawConfig.ryDesign;

  /// Analytics name of a design (§6 `sawring_*` {design}).
  static String storageName(SawDesign d) => switch (d) {
    SawDesign.liveWire => 'live_wire',
    SawDesign.frostRing => 'frost_ring',
    SawDesign.blackHole => 'black_hole',
  };

  // ------------------------------------------------------------- the pull

  /// §3.18 / §5.17 The Black Hole's hunger 0..1 at [runClock] for a hole
  /// with [seed]: 0, except during the 0.9 s inhale every 3.4 s (a sine
  /// bump; the mock's `hunger`).
  static double hunger(double runClock, int seed) {
    final u =
        (runClock + seed * SawConfig.inhalePhasePerSeed) %
        SawConfig.inhalePeriod;
    final from = SawConfig.inhalePeriod - SawConfig.inhaleLength;
    return u > from
        ? math.sin((u - from) / SawConfig.inhaleLength * math.pi)
        : 0;
  }

  /// §3.18 The pull strength (pt/s²): 260, rising to 570 at the inhale
  /// peak.
  static double pullStrength(double runClock, int seed) =>
      SawConfig.pull +
      (SawConfig.inhalePull - SawConfig.pull) * hunger(runClock, seed);

  /// §3.18 The vertical acceleration (pt/s², + = down) a Black Hole with
  /// frame [f] puts on a bird at [bird] (track) with radius [birdR]: toward
  /// the nearest rim end whose centre is within 34 pt of the bird's edge
  /// (the mock: `d < 34 + BR`, one end per hole), else 0.
  static double pullAt(
    HoopFrame f,
    Vector2 bird,
    double birdR,
    double runClock,
    int seed,
  ) {
    for (final side in const [-1, 1]) {
      final e = f.rimEnd(0, side);
      if (e.distanceTo(bird) < SawConfig.pullRange + birdR) {
        final dy = e.y - bird.y;
        return dy == 0 ? 0 : dy.sign * pullStrength(runClock, seed);
      }
    }
    return 0;
  }

  /// The pull on a bird at [bird] from [h] if it is a Black Hole saw ring
  /// (the autopilot's rollout uses this with a future [runClock]).
  static double pullFrom(Hoop h, Vector2 bird, double birdR, double runClock) {
    if (h.kind is! SawHoopKind || designOf(h) != SawDesign.blackHole) return 0;
    if (h.resolved) return 0;
    final s = _states[h];
    return pullAt(h.frame(), bird, birdR, runClock, s?.seed ?? 0);
  }
}

/// Per-ring state (world time: the pause freezes it, the Hourglass slows
/// it): the design clock, a cosmetic seed, the ambient particle pools
/// (behind / over the bird) and the Black Hole pull on the live bird.
class SawRingState extends Component {
  SawRingState(this.hoop, this.c, this.art, {int? seed})
    : seed = seed ?? c.cosmetic.nextInt(100);

  final Hoop hoop;
  final RunContext c;
  final SawDesignArt art;
  final int seed;

  /// Design clock (s since spawn).
  double t = 0;

  final ParticlePool backPool = ParticlePool(capacity: 40);
  final ParticlePool frontPool = ParticlePool(capacity: 60);

  /// Design scratch values (lightning cache, sound edges).
  final Map<String, Object> fx = {};

  /// Half height of the ring's stroke centre line (the rim-end centres).
  double get ry => hoop.opening / 2 + hoop.kind.rimRadius(hoop);

  /// PRD-2.2 §25 Decoration scale (`ry / ryDesign`) of this ring.
  double get decor => SawHoopKind.decorScaleFor(hoop.opening);

  /// The run clock (the Black Hole's inhale is on it).
  double get clock => c.s.runClock;

  /// The bird centre in this ring's local coordinates (null without one).
  Vector2? get birdLocal {
    final b = c.run.birdTrackPosition();
    if (b == null) return null;
    return b - hoop.position;
  }

  double get birdR => RunConfig.birdRadius * c.s.birdScale;

  /// On screen (with a margin): ambient effects run only then.
  bool get onScreen {
    final x = hoop.planeX - c.s.camX;
    return x > -60 && x < RunConfig.worldWidth + 60;
  }

  @override
  void update(double dt) {
    t += dt;
    if (onScreen && !hoop.look.missed) art.ambient(this, dt);
    _pull(dt);
  }

  /// §3.18 The Black Hole pulls the flying bird toward its rim.
  void _pull(double dt) {
    if (art.design != SawDesign.blackHole || hoop.resolved) return;
    final run = c.run;
    if (!run.isScrolling || run.rideHold || c.s.ride != null) return;
    final bird = c.game.runBird;
    final pos = run.birdTrackPosition();
    if (bird == null || !bird.isLoaded || pos == null) return;
    final a = SawHoopKind.pullAt(hoop.frame(), pos, birdR, clock, seed);
    if (a != 0) bird.body.linearVelocity.y += a * dt;
  }
}
