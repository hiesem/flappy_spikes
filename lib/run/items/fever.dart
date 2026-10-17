import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../config/fever_config.dart';
import '../effects/bird_attachment.dart';
import '../config/run_config.dart';
import '../config/streak_config.dart';
import '../director/plans.dart';
import '../../skins/art/trail.dart';
import '../effects/particle_pool.dart';
import '../hud/fever_banner.dart';
import '../hud/run_hud.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// FEVER and the bird's fire (PRD-2 §3.19, §5.18; PRD-2.2 §21).
///
/// - **The fire master** (PRD-2.2 §21, one master, PRD-2 §3.0.9): the bird
///   burns from the 3rd perfect pass in a row ([StreakChanged] to ≥ ×3) or
///   from FEVER, until the streak breaks. Flame teardrops rise from the
///   bird's back, top and bottom edges and stream back and up, with a warm
///   halo, drawn behind the bird only (no outline). The size grows with the
///   streak (×3 / ×5 / ×7, [FireLevel]); the colours follow a flame-type
///   trail ([fireColorsFor]). Hidden inside the comet fireball, kept through
///   portal rides. Visual only.
/// - **FEVER lights** on a *perfect* pass through the FEVER ring — PRD-2.3.1
///   §15: on the FEVER ring that is any rim-free pass; the perfect band
///   (`point_perfect_band`) does not apply there (`RunController._pass`) —
///   (and on a
///   [FeverIgnite] — the pair FEVER gift, Q59): the fire (at least the ×5
///   size), the FEVER! banner above the tier banner, the crackle loop at
///   the FEVER volume (a ≈ 0.3 s ramp up from the quiet crackle when the
///   bird already burned), unchanged until the streak breaks (S7-07);
///   `fever_ring_passed` {perfect, streak_before, streak_after}. A rim
///   touch on the FEVER ring gives no FEVER (Q50).
/// - **Goes out** on a graze (at the rim contact, S6-40), a clean off-centre
///   pass (PRD-2.2 §11), a save (extra life / shield) or a death: smoke
///   puffs, the sizzle (not on a death: the game-over sound plays),
///   `fever_fire_out` {streak, hoops_burned, cause}.
/// - **Sound**: one `fever_loop` player while burning (quiet crackle,
///   [FeverConfig.crackleVolume]; [FeverConfig.loopVolume] during FEVER,
///   a ≈ 0.3 s ramp between them); it stops on pause, death and the end.
///
/// Attached before `StreakFeature` (features region WP-3c), so its handlers
/// see the streak before the streak feature changes it.
class FeverFeature extends RunFeature {
  RunContext? _c;
  FireMaster? _fire;
  LoopHandle? _loop;

  /// The loop volume last sent and the ramp's step clock.
  double _volume = 0;
  double _rampClock = 0;

  /// The fire's particles and halo (tests, shots).
  ParticlePool? get flames => _fire?.pool;

  /// The fire master (tests, shots).
  FireMaster? get fire => _fire;

  /// The crackle loop (tests).
  LoopHandle? get loop => _loop;

  /// The loop volume the feature has set last (tests).
  double get loopVolume => _volume;

  @override
  void attach(RunContext c) {
    _c = c;
    _fire = FireMaster(c, colors: fireColorsFor(c.game.menu.items.look.trail));
    c.game.world.add(_fire!);
    c.events
      ..on<HoopSpawned>(_onSpawned)
      ..on<HoopPassed>(_onPassed)
      ..on<RimTouched>(_onRim)
      ..on<MistakeSaved>(_onSaved)
      ..on<RunDied>(_onDied)
      ..on<FeverIgnite>(_onIgnite)
      ..on<StreakChanged>(_onStreak);
  }

  /// PRD-2.2 §21.1 The fire's colours for the equipped trail [trailId]: a
  /// flame-type trail's four colours, else the classic orange fire.
  static List<Color> fireColorsFor(String trailId) =>
      TrailEmitter.flameColors(trailId) ?? FeverConfig.firePalette;

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
        _light(fever: true);
        return;
      }
    }
    if (!s.onFire) return;
    if (e.perfect) {
      s.hoopsBurned++;
    } else {
      // PRD-2.2 §11.2 a clean off-centre pass is an ordinary non-perfect
      // pass: it puts the fire out too.
      _out(e.clean ? 'clean' : 'graze');
    }
  }

  /// PRD-2.2 §21.1 the 3rd perfect pass in a row lights the fire.
  void _onStreak(StreakChanged e) {
    final c = _c;
    if (c == null) return;
    if (e.newStreak >= FeverConfig.fireStreak && !c.s.onFire) _light();
  }

  /// §3.19 a graze puts the fire out at the rim contact itself, not when
  /// the pass resolves (S6-40). Ride rings never graze the fire (rides keep
  /// it burning).
  void _onRim(RimTouched e) {
    if (_c?.s.ride != null) return;
    _out('graze');
  }

  void _onSaved(MistakeSaved e) => _out(e.by);

  void _onDied(RunDied e) => _out('death', sizzle: false);

  void _onIgnite(FeverIgnite e) => _light(fever: true);

  /// Sets the bird on fire: by the streak (×3) or by FEVER ([fever]: the
  /// FEVER! banner and the FEVER phase, also when the bird already burns).
  void _light({bool fever = false}) {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    if (fever) {
      // PRD-2.3.1 §12.2 a real FEVER (ring or pair gift), also when the
      // bird already burns; never the streak's on-fire state.
      c.emit(const FeverStarted());
      s.feverLit = true;
      RunHud.ensureFor(c.run).banners.showFever(FeverBanner());
    }
    if (s.onFire) {
      if (fever) s.hoopsBurned = 0;
      return;
    }
    s
      ..onFire = true
      ..hoopsBurned = 0;
    c.emit(const FeverFireChanged(lit: true));
  }

  void _out(String cause, {bool sizzle = true}) {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    s.feverLit = false;
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

  /// PRD-2.2 §21.1 the loop's target volume right now.
  double get _target =>
      (_c?.s.fever ?? false) ? FeverConfig.loopVolume : FeverConfig.crackleVolume;

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
    final target = _target;
    if (want && (_loop == null || _loop!.stopped)) {
      _volume = target;
      _rampClock = 0;
      _loop = c.loop(SfxLoop.feverLoop, volume: _volume);
    } else if (!want && _loop != null) {
      _stopLoop();
    } else if (want && _volume != target) {
      // PRD-2.2 §21.1 a ≈ 0.3 s ramp on the one loop player, sent in
      // steps (no per-frame platform traffic, §33).
      const speed =
          (FeverConfig.loopVolume - FeverConfig.crackleVolume) /
          FeverConfig.loopRamp;
      final d = speed * realDt;
      _volume = _volume < target
          ? math.min(target, _volume + d)
          : math.max(target, _volume - d);
      _rampClock += realDt;
      if (_volume == target || _rampClock >= 1 / FeverConfig.loopRampSteps) {
        _rampClock = 0;
        _loop?.setVolume(_volume);
      }
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
        ..off<RimTouched>(_onRim)
        ..off<MistakeSaved>(_onSaved)
        ..off<RunDied>(_onDied)
        ..off<FeverIgnite>(_onIgnite)
        ..off<StreakChanged>(_onStreak);
    }
    _stopLoop();
    _fire?.removeFromParent();
    _fire = null;
    _c = null;
  }
}

/// PRD-2.2 §21.1 the fire's size level for an effective streak: 0 (none),
/// 1 (×3–×4), 2 (×5–×6), 3 (×7+).
abstract final class FireLevel {
  static int of(int streak) {
    var l = 0;
    for (final at in FeverConfig.fireLevelStreaks) {
      if (streak >= at) l++;
    }
    return l;
  }
}

/// The one fire master (PRD-2 §3.0.9; PRD-2.2 §21): the bird's flames, the
/// warm halo and the smoke puffs when it goes out. Screen space, behind the
/// bird ([FeverConfig.firePriority]). Allocation-free per frame: the halo
/// paints are built once per colour set (PRD-2.2 §33.4 item 6).
class FireMaster extends Component with BirdAttachment {
  FireMaster(this.c, {List<Color> colors = FeverConfig.firePalette})
    : super(priority: FeverConfig.firePriority) {
    this.colors = colors;
  }

  final RunContext c;

  @override
  FlappySpikesGame get birdGame => c.game;

  /// Flames already shed and the smoke drift free of the bird.
  @override
  bool get hidesWholly => false;
  final ParticlePool pool = ParticlePool(capacity: 120);
  final ParticlePool smokePool = ParticlePool(capacity: 24);
  double _acc = 0;

  /// One halo paint per size level, its shader centred on the origin.
  final List<Paint> _halos = [Paint(), Paint(), Paint()];

  late List<Color> _colors;

  /// The flame colours over the life (lightest → darkest).
  List<Color> get colors => _colors;
  set colors(List<Color> value) {
    _colors = value;
    final warm = value[2];
    for (var i = 0; i < _halos.length; i++) {
      final r = FeverConfig.fireHaloRadii[i];
      final a = FeverConfig.fireHaloAlphas[i];
      _halos[i].shader = Gradient.radial(
        Offset.zero,
        r,
        [warm.withValues(alpha: a), warm.withValues(alpha: 0)],
        [FeverConfig.fireHaloCore / r, 1],
      );
    }
  }

  /// Whether the bird burns (state).
  bool get burning => c.s.onFire && !c.run.dying && !c.run.ended;

  /// PRD-2.2 §21.1 hidden inside the comet fireball and while a portal
  /// ride hides the bird (cannon barrel, volcano, rocket). Audit HIDE: and
  /// whenever else the bird is not drawn ([BirdAttachment.birdPresented]).
  bool get hidden =>
      c.s.ride?.kind == RideKind.comet ||
      (c.s.ride?.birdHidden ?? false) ||
      !birdPresented;

  /// Whether the fire shows (emits and draws its halo).
  bool get showing => burning && !hidden && _hasBird;

  /// The streak that sets the size (FEVER: at least ×5).
  int get sizeStreak {
    final s = c.s;
    final n = s.fever
        ? math.max(s.streak, FeverConfig.feverSizeStreak)
        : s.streak;
    return math.max(n, FeverConfig.fireStreak);
  }

  /// The size level (1 … 3) while burning, 0 otherwise.
  int get level => burning ? FireLevel.of(sizeStreak) : 0;

  /// Flames per second now.
  double get rate {
    final l = level;
    return l == 0 ? 0 : FeverConfig.fireRates[l - 1];
  }

  /// Size factor now (0.7 / 0.85 / 1).
  double get scale {
    final l = level;
    return l == 0 ? 0 : FeverConfig.fireScales[l - 1];
  }

  bool _hasBird = false;
  double _bx = 0, _by = 0;

  void _readBird() {
    final b = c.game.runBird;
    if (b == null || !b.isLoaded) {
      _hasBird = false;
      return;
    }
    final p = b.body.position;
    _hasBird = true;
    _bx = p.x;
    _by = p.y;
  }

  @override
  void update(double dt) {
    _readBird();
    if (showing) {
      final sc = scale;
      final k = c.s.birdScale;
      _acc += rate * dt;
      final r = c.cosmetic;
      while (_acc >= 1) {
        _acc -= 1;
        final e = r.nextDouble();
        double x, y, lift = 1;
        if (e < FeverConfig.fireBackShare) {
          x = FeverConfig.fireBackX - 2 + r.nextDouble() * 6;
          y = (r.nextDouble() * 2 - 1) * FeverConfig.fireBackSpread;
        } else if (e < FeverConfig.fireBackShare + FeverConfig.fireTopShare) {
          x = -20 + r.nextDouble() * 36;
          y = -FeverConfig.fireEdgeY - 3 + r.nextDouble() * 5;
        } else {
          x = -20 + r.nextDouble() * 30;
          y = FeverConfig.fireEdgeY - 2 + r.nextDouble() * 5;
          lift = FeverConfig.fireBottomLift;
        }
        final size =
            (FeverConfig.fireSizeMin +
                r.nextDouble() *
                    (FeverConfig.fireSizeMax - FeverConfig.fireSizeMin)) *
            sc;
        final life =
            (FeverConfig.fireLifeMin +
                r.nextDouble() *
                    (FeverConfig.fireLifeMax - FeverConfig.fireLifeMin)) *
            (.8 + .2 * sc);
        final vx =
            FeverConfig.fireVxMin +
            r.nextDouble() * (FeverConfig.fireVxMax - FeverConfig.fireVxMin);
        final vy =
            (FeverConfig.fireVyMin +
                r.nextDouble() *
                    (FeverConfig.fireVyMax - FeverConfig.fireVyMin)) *
            lift;
        pool.spawn(
          shape: ParticleShape.flame,
          x: _bx + x * k,
          y: _by + y * k,
          vx: vx,
          vy: vy,
          // The tip points along the motion (the mock's rotation).
          rot: math.atan2(vy, vx) + math.pi / 2,
          w: size * FeverConfig.fireDropWidth * k,
          color: _colors.first,
          ramp: _colors,
          life: life,
          alpha1: .2,
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
    _readBird();
    final bx = _hasBird ? _bx : RunConfig.birdX;
    final by = _hasBird ? _by : c.viewHeight / 2;
    final r = c.cosmetic;
    for (var i = 0; i < FeverConfig.smokePuffs; i++) {
      smokePool.spawn(
        shape: ParticleShape.circle,
        x: bx + (r.nextDouble() - .5) * 20,
        y: by + (r.nextDouble() - .5) * 20,
        vx: -60 + (r.nextDouble() - .5) * 40,
        vy: -40 - r.nextDouble() * 40,
        w: 12,
        color: FeverConfig.smoke,
        life: 1,
        scale1: 4,
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final l = level;
    if (l > 0 && showing) {
      final k = c.s.birdScale;
      canvas
        ..save()
        ..translate(
          _bx + FeverConfig.fireHaloDx * k,
          _by + FeverConfig.fireHaloDy * k,
        )
        ..scale(k)
        ..drawCircle(
          Offset.zero,
          FeverConfig.fireHaloRadii[l - 1],
          _halos[l - 1],
        )
        ..restore();
    }
    pool.paint(canvas);
    smokePool.paint(canvas);
  }
}
