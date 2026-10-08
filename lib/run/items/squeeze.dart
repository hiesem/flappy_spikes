import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../components/score_hud.dart';
import '../../components/spike_strip.dart';
import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../config/run_config.dart';
import '../config/squeeze_config.dart';
import '../effects/particle_pool.dart';
import '../effects/run_shake.dart';
import '../elements.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_layers.dart';
import '../run_state.dart';

/// §3.17 / §5.16 the spike squeeze: the scheduler and the phases.
///
/// - **When:** the first squeeze at a random 60–120 s of `runClock`, the
///   next 60–120 s after a squeeze has fully opened (the director's timing
///   stream rolls both). A moment that falls inside a ride (portal, comet)
///   or a revive waits until it ends + 2 s.
/// - **Phases** (`RunState.squeeze`): warning 1.5 s → closing 3 s
///   (ease-in-out) → lock → hold 10–20 s (no indicator; ticks in the last
///   3 s) → opening 3 s → idle. The feature only writes
///   `RunState.squeeze.inset`; the tooth lines ([RunGeometry],
///   `SpikeWalls`: contact = a mistake as on the normal spikes), the strips
///   (they follow the inset) and the director's squeezed band read it.
/// - **Look / sound:** the world shake (a [RunShake] applied to the camera
///   as a delta, so it composes with the FEVER pass shake), the teeth's red
///   warning flash ([SpikeStrip.toothFlash]), falling bits and the lock
///   dust (own [ParticlePool] in the fx track), the score circle cover
///   ([ScoreHud.setSqueezeCover] + [ScoreCoverOverlay]), `sq_*` sounds and
///   the `sq_hold` loop.
/// - **Revive:** `ReviveRulesFeature` (WP-2d) resets a running squeeze to
///   open over 0.5 s and re-rolls the moment; this feature counts the
///   interrupted squeeze (the next one is tighter), drops its shake / loop
///   and lets bits fall while the walls slide out.
class SqueezeFeature extends RunFeature {
  RunContext? _c;

  /// Seconds in the current phase (runClock time).
  double phaseT = 0;

  /// The inset the current squeeze closes to (pt).
  double depth = 0;

  /// Squeezes started this run (warning reached).
  int started = 0;

  /// runClock before which no squeeze may start (ride / revive + 2 s).
  double _waitUntil = 0;
  double _openFrom = 0;
  int _ticks = 0;
  double _bitAcc = 0;
  double _lastInset = 0;

  LoopHandle? _hold;
  final RunShake shake = RunShake();
  Offset _applied = Offset.zero;
  ParticlePool? _pool;
  ScoreHud? _hud;
  ScoreCoverOverlay? _overlay;

  /// The bits and dust (tests).
  ParticlePool? get pool => _pool;

  SqueezeState get _sq => _c!.s.squeeze;

  @override
  void attach(RunContext c) {
    _c = c;
    final sq = c.s.squeeze;
    sq.nextAt = c.director.rollSqueezeAt(c.s.runClock);
    c.events
      ..on<DebugForced>(_onForced)
      ..on<RideEnded>(_onRideEnded)
      ..on<Revived>(_onRevived);
    final pool = ParticlePool(capacity: SqueezeConfig.poolCapacity);
    _pool = pool;
    c.layers.fx.add(pool);
    final world = c.game.world;
    final hud = world.children.whereType<ScoreHud>().firstOrNull;
    _hud = hud;
    if (hud != null) {
      final o = ScoreCoverOverlay(hud, priority: RunLayer.strips + 1);
      _overlay = o;
      world.add(o);
    }
    if (c.run.setup.forced.contains(ElementId.squeeze)) force();
  }

  // ------------------------------------------------------------ schedule

  /// §3.0.8 debug force: the squeeze comes as soon as every hoop already
  /// on screen is behind the bird by the window rule (3 s before the
  /// warning only squeezed-band hoops may be ahead).
  void force() {
    final c = _c;
    if (c == null || _sq.phase != SqueezePhase.idle) return;
    final s = c.s;
    final birdX = c.run.birdTrackPosition()?.x ?? s.camX + RunConfig.birdX;
    var ahead = 0.0;
    for (final h in c.run.spawner.hoops) {
      ahead = math.max(ahead, h.planeX - birdX);
    }
    final lead = ahead / RunConfig.cruise(s.runClock);
    _sq.nextAt = s.runClock + RunConfig.squeezeWindowLead + lead + .05;
  }

  void _onForced(DebugForced e) {
    if (e.element == ElementId.squeeze) force();
  }

  void _onRideEnded(RideEnded e) => _wait();

  void _onRevived(Revived e) => _wait();

  void _wait() {
    final c = _c;
    if (c == null) return;
    _waitUntil = math.max(_waitUntil, c.s.runClock + SqueezeConfig.waitAfter);
  }

  bool get _mayStart {
    final c = _c!;
    return c.s.ride == null &&
        c.s.runClock >= _waitUntil &&
        c.run.isScrolling &&
        !c.run.rideHold;
  }

  // ------------------------------------------------------------ phases

  void _enter(SqueezePhase p) {
    final c = _c!;
    _sq.phase = p;
    phaseT = 0;
    c.emit(SqueezePhaseChanged(p, _sq.index));
  }

  void _start() {
    final c = _c!;
    final sq = _sq;
    depth = SqueezeConfig.insetFor(sq.index, c.viewHeight);
    sq.holdS = c.director.rollSqueezeHold();
    _ticks = 0;
    started++;
    _enter(SqueezePhase.warning);
    c.sfx(Sfx.sqWarn);
    c.emit(const ElementSpawned(ElementId.squeeze));
    c.track('squeeze_started', {
      'index': sq.index + 1,
      'open_pct': (SqueezeConfig.openFor(sq.index, c.viewHeight) /
              c.viewHeight *
              100)
          .round(),
      'hold_s': sq.holdS.round(),
    });
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    final sq = _sq;
    final dt = gameDt;
    if (dt > 0) {
      switch (sq.phase) {
        case SqueezePhase.idle:
          if (c.s.runClock >= sq.nextAt && _mayStart) _start();
        case SqueezePhase.warning:
          phaseT += dt;
          shake.sustain =
              SqueezeConfig.warnShake *
              (phaseT / SqueezeConfig.warnShakeRamp).clamp(0.0, 1.0);
          if (phaseT >= SqueezeConfig.warning) {
            _enter(SqueezePhase.closing);
            c.sfx(Sfx.sqClose);
          }
        case SqueezePhase.closing:
          phaseT += dt;
          shake.sustain = SqueezeConfig.closeShake;
          sq.inset = depth * SqueezeConfig.ease(phaseT / SqueezeConfig.closing);
          if (phaseT >= SqueezeConfig.closing) _lock();
        case SqueezePhase.hold:
          phaseT += dt;
          sq.inset = depth;
          while (_ticks < SqueezeConfig.lastTicks &&
              phaseT >= sq.holdS - (SqueezeConfig.lastTicks - _ticks)) {
            _ticks++;
            c.sfx(Sfx.sqTick);
            shake.kick(
              SqueezeConfig.tickTremble,
              decay: SqueezeConfig.tickTremble / SqueezeConfig.tickTrembleTime,
            );
          }
          if (phaseT >= sq.holdS) _open();
        case SqueezePhase.opening:
          phaseT += dt;
          sq.inset =
              _openFrom *
              (1 - SqueezeConfig.ease(phaseT / SqueezeConfig.opening));
          if (phaseT >= SqueezeConfig.opening) _done();
      }
      _emitBits(dt);
      shake.update(dt);
      _applyShake(shake.offset);
    }
    _syncLoop();
    _syncLook();
  }

  void _lock() {
    final c = _c!;
    _sq.inset = depth;
    shake
      ..sustain = 0
      ..kick(
        SqueezeConfig.lockShake,
        decay: SqueezeConfig.lockShake / SqueezeConfig.lockShakeTime,
      );
    _enter(SqueezePhase.hold);
    c.sfx(Sfx.sqLock);
    _dust();
  }

  void _open() {
    final c = _c!;
    _openFrom = _sq.inset;
    _stopLoop();
    shake
      ..sustain = 0
      ..kick(
        SqueezeConfig.openShake,
        decay: SqueezeConfig.openShake / SqueezeConfig.openShakeTime,
      );
    _enter(SqueezePhase.opening);
    c.sfx(Sfx.sqOpen);
  }

  void _done() {
    final c = _c!;
    final sq = _sq;
    sq.inset = 0;
    shake.sustain = 0;
    c.track('squeeze_survived', {'index': sq.index + 1});
    sq.index++;
    sq.nextAt = c.director.rollSqueezeAt(c.s.runClock);
    _enter(SqueezePhase.idle);
  }

  // ------------------------------------------------------------ look

  bool get _bitsOn {
    final sq = _sq;
    return switch (sq.phase) {
      SqueezePhase.warning ||
      SqueezePhase.closing ||
      SqueezePhase.opening => true,
      // The revive's 0.5 s slide out (WP-2d drives the inset).
      SqueezePhase.idle => sq.inset > 0 && sq.inset < _lastInset,
      SqueezePhase.hold => false,
    };
  }

  void _emitBits(double dt) {
    final c = _c!;
    final pool = _pool;
    final on = _bitsOn;
    _lastInset = _sq.inset;
    if (pool == null || !on) {
      _bitAcc = 0;
      return;
    }
    _bitAcc += dt * SqueezeConfig.bitsPerSecond;
    final r = c.cosmetic;
    final color = c.game.foregroundColor;
    while (_bitAcc >= 1) {
      _bitAcc -= 1;
      final top = r.nextBool();
      final y = top ? c.geo.topTooth : c.geo.floorTooth;
      final v =
          SqueezeConfig.bitSpeedMin +
          r.nextDouble() *
              (SqueezeConfig.bitSpeedMax - SqueezeConfig.bitSpeedMin);
      pool.spawn(
        x: c.s.camX + r.nextDouble() * RunConfig.worldWidth,
        y: y + c.s.camY,
        vx: (r.nextDouble() * 2 - 1) * SqueezeConfig.bitDrift,
        vy: top ? v : -v,
        w:
            SqueezeConfig.bitMin +
            r.nextDouble() * (SqueezeConfig.bitMax - SqueezeConfig.bitMin),
        color: color,
        life: SqueezeConfig.bitLife,
        alpha0: SqueezeConfig.bitAlpha,
      );
    }
  }

  void _dust() {
    final c = _c!;
    final pool = _pool;
    if (pool == null) return;
    final r = c.cosmetic;
    final color = Color.lerp(
      c.game.foregroundColor,
      const Color(0xFF000000),
      SqueezeConfig.dustDarken,
    )!;
    for (var i = 0; i < SqueezeConfig.dustCount; i++) {
      final top = i.isEven;
      final v =
          SqueezeConfig.dustSpeedMin +
          r.nextDouble() *
              (SqueezeConfig.dustSpeedMax - SqueezeConfig.dustSpeedMin);
      pool.spawn(
        x: c.s.camX + r.nextDouble() * RunConfig.worldWidth,
        y: (top ? c.geo.topTooth : c.geo.floorTooth) + c.s.camY,
        vx: (r.nextDouble() * 2 - 1) * SqueezeConfig.dustDrift,
        vy: top ? v : -v,
        w:
            SqueezeConfig.dustMin +
            r.nextDouble() * (SqueezeConfig.dustMax - SqueezeConfig.dustMin),
        color: color,
        life:
            SqueezeConfig.dustLifeMin +
            r.nextDouble() *
                (SqueezeConfig.dustLifeMax - SqueezeConfig.dustLifeMin),
        alpha0: SqueezeConfig.dustAlpha,
      );
    }
  }

  /// §5.16 the teeth flash (warning + the first 0.4 s of closing) and the
  /// score circle cover.
  void _syncLook() {
    final c = _c!;
    final sq = _sq;
    final flashT = switch (sq.phase) {
      SqueezePhase.warning => phaseT,
      SqueezePhase.closing => SqueezeConfig.warning + phaseT,
      _ => -1.0,
    };
    final flash = SqueezeConfig.flashAt(flashT);
    for (final strip in c.game.world.children.whereType<SpikeStrip>()) {
      strip.toothFlash = flash;
    }
    final hud = _hud;
    if (hud != null) {
      final top = c.geo.topTooth, floor = c.geo.floorTooth;
      hud.setSqueezeCover(
        ScoreHud.coverFor(
          centreY: hud.position.y,
          radius: Config.scoreCircleSize.x / 2,
          top: top,
          floor: floor,
          ramp: SqueezeConfig.coverRamp,
        ),
        c.game.foregroundColor,
      );
      _overlay
        ?..top = top
        ..floor = floor;
    }
  }

  /// The world shake as a camera delta (composes with other shakes; the
  /// HUD in the viewport stays still).
  void _applyShake(Offset o) {
    final c = _c;
    if (c == null || o == _applied) return;
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position + Vector2(o.dx - _applied.dx, o.dy - _applied.dy);
    _applied = o;
  }

  // ------------------------------------------------------------ sound

  void _syncLoop() {
    final c = _c!;
    final want =
        _sq.phase == SqueezePhase.hold &&
        c.game.state == GameState.playing &&
        !c.run.dying &&
        !c.run.ended;
    if (want && (_hold == null || _hold!.stopped)) {
      _hold = c.loop(SfxLoop.sqHold, volume: SqueezeConfig.holdVolume);
    } else if (!want && _hold != null) {
      _stopLoop();
    }
  }

  void _stopLoop() {
    final l = _hold;
    _hold = null;
    if (l != null && !l.stopped) l.stop();
  }

  // ------------------------------------------------------------ death

  @override
  void onDeath(Mistake m) {
    final c = _c;
    if (c == null) return;
    _stopLoop();
    shake.stop();
    _applyShake(Offset.zero);
    for (final strip in c.game.world.children.whereType<SpikeStrip>()) {
      strip.toothFlash = 0;
    }
    final sq = _sq;
    if (sq.phase != SqueezePhase.idle) {
      c.track('squeeze_death', {'index': sq.index + 1, 'phase': sq.phase.name});
    }
  }

  @override
  void onRevive() {
    // Runs before WP-2d's ReviveRulesFeature resets the state: an
    // interrupted squeeze still counts (the next one is tighter).
    final c = _c;
    if (c == null) return;
    if (_sq.phase != SqueezePhase.idle) _sq.index++;
    phaseT = 0;
    _ticks = 0;
    _lastInset = _sq.inset;
    _stopLoop();
    shake.stop();
    _applyShake(Offset.zero);
  }

  @override
  void detach() {
    final c = _c;
    if (c == null) return;
    _stopLoop();
    shake.stop();
    _applyShake(Offset.zero);
    c.events
      ..off<DebugForced>(_onForced)
      ..off<RideEnded>(_onRideEnded)
      ..off<Revived>(_onRevived);
    for (final strip in c.game.world.children.whereType<SpikeStrip>()) {
      strip.toothFlash = 0;
    }
    _hud?.setSqueezeCover(0, c.game.foregroundColor);
    _overlay?.removeFromParent();
    _overlay = null;
    _pool?.removeFromParent();
    _pool = null;
    _c = null;
  }
}
