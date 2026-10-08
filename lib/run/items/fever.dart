import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../config/fever_config.dart';
import '../config/run_config.dart';
import '../config/streak_config.dart';
import '../director/plans.dart';
import '../effects/particle_pool.dart';
import '../hud/fever_banner.dart';
import '../hud/run_hud.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// FEVER: the fire (PRD-2 §3.19, §5.18).
///
/// - **Lights** on a *perfect* pass through the FEVER ring (and on a
///   [FeverIgnite] — the pair FEVER gift, Q59): `RunState.onFire`, the
///   FEVER! banner above the tier banner, the burning crackle loop,
///   `fever_ring_passed` {perfect, streak_before, streak_after}. Reaching
///   ×5 through normal passes never lights it (Q51); a rim touch on the
///   FEVER ring gives no fire (Q50).
/// - **Burns** until the streak breaks: ≈ 115 teardrop flames/s streaming
///   back and up from the bird with a warm halo, drawn behind the bird (the
///   gold bird, tier look and trail stay). Visual only — no speed, score,
///   coin or hitbox change. It keeps burning through rides.
/// - **Goes out** on a graze, a save (extra life / shield) or a death:
///   smoke puffs, the sizzle (not on a death: the game-over sound plays),
///   `fever_fire_out` {streak, hoops_burned, cause}.
///
/// Attached before `StreakFeature` (features region WP-3c), so its handlers
/// see the streak before the streak feature changes it.
class FeverFeature extends RunFeature {
  RunContext? _c;
  _FireComponent? _fire;
  LoopHandle? _loop;

  /// The fire's particles and halo (tests, shots).
  ParticlePool? get flames => _fire?.pool;

  @override
  void attach(RunContext c) {
    _c = c;
    _fire = _FireComponent(c);
    c.game.world.add(_fire!);
    c.events
      ..on<HoopSpawned>(_onSpawned)
      ..on<HoopPassed>(_onPassed)
      ..on<MistakeSaved>(_onSaved)
      ..on<RunDied>(_onDied)
      ..on<FeverIgnite>(_onIgnite);
  }

  void _onSpawned(HoopSpawned e) {
    if (e.plan.kind != HoopKindId.fever) return;
    _c?.track('fever_ring_spawned', {'hoop_index': e.plan.index});
  }

  void _onPassed(HoopPassed e) {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    final fever = e.hoop?.plan.kind == HoopKindId.fever;
    final before = s.streak;
    if (fever) {
      final after = e.perfect
          ? math.max(StreakConfig.feverMinStreak, before + 1)
          : 0;
      c.track('fever_ring_passed', {
        'perfect': e.perfect ? 1 : 0,
        'streak_before': before,
        'streak_after': after,
      });
      if (e.perfect) {
        _light();
        return;
      }
    }
    if (!s.onFire) return;
    if (e.perfect) {
      s.hoopsBurned++;
    } else {
      _out('graze');
    }
  }

  void _onSaved(MistakeSaved e) => _out(e.by);

  void _onDied(RunDied e) => _out('death', sizzle: false);

  void _onIgnite(FeverIgnite e) => _light();

  /// Sets the bird on fire (FEVER ring / gift).
  void _light() {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    s.hoopsBurned = 0;
    RunHud.ensureFor(c.run).banners.showFever(FeverBanner());
    if (s.onFire) return;
    s.onFire = true;
    c.emit(const FeverFireChanged(lit: true));
  }

  void _out(String cause, {bool sizzle = true}) {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    if (!s.onFire) return;
    c.track('fever_fire_out', {
      'streak': s.streak,
      'hoops_burned': s.hoopsBurned,
      'cause': cause,
    });
    s.onFire = false;
    if (sizzle) c.sfx(Sfx.feverOut);
    _fire?.smoke();
    _stopLoop();
    c.emit(FeverFireChanged(lit: false, cause: cause));
  }

  void _stopLoop() {
    final l = _loop;
    _loop = null;
    if (l != null && !l.stopped) l.stop();
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    // The crackle loop plays while the bird burns and the run is live (it
    // stops in pause and after a death).
    final want =
        c.s.onFire &&
        c.game.state == GameState.playing &&
        !c.run.dying &&
        !c.run.ended;
    if (want && (_loop == null || _loop!.stopped)) {
      _loop = c.loop(SfxLoop.feverLoop, volume: FeverConfig.loopVolume);
    } else if (!want && _loop != null) {
      _stopLoop();
    }
  }

  @override
  void onDeath(Mistake m) => _stopLoop();

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.events
        ..off<HoopSpawned>(_onSpawned)
        ..off<HoopPassed>(_onPassed)
        ..off<MistakeSaved>(_onSaved)
        ..off<RunDied>(_onDied)
        ..off<FeverIgnite>(_onIgnite);
    }
    _stopLoop();
    _fire?.removeFromParent();
    _fire = null;
    _c = null;
  }
}

/// The bird's fire (screen space, behind the bird): the flame stream, the
/// warm halo and the smoke puffs when it goes out.
class _FireComponent extends Component {
  _FireComponent(this.c) : super(priority: FeverConfig.firePriority);

  final RunContext c;
  final ParticlePool pool = ParticlePool(capacity: 110);
  final ParticlePool smokePool = ParticlePool(capacity: 24);
  double _acc = 0;

  bool get burning => c.s.onFire && !c.run.dying && !c.run.ended;

  Vector2? get _bird => c.game.runBirdPosition;

  @override
  void update(double dt) {
    final bird = _bird;
    if (burning && bird != null) {
      _acc += FeverConfig.fireRate * dt;
      final r = c.cosmetic;
      while (_acc >= 1) {
        _acc -= 1;
        final s = FeverConfig.fireSize + r.nextDouble() * 8;
        pool.spawn(
          shape: ParticleShape.flame,
          x: bird.x - 4 + (r.nextDouble() - .5) * 24,
          y: bird.y + (r.nextDouble() - .5) * 22,
          vx: -130 - r.nextDouble() * 90,
          vy: -70 - r.nextDouble() * 70,
          w: 2 * s,
          color: FeverConfig.firePalette.first,
          ramp: FeverConfig.firePalette,
          life:
              FeverConfig.fireLifeMin +
              r.nextDouble() * FeverConfig.fireLifeRange,
          fadePow: 2,
        );
      }
    } else {
      _acc = 0;
    }
    pool.step(dt);
    smokePool.step(dt);
  }

  /// §5.18 the fire goes out: grey smoke puffs rising from the bird.
  void smoke() {
    final bird = _bird ?? Vector2(RunConfig.birdX, c.viewHeight / 2);
    final r = c.cosmetic;
    for (var i = 0; i < FeverConfig.smokePuffs; i++) {
      smokePool.spawn(
        shape: ParticleShape.circle,
        x: bird.x + (r.nextDouble() - .5) * 20,
        y: bird.y + (r.nextDouble() - .5) * 20,
        vx: -60 + (r.nextDouble() - .5) * 40,
        vy: -40 - r.nextDouble() * 40,
        w: 12,
        color: FeverConfig.smoke,
        life: 1,
        scale1: 4,
      );
    }
  }

  final Paint _halo = Paint();

  @override
  void render(Canvas canvas) {
    final bird = _bird;
    if (burning && bird != null) {
      const hr = FeverConfig.fireHalo;
      _halo.shader = Gradient.radial(Offset(bird.x, bird.y), hr, [
        const Color.fromRGBO(255, 190, 70, FeverConfig.fireHaloAlpha),
        const Color.fromRGBO(255, 190, 70, 0),
      ]);
      canvas.drawRect(
        Rect.fromCircle(center: Offset(bird.x, bird.y), radius: hr),
        _halo,
      );
    }
    pool.paint(canvas);
    smokePool.paint(canvas);
  }
}
