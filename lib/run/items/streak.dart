import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../components/skins/item_art.dart' show paintLookForTrail;
import '../../game/flappy_game.dart';
import '../config/run_config.dart';
import '../config/streak_config.dart';
import '../config/trail_config.dart';
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
import '../run_scaled_world.dart';

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
/// burst #9 at the bird ([PerfectBurst], screen space like the §5.3 mock).
/// PRD-2.6 WP-A: there is no per-pass `perfect_pass` event; the analytics
/// router counts the tiers per run for `run_extra`. The "+2 coin" popup #8
/// and the coins belong to `ScoringFeature`; a graze keeps `point` + the
/// ring pulse there. **No screen flash** (#13).
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
    world.addRun(_burst!);
    final look = c.game.menu.items.look;
    _trail = _TrailComponent(
      c,
      TierTrail(
        trailId: look.trail,
        random: c.cosmetic,
        lookPainter: paintLookForTrail,
      )..emitter.look = look,
    );
    world.addRun(_trail!);
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
///
/// WP-TRAIL (owner 2026-10-18): the trail lies along the bird's real path.
/// Each frame everything already drawn moves with the world on screen (the
/// camera's motion, ride camera included: climbs, loops, the launch
/// flight), and the trail is emitted at the point [TrailConfig.runBack]
/// back along the bird's own recent path (its centre path, sampled every
/// [TrailConfig.pathStep] pt), in the path's direction. So the trail
/// follows the bird like a snake follows its head.
///
/// Hide rule (Audit HIDE + WP-TRAIL): while the bird is drawn the trail is
/// connected to it, with its drawn scale and opacity; when the bird is
/// hidden the trail detaches (shed parts stay and fade in place); when it
/// is back a fresh trail starts from it.
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

  /// Whether the trail was switched on last frame (streak tier / ride, run
  /// live), regardless of the bird being hidden.
  bool _wasOn = false;

  /// Whether the bird was drawn last frame.
  bool _wasShown = false;

  bool _hasCam = false;
  double _prevCamX = 0, _prevCamY = 0;

  /// The bird's recent centre path (screen, moved with the world), newest
  /// at [_pHead]; a ring of [_pathCap] points [TrailConfig.pathStep] apart.
  static const int _pathCap = 48;
  final Float64List _px = Float64List(_pathCap);
  final Float64List _py = Float64List(_pathCap);
  int _pHead = 0, _pCount = 0;

  /// The flight direction last frame (rad), kept while the bird stands.
  double _heading = 0;

  /// The emission point and heading this frame (tests).
  Offset tail = Offset.zero;
  double get heading => _heading;

  /// The world's motion on screen this frame: minus the camera's move;
  /// a cut (a jump no motion could make) moves nothing.
  (double, double) _worldShift(double dt) {
    final s = c.s;
    final dx = s.camX - _prevCamX, dy = s.camY - _prevCamY;
    final had = _hasCam;
    _hasCam = true;
    _prevCamX = s.camX;
    _prevCamY = s.camY;
    if (!had) return (0, 0);
    final limit = TrailConfig.cutSlack + TrailConfig.maxWorldSpeed * dt;
    if (dx * dx + dy * dy > limit * limit) return (0, 0);
    return (-dx, -dy);
  }

  int _pi(int i) => (_pHead - i + _pathCap) % _pathCap;

  void _record(double x, double y) {
    if (_pCount > 0) {
      final h = _pHead;
      final ddx = x - _px[h], ddy = y - _py[h];
      if (ddx * ddx + ddy * ddy < TrailConfig.pathStep * TrailConfig.pathStep) {
        return;
      }
    }
    _pHead = (_pHead + 1) % _pathCap;
    _px[_pHead] = x;
    _py[_pHead] = y;
    if (_pCount < _pathCap) _pCount++;
  }

  /// The point [back] pt back along the centre path from ([bx], [by]) and
  /// the path direction there; with too little path, the oldest point (a
  /// fresh trail starts at the bird).
  Offset _tailOf(double bx, double by, double back) {
    var x0 = bx, y0 = by;
    var left = back;
    for (var i = 0; i < _pCount; i++) {
      final h = _pi(i);
      final x1 = _px[h], y1 = _py[h];
      final dx = x0 - x1, dy = y0 - y1;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d >= left && d > 1e-9) {
        final t = left / d;
        final tx = x0 - dx * t, ty = y0 - dy * t;
        _heading = math.atan2(by - ty, bx - tx);
        return Offset(tx, ty);
      }
      left -= d;
      x0 = x1;
      y0 = y1;
    }
    final dx = bx - x0, dy = by - y0;
    if (dx * dx + dy * dy > 1) _heading = math.atan2(dy, dx);
    return Offset(x0, y0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final s = c.s;
    final bird = c.game.runBirdPosition;
    final live = !c.run.dying && !c.run.ended;
    final on =
        live &&
        bird != null &&
        (s.tier >= StreakConfig.trailTier || s.ride != null);
    // Audit HIDE: the bird hidden by a ride or anything else.
    final shown = birdPresented && !(s.ride?.birdHidden ?? false);
    active = on && shown;
    // The world's motion: everything shed stays where the bird was.
    final (wx, wy) = _worldShift(dt);
    trail.shift(pool, wx, wy);
    for (var i = 0; i < _pCount; i++) {
      final h = _pi(i);
      _px[h] += wx;
      _py[h] += wy;
    }
    // The bird's centre path (fresh when it reappears).
    if (shown && !_wasShown) _pCount = 0;
    final b = c.game.runBird;
    final scale = b?.drawnScale ?? 1;
    if (shown && bird != null) _record(bird.x, bird.y);
    if (bird != null) {
      tail = _tailOf(bird.x, bird.y, TrailConfig.runBack * scale);
    }
    // Audit A2-1: switched off (streak break, death): no frozen stripe.
    if (_wasOn && !on) trail.dropPath();
    // WP-TRAIL: the bird hidden while the trail is on: shed and fade.
    if (on && !shown && _wasShown) trail.detach();
    _wasOn = on;
    _wasShown = shown;
    // The bird's opacity, except the invulnerability blink (the trail
    // does not blink).
    final opacity = s.invulnerable > 0 ? 1.0 : (b?.drawnOpacity ?? 1);
    trail.update(
      pool,
      dt,
      bird == null ? Offset.zero : Offset(bird.x, bird.y),
      _heading,
      active: active,
      tail: bird == null ? null : tail,
      scale: scale,
      opacity: opacity,
      angle: b != null && b.isLoaded ? b.body.angle : 0,
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
