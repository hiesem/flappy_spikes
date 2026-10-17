import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../../game/flappy_game.dart' show FlappySpikesGame, GameState;
import '../../game/sound.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/look.dart';
import '../config/egg_config.dart';
import '../config/tuning_values.dart';
import '../elements.dart';
import '../effects/bird_attachment.dart';
import '../effects/collect_fx.dart';
import '../effects/particle_pool.dart';
import '../effects/text_pop.dart';
import '../hud/banners.dart';
import '../hud/run_badges.dart';
import '../hud/run_hud.dart';
import '../mistakes.dart';
import '../pickups/egg_pickup.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_layers.dart';
import '../run_state.dart';

/// The egg and the ×2 chick (PRD-2 §3.27, §5.26).
///
/// Picking the egg up puts it on the bird's back ("EGG! hatches in 5
/// rings"); every ring passed — not ride rings (PRD-2.2 §23) — cracks it (countdown
/// 4…1, a wobble), and after 5 it hatches into a `golden` chick that flies
/// behind the bird. PRD-2.3 §14.3: while the chick is alive every hoop
/// passed scores +1 point (`ScoringFeature.chickBonus`); it no longer
/// doubles coins or other points. A rim touch while
/// still an egg breaks it quietly (PRD-2.2 §23); after hatching it scares
/// the chick away ("bye!", "+1 LOST"); a crash (death or a shield / extra
/// life save) loses the egg or chick silently, and a death that brings up
/// the revive offer loses it even if the player revives (the WP-2d
/// `ReviveRulesFeature` clears `RunState.egg`).
class EggFeature extends RunFeature {
  RunContext? _c;
  EggView? _view;
  CollectBursts? _bursts;
  EggBadge? _badge;

  /// PRD-2.3 §14.8 points the chick added (the analytics `chick_lost
  /// {points_added}`; was `coins_doubled`).
  int pointsAdded = 0;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<PickupCollected>(_onCollected)
      ..on<HoopPassed>(_onPassed)
      ..on<RimTouched>(_onRim)
      ..on<MistakeSaved>(_onSaved)
      ..on<RunDied>(_onDied);
    _view = EggView(c);
    c.game.world.add(_view!);
    _bursts = CollectBursts();
    c.game.world.add(_bursts!);
  }

  void _onCollected(PickupCollected e) {
    final c = _c;
    if (c == null || e.element != ElementId.egg) return;
    c.s.egg = EggState();
    _view?.reset();
    c.sfx(Sfx.eggPickup);
    c.track('egg_collected');
    final at = _atBird(
      c,
      EggConfig.popDx,
      EggConfig.popDy,
    );
    if (at != null) {
      c.layers.fx.add(
        TextPop(
          EggConfig.pickupPop,
          at,
          EggConfig.popColor,
          fontSize: EggConfig.popSize,
        ),
      );
    }
  }

  void _onPassed(HoopPassed e) {
    final c = _c;
    if (c == null) return;
    final egg = c.s.egg;
    if (egg?.stage == EggStage.chick) {
      // PRD-2.3 §14.3 the chick's +1 per hoop (added with the pass by
      // `ScoringFeature`; counted here for `chick_lost`).
      pointsAdded += TuningValues.current.i('point_chick');
      return;
    }
    if (egg == null || egg.stage != EggStage.egg) return;
    // PRD-2.2 §23 ride rings (portal and comet) no longer crack the egg;
    // the hoop whose rim broke an egg never cracks the next one.
    if (e.duringRide || c.s.ride != null) return;
    if (e.hoop != null && identical(e.hoop, _brokenOn)) return;
    egg.cracks++;
    _view?.wob = EggConfig.wobbleSeconds;
    c.sfx(Sfx.eggCrack);
    if (egg.cracks >= EggConfig.rings) {
      _hatch(c);
      return;
    }
    final at = _atBird(c, 0, EggConfig.countdownDy);
    if (at != null) {
      c.layers.fx.add(
        TextPop(
          '${EggConfig.rings - egg.cracks}',
          at,
          EggConfig.popColor,
          fontSize: EggConfig.countdownSize,
        ),
      );
    }
  }

  void _hatch(RunContext c) {
    final egg = c.s.egg!;
    egg.stage = EggStage.chick;
    _view?.hatched();
    c.sfx(Sfx.eggHatch);
    c.track('egg_hatched');
    c.emit(const EggHatched()); // PRD-2.3.1 §12.2
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(
        EggConfig.hatchText,
        color: EggConfig.gold,
        subtitle: EggConfig.hatchSub,
      ),
    );
    _mountBadge(c);
    final bird = c.game.runBirdPosition;
    if (bird != null) {
      _bursts?.burst(
        at: Offset(bird.x, bird.y + EggConfig.countdownDy),
        colors: EggConfig.hatchColors,
        pieces: EggConfig.hatchPieces,
        speed: EggConfig.hatchSpeed,
        shape: ParticleShape.triangle,
      );
    }
  }

  /// PRD-2.2 §23 the hoop whose rim broke the egg (it does not crack).
  Object? _brokenOn;

  /// Eggs broken on a rim this run (tests / debug).
  int broken = 0;

  /// The egg / chick view (tests).
  EggView? get view => _view;

  /// The shell / burst particles (tests).
  CollectBursts? get bursts => _bursts;

  void _onRim(RimTouched e) {
    final c = _c;
    if (c == null) return;
    if (c.s.egg?.stage == EggStage.egg) {
      // Rides ignore rims; a ride ring never breaks the egg (§23).
      if (c.s.ride == null) _break(c, e.hoop);
      return;
    }
    if (c.s.egg?.stage != EggStage.chick) return;
    final screen = c.geo.toScreen(e.point);
    _bursts?.burst(
      at: Offset(screen.x, screen.y),
      colors: const [Color(0xFFFFFFFF), Color(0xFFFFD54A)],
      pieces: 10,
      speed: 140,
    );
    _lose(c, 'rim');
  }

  /// PRD-2.2 §23 any rim touch while still an egg breaks it, quietly: the
  /// shell pieces (the hatch's shell triangles + a few yolk pieces) fall
  /// away from the bird's back with `egg_crack`; no banner, no other sound.
  void _break(RunContext c, Object hoop) {
    final egg = c.s.egg;
    if (egg == null) return;
    final cracks = egg.cracks;
    c.s.egg = null;
    _brokenOn = hoop;
    broken++;
    _dropBadge();
    _view?.reset();
    c.sfx(Sfx.eggCrack);
    c.track('egg_broken', {'cause': 'rim', 'cracks': cracks});
    final bird = c.game.runBirdPosition;
    if (bird != null) {
      _bursts?.burst(
        at: Offset(bird.x + EggConfig.onBirdDx, bird.y + EggConfig.onBirdDy),
        colors: EggConfig.breakColors,
        pieces: EggConfig.breakPieces,
        speed: EggConfig.breakSpeed,
        shape: ParticleShape.triangle,
        gravity: EggConfig.breakGravity,
        life: EggConfig.breakLife,
      );
    }
  }

  void _onSaved(MistakeSaved e) => _lose(_c, 'crash', saved: true);

  void _onDied(RunDied e) => _lose(_c, 'crash');

  /// Drops the egg / chick. [cause] is the analytics `chick_lost` cause
  /// (`rim` / `crash`); a rim touch also shows the "×2 LOST" banner. An
  /// unhatched egg lost to a crash or a save ([saved]) tracks `egg_lost
  /// {cause: crash | save}` (ARCH §25, audit A4-8).
  void _lose(RunContext? c, String cause, {bool saved = false}) {
    if (c == null) return;
    final egg = c.s.egg;
    if (egg == null) return;
    final chick = egg.stage == EggStage.chick;
    c.s.egg = null;
    _dropBadge();
    if (!chick) {
      _view?.reset();
      c.track('egg_lost', {'cause': saved ? 'save' : cause});
      return;
    }
    c.track('chick_lost', {'cause': cause, 'points_added': pointsAdded});
    // Audit A4-5 (SPEC WP-3e): only a rim touch scares the chick away with
    // "bye!"; a crash or a save loses it silently.
    if (cause != 'rim') {
      _view?.reset();
      return;
    }
    _view?.leave();
    c.sfx(Sfx.eggBye);
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(
        EggConfig.lostText,
        color: EggConfig.lostGrey,
        subtitle: EggConfig.lostSub,
      ),
    );
  }

  /// The track position [dx] right, [dy] up of the bird (for the pops).
  Vector2? _atBird(RunContext c, double dx, double dy) {
    final bird = c.run.birdTrackPosition();
    if (bird == null) return null;
    return Vector2(bird.x + dx, bird.y + dy);
  }

  void _mountBadge(RunContext c) {
    _dropBadge();
    _badge = EggBadge(c.run);
    RunHud.ensureFor(c.run).add(_badge!);
  }

  void _dropBadge() {
    _badge?.removeFromParent();
    _badge = null;
  }

  @override
  void onDeath(Mistake m) {
    _dropBadge();
    _view?.reset();
  }

  @override
  void detach() {
    final c = _c;
    c?.events
      ?..off<PickupCollected>(_onCollected)
      ..off<HoopPassed>(_onPassed)
      ..off<RimTouched>(_onRim)
      ..off<MistakeSaved>(_onSaved)
      ..off<RunDied>(_onDied);
    _dropBadge();
    _view?.removeFromParent();
    _bursts?.removeFromParent();
    _view = null;
    _bursts = null;
    _c = null;
  }
}

/// The egg on the bird's back and the chick behind it (§5.26), in screen
/// space just behind the bird (`RunLayer.bird − 1`). Reads `RunState.egg`,
/// so it draws nothing while no egg / chick runs; the feature drives the
/// wobble and the departure. Audit HIDE: the egg and the following chick
/// are worn on the bird ([BirdAttachment]) — not drawn while the bird is
/// hidden (cannon barrel, volcano, rocket, Black Hole, phoenix); a chick
/// that already left keeps flying away.
class EggView extends Component with BirdAttachment {
  EggView(this.c) : super(priority: RunLayer.bird - 1);

  final RunContext c;

  @override
  FlappySpikesGame get birdGame => c.game;

  /// The departing chick is no longer on the bird.
  @override
  bool get hidesWholly => false;

  /// Audit HIDE: whether [render] draws the egg on the bird's back now.
  bool get paintsEgg =>
      c.s.egg?.stage == EggStage.egg &&
      c.game.runBirdPosition != null &&
      birdPresented;

  /// Audit HIDE: whether [render] draws the following chick now.
  bool get paintsChick =>
      c.s.egg?.stage == EggStage.chick &&
      !leaving &&
      c.game.runBirdPosition != null &&
      birdPresented;

  /// Wobble time left (s), set on each crack.
  double wob = 0;

  double _t = 0;
  double _peep = EggConfig.peepEvery;
  bool _chickInit = false;
  double _chickX = 0, _chickY = 0;

  bool leaving = false;
  double _leaveT = 0;
  double _leaveX = 0, _leaveY = 0;

  late final TextPainter _bye = TextPainter(
    text: const TextSpan(
      text: EggConfig.byeText,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: EggConfig.byeSize,
        color: EggConfig.popColor,
      ),
    ),
    textDirection: p.TextDirection.ltr,
  )..layout();

  /// A new egg was grabbed: forget the old chick's follow / departure.
  void reset() {
    _chickInit = false;
    wob = 0;
    leaving = false;
    _leaveT = 0;
  }

  /// The egg hatched: the chick starts at the bird's back.
  void hatched() => _chickInit = false;

  /// The chick was scared away: it flies up and right for 1.6 s.
  void leave() {
    if (leaving) return;
    leaving = true;
    _leaveT = 0;
    _leaveX = _chickX;
    _leaveY = _chickY;
  }

  @override
  void update(double dt) {
    _t += dt;
    if (wob > 0) wob = math.max(0, wob - dt);
    final bird = c.game.runBirdPosition;
    final egg = c.s.egg;
    if (bird != null && egg != null && egg.stage == EggStage.chick) {
      if (!_chickInit) {
        _chickInit = true;
        _chickX = bird.x - 10;
        _chickY = bird.y - 18;
      }
      final tx = bird.x - EggConfig.chickBehind;
      final ty = bird.y +
          EggConfig.chickBelow +
          math.sin(_t * EggConfig.chickBobOmega) * EggConfig.chickBobAmp;
      _chickX += (tx - _chickX) * math.min(1, dt * EggConfig.chickLagX);
      _chickY += (ty - _chickY) * math.min(1, dt * EggConfig.chickLagY);
      // PRD-2.2 §28.1 / §28.2: the chick only peeps while the run is live
      // (never after a death, in pause or under a full-screen ad).
      final live =
          c.game.state == GameState.playing &&
          !c.run.dying &&
          !c.run.ended &&
          !c.game.liveMotionPaused;
      if (live) _peep -= dt;
      if (live && _peep <= 0) {
        _peep = EggConfig.peepEvery * (.6 + c.cosmetic.nextDouble() * .8);
        c.sfx(Sfx.eggPeep);
      }
    } else {
      _chickInit = false;
    }
    if (leaving) {
      _leaveT += dt;
      _leaveX += EggConfig.byeOutX * dt;
      _leaveY -= EggConfig.byeOutY * dt;
      if (_leaveT >= EggConfig.byeSeconds) leaving = false;
    }
  }

  @override
  void render(Canvas canvas) {
    final bird = c.game.runBirdPosition;
    if (bird == null) return;
    final egg = c.s.egg;
    final worn = birdPresented;
    if (worn && egg != null && egg.stage == EggStage.egg) {
      canvas.save();
      canvas.translate(
        bird.x + EggConfig.onBirdDx,
        bird.y + EggConfig.onBirdDy,
      );
      canvas.rotate(math.sin(wob * EggConfig.wobbleOmega) * EggConfig.wobbleAmp);
      EggArt.paint(canvas, Offset.zero, cracks: egg.cracks);
      canvas.restore();
    }
    if (worn && egg != null && egg.stage == EggStage.chick && !leaving) {
      _paintChick(canvas, _chickX, _chickY, _t);
    }
    if (leaving) {
      _paintChick(canvas, _leaveX, _leaveY, _leaveT);
      _bye.paint(
        canvas,
        Offset(
          _leaveX - _bye.width / 2,
          _leaveY - EggConfig.byeDy.abs() - _bye.height / 2,
        ),
      );
    }
  }

  void _paintChick(Canvas canvas, double x, double y, double clock) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(EggConfig.chickScale * Config.lookScale);
    LookPainter.paint(
      canvas,
      const Look(bird: 'golden'),
      t: clock * EggConfig.chickArtRate,
      flap: math.sin(clock * EggConfig.chickFlapOmega) > 0,
    );
    canvas.restore();
  }
}
