import 'package:flame/components.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../menu/powerup_slot.dart';
import 'config/run_config.dart';
import 'director/run_director.dart';
import 'elements.dart';
import 'features.dart';
import 'hoops/kinds/registry.dart';
import 'mistakes.dart';
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
/// layers, the mistake pipeline and the end of the run.
///
/// WP-0b plumbing: until WP-1a registers the normal hoop the 1.0 pipes keep
/// running in `FlappySpikesGame` ("legacy pipes"); the controller then
/// tracks the run (clock, score mirror, analytics, summary) and drives the
/// post-run flow, so the pipe game plays exactly as before.
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

  /// The 1.0 pipes are still the course (WP-1a not landed).
  bool get legacyPipes => !spawner.live;

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
    state.forwardSpeed = legacyPipes
        ? Config.scrollSpeed
        : RunConfig.cruise(state.runClock);
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
    if (!_started || _ended || _frozen) return;
    final gameDt = dt;
    clock.tick(gameDt);
    state.runClock = clock.t;
    if (isScrolling) {
      if (!legacyPipes) {
        // §3.0.1 cruise ramp; WP-1a adds the knock-back recovery.
        state.forwardSpeed = RunConfig.cruise(state.runClock);
      }
      state.camX += state.forwardSpeed * gameDt;
      if (state.invulnerable > 0) {
        state.invulnerable = (state.invulnerable - gameDt).clamp(0, 99);
      }
    }
    layers.follow(state.camX, state.camY);
    spawner.update(gameDt);
    final scale = state.timeScale <= 0 ? 1 : state.timeScale;
    for (final f in features) {
      f.update(gameDt, gameDt / scale);
    }
  }

  /// The one mistake path (ARCH §2.6).
  void mistake(Mistake m) {
    if (!_started || _dying || _ended) return;
    switch (pipeline.resolve(m, ctx)) {
      case MistakeOutcome.ignored:
      case MistakeOutcome.saved:
        return;
      case MistakeOutcome.died:
        _die(m);
    }
  }

  void _die(Mistake m) {
    _dying = true;
    _cause = m.cause;
    clock.running = false;
    for (final f in features) {
      f.onDeath(m);
    }
    // WP-0b: no tumble yet (WP-1a) — the run ends at once, as in 1.0.
    final summary = endRun();
    game.endRun(summary);
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

  RunSummary summarize() {
    final s = state;
    final hoop = spawner.nextHoopAhead();
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
      hoopIndex: s.hoopIndex,
      timeline: s.timeline,
      opponent: setup.opponent,
      spawned: {...director.spawnedCounts, ...s.spawned},
      rimTouches: s.rimTouches,
      passes: s.passes,
      perfectPasses: s.perfectPasses,
    );
  }

  // region WP-0b — legacy pipes (removed by WP-1a)
  /// A 1.0 pipe was passed: mirror the point into the run.
  void legacyPoint(int newScore) {
    final old = state.score;
    state.score = newScore;
    state.hoopsPassed++;
    state.passes++;
    events.emit(const HoopPassed(null));
    events.emit(ScoreChanged(old, newScore));
  }
  // endregion WP-0b

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
    events.clear();
    game.sound.stopAllLoops();
    for (final l in layers.all) {
      l.removeFromParent();
    }
    removeFromParent();
  }
}
