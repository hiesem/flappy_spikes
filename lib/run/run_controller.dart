import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../components/bird.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../menu/powerup_slot.dart';
import 'config/gates_config.dart';
import 'config/physics_config.dart';
import 'config/revive_config.dart';
import 'config/saw_config.dart'; // WP-3d
import 'config/squeeze_config.dart'; // WP-3g
import 'config/run_config.dart';
import 'config/streak_config.dart'; // owner 2026-10-13 perfect band
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
    final all =
        setup.enabledOverride ??
        {...registeredElements(), ...registeredPickupElements()};
    // PRD-2.3 §14.6 lifetime unlock gates (a debug force ignores them).
    final games = storage.gamesPlayed;
    enabled = setup.ignoreGates
        ? all
        : GatesConfig.filter(
            all,
            games,
            keep: [...setup.forced, if (setup.forcedRide != null) ElementId.portal],
          );
    director = RunDirector(
      seed: setup.seed,
      enabled: enabled,
      met: state.metElements,
      startHoopIndex: setup.startHoopIndex,
      lastPortalRide: RideId.fromStorageId(storage.lastPortalRide),
      forced: setup.forced,
      forcedRide: setup.forcedRide,
      // PRD-2.3 §10.2 hoop 0 stands at its fixed spot, already there while
      // the bird waits (not in a startHoopIndex debug / e2e run).
      fixedFirstHoop: setup.startHoopIndex == 0,
      firstTrackX: setup.startHoopIndex == 0
          ? RunConfig.hoop0X
          : RunConfig.worldWidth + RunConfig.firstHoopOffscreen,
      // PRD-2.3 §14.2 never in two runs in a row.
      featherAllowed:
          setup.forced.contains(ElementId.feather) ||
          !GatesConfig.shownLastRun(storage.lastFeatherRun, games),
      pieceAllowed:
          setup.forced.contains(ElementId.puzzlePiece) ||
          !GatesConfig.shownLastRun(storage.lastPieceRun, games),
      oneBigBonus: setup.oneBigBonus,
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

  // region P23-10 — the waiting start (PRD-2.3 §10.1)
  bool _opened = false;
  bool _waitBegun = false;
  double _waitClock = 0;

  /// PRD-2.3 §10.1 the run is open and the bird waits for the first tap
  /// (the clock stands still, the world does not scroll).
  bool get waiting => !_started && !_ended;

  /// PRD-2.3 §10.3b the bird floats and is tappable: the tap-reminder count
  /// runs ([beginWaiting]).
  bool get waitingBegun => _waitBegun;

  /// PRD-2.3 §10.3b seconds the bird has waited since [beginWaiting]
  /// (stands still while paused; the world passes dt 0).
  double get waitClock => _waitClock;

  /// PRD-2.3 §10.1 / §10.2 opens the run in the waiting state: the features
  /// attach and hoop 0 is placed at its fixed spot, before the first tap.
  /// Called by the game right after the controller is added; [start] calls
  /// it too if nobody did.
  void open() {
    if (_opened) return;
    _opened = true;
    if (setup.starter == Powerup.shield) state.shield = true;
    for (final f in features) {
      f.attach(ctx);
    }
    spawner.update(0);
  }

  /// PRD-2.3 §10.3b the bird is floating and tappable now: the tap-reminder
  /// count starts. Solo runs call it at START; in versus the game calls it
  /// when the VS screen has finished (PRD-2.3 §25.3 makes that screen the
  /// loading screen: call this when it hands over, not at START).
  void beginWaiting() {
    if (_waitBegun) return;
    _waitBegun = true;
    _waitClock = 0;
  }

  /// The first playfield tap (PRD-2.3 §10.1; §3.0.1): the clock runs,
  /// `RunStarted` is emitted; the game switches gravity on and flaps.
  void start() {
    if (_started) return;
    open();
    _started = true;
    clock.running = true;
    state.forwardSpeed = BirdMotion.cruise(state.hoopIndex);
    events.emit(RunStarted(setup));
    spawner.update(0);
  }
  // endregion P23-10

  /// A tap while playing. WP-0b: the game flaps the bird itself; later WPs
  /// gate it (rides, flap lock, tumble).
  void onTap() {}

  // region WP-3c — §3.23 spring flap lock
  /// Flap input is ignored (the spring launch's 0.45 s / 0.28 s).
  bool get flapLocked => state.flapLock > 0;
  // endregion WP-3c

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
    final cruise = RunConfig.cruise(s.hoopIndex);
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
      // region WP-3g — §3.17 in the window new hoops fit the band of the
      // squeeze that is coming / running (its full depth), not the walls'
      // current position.
      squeezeTopTooth: window
          ? math.max(geo.topTooth, geo.stripHeight + _squeezeDepth())
          : geo.topTooth,
      squeezeFloorTooth: window
          ? math.min(
              geo.floorTooth,
              s.viewHeight - geo.stripHeight - _squeezeDepth(),
            )
          : geo.floorTooth,
      // endregion WP-3g
      squeezeWindow: window,
      rideActive: s.ride != null,
      ride: s.ride?.kind,
      timedPowerupRunning: s.timed != null,
      onFire: s.onFire,
      fever: s.fever,
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
      // region WP-G2 — PRD-2.2 §27 one bonus at a time
      activity: s.activity != null || RunActivity.of(s) != null,
      activityEndedAtSlot: s.activityEndedAtSlot,
      // endregion WP-G2
      // PRD-2.3 §17.3 rule 1 at most one open big bonus.
      bigBonusOpen: spawner.bigBonusOpen,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_started && _waitBegun && !_paused && !_ended) _waitClock += dt;
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
    if (isScrolling && !rideHold) {
      BirdMotion.step(state, gameDt);
      if (state.invulnerable > 0) {
        state.invulnerable = (state.invulnerable - gameDt).clamp(0, 99);
      }
    }
    layers.follow(state.camX, state.camY);
    spawner.update(gameDt);
    if (isScrolling && !rideHold) _stepPhysics(gameDt);
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

  /// PRD-2.2 §30.2 each hoop's pose at the end of the previous physics step
  /// (the pass test's and the rim sweep's "before" pose; paired with
  /// [_prevBird]).
  final Map<Hoop, HoopFrame> _prevFrames = Map.identity();

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
    final fresh = _prevBird == null;
    final prev = _prevBird ?? pos.clone();
    final poses = Map<Hoop, HoopFrame>.identity();
    for (final h in List.of(spawner.hoops)) {
      h.syncMotion(state.runClock);
      if (h.resolved || h.isRemoved) continue;
      final kind = h.kind;
      var f = h.frame();
      // PRD-2.2 §30.2 the pose of the previous step (null: first step).
      final pf = fresh ? null : _prevFrames[h];
      poses[h] = f;
      final mode = kind.rimMode(h, state);
      if (mode != RimMode.ignored && state.invulnerable <= 0) {
        final vy = bird.body.linearVelocity.y;
        final res = collideRimsSwept(
          pf,
          f,
          BirdCircle(prev, r),
          BirdCircle(pos, r),
          Vector2(state.forwardSpeed, vy),
        );
        if (res != null) {
          if (mode == RimMode.deadly) {
            final c0 = res.contacts.first;
            h.resolveMiss();
            final rc = RimTouch(point: c0.point, normal: c0.normal, ring: c0.ring);
            kind.onRim(h, rc, ctx);
            mistake(
              Mistake(
                MistakeCause.saw,
                normal: c0.normal,
                hoop: h,
                themed: kind.themedDeath(h), // WP-3d
              ),
            );
            if (_dying) return;
            continue;
          }
          _applyRim(h, bird, pos, res);
          pos = res.position;
          f = h.frame();
        }
      }
      final ev = testPlane(
        f,
        BirdCircle(prev, r),
        BirdCircle(pos, r),
        prevFrame: pf,
      );
      if (ev != null) {
        if (state.ride == null &&
            kind.onPlane(h, ev.ring, ctx) == PlaneVerdict.mistake) {
          h.resolveMiss();
          events.emit(ClosedSwitchReached(h));
          mistake(
            Mistake(
              MistakeCause.closedSwitch,
              normal: Vector2(-1, 0),
              hoop: h,
              themed: kind.themedDeath(h), // WP-3d
            ),
          );
          if (_dying) return;
          continue;
        }
        h.passOffset = ev.offset;
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
    _prevFrames
      ..clear()
      ..addAll(poses);
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

  /// §3.0.4 5 a pass. PRD-2.3 §14.3: perfect = a pass with no rim touch,
  /// anywhere in the gap (Flappy Dunk's swish; the PRD-2.2 §11 centre zone
  /// is retired); rides: always perfect. A graze is a pass after a rim
  /// touch. ([HoopPassed.clean], a rim-free pass outside the old zone, no
  /// longer happens.) Owner 2026-10-13: with a remote `point_perfect_band`
  /// > 0 a rim-free pass must also cross within that band
  /// ([PerfectBandConfig]); a rim-free pass outside it is [HoopPassed.clean].
  void _pass(Hoop h, int ring) {
    h.resolvePass(ring);
    final ride = state.ride != null;
    final perfect =
        ride ||
        PerfectBandConfig.isPerfect(
          touched: h.touched,
          hoopIndex: h.plan.index,
          offset: h.passOffset,
        );
    final clean = !perfect && !h.touched && !ride;
    state.passes++;
    state.hoopsPassed++;
    if (perfect) state.perfectPasses++;
    if (clean) state.cleanPasses++;
    final id = h.plan.element.storageId;
    state.taken[id] = (state.taken[id] ?? 0) + 1;
    events.emit(
      HoopPassed(
        h,
        ring: ring,
        perfect: perfect,
        clean: clean,
        rimTouched: h.touched,
        duringRide: ride,
      ),
    );
    h.kind.onPass(
      h,
      PassInfo(
        ring: ring,
        perfect: perfect,
        clean: clean,
        rimTouched: h.touched,
        duringRide: ride,
      ),
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
    // region WP-3d — §3.0.5 themed deaths: the design's moment holds the
    // bird (the world still eases to a stop), then the same tumble; the
    // Black Hole swallows it (no tumble, no body).
    final themed = _death?.themed;
    if (themed != null &&
        (_deathTime < themed.holdSeconds || themed.noBody)) {
      t.stepCamera(dt);
      state.camX = t.camX;
      state.forwardSpeed = t.camSpeed;
      final pose = themedPose;
      _bird?.placeTumble(
        geo.toScreen(pose == null ? t.position : t.position + pose.offset),
        pose?.angle ?? t.angle,
      );
      _deathTime += dt;
      if (!_handedOff &&
          themed.noBody &&
          _deathTime >= themed.holdSeconds + SawConfig.holeAfter) {
        _handedOff = true;
        game.runDeathSettled(this);
      }
      return;
    }
    // endregion WP-3d
    t
      ..top = walls.top
      ..floor = walls.floor
      ..step(dt);
    state.camX = t.camX;
    state.forwardSpeed = t.camSpeed;
    _bird?.placeTumble(geo.toScreen(t.position), t.angle);
    _deathTime += dt;
    if (_handedOff) return;
    // WP-3d: a themed death hands over after its moment + up to 1.5 s, at
    // most 2.2 s (§3.0.5).
    final limit = themed != null
        ? math.min(
            themed.holdSeconds + PhysicsConfig.resultsDelay,
            PhysicsConfig.themedResultsMax,
          )
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
  ///
  /// PRD-2.2 §11: [clean] makes a non-perfect pass a clean off-centre one
  /// (no rim touched) instead of a graze.
  void debugPass({bool perfect = false, bool clean = false}) {
    final isClean = clean && !perfect;
    state.passes++;
    state.hoopsPassed++;
    if (perfect) state.perfectPasses++;
    if (isClean) state.cleanPasses++;
    events.emit(
      HoopPassed(
        null,
        perfect: perfect,
        clean: isClean,
        rimTouched: !perfect && !isClean,
      ),
    );
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
    // PRD-2.2 §28.1: at the moment of death every run sound stops (loops;
    // the chick is lost through RunDied and stops peeping). One-shots
    // already playing finish; features restart their own loops after a
    // revive.
    game.sound.stopAllLoops();
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
    // region WP-5b — the duel settles (win / draw bonus) before the summary
    events.emit(const RunEnding());
    // endregion WP-5b
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
    themedPose = null; // WP-3d
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
    _prevFrames.clear();
    clock.running = true;
    state.invulnerable = ReviveConfig.invulnerable;
    events.emit(Revived(k, price));
  }
  // endregion WP-2d

  // region WP-3d — themed death moments (PRD-2 §3.0.5, §3.18, §5.17)
  /// The held bird's pose during a themed death's moment (Live Wire jitter,
  /// Black Hole pull), relative to where it was hit; set by the saw
  /// feature on [RunDied]. Null = held still.
  ThemedDeathPose? themedPose;
  // endregion WP-3d

  // region WP-3g — spike squeeze (PRD-2 §3.17)
  /// The inset of the squeeze that is coming or running (§3.17 table).
  double _squeezeDepth() =>
      SqueezeConfig.insetFor(state.squeeze.index, state.viewHeight);
  // endregion WP-3g

  // region WP-3b — portal rides (PRD-2 §3.12)
  /// The portal ride drives the bird and the camera itself: no forward
  /// motion, rims, plane tests or spikes while it holds (ARCH §17).
  bool rideHold = false;

  /// §3.12 a ride ring is passed (always perfect in a ride).
  void ridePass(Hoop h) {
    if (h.resolved) return;
    _pass(h, 0);
  }

  /// The ride handed the bird back (the next physics step starts fresh).
  void endRideHold() {
    rideHold = false;
    _prevBird = null;
    _prevFrames.clear();
  }
  // endregion WP-3b

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
      duel: s.duel, // WP-5b
      spawned: {...spawner.spawnedCounts, ...s.spawned},
      rimTouches: s.rimTouches,
      passes: s.passes,
      perfectPasses: s.perfectPasses,
      cleanPasses: s.cleanPasses,
      maxStreak: s.bestStreak,
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

// region WP-3d — themed death pose (PRD-2 §3.0.5)
/// Offset (track pt) and angle (rad) of the held bird during a themed
/// death's moment; the owner (the saw death) updates it every frame.
class ThemedDeathPose {
  final Vector2 offset = Vector2.zero();
  double angle = 0;
}
// endregion WP-3d
