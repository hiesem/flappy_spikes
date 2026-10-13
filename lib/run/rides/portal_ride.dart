import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../components/score_hud.dart';
import '../../components/spike_strip.dart';
import '../../game/sound.dart';
import '../config/portal_config.dart';
import '../config/run_config.dart';
import '../director/plans.dart';
import '../hoops/hoop.dart';
import '../hoops/kinds/portal.dart';
import '../hoops/kinds/registry.dart';
import '../hud/banners.dart';
import '../hud/run_hud.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';
import 'ride.dart';
import 'ride_path.dart';
import 'ride_theme.dart';
import 'speed_lines.dart';
import 'themes/storm.dart';
import 'themes/themes.dart';
import '../../game/paints.dart';

/// A ride's chain before it starts: theme, path, ring stations and the
/// preview of the first curve ring (§3.12 "the next chain ring is already
/// visible ahead").
class _Chain {
  _Chain(this.theme, this.path, this.stations);
  final RideTheme theme;
  final RidePath path;
  final List<double> stations;
  Hoop? preview;
}

/// Hosts the portal roller-coaster in a run (PRD-2 §3.12, §5.12b, §7):
/// on a portal's spawn it prepares the chain (theme from `SlotPlan.extra`,
/// path, the first ring shown ahead), on the portal pass it plays
/// `pu_portal` and starts one [PortalRide], and it drives the ride every
/// frame until the bird is home.
class PortalRideFeature extends RunFeature {
  RunContext? _c;
  final Map<Hoop, _Chain> _chains = {};
  Hoop? _pending;
  double _sparkAcc = 0;

  /// The running ride (null in normal play).
  PortalRide? ride;

  /// Every ride started this run (tests, debug).
  final List<RideId> started = [];

  /// The prepared chain of a portal hoop (tests).
  Hoop? previewOf(Hoop portal) => _chains[portal]?.preview;

  @override
  void attach(RunContext c) {
    _c = c;
    for (final s in c.game.world.children.whereType<SpikeStrip>()) {
      s.rideShift = 0;
    }
    c.events
      ..on<HoopSpawned>(_onSpawned)
      ..on<HoopPassed>(_onPassed);
  }

  void _onSpawned(HoopSpawned e) {
    final c = _c;
    if (c == null || e.plan.kind != HoopKindId.portal) return;
    final id = e.plan.extra is RideId ? e.plan.extra! as RideId : RideId.cannon;
    final theme = rideThemeFor(id);
    final path = theme.buildPath();
    final chain = _Chain(theme, path, theme.ringStations(path));
    _chains[e.hoop] = chain;
    chain.preview = PortalRide.buildRing(c, e.hoop, chain.path, chain.stations[0]);
    PortalRide.addRing(c, chain.preview!);
  }

  void _onPassed(HoopPassed e) {
    final h = e.hoop;
    final c = _c;
    if (c == null || h == null || h.plan.kind != HoopKindId.portal) return;
    if (ride != null || e.duringRide) return;
    // §3.12 the portal pass: banner, +2, tier sound (streak / scoring) and
    // the portal sound; the ride starts on the next frame.
    c.sfx(Sfx.puPortal);
    _pending = h;
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    final p = _pending;
    if (p != null && ride == null) {
      _pending = null;
      final chain = _chains.remove(p) ?? _chainFor(p);
      final r = PortalRide(
        c,
        p,
        theme: chain.theme,
        path: chain.path,
        stations: chain.stations,
        firstRing: chain.preview,
      );
      ride = r;
      started.add(r.theme.id);
      r.start(c);
    }
    final r = ride;
    if (r != null) {
      r.update(gameDt);
      if (r.done) ride = null;
    }
    _sparkle(c, gameDt);
    _tidy(c);
  }

  _Chain _chainFor(Hoop portal) {
    final id = portal.plan.extra is RideId
        ? portal.plan.extra! as RideId
        : RideId.cannon;
    final theme = rideThemeFor(id);
    final path = theme.buildPath();
    return _Chain(theme, path, theme.ringStations(path));
  }

  /// §3.12 cyan sparkles drift off portals that wait ahead.
  void _sparkle(RunContext c, double dt) {
    if (_chains.isEmpty || dt <= 0) return;
    _sparkAcc += dt * PortalConfig.portalSparkles;
    while (_sparkAcc >= 1) {
      _sparkAcc--;
      for (final h in _chains.keys) {
        if (h.resolved) continue;
        final r = c.cosmetic;
        c.run.particles.spawn(
          x: h.planeX - 40 + (r.nextDouble() * 30 - 20),
          y: h.position.y + (r.nextDouble() * 100 - 50),
          vx: -(30 + r.nextDouble() * 60) / .5,
          w: 6,
          color: r.nextBool() ? PortalConfig.portalCyan : const Color(0xFFFFFFFF),
          life: .5,
        );
      }
    }
  }

  /// Portals that left without a ride (missed, culled) drop their preview.
  void _tidy(RunContext c) {
    _chains.removeWhere((h, chain) {
      final gone =
          h.isRemoved ||
          (h.resolved && h.takenRing == null) ||
          h.planeX + 200 < c.s.camX;
      if (gone) chain.preview?.removeFromRun();
      return gone;
    });
  }

  @override
  void detach() {
    ride?.abort();
    ride = null;
    for (final chain in _chains.values) {
      chain.preview?.removeFromRun();
    }
    _chains.clear();
    final c = _c;
    if (c != null) {
      c.events
        ..off<HoopSpawned>(_onSpawned)
        ..off<HoopPassed>(_onPassed);
    }
    _c = null;
  }
}

/// A screen-space paint layer of the ride in the run world.
class _RideLayer extends Component {
  _RideLayer(this.painter, {required super.priority});
  final void Function(Canvas c) painter;

  @override
  void render(Canvas canvas) => painter(canvas);
}

/// The portal ride engine (PRD-2 §3.12, §5.12b, §7; `rides84.js`): one
/// engine for the cannon and the five themed rides. Path from arc / line
/// segments or a sampled curve, [PortalConfig.rideRings] rings at equal arc length (+ the
/// portal = 6 passes), the ride camera starting at the live scroll speed, then
/// the theme's exit moment → launch flight (560 / −640 pt/s, g 520, 1.7 s)
/// → glide home (2.5 s + 0.6 s settle). Input is ignored and the run cannot
/// end while it runs; the run clock keeps running.
///
/// PRD-2.2 §18: the score circle and the banners sit inside the scene
/// (between its backdrop and its objects) at 50 % in the scene's colours,
/// and crossfade back to the normal look over the launch flight, drawn
/// above the wash; control returns with one automatic flap; the first ring
/// reaches the bird 2 s after control returns.
class PortalRide implements Ride {
  PortalRide(
    this.c,
    this.portal, {
    required this.theme,
    required this.path,
    required this.stations,
    this.firstRing,
  }) : view = RideView(
         path: path,
         h: c.viewHeight,
         rnd: c.cosmetic,
         cue: (_) {},
       );

  final RunContext c;
  final Hoop portal;
  final RideTheme theme;
  final RidePath path;
  final List<double> stations;
  final RideView view;
  final Hoop? firstRing;

  late final List<Hoop> rings;
  final Set<int> _added = {};
  final Set<int> _passed = {};

  /// Passes made by the ride (the [PortalConfig.rideRings] ride rings).
  int get ringsPassed => _passed.length;

  @override
  RideKind get kind => RideKind.portal;

  @override
  RideId get rideId => theme.id;

  bool _done = false;
  @override
  bool get done => _done;

  RidePhase get phase => view.phase;

  /// The bird's speed along the path (pt/s).
  double get speed => _speed;

  /// Where the bird is drawn now (screen).
  BirdPose get pose => _pose;

  /// The launch point of the flight (screen).
  Offset get launch => _flyLaunch;

  /// The teeth's extra scroll (pt).
  double get teethShift => _spOff;

  late final Vector2 _origin;
  late Offset _join;
  late Offset _entry;
  late double _v0;
  double _speed = 0;
  Offset _camEndTrack = Offset.zero;
  late double _glideCamX;
  double _prevCamX = 0;
  Offset _flyLaunch = Offset.zero;
  Offset _offEnd = Offset.zero;
  double _flyAngle = 0;
  Offset _glideFrom = Offset.zero;
  bool _landed = false;
  double _spOff = 0, _spV = 0;
  double _umbrella = 0;
  BirdPose _pose = const BirdPose(Offset.zero);

  final CannonSpeedLines cannonLines = CannonSpeedLines();
  final RideSpeedLines rideLines = RideSpeedLines();
  final List<_RideLayer> _layers = [];
  List<SpikeStrip> _strips = const [];

  // region WP-G3 — the circle and banners in the scene (PRD-2.2 §18.1)
  ScoreHud? _hud;
  int _hudPriority = -100;
  BannerHost? _banners;
  _RideLayer? _bannerLayer;

  /// PRD-2.2 §18.1 how far the circle / banners show the scene look now
  /// (ride: the world's fade-in; exit: 1; flight: 1 → 0; glide: 0).
  double get sceneMix => switch (view.phase) {
    RidePhase.ride => view.envA,
    RidePhase.exit => 1.0,
    RidePhase.fly =>
      1 - sm(view.ft / (PortalConfig.flyTime - PortalConfig.flyEndEarly)),
    _ => 0.0,
  };

  /// PRD-2.2 §18.1 the banners' opacity now (50 % in the scene).
  double get bannerOpacity =>
      1 - (1 - PortalConfig.sceneCircleOpacity) * sceneMix;

  /// The scene layers (tests): backdrop, banner, objects.
  Component? get backdropLayer => _layers.isEmpty ? null : _layers[0];
  Component? get bannerLayer => _bannerLayer;
  Component? get objectsLayer => _layers.length < 3 ? null : _layers[2];
  // endregion WP-G3

  bool get _cannon => theme.id == RideId.cannon;

  // ------------------------------------------------------------ the chain

  /// A ride ring at arc length [s] of [path] from [portal]'s centre.
  static Hoop buildRing(RunContext c, Hoop portal, RidePath path, double s) {
    final p = path.at(s);
    final h = path.headingAt(s);
    final plan = SlotPlan(
      index: portal.plan.index,
      kind: HoopKindId.rideRing,
      element: HoopKindId.rideRing.element,
      trackX: portal.planeX + p.x,
      centreY: portal.position.y + p.y,
      opening: PortalConfig.ringOpening,
      tiltDeg: h * 180 / math.pi,
      advance: 0,
      duringRide: true,
    );
    final kind = hoopKindFor(HoopKindId.rideRing) ?? RideRingKind();
    final hoop = Hoop(plan: plan, kind: kind);
    kind.onSpawn(hoop, c.run.ctx);
    kind.buildVisual(hoop, c.run.ctx);
    return hoop;
  }

  /// Shows [ring] (track layers) and announces it (tier look, §3.5).
  static void addRing(RunContext c, Hoop ring) {
    c.layers.back.add(ring);
    c.layers.front.add(ring.front);
    c.emit(HoopSpawned(ring, ring.plan));
  }

  // ------------------------------------------------------------- start

  @override
  void start(RunContext _) {
    final s = c.s;
    final game = c.game;
    _origin = Vector2(portal.planeX, portal.position.y);
    final bird = game.runBirdPosition ??
        Vector2(RunConfig.birdX, c.viewHeight / 2);
    _entry = Offset(bird.x, bird.y);
    final birdTrack = c.geo.toTrack(bird);
    _join = Offset(birdTrack.x - _origin.x, birdTrack.y - _origin.y);
    _v0 = math.max(0, s.forwardSpeed);
    _speed = _v0;
    _prevCamX = s.camX;
    view
      ..bird = _entry
      ..lastRot = 0;
    view.cue = _playCue;
    theme.init(view);

    final first = firstRing;
    rings = [
      for (var i = 0; i < stations.length; i++)
        i == 0 && first != null ? first : buildRing(c, portal, path, stations[i]),
    ];
    if (firstRing != null) _added.add(0);

    s.ride = RideState(kind: RideKind.portal, rideId: theme.id, phase: 'ride');
    c.run.rideHold = true;
    c.run.spawner
      ..hold = true
      ..clearAhead(fade: PortalConfig.clearFade);
    c.director.onRideStart(RideKind.portal);
    final timed = s.timed;
    if (timed != null && !timed.paused) {
      timed.paused = true;
      c.emit(PowerupPaused(timed.type));
    }
    game.runBird?.beginRide();
    _strips = game.world.children.whereType<SpikeStrip>().toList();
    for (final st in _strips) {
      _spOff = st.rideShift;
    }
    final world = game.world;
    // PRD-2.2 §18.1 the circle and the banners move into the scene.
    final hud = game.scoreHud;
    _hud = hud;
    _hudPriority = hud.priority;
    _banners = RunHud.of(c.run)?.banners?..drawnByScene = true;
    _bannerLayer = _RideLayer(
      _paintSceneBanners,
      priority: PortalConfig.sceneBannerPriority,
    );
    for (final l in [
      _RideLayer(_paintBackdrop, priority: PortalConfig.backdropPriority),
      _bannerLayer!,
      _RideLayer(_paintWorld, priority: PortalConfig.worldPriority),
      _RideLayer(_paintUnder, priority: PortalConfig.underBirdPriority),
      _RideLayer(_paintFront, priority: PortalConfig.frontPriority),
      _RideLayer(_paintFx, priority: PortalConfig.fxPriority),
    ]) {
      _layers.add(l);
      world.add(l);
    }
    c.emit(RideStarted(RideKind.portal, theme.id));
    c.track('portal_entered', {'ride': theme.id.storageId});
    game.storage.saveLastPortalRide(theme.id.storageId);
    _stepRide(0);
    _applySceneLook();
  }

  /// PRD-2.2 §18.1 the circle's look and layer, the banners' opacity and
  /// layer for this frame.
  void _applySceneLook() {
    final hud = _hud;
    if (hud == null) return;
    hud.setSceneLook(
      circle: theme.circleColor,
      digits: theme.circleDigits,
      mix: sceneMix,
      alpha: PortalConfig.sceneCircleOpacity,
    );
    final over =
        view.phase == RidePhase.fly || view.phase == RidePhase.glide;
    final hp = over ? PortalConfig.circleOverWashPriority : _hudPriority;
    if (hud.priority != hp) hud.priority = hp;
    final bl = _bannerLayer;
    final bp = over
        ? PortalConfig.bannerOverWashPriority
        : PortalConfig.sceneBannerPriority;
    if (bl != null && bl.priority != bp) bl.priority = bp;
  }

  /// PRD-2.2 §18.1 the circle and the banners go back to normal.
  void _restoreScene() {
    final hud = _hud;
    if (hud != null) {
      hud.clearSceneLook();
      if (hud.priority != _hudPriority) hud.priority = _hudPriority;
    }
    _hud = null;
    _banners?.drawnByScene = false;
    _banners = null;
  }

  void _paintSceneBanners(Canvas canvas) {
    final b = _banners;
    final hud = RunHud.of(c.run);
    if (b == null || (hud?.hidden ?? false)) return;
    // PRD-2.2 §12.2: the bands fade with the HUD row here as in the world.
    b.renderInScene(canvas, bannerOpacity * (hud?.rowOpacity ?? 1));
  }

  void _playCue(RideCue cue) {
    final sfx = theme.sounds[cue];
    if (sfx != null) c.sfx(sfx);
  }

  // ------------------------------------------------------------- update

  @override
  void update(double dt) {
    if (_done) return;
    view.t += dt;
    switch (view.phase) {
      case RidePhase.ride:
        _stepRide(dt);
      case RidePhase.exit:
        _stepExit(dt);
      case RidePhase.fly:
        _stepFly(dt);
      case RidePhase.glide:
        _stepGlide(dt);
      case RidePhase.done:
        break;
    }
    if (_done) return;
    c.s.ride?.phase = view.phase.name;
    theme.tick(view, dt);
    view.screen.step(dt);
    view.scenePool.step(dt);
    view.stepBlobs(dt);
    if (_cannon) {
      cannonLines.update(dt, view);
    } else {
      rideLines.update(dt, view, path.headingAt(view.s));
    }
    // Spike teeth scroll (decaying, §3.12 return).
    if (_spV > 4) {
      _spOff -= _spV * dt;
      _spV *= math.exp(-dt * PortalConfig.teethDecay);
    }
    final stripA = switch (view.phase) {
      RidePhase.ride => 1 - sm(view.rt / PortalConfig.stripsFadeOut),
      RidePhase.exit || RidePhase.fly => 0.0,
      _ => sm(view.gt / PortalConfig.stripsFadeIn),
    };
    for (final st in _strips) {
      st
        ..teethOpacity = stripA
        ..rideShift = _spOff;
    }
    c.layers.follow(c.s.camX, c.s.camY);
    final dx = c.s.camX - _prevCamX;
    _prevCamX = c.s.camX;
    if (dt > 0 && view.phase != RidePhase.glide) c.s.forwardSpeed = dx / dt;
    _placeBird();
    _applySceneLook();
  }

  void _placeBird() {
    final bird = c.game.runBird;
    if (bird == null) return;
    final p = _pose;
    view.bird = p.pos;
    c.s.ride?.birdHidden = p.hidden;
    bird.placeRide(Vector2(p.pos.dx, p.pos.dy), p.rot, scale: p.scale, hidden: p.hidden);
  }

  void _stepRide(double dt) {
    final v = view;
    v.rt += dt;
    _speed = lerpD(_v0, PortalConfig.rideSpeed, easeOut(v.rt / PortalConfig.rideRamp));
    v.s = math.min(path.length, v.s + _speed * dt);
    final p = path.at(v.s);
    final h = path.headingAt(v.s);
    final blend = 1 - sm(v.rt / PortalConfig.joinTime);
    final bx = p.x + _join.dx * blend, by = p.y + _join.dy * blend;
    final k = sm(v.rt / PortalConfig.rideOffsetTime);
    final screen = Offset(
      _entry.dx + PortalConfig.rideOffsetX * k,
      lerpD(_entry.dy, c.viewHeight / 2, k) + PortalConfig.rideOffsetY * k,
    );
    v.cam = Vector2(bx - screen.dx, by - screen.dy);
    c.s
      ..camX = _origin.x + v.cam.x
      ..camY = _origin.y + v.cam.y;
    v.envA = sm(v.rt / theme.worldFadeIn);
    final scale = theme.depth ? 1 + PortalConfig.depthScale * path.depthAt(v.s) : 1.0;
    _pose = BirdPose(
      screen,
      rot: theme.spin ? v.s * PortalConfig.pinballSpinPerPt : h,
      scale: scale,
    );
    // The portal fades away behind.
    portal.look.opacity =
        1 - sm((v.rt - PortalConfig.portalFadeFrom) / PortalConfig.portalFade);
    // §3.12 rings within ≈ 1 500 pt ahead are shown; each passes (perfect)
    // when the bird reaches its station.
    for (var i = 0; i < rings.length; i++) {
      final ring = rings[i];
      if (!_added.contains(i) && stations[i] - v.s < PortalConfig.ringsAhead) {
        _added.add(i);
        addRing(c, ring);
      }
      if (theme.depth && _added.contains(i)) {
        final sc = 1 + PortalConfig.depthScale * path.depthAt(stations[i]);
        ring.scale.setValues(sc, sc);
        ring.front.scale.setValues(sc, sc);
      }
      if (!_passed.contains(i) && v.s >= stations[i] && _added.contains(i)) {
        _passed.add(i);
        c.run.ridePass(ring);
      }
    }
    if (v.s >= path.length - 2) _beginExit(screen, _pose.rot);
  }

  void _beginExit(Offset screen, double rot) {
    final v = view;
    v
      ..phase = RidePhase.exit
      ..et = 0
      ..lastBird = screen
      ..lastRot = theme.spin ? 0 : rot
      ..camEnd = v.cam.clone();
    _camEndTrack = Offset(c.s.camX, c.s.camY);
    for (var i = 0; i < rings.length; i++) {
      if (!_passed.contains(i)) {
        // Never left behind unjudged (the station lies before the end).
        _passed.add(i);
        if (!_added.contains(i)) addRing(c, rings[i]);
        c.run.ridePass(rings[i]);
      }
      rings[i].removeFromRun();
    }
    portal.look.opacity = 0;
    _stepExit(0);
  }

  void _stepExit(double dt) {
    final v = view;
    v.et += dt;
    _pose = theme.exitPose(v, v.et);
    v.envA = 1;
    if (v.et >= theme.exitDuration) _beginFly();
  }

  void _beginFly() {
    final v = view;
    v
      ..phase = RidePhase.fly
      ..ft = 0
      ..off = Offset.zero;
    _flyLaunch = theme.launchPoint(v);
    theme.onLaunch(v);
    c.game.runBird?.priority = PortalConfig.birdAfterShot;
    _stepFly(0);
  }

  void _stepFly(double dt) {
    final v = view;
    v.ft += dt;
    final ft = v.ft;
    const g = PortalConfig.launchGravity;
    final bx = PortalConfig.launchVx * ft;
    final by = PortalConfig.launchVy * ft + .5 * g * ft * ft;
    final k = sm(ft / PortalConfig.flyEase);
    final d = sm(ft / PortalConfig.flyDrift);
    final target = Offset(
      lerpD(PortalConfig.flyX0, PortalConfig.flyX1, d),
      c.viewHeight / 2 - PortalConfig.flyYAboveCentre - PortalConfig.flyYDrift * d,
    );
    final fs = lerpO(_flyLaunch, target, k);
    v.off = Offset(_flyLaunch.dx + bx - fs.dx, _flyLaunch.dy + by - fs.dy);
    _flyAngle = math.atan2(PortalConfig.launchVy + g * ft, PortalConfig.launchVx);
    c.s
      ..camX = _camEndTrack.dx + v.off.dx
      ..camY = _camEndTrack.dy + v.off.dy;
    final swell = PortalConfig.flySwell *
        math.sin(math.min(1, ft / PortalConfig.flySwellTime) * math.pi);
    _pose = BirdPose(
      fs,
      rot: _flyAngle,
      scale: 1 + swell,
      hidden: theme.projectileActive(v, ft),
    );
    if (ft >= PortalConfig.flyTime - PortalConfig.flyEndEarly) _beginGlide(fs);
  }

  void _beginGlide(Offset from) {
    final v = view;
    v
      ..phase = RidePhase.glide
      ..gt = 0;
    _offEnd = v.off;
    _glideFrom = from;
    _spV = PortalConfig.teethScroll;
    if (theme.umbrella) c.sfx(Sfx.rdStormUmbrella);
    // Back to the normal course: camY 0, the old track cleared, the next
    // hoop placed to reach the bird ≈ 1 s after the landing (§3.12).
    final s = c.s;
    final cruise = RunConfig.cruise(s.hoopIndex);
    s
      ..camY = 0
      ..forwardSpeed = cruise;
    _glideCamX = s.camX;
    _prevCamX = s.camX;
    c.run.spawner
      ..clearAll()
      ..hold = false;
    // PRD-2.2 §18.3 the first ring reaches the bird 2 s after control
    // returns (glide + settle), at cruise.
    c.director.resumeAt(
      _glideCamX +
          RunConfig.birdX +
          cruiseDistance(
            s.hoopIndex,
            PortalConfig.glideTime +
                PortalConfig.settleTime +
                PortalConfig.firstRingAfterControl,
          ),
    );
    _stepGlide(0);
  }

  /// PRD-2.2 §18.3 the track the bird covers at cruise in [seconds] at
  /// hoop [hoopIndex] (PRD-2.3 §14.4: the cruise follows the hoop index,
  /// which does not change while no hoop spawns).
  static double cruiseDistance(int hoopIndex, double seconds) =>
      RunConfig.cruise(hoopIndex) * seconds;

  void _stepGlide(double dt) {
    final v = view;
    v.gt += dt;
    final gt = v.gt;
    final s = c.s;
    s.forwardSpeed = RunConfig.cruise(s.hoopIndex);
    s.camX += s.forwardSpeed * dt;
    v.envA = 1 - sm(gt / PortalConfig.tintFadeOut);
    final k = math.min(1.0, gt / PortalConfig.glideTime);
    final ke = smoother(k);
    final home = Offset(RunConfig.birdX, c.viewHeight / 2);
    final x = lerpD(_glideFrom.dx, home.dx, ke);
    final y = lerpD(_glideFrom.dy, home.dy, ke) -
        PortalConfig.glideArc * math.sin(math.min(1.0, ke) * math.pi);
    final w = gt - PortalConfig.glideTime;
    final settle = k >= 1
        ? math.exp(-w * PortalConfig.settleDecay) *
              math.sin(w * PortalConfig.settleFreq) *
              PortalConfig.settleAmp
        : 0.0;
    _pose = BirdPose(
      Offset(x, y + settle),
      rot: _flyAngle * (1 - ke),
      scale: 1 + PortalConfig.glideSquash * math.sin(ke * math.pi),
    );
    if (theme.umbrella) {
      _umbrella = k < 1
          ? math.min(1, gt / .3)
          : math.max(0, 1 - (gt - PortalConfig.glideTime) / .3);
    }
    if (k >= 1 && !_landed) {
      _landed = true;
      c.sfx(Sfx.puLand);
    }
    if (gt >= PortalConfig.glideTime + PortalConfig.settleTime) _finish();
  }

  void _finish() {
    view.phase = RidePhase.done;
    _done = true;
    final s = c.s;
    final y = _pose.pos.dy;
    s.ride = null;
    for (final st in _strips) {
      st
        ..teethOpacity = 1
        ..rideShift = _spOff;
    }
    final bird = c.game.runBird;
    if (bird != null) {
      bird.endRide(y);
      // PRD-2.2 §18.2 one normal flap (a tap's impulse, animation and
      // flap.mp3); no slow motion, no text.
      bird.flap();
    }
    c.run.endRideHold();
    c.director.onRideEnd(RideKind.portal);
    final timed = s.timed;
    if (timed != null && timed.paused) {
      timed.paused = false;
      c.emit(PowerupResumed(timed.type));
    }
    _removeLayers();
    _restoreScene();
    c.emit(RideEnded(RideKind.portal, theme.id));
  }

  /// The run went away mid-ride (dispose): tidy without the hand-over.
  void abort() {
    if (_done) return;
    _done = true;
    for (final r in rings) {
      r.removeFromRun();
    }
    for (final st in _strips) {
      st.teethOpacity = 1;
    }
    c.game.runBird?.endRide(c.viewHeight / 2);
    c.run.endRideHold();
    c.run.spawner.hold = false;
    c.s.ride = null;
    _removeLayers();
    _restoreScene();
  }

  void _removeLayers() {
    for (final l in _layers) {
      l.removeFromParent();
    }
    _layers.clear();
  }

  // -------------------------------------------------------------- paint

  Rect get _screen => Rect.fromLTWH(0, 0, view.w, view.h);

  double get _exitTime =>
      view.phase == RidePhase.exit ? view.et : theme.exitDuration + view.ft;

  /// PRD-2.2 §18.5 the scene's backdrop (under the circle and banners).
  void _paintBackdrop(Canvas canvas) {
    final v = view;
    switch (v.phase) {
      case RidePhase.ride:
        if (v.envA <= 0) break;
        final layer = v.envA < 1;
        if (layer) {
          canvas.saveLayer(_screen, Paint()..color = Color.fromRGBO(0, 0, 0, v.envA));
        }
        theme.paintBackdrop(canvas, v, v.cam);
        if (layer) canvas.restore();
      case RidePhase.exit:
      case RidePhase.fly:
        final off = v.phase == RidePhase.fly ? v.off : Offset.zero;
        if (!theme.exitFill) {
          theme.paintBackdrop(
            canvas,
            v,
            v.camEnd + Vector2(off.dx * .5, off.dy * .5),
          );
        }
        theme.paintExitBackdrop(canvas, v, _exitTime, off);
      case RidePhase.glide:
      case RidePhase.done:
        break;
    }
  }

  /// The scene's objects (over the circle and banners), the way-back wash.
  void _paintWorld(Canvas canvas) {
    final v = view;
    switch (v.phase) {
      case RidePhase.ride:
        if (v.envA <= 0) break;
        final layer = v.envA < 1;
        if (layer) {
          canvas.saveLayer(_screen, layerPaint(v.envA));
        }
        theme.paintWorld(canvas, v, v.cam);
        if (layer) canvas.restore();
      case RidePhase.exit:
      case RidePhase.fly:
        final off = v.phase == RidePhase.fly ? v.off : Offset.zero;
        if (!theme.exitFill) {
          theme.paintWorld(
            canvas,
            v,
            v.camEnd + Vector2(off.dx * .5, off.dy * .5),
          );
        }
        theme.paintExit(canvas, v, _exitTime, off);
        if (v.phase == RidePhase.fly && !_cannon) {
          final (top, bottom) = theme.washTint;
          vGradient(
            canvas,
            _screen,
            top,
            bottom,
            sm(v.ft / (PortalConfig.flyTime - PortalConfig.flyEndEarly)),
          );
        }
      case RidePhase.glide:
        if (v.envA <= 0) break;
        final (top, bottom) = theme.washTint;
        vGradient(canvas, _screen, top, bottom, v.envA);
      case RidePhase.done:
        break;
    }
    if (_cannon) cannonLines.paint(canvas);
  }

  void _paintUnder(Canvas canvas) {
    if (view.phase == RidePhase.glide && _umbrella > 0) {
      StormTheme.paintUmbrella(canvas, _pose.pos, _pose.rot, _umbrella);
    }
  }

  void _paintFront(Canvas canvas) {
    final v = view;
    switch (v.phase) {
      case RidePhase.ride:
        theme.paintWorldFront(canvas, v);
      case RidePhase.exit:
        theme.paintExitFront(canvas, v, _exitTime, Offset.zero);
      case RidePhase.fly:
        theme.paintExitFront(canvas, v, _exitTime, v.off);
        if (theme.projectileActive(v, v.ft)) {
          theme.paintProjectile(canvas, v, v.ft, _pose.pos, _flyAngle);
        }
      default:
        break;
    }
  }

  void _paintFx(Canvas canvas) {
    final v = view;
    if (!_cannon) rideLines.paint(canvas);
    final off = switch (v.phase) {
      RidePhase.fly => v.off,
      RidePhase.glide || RidePhase.done => _offEnd,
      _ => Offset.zero,
    };
    canvas
      ..save()
      ..translate(-off.dx, -off.dy);
    v.scenePool.paint(canvas);
    paintBlobs(canvas, v, scene: true);
    canvas.restore();
    v.screen.paint(canvas);
    paintBlobs(canvas, v, scene: false);
    theme.paintExtra(canvas, v);
  }
}
