import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../components/skins/item_art.dart' show paintLookForTrail;
import '../../game/flappy_game.dart';
import '../config/run_config.dart';
import '../config/streak_config.dart';
import '../director/plans.dart';
import '../effects/bird_attachment.dart';
import '../effects/particle_pool.dart';
import '../effects/perfect_burst.dart';
import '../effects/ring_tier_fx.dart';
import '../effects/tier_trail.dart';
import '../hoops/hoop.dart';
import '../hoops/ring_painter.dart';
import '../hud/banners.dart';
import '../hud/run_hud.dart';
import 'big_hoops.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// The perfect-pass streak (PRD-2 §3.4, §3.5, §3.19 FEVER hook, §5.3, §5.4).
///
/// **Rules.** A perfect pass (no rim touch and inside the PRD-2.2 §11
/// perfect zone; every ride hoop) adds one to
/// `RunState.streak`; a perfect FEVER pass sets it to
/// max([StreakConfig.feverMinStreak], streak + 1); its points still use the
/// ordinary increment (`RunState.pointStreak`, PRD-2.3.1 §15.1). A non-perfect pass (a
/// graze, or a clean off-centre pass, PRD-2.2 §11), a saved mistake
/// ([MistakeSaved]) and a death ([RunDied]) reset it
/// to 0. The tier is `RunState.tier` (streak capped at 10). Every change
/// emits [StreakChanged]; a tier change emits [TierChanged].
///
/// **Per perfect pass** (the §3.0.9 masters, never redrawn here): the
/// streak banner #7 ([BannerHost.showStreak], one host shared with the
/// FEVER / element banners), the tier sound `perfect_1/2/3`, the small
/// burst #9 at the bird ([PerfectBurst], screen space like the §5.3 mock)
/// and `perfect_pass` (tier). The "+2 coin" popup #8 and the coins belong to
/// `ScoringFeature`; a graze keeps `point` + the ring pulse there. **No
/// screen flash** (#13).
///
/// **The ring field** (§3.5): every hoop whose kind `usesTierLook` gets one
/// [RingTierFx] per ring (#11: sparkles / flame flicks in front, the glow
/// behind) and the tier colours on `Hoop.look.colors` — passed rings, rings
/// ahead and rings spawned later alike; a missed hoop (`look.missed`) stays
/// out of it. The streak only writes `look.colors` while they still hold
/// the value it wrote last, so another owner (Big Hoops gold, the miss
/// flash) keeps its colours.
///
/// **The bird**: gold from tier 2 (#5, `LookComponent.goldTier`), its trail
/// from tier 3 (#10 via [TierTrail]: the equipped trail, or the block trail
/// for the blocks item) — also during a ride (comet / portal).
///
/// **Graze** with a streak running: the streak resets at once, with no text
/// (PRD-2.3.1 §8 removed the "GRAZE · streak lost" notice). The rim touch
/// keeps its sparks, tonk and spin.
class StreakFeature extends RunFeature {
  RunContext? _c;

  final Map<Hoop, _HoopTier> _hoops = {};

  /// Screen-space pool of the perfect bursts.
  ParticlePool? _burst;
  _TrailComponent? _trail;
  BannerHost? _banners;

  int get tier => _c?.s.tier ?? 0;

  /// The bursts' pool (tests).
  ParticlePool? get burstPool => _burst;

  /// The bird's trail (tests).
  TierTrail? get trail => _trail?.trail;

  /// Whether the bird's trail is emitting (tests).
  bool get trailActive => _trail?.active ?? false;

  /// The banner host (tests).
  BannerHost? get banners => _banners;

  /// The tier fx of [h]'s rings (null for kinds without the tier look).
  List<RingTierFx>? fxOf(Hoop h) => _hoops[h]?.fx;

  @override
  void attach(RunContext c) {
    _c = c;
    final world = c.game.world;
    _burst = ParticlePool(priority: StreakConfig.burstPriority);
    world.add(_burst!);
    final look = c.game.menu.items.look;
    _trail = _TrailComponent(
      c,
      TierTrail(
        trailId: look.trail,
        random: c.cosmetic,
        lookPainter: paintLookForTrail,
      )..emitter.look = look,
    );
    world.add(_trail!);
    // WP-2d: the banner band lives in the run HUD (viewport, real time).
    _banners = RunHud.ensureFor(c.run).banners;
    c.events
      ..on<HoopSpawned>(_onSpawned)
      ..on<HoopPassed>(_onPassed)
      ..on<MistakeSaved>(_onSaved)
      ..on<RunDied>(_onDied)
      ..on<StreakAtLeast>(_onAtLeast); // WP-3d
    for (final h in c.run.spawner.hoops) {
      _track(h);
    }
  }

  // ---------------------------------------------------------------- events

  void _onSpawned(HoopSpawned e) => _track(e.hoop);

  void _onPassed(HoopPassed e) {
    final c = _c;
    if (c == null) return;
    final s = c.s;
    if (!e.perfect) {
      // PRD-2.2 §11.1 a clean off-centre pass also resets the streak. A
      // graze resets it with no text (PRD-2.3.1 §8).
      if (e.clean) {
        _break(StreakCause.clean);
      } else {
        _break(StreakCause.graze);
      }
      return;
    }
    final old = s.streak;
    // PRD-2.3.1 §15.1 the pass scores max(2, streak) with the ordinary
    // increment, before the FEVER boost below.
    s.pointStreak = old + 1;
    final fever = e.hoop?.plan.kind == HoopKindId.fever;
    final next = fever
        ? math.max(StreakConfig.feverMinStreak, old + 1)
        : old + 1;
    _set(next, fever ? StreakCause.fever : StreakCause.pass);
    final tier = s.tier;
    _banners?.showStreak(s.streak); // PRD-2.2 §29: the streak number
    c.sfx(StreakConfig.tierSounds[math.min(s.streak, 3) - 1]);
    final bird = c.game.runBirdPosition;
    final burst = _burst;
    if (burst != null) {
      final at = bird != null
          ? Offset(bird.x, bird.y)
          : Offset(RunConfig.birdX, c.viewHeight / 2);
      PerfectBurst.emit(burst, at, tier, c.cosmetic);
    }
    c.track('perfect_pass', {'tier': tier});
  }

  // region WP-3d — §3.21 the pair FEVER gift: streak at least ×5
  void _onAtLeast(StreakAtLeast e) {
    final c = _c;
    if (c == null || c.s.streak >= e.value) return;
    _set(e.value, StreakCause.fever);
    _banners?.showStreak(c.s.streak);
  }
  // endregion WP-3d

  void _onSaved(MistakeSaved e) => _break(StreakCause.save);

  void _onDied(RunDied e) => _break(StreakCause.death);

  // ----------------------------------------------------------------- rules

  void _break(StreakCause cause) {
    final c = _c;
    if (c == null) return;
    final old = c.s.streak;
    if (old == 0) return;
    _set(0, cause);
    c.track('streak_broken', {'length': old, 'cause': cause.name});
  }

  void _set(int value, StreakCause cause) {
    final c = _c!;
    final s = c.s;
    final old = s.streak;
    final oldTier = s.tier;
    s.streak = value;
    if (value > s.bestStreak) s.bestStreak = value;
    if (old != value) c.emit(StreakChanged(old, value, cause));
    final newTier = s.tier;
    if (newTier != oldTier) {
      _applyTier(newTier);
      c.emit(TierChanged(oldTier, newTier));
    }
  }

  // ------------------------------------------------------------ ring field

  void _track(Hoop h) {
    final c = _c;
    if (c == null || _hoops.containsKey(h) || !h.kind.usesTierLook) return;
    final fx = [
      for (final _ in h.rings)
        RingTierFx(random: c.cosmetic, opening: h.opening),
    ];
    final entry = _HoopTier(fx, h.look.colors);
    _hoops[h] = entry;
    final back = h.paintBack;
    h.paintBack = (canvas) {
      if (entry.visible) {
        for (var i = 0; i < fx.length; i++) {
          canvas.save();
          canvas.translate(0, h.rings[i]);
          fx[i].paintBack(canvas);
          canvas.restore();
        }
      }
      back?.call(canvas);
    };
    final front = h.front.paintFront;
    h.front.paintFront = (canvas) {
      front?.call(canvas);
      if (!entry.visible) return;
      for (var i = 0; i < fx.length; i++) {
        canvas.save();
        canvas.translate(0, h.rings[i]);
        fx[i].paintFront(canvas);
        canvas.restore();
      }
    };
    _applyHoop(h, entry, tier);
  }

  void _applyTier(int tier) {
    for (final e in _hoops.entries) {
      _applyHoop(e.key, e.value, tier);
    }
    _applyBird(tier);
  }

  void _applyHoop(Hoop h, _HoopTier e, int tier) {
    final t = h.look.missed ? 0 : tier;
    for (final f in e.fx) {
      f
        ..opening = h.opening
        ..tier = t;
    }
    e.visible = !h.look.missed;
    if (h.look.missed) return;
    var want = RingPainter.colorsForTier(t);
    // WP-2d fix: a Big Hoops hoop keeps its gold at every tier (its tier
    // sparkles / glow still play); other owners (miss flash) keep their
    // colours — the streak only overwrites what it wrote itself.
    final bigGold = BigHoopsFeature.isGold(h);
    if (bigGold) want = RingColors.gold;
    if (bigGold || h.look.colors == e.written) {
      h.look.colors = want;
      e.written = want;
    }
  }

  void _applyBird(int tier) {
    final bird = _c?.game.runBird;
    if (bird == null || !bird.isLoaded) return;
    bird.lookComponent.goldTier = tier >= StreakConfig.goldBirdTier;
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    final t = tier;
    _hoops.removeWhere((h, _) => h.isRemoved || h.isRemoving);
    for (final e in _hoops.entries) {
      final h = e.key;
      final entry = e.value;
      if (h.look.missed && entry.visible) _applyHoop(h, entry, t);
      if (!entry.visible) continue;
      for (final f in entry.fx) {
        f.opening = h.opening;
        f.update(gameDt);
      }
    }
    _applyBird(t);
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.events
        ..off<HoopSpawned>(_onSpawned)
        ..off<HoopPassed>(_onPassed)
        ..off<MistakeSaved>(_onSaved)
        ..off<RunDied>(_onDied)
        ..off<StreakAtLeast>(_onAtLeast); // WP-3d
      final bird = c.game.runBird;
      if (bird != null && bird.isLoaded) bird.lookComponent.goldTier = false;
    }
    for (final e in _hoops.values) {
      for (final f in e.fx) {
        f.clear();
      }
    }
    _hoops.clear();
    _burst?.removeFromParent();
    _trail?.removeFromParent();
    _banners?.clear();
    _burst = null;
    _trail = null;
    _banners = null;
    _c = null;
  }
}

class _HoopTier {
  _HoopTier(this.fx, this.written);
  final List<RingTierFx> fx;

  /// The colours the streak wrote last (null = the skin).
  RingColors? written;

  /// False once the hoop was missed (§5.13: its tier look stays off).
  bool visible = true;
}

/// The bird's tier-3+ trail (master #10 / equipped trail via [TierTrail]),
/// in screen space right behind the bird. It also runs during a ride.
class _TrailComponent extends Component with BirdAttachment {
  _TrailComponent(this.c, this.trail)
    : super(priority: StreakConfig.trailPriority);

  final RunContext c;

  @override
  FlappySpikesGame get birdGame => c.game;

  /// The trail already shed stays where it was left (it only stops
  /// emitting while the bird is hidden).
  @override
  bool get hidesWholly => false;
  final TierTrail trail;

  /// Screen-space blocks of the block trail.
  final ParticlePool pool = ParticlePool(capacity: 48);

  bool active = false;

  Vector2? _prevBird;
  double _prevCamX = 0, _prevCamY = 0;

  /// The flight direction for master #10 (radians, 0 = right). Normal
  /// flight: 0 — the camera follows the bird forward, so the trail lies
  /// level behind it and drifts with the world, exactly the §5.3 mock (call:
  /// the vertical flap motion does not tilt it). Rides (comet / portal):
  /// the bird's motion relative to the world (screen motion + camera
  /// motion), so the trail bends with diagonal and curved flight.
  double _heading(Vector2? bird, double dt) {
    final s = c.s;
    final prev = _prevBird;
    final dxCam = s.camX - _prevCamX, dyCam = s.camY - _prevCamY;
    _prevBird = bird?.clone();
    _prevCamX = s.camX;
    _prevCamY = s.camY;
    if (s.ride == null || bird == null || prev == null || dt <= 0) return 0;
    final vx = bird.x - prev.x + dxCam;
    final vy = bird.y - prev.y + dyCam;
    if (vx * vx + vy * vy < 1e-6) return 0;
    return math.atan2(vy, vx);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final s = c.s;
    final bird = c.game.runBirdPosition;
    final live = !c.run.dying && !c.run.ended;
    active =
        live &&
        bird != null &&
        (s.tier >= StreakConfig.trailTier || s.ride != null) &&
        // region WP-3b — no trail while a ride hides the bird (§3.12)
        !(s.ride?.birdHidden ?? false) &&
        // Audit HIDE: nor while anything else hides the bird.
        birdPresented;
    // endregion WP-3b
    final vx = s.forwardSpeed;
    final heading = _heading(bird, dt);
    trail.update(
      pool,
      dt,
      bird == null ? Offset.zero : Offset(bird.x, bird.y),
      heading,
      active: active,
      scrollVx: -vx,
    );
    pool.step(dt);
  }

  @override
  void render(Canvas canvas) {
    pool.paint(canvas);
    trail.paint(canvas);
  }

  @override
  void onRemove() {
    trail.clear();
    pool.clear();
    super.onRemove();
  }
}
