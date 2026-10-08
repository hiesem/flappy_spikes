import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../components/bird.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../menu/powerup_slot.dart';
import 'config/physics_config.dart';
import 'config/revive_config.dart';
import 'config/run_config.dart';
import 'director/run_director.dart';
import 'effects/dust_puff.dart';
import 'effects/miss_flash.dart';
import 'effects/particle_pool.dart';
import 'elements.dart';
import 'features.dart';
import 'hoops/hoop.dart';
import 'hoops/hoop_kind.dart';
import 'hoops/kinds/registry.dart';
import 'mistakes.dart';
import 'physics/bird_motion.dart';
import 'physics/death_tumble.dart';
import 'physics/hoop_frame.dart';
import 'physics/pass_test.dart';
import 'physics/rim_collision.dart';
import 'physics/spike_walls.dart';
import 'pickups/registry.dart';
import 'rides/ride.dart';
import 'run_clock.dart';
import 'run_context.dart';
import 'run_events.dart';
import 'run_feature.dart';
import 'run_geometry.dart';
import 'run_layers.dart';
import 'run_setup.dart';
import 'run_spawner.dart';
import 'run_state.dart';
import 'run_summary.dart';

/// Owns one run (ARCH §1.1): state, clock, director, spawner, features,
/// layers, the physics step, the mistake pipeline and the end of the run.
///
/// Physics (WP-1a, PRD-2 §3.0.1 / §3.0.4 / §3.0.5 / §7): Forge2D only moves
/// the bird vertically; the world scrolls at the bird's forward speed
/// ([BirdMotion]); rim ends, the pass plane, the miss rule and the spike
/// tooth lines are plain math against the bird circle; a death turns the
/// bird into the [DeathTumble] and the post-run flow starts 1.5 s later
/// (or once the bird rests).
class RunController extends Component {
  RunController({required this.setup, required this.game}) {
    final storage = game.storage;
    state = RunState(
      seed: setup.seed,
      viewHeight: setup.viewHeight,
      metElements: {
        for (final id in storage.metElements) ?ElementId.fromStorageId(id),
      },
    );
    enabled =
        setup.enabledOverride ??
        {...registeredElements(), ...registeredPickupElements()};
    director = RunDirector(
      seed: setup.seed,
      enabled: enabled,
      met: state.metElements,
      startHoopIndex: setup.startHoopIndex,
      lastPortalRide: RideId.fromStorageId(storage.lastPortalRide),
      forced: setup.forced,
      forcedRide: setup.forcedRide,
    );
    state.hoopIndex = setup.startHoopIndex;
    geo = RunGeometry(state);
    walls = SpikeWalls(geo);
    ctx = RunContext(this);
    spawner = RunSpawner(this);
    features = buildRunFeatures();
    _bestBefore = storage.bestScore;
  }

  final RunSetup setup;
  final FlappySpikesGame game;

  late final RunState state;
  late final Set<ElementId> enabled;
  late final RunDirector director;
  final RunClock clock = RunClock();
  final RunEvents events = RunEvents();
  final RunLayers layers = RunLayers();
  final MistakePipeline pipeline = MistakePipeline();
  late final RunGeometry geo;
  late final SpikeWalls walls;
  late final RunContext ctx;
  late final RunSpawner spawner;
  late final List<RunFeature> features;
  Ride? ride;

  late final int _bestBefore;
  bool _started = false;
  bool _dying = false;
  bool _ended = false;
  bool _paused = false;
  bool _frozen = false;
  MistakeCause? _cause;
  RunSummary? _summary;

  bool get started => _started;
  bool get ended => _ended;
  bool get dying => _dying;

  /// True while playing and the world moves.
  bool get isScrolling =>
      _started &&
      !_dying &&
      !_ended &&
      !_paused &&
      game.state == GameState.playing;

  /// Pickups can be collected (not while tumbling; ARCH §0).
  bool get canCollect => isScrolling;

  @override
  void onMount() {
    super.onMount();
    for (final l in layers.all) {
      parent?.add(l);
    }
    layers.fx.add(particles);
  }

  @override
  void onRemove() {
    for (final l in layers.all) {
      l.removeFromParent();
    }
    super.onRemove();
  }

  /// First tap (§3.0.1): flap (by the game) + the first hoop scheduled 60 pt
  /// past the right edge, scrolling in at cruise.
  void start() {
    if (_started) return;
    _started = true;
    clock.running = true;
    state.forwardSpeed = BirdMotion.cruise(state.runClock);
    if (setup.starter == Powerup.shield) state.shield = true;
    for (final f in features) {
      f.attach(ctx);
    }
    events.emit(RunStarted(setup));
    spawner.update(0);
  }

  /// A tap while playing. WP-0b: the game flaps the bird itself; later WPs
  /// gate it (rides, flap lock, tumble).
  void onTap() {}

  void pause() {
    _paused = true;
    clock.running = false;
  }

  void resume() {
    _paused = false;
    if (_started && !_dying && !_ended) clock.running = true;
  }

  /// The bird's centre in track coordinates (null without a bird).
  Vector2? birdTrackPosition() {
    final p = game.runBirdPosition;
    if (p == null) return null;
    return geo.toTrack(p);
  }

  /// The director's per-decision snapshot (ARCH §2.2).
  DirectorContext directorContext() {
    final s = state;
    final cruise = RunConfig.cruise(s.runClock);
    final birdX = birdTrackPosition()?.x ?? s.camX + RunConfig.birdX;
    final lead = (director.nextTrackX - birdX) / cruise;
    final sq = s.squeeze;
    final window =
        sq.phase != SqueezePhase.idle ||
        s.runClock > sq.nextAt - RunConfig.squeezeWindowLead - lead;
    final storage = game.storage;
    return DirectorContext(
      viewHeight: s.viewHeight,
      topTooth: geo.stripHeight,
      floorTooth: s.viewHeight - geo.stripHeight,
      squeezeTopTooth: geo.topTooth,
      squeezeFloorTooth: geo.floorTooth,
      squeezeWindow: window,
      rideActive: s.ride != null,
      ride: s.ride?.kind,
      timedPowerupRunning: s.timed != null,
      onFire: s.onFire,
      shieldArmed: s.shield,
      extraLifeActive: s.extraLife,
      eggOrChick: s.egg != null,
      piggyRunning: s.piggy != null,
      jarRunning: s.jar != null,
      shieldPickupsThisRun: s.shieldPickups,
      scrollSpeed: cruise,
      runClock: s.runClock,
      bigHoopsMult: s.bigHoops?.mult(s.runClock) ?? 1,
      featherWanted: storage.feathers < 3 && !s.featherSpawned,
      puzzleMask: storage.puzzlePieces,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_started || _frozen) return;
    final gameDt = dt;
    if (tumble != null) {
      // §3.0.5 the tumble keeps playing (and the bird keeps lying on the
      // floor spikes) through the revive offer and the results.
      _stepDeath(gameDt);
      layers.follow(state.camX, state.camY);
      return;
    }
    if (_ended) return;
    clock.tick(gameDt);
    state.runClock = clock.t;
    if (isScrolling) {
      BirdMotion.step(state, gameDt);
      if (state.invulnerable > 0) {
        state.invulnerable = (state.invulnerable - gameDt).clamp(0, 99);
      }
    }
    layers.follow(state.camX, state.camY);
    spawner.update(gameDt);
    if (isScrolling) _stepPhysics(gameDt);
    layers.follow(state.camX, state.camY);
    final scale = state.timeScale <= 0 ? 1 : state.timeScale;
    for (final f in features) {
      f.update(gameDt, gameDt / scale);
    }
  }

  // region WP-1a — physics step, pass / miss / rim, death tumble
  // (PRD-2 §3.0.1, §3.0.4, §3.0.5, §3.1, §5.13)

  /// The shared run particle pool (sparks, dust; ARCH §3), in `layers.fx`.
  final ParticlePool particles = ParticlePool();

  /// §3.0.5 the death tumble (null while flying).
  DeathTumble? tumble;
  Mistake? _death;

  /// §6 `run_end`: the slot tied to the run-ending cause (the missed /
  /// touched ring, else the next ring ahead at the moment of death).
  Hoop? _deathHoop;
  double _deathTime = 0;
  bool _handedOff = false;

  /// The bird's track position at the end of the previous physics step
  /// (the pass test's "before").
  Vector2? _prevBird;

  Bird? get _bird {
    final b = game.runBird;
    return b != null && b.isLoaded ? b : null;
  }

  double get _birdR => RunConfig.birdRadius * state.birdScale;

  void _stepPhysics(double dt) {
    final bird = _bird;
    if (bird == null) return;
    final r = _birdR;
    var pos = geo.toTrack(bird.body.position);
    final prev = _prevBird ?? pos.clone();
    for (final h in List.of(spawner.hoops)) {
      h.syncMotion(state.runClock);
      if (h.resolved || h.isRemoved) continue;
      final kind = h.kind;
      var f = h.frame();
      final mode = kind.rimMode(h, state);
      if (mode != RimMode.ignored && state.invulnerable <= 0) {
        final vy = bird.body.linearVelocity.y;
        final res = collideRims(
          f,
          BirdCircle(pos, r),
          Vector2(state.forwardSpeed, vy),
        );
        if (res != null) {
          if (mode == RimMode.deadly) {
            final c0 = res.contacts.first;
            h.resolveMiss();
            final rc = RimTouch(point: c0.point, normal: c0.normal, ring: c0.ring);
            kind.onRim(h, rc, ctx);
            mistake(Mistake(MistakeCause.saw, normal: c0.normal, hoop: h));
            if (_dying) return;
            continue;
          }
          _applyRim(h, bird, pos, res);
          pos = res.position;
          f = h.frame();
        }
      }
      final ev = testPlane(f, BirdCircle(prev, r), BirdCircle(pos, r));
      if (ev != null) {
        if (state.ride == null &&
            kind.onPlane(h, ev.ring, ctx) == PlaneVerdict.mistake) {
          h.resolveMiss();
          events.emit(ClosedSwitchReached(h));
          mistake(
            Mistake(MistakeCause.closedSwitch, normal: Vector2(-1, 0), hoop: h),
          );
          if (_dying) return;
          continue;
        }
        _pass(h, ev.ring);
        continue;
      }
      if (isFullyPast(f, BirdCircle(pos, r))) {
        if (state.ride != null) {
          _pass(h, 0);
          continue;
        }
        _miss(h);
        if (_dying) return;
      }
    }
    // §3.1 spikes: contact = a mistake; a save bounces off the tooth line.
    final side = walls.touches(BirdCircle(pos, r));
    if (side != null) {
      final normal = side == SpikeSide.top ? Vector2(0, 1) : Vector2(0, -1);
      final outcome = mistake(Mistake(MistakeCause.spikes, normal: normal));
      if (_dying) return;
      if (outcome != MistakeOutcome.died) {
        final (y, vy) = walls.saveBounce(side, r, bird.body.linearVelocity.y);
        bird.setFlight(y: y, vy: vy);
        pos = Vector2(pos.x, y);
      }
    }
    _prevBird = pos;
  }

  /// §3.0.4 3 the rim "tonk". WP-3h registers `Sfx.rimTonk` (parallel
  /// WP); it is looked up by name so this compiles before that merge and
  /// plays once it has landed.
  static final Sfx? _rimTonk = Sfx.values
      .where((s) => s.name == 'rimTonk')
      .firstOrNull;

  /// §3.0.4 2–3: push-out, reflected velocity (the forward part moves the
  /// camera: the world jolts back), touched, tonk, spin, sparks. Any
  /// contact marks the hoop touched (S6-02).
  void _applyRim(Hoop h, Bird bird, Vector2 pos, RimResult res) {
    state.camX += res.position.x - pos.x;
    state.forwardSpeed = res.velocity.x;
    bird.setFlight(y: res.position.y, vy: res.velocity.y);
    for (final c in res.contacts) {
      // §3.0.4 2–3 every rim touch is a graze, also an overlap that was
      // already separating (pushed out, not reflected). Such a contact
      // gives its feedback once; reflected contacts give it each hit.
      if (!c.bounced && h.touched) continue;
      if (!h.touched) {
        state.rimTouches++;
        bird.startRimSpin(rimSpinVelocity(res.velocity.y));
      }
      h.touched = true;
      final tonk = _rimTonk;
      if (tonk != null) ctx.sfx(tonk);
      final at = c.point;
      for (var i = 0; i < PhysicsConfig.rimSparks; i++) {
        final r = ctx.cosmetic;
        particles.spawn(
          x: at.x,
          y: at.y,
          vx: c.normal.x * 60 + (r.nextDouble() - .5) * 160,
          vy: c.normal.y * 60 + (r.nextDouble() - .5) * 160,
          w: 3 + r.nextDouble() * 2,
          color: const Color(0xFFFFFFFF),
          life: .25 + r.nextDouble() * .15,
          damp: 3,
        );
      }
      events.emit(RimTouched(h, at, c.normal));
      h.kind.onRim(h, RimTouch(point: at, normal: c.normal, ring: c.ring), ctx);
    }
  }

  /// §3.0.4 5 a pass: perfect when no rim was touched (rides: always).
  void _pass(Hoop h, int ring) {
    h.resolvePass(ring);
    final ride = state.ride != null;
    final perfect = !h.touched || ride;
    state.passes++;
    state.hoopsPassed++;
    if (perfect) state.perfectPasses++;
    final id = h.plan.element.storageId;
    state.taken[id] = (state.taken[id] ?? 0) + 1;
    events.emit(
      HoopPassed(
        h,
        ring: ring,
        perfect: perfect,
        rimTouched: h.touched,
        duringRide: ride,
      ),
    );
    h.kind.onPass(
      h,
      PassInfo(ring: ring, perfect: perfect, rimTouched: h.touched, duringRide: ride),
      ctx,
    );
  }

  /// §3.0.4 5 / §5.13 a miss: the shock-ring miss flash, then the mistake
  /// (death tumble, or a save by an extra life / shield).
  void _miss(Hoop h) {
    h.resolveMiss();
    events.emit(HoopMissed(h));
    h.kind.onMiss(h, ctx);
    MissFlash.play(
      h,
      fx: layers.fx,
      glowParent: game.world,
      glowPriority: RunLayer.items,
      screen: Vector2(RunConfig.worldWidth, state.viewHeight),
    );
    ctx.sfx(Sfx.missShock);
    final cause = h.plan.kind == HoopKindId.pair
        ? MistakeCause.pairMissed
        : MistakeCause.missedHoop;
    mistake(Mistake(cause, hoop: h));
  }

  void _stepDeath(double dt) {
    final t = tumble!;
    t
      ..top = walls.top
      ..floor = walls.floor
      ..step(dt);
    state.camX = t.camX;
    state.forwardSpeed = t.camSpeed;
    _bird?.placeTumble(geo.toScreen(t.position), t.angle);
    _deathTime += dt;
    if (_handedOff) return;
    final limit = _death?.themed != null
        ? PhysicsConfig.themedResultsMax
        : PhysicsConfig.resultsDelay;
    if (_deathTime >= limit || t.resting) {
      _handedOff = true;
      // WP-2d: the revive offer (≥ 6 hoops) comes before the run ends.
      game.runDeathSettled(this);
    }
  }

  /// Test seam: a pass of no particular hoop (scoring, stage, coins) —
  /// replaces the 1.0 tests' `onScoreSensor(PipePair(...))`.
  @visibleForTesting
  void debugPass({bool perfect = false}) {
    state.passes++;
    state.hoopsPassed++;
    if (perfect) state.perfectPasses++;
    events.emit(HoopPassed(null, perfect: perfect, rimTouched: !perfect));
  }
  // endregion WP-1a

  /// The one mistake path (ARCH §2.6). Returns what happened.
  MistakeOutcome mistake(Mistake m) {
    if (!_started || _dying || _ended) return MistakeOutcome.ignored;
    if (FlappySpikesGame.debugAvailable && game.runDebug.god) {
      return MistakeOutcome.ignored;
    }
    final outcome = pipeline.resolve(m, ctx);
    if (outcome == MistakeOutcome.died) _die(m);
    return outcome;
  }

  void _die(Mistake m) {
    _dying = true;
    _cause = m.cause;
    _death = m;
    _deathHoop = m.hoop ?? spawner.nextHoopAhead();
    clock.running = false;
    for (final f in features) {
      f.onDeath(m);
    }
    final bird = _bird;
    final birdPos = bird != null
        ? geo.toTrack(bird.body.position)
        : Vector2(state.camX + RunConfig.birdX, state.viewHeight / 2);
    final vy = bird?.body.linearVelocity.y ?? 0;
    final t = DeathTumble(
      position: birdPos,
      velocity: Vector2(state.forwardSpeed, vy),
      normal: m.normal,
      camX: state.camX,
      camSpeed: state.forwardSpeed,
      top: walls.top,
      floor: walls.floor,
      radius: _birdR,
      angle: bird?.body.angle ?? 0,
    );
    t.onLand = (at) => DustPuff.emit(
      particles,
      Offset(at.x, at.y),
      game.foregroundColor,
      ctx.cosmetic,
    );
    tumble = t;
    _deathTime = 0;
    game.beginDying();
  }

  /// Ends the run (idempotent) and emits [RunEnded].
  RunSummary endRun() {
    final existing = _summary;
    if (existing != null) return existing;
    _ended = true;
    clock.running = false;
    state.timeline.end(state.runClock);
    final s = summarize();
    _summary = s;
    events.emit(RunEnded(s));
    return s;
  }

  /// §3.14 revive (WP-2d fills the phoenix); the next slot is normal.
  void revive(ReviveKind k) {
    state.revivesThisGame++;
    state.firstSlotAfterRevive = true;
    director.onRevive();
    for (final f in features) {
      f.onRevive();
    }
  }

  // region WP-2d — revive v2 (PRD-2 §3.14, §5.9)
  /// The mistake that killed the bird last (null while flying).
  Mistake? get lastDeath => _death;

  /// §5.9 the phoenix takes the bird over: the tumble stops, the ladder
  /// and the director move on (next slot normal), features reset what a
  /// revive resets (squeeze opens), [RevivePhoenixStarted].
  void beginRevive(ReviveKind k, int price) {
    tumble = null;
    _handedOff = false;
    _deathTime = 0;
    revive(k);
    events.emit(RevivePhoenixStarted(k, price));
  }

  /// §3.14 straight back in at 1.65 s: the bird flies again at [birdY]
  /// (screen), runClock runs, 2 s of invulnerability (the flash follows
  /// `state.invulnerable`), [Revived].
  void finishRevive(ReviveKind k, int price, double birdY) {
    _dying = false;
    _death = null;
    _cause = null;
    _prevBird = geo.toTrack(Vector2(RunConfig.birdX, birdY));
    clock.running = true;
    state.invulnerable = ReviveConfig.invulnerable;
    events.emit(Revived(k, price));
  }
  // endregion WP-2d

  RunSummary summarize() {
    final s = state;
    final hoop = _deathHoop ?? spawner.nextHoopAhead();
    return RunSummary(
      score: s.score,
      hoopsPassed: s.hoopsPassed,
      coins: s.coinsThisRun,
      bestBefore: _bestBefore,
      bestAfter: s.score > _bestBefore ? s.score : _bestBefore,
      saves: s.saves,
      revives: s.revivesThisGame,
      runSeconds: s.runClock,
      cause: _cause ?? MistakeCause.missedHoop,
      hoopKind: hoop?.plan.kind,
      hoopIndex: hoop?.plan.index ?? s.hoopIndex,
      timeline: s.timeline,
      opponent: setup.opponent,
      spawned: {...director.spawnedCounts, ...s.spawned},
      rimTouches: s.rimTouches,
      passes: s.passes,
      perfectPasses: s.perfectPasses,
    );
  }

  /// §3.0.8 debug force: the next slot / gap; elements the director does not
  /// place (squeeze) go to their feature as [DebugForced].
  void debugForce(ElementId e) {
    if (!director.debugForce(e)) events.emit(DebugForced(e));
  }

  void debugForceRide(RideId id) => director.debugForceRide(id);

  /// Freezes the run at its current time (screenshot tests, ARCH §7.1).
  void debugFreeze([double? t]) => _frozen = true;

  void disposeRun() {
    for (final f in features) {
      f.detach();
    }
    spawner.dispose();
    particles.clear();
    events.clear();
    game.sound.stopAllLoops();
    for (final l in layers.all) {
      l.removeFromParent();
    }
    removeFromParent();
  }
}
