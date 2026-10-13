import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../../game/config.dart';
import '../../game/sound.dart';
import '../config/comet_config.dart';
import '../config/parts_config.dart';
import '../config/run_config.dart';
import '../effects/particle_pool.dart';
import '../effects/pickup_touch_fx.dart';
import '../hoops/hoop.dart';
import '../hoops/motion/hoop_motion.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_layers.dart';
import '../run_state.dart';
import 'ride.dart';
import 'speed_lines.dart';

/// The comet boost engine (PRD-2 §3.8, §3.9, §5.6; `screen_comet2.html`).
///
/// - **10 s** of game time ([CometConfig.duration]); the forward motion
///   eases to **1.7 × cruise** in 0.45 s and back over the last 0.9 s
///   ([cruiseMultAt], via `RunState.cruiseMult` → `BirdMotion.step`), so
///   the world, the camera and the spawner all run at the boost speed.
/// - The bird **flies itself** (kinematic, taps ignored — `Bird.beginRide`)
///   toward the next unresolved hoop: the ring nearest its line
///   (`HoopKind.autopilotTarget`, moving rings where they will be at the
///   crossing). PRD-2.2 §16: on a smooth ease-in-out curve over track x
///   from the last hoop's plane (or the pickup) to the next one's, level at
///   each hoop and through its centre, tilting along its flight direction
///   (max ±35°); the hoops the director plans meanwhile zigzag ±70 pt
///   around the middle ([RunDirector.onCometStart]).
/// - PRD-2.2 §17: at the end the bird gets one normal flap and the run
///   world runs in a quiet slow motion for ≈ 1.5 s ([LandingSlowMo]).
/// - It is a ride (`RunState.ride` = comet): rims are ignored, closed
///   switches never stop it, every hoop passed is a perfect pass (the
///   controller), the mistake pipeline ignores mistakes, hoops spawned now
///   are full size, upright and still (the director). It also holds the
///   timed-powerup slot (`RunState.timed` = comet): no capsule, comet hoop
///   or COMET gift meanwhile.
/// - Looks: the bird at 90 % inside the fireball (tail, gold shell with a
///   pink rim, inner glow), the countdown ring drawn with it (r 34, drains
///   over the boost), "Ns" 50 pt below, the comet's own speed streaks
///   ([CometSpeedLines], master #12). The trail is the shared master #10
///   (`TierTrail`, active in every ride).
/// - Sounds: `pu_comet_get` on collection, `pu_comet_loop` (30 %) from
///   1.2 s until the end (0.3 s fade), `pu_comet_end` at the end.
/// - Pop (white flash, pink / gold squares, gold ring, the graphic 0.4 →
///   1.3 → 1) on collection and when the bird pops back at the end.
class CometRide implements Ride {
  CometRide(this.c, {this.source = 'hoop', this.starY});

  final RunContext c;

  /// 'hoop' (the star in a comet hoop) or 'pair' (a pair's COMET gift).
  final String source;

  /// PRD-2.2 §16.1 the centre of the hoop the star hung in (null: a pair's
  /// gift — the bird's height at the pickup is used).
  final double? starY;

  @override
  RideKind get kind => RideKind.comet;

  @override
  RideId? get rideId => null;

  /// Boost time (s of game time).
  double t = 0;

  /// Time since the boost ended (the pop and the loop fade play on).
  double _after = 0;

  bool _done = false;

  /// The boost is over (control is back); [finished] once the landing pop
  /// and the loop fade have played.
  @override
  bool get done => _done;

  bool get finished => _done && _after >= _tailLength;

  static double get _tailLength =>
      math.max(CometConfig.popLength, math.max(CometConfig.loopFade, .6));

  /// Seconds left of the boost.
  double get remaining => math.max(0, CometConfig.duration - t);

  /// The "Ns" label (10s → 1s).
  String get label => '${remaining.ceil().clamp(1, 99)}s';

  /// The comet's screen y and tilt (rad).
  double y = 0;
  double tilt = 0;

  // region WP-G3 — the curve (PRD-2.2 §16)
  /// The hoop the curve leads to now (null: none ahead, fly level).
  Hoop? _target;

  /// The curve's start: the last hoop's plane (track x) and the comet's y
  /// there (at the pickup: the bird's x and height).
  double _x0 = 0, _y0 = 0;

  /// The curve's slope dy/dx now (0 at each hoop).
  double slope = 0;

  /// PRD-2.2 §16.1 the flight direction now (rad, unclamped, unsmoothed).
  double get flightAngle => math.atan(slope);
  // endregion WP-G3

  /// The graphic's pop scale now.
  double get popScale => _popAt(_done ? _after : t);

  /// §3.8 the cruise multiplier at boost time [t]: smoothstep 1 → 1.7 over
  /// 0.45 s, then back to 1 over the last 0.9 s.
  static double cruiseMultAt(double t) {
    const d = CometConfig.duration;
    if (t < 0 || t >= d) return 1;
    final up = _sm(t / CometConfig.easeIn);
    final down = 1 - _sm((t - (d - CometConfig.easeOut)) / CometConfig.easeOut);
    return 1 + (CometConfig.speedMult - 1) * up * down;
  }

  static double _sm(double u) {
    final x = u.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// §5.6 pop 0.4 → 1.3 (half-way) → 1 over 0.38 s (linear keyframes).
  static double _popAt(double s) {
    const len = CometConfig.popLength;
    if (s >= len) return 1;
    final u = (s / len).clamp(0.0, 1.0);
    if (u < .5) {
      return CometConfig.popFrom +
          (CometConfig.popPeak - CometConfig.popFrom) * (u / .5);
    }
    return CometConfig.popPeak + (1 - CometConfig.popPeak) * ((u - .5) / .5);
  }

  LoopHandle? _loop;
  bool _loopSilenced = false;

  /// The loop is silenced (the run is paused).
  bool get loopSilenced => _loopSilenced;
  double _loopFadeT = -1;

  final CometSpeedLines lines = CometSpeedLines();
  final List<Component> _parts = [];
  late final ParticlePool _pool;
  final _touch = PickupTouchFx.newPool();
  _CometFlash? _flash;

  @override
  void start(RunContext _) {
    final s = c.s;
    final bird = c.game.runBirdPosition;
    y = bird?.y ?? c.viewHeight / 2;
    _x0 = s.camX + RunConfig.birdX;
    _y0 = y;
    s.ride = RideState(kind: RideKind.comet, phase: 'boost');
    s.timed = TimedPowerupState(
      type: TimedPowerup.comet,
      duration: CometConfig.duration,
    );
    c.director
      ..onRideStart(RideKind.comet)
      ..onCometStart(
        fromY: starY ?? y,
        endTrackX: predictEndTrackX(),
        viewHeight: c.viewHeight,
        amplitude: CometConfig.zigzagAmp,
      );
    c.game.runBird?.beginRide();
    final world = c.game.world;
    _pool = ParticlePool(capacity: 40, priority: RunLayer.fx);
    for (final part in <Component>[
      _CometLines(this, priority: RunLayer.guides),
      _CometBack(this, priority: RunLayer.bird - 1),
      _CometFront(this, priority: RunLayer.bird + 1),
      _pool,
    ]) {
      _parts.add(part);
      world.add(part);
    }
    c.sfx(Sfx.puCometGet);
    _pop();
    c.emit(PowerupStarted(TimedPowerup.comet, CometConfig.duration));
    c.emit(const RideStarted(RideKind.comet));
    _place(0);
  }

  @override
  void update(double dt) {
    final s = c.s;
    if (_done) {
      _after += dt;
      _stepLoopFade(dt);
      lines.update(dt, c.viewHeight, c.cosmetic, active: false);
      final bird = c.game.runBird;
      if (bird != null && bird.isLoaded) {
        final k = _popAt(_after);
        bird.lookComponent.scale.setValues(k, k);
      }
      if (finished) _removeParts();
      return;
    }
    t += dt;
    s.cruiseMult = cruiseMultAt(t);
    s.timed?.remaining = remaining;
    if (t >= CometConfig.duration - CometConfig.easeOut) s.ride?.phase = 'landing';
    c.director.updateCometEnd(predictEndTrackX());
    _steer(dt);
    _place(dt);
    lines.update(dt, c.viewHeight, c.cosmetic);
    _stepLoop();
    if (t >= CometConfig.duration) _finish();
  }

  /// PRD-2.2 §16.2 the bird's track x when the boost (and its ease-out)
  /// ends: the rest of the boost at `cruise · cruiseMultAt` (the forward
  /// speed follows that target within a few frames).
  double predictEndTrackX() {
    final s = c.s;
    var x = s.camX + RunConfig.birdX;
    const step = 1 / 60;
    var tau = t;
    final cruise = RunConfig.cruise(s.hoopIndex);
    while (tau < CometConfig.duration) {
      final h = math.min(step, CometConfig.duration - tau);
      x += cruise * cruiseMultAt(tau + h / 2) * h;
      tau += h;
    }
    return x;
  }

  /// PRD-2.2 §16.1 the bird flies itself on an ease-in-out curve over
  /// track x: from the last hoop's plane (or the pickup) at [_y0] to the
  /// next ring's centre at its crossing, `y = y0 + (y1 − y0) · (1 −
  /// cos(π·u)) / 2` — level at each hoop. A new target starts the next
  /// curve at the comet's current height, so nothing ever jumps.
  void _steer(double dt) {
    final s = c.s;
    final bx = s.camX + RunConfig.birdX;
    final cur = _target;
    final keep =
        cur != null && !cur.resolved && !cur.isRemoved && cur.planeX > bx;
    final h = keep ? cur : nextPlaneAhead(minAhead: CometConfig.minCurveSpan);
    if (!identical(h, _target)) {
      final prev = _target;
      _x0 = prev == null ? bx : math.min(prev.planeX, bx);
      _y0 = y;
      _target = h;
    }
    if (h == null) {
      slope = 0;
    } else {
      final y1 = ringYAtCrossing(h);
      final span = h.planeX - _x0;
      if (span <= 1) {
        y = y1;
        slope = 0;
      } else {
        final u = ((bx - _x0) / span).clamp(0.0, 1.0);
        y = _y0 + (y1 - _y0) * (1 - math.cos(math.pi * u)) / 2;
        slope = u >= 1
            ? 0
            : (y1 - _y0) * math.pi / 2 * math.sin(math.pi * u) / span;
      }
    }
    final r = RunConfig.birdRadius * c.s.birdScale;
    final lo = c.run.walls.top + r + 4;
    final hi = c.run.walls.floor - r - 4;
    if (lo < hi) y = y.clamp(lo, hi).toDouble();
    // PRD-2.2 §16.1 the tilt is the flight direction (atan2(vy, forward)
    // = atan(dy/dx)), max ±35°, turning at a bounded rate (no snaps).
    const cap = CometConfig.maxTiltDeg * math.pi / 180;
    final want = flightAngle.clamp(-cap, cap);
    if (dt > 0) {
      final turn = CometConfig.maxTiltRateDeg * math.pi / 180 * dt;
      tilt = (tilt + (want - tilt).clamp(-turn, turn)).clamp(-cap, cap);
    }
  }

  /// PRD-2.2 §16.1 the next hoop whose plane the comet has not reached
  /// yet (the curve switches to the next hoop at the plane, so it stays
  /// level and centred there).
  Hoop? nextPlaneAhead({double minAhead = 0}) {
    final bx = c.s.camX + RunConfig.birdX;
    Hoop? best;
    for (final h in c.run.spawner.hoops) {
      if (h.resolved || h.isRemoved || h.planeX <= bx + minAhead) continue;
      if (best == null || h.planeX < best.planeX) best = h;
    }
    return best;
  }

  /// The screen y the comet steers to: the next unresolved hoop's ring
  /// nearest the comet (a pair: the nearer ring; moving rings: where they
  /// will be when the comet crosses), else straight on.
  double targetY() {
    final h = c.run.spawner.nextHoopAhead();
    if (h == null) return y;
    return ringYAtCrossing(h);
  }

  double ringYAtCrossing(Hoop h) {
    final s = c.s;
    final aim = h.kind.autopilotTarget(h, s, y);
    var ty = aim.y;
    final m = h.motion;
    if (m is HoopMotion) {
      final birdX = s.camX + RunConfig.birdX;
      final v = s.forwardSpeed <= 1 ? 1.0 : s.forwardSpeed;
      final dt = ((h.position.x - birdX) / v).clamp(0.0, 3.0);
      ty += m.offsetAt(s.runClock + dt).y - m.offset.y;
    }
    return ty;
  }

  void _place(double dt) {
    final bird = c.game.runBird;
    if (bird == null || !bird.isLoaded) return;
    final k = CometConfig.birdScale * popScale;
    bird.placeRide(Vector2(RunConfig.birdX, y), tilt, scale: k);
  }

  void _stepLoop() {
    if (_loop == null && t >= CometConfig.loopDelay) {
      _loop = c.loop(SfxLoop.cometLoop, volume: CometConfig.loopVolume);
    }
    final loop = _loop;
    if (loop == null || loop.stopped) return;
    // A paused run silences the loop; it comes back on resume.
    final silent = !c.run.isScrolling;
    if (silent != _loopSilenced) {
      _loopSilenced = silent;
      loop.setVolume(silent ? 0 : CometConfig.loopVolume);
    }
  }

  void _stepLoopFade(double dt) {
    final loop = _loop;
    if (loop == null || loop.stopped || _loopFadeT < 0) return;
    _loopFadeT += dt;
    final k = 1 - (_loopFadeT / CometConfig.loopFade).clamp(0.0, 1.0);
    if (k <= 0) {
      loop.stop();
    } else {
      loop.setVolume(CometConfig.loopVolume * k);
    }
  }

  /// §5.6 the pop at the comet: white flash, squares and a gold ring.
  void _pop() {
    final world = c.game.world;
    final at = Offset(RunConfig.birdX, y);
    _flash?.removeFromParent();
    final flash = _CometFlash(
      Size(RunConfig.worldWidth, c.viewHeight),
      priority: RunLayer.fx + 1,
    );
    _flash = flash;
    world.add(flash);
    world.add(
      _touch.obtain()
        ..priority = RunLayer.fx
        ..play(at, CometConfig.pop, pool: _pool, random: c.cosmetic),
    );
  }

  /// §3.8 ending: the bird pops back into its normal shape, control
  /// returns at its current height (no invulnerability beyond the landing)
  /// with one automatic flap (PRD-2.2 §17).
  void _finish() {
    _done = true;
    _after = 0;
    final s = c.s;
    s
      ..cruiseMult = 1
      ..ride = null
      ..timed = null;
    final bird = c.game.runBird;
    bird?.endRide(y);
    // PRD-2.2 §17.1 one normal flap (a tap's impulse, animation and
    // flap.mp3); the feature starts the landing slow motion.
    bird?.flap();
    c.director.onRideEnd(RideKind.comet);
    c.sfx(Sfx.puCometEnd);
    _loopFadeT = _loop == null ? -1 : 0;
    _pop();
    c.emit(const PowerupEnded(TimedPowerup.comet));
    c.emit(const RideEnded(RideKind.comet));
  }

  /// The run went away mid-boost (dispose): tidy without the hand-over.
  void abort() {
    if (!_done) {
      _done = true;
      c.s
        ..cruiseMult = 1
        ..ride = null
        ..timed = null;
      c.game.runBird?.endRide(c.viewHeight / 2);
      c.director.onRideEnd(RideKind.comet);
    }
    _after = _tailLength;
    _loop?.stop();
    final bird = c.game.runBird;
    if (bird != null && bird.isLoaded) bird.lookComponent.scale.setValues(1, 1);
    _removeParts();
  }

  void _removeParts() {
    for (final p in _parts) {
      p.removeFromParent();
    }
    _parts.clear();
    lines.clear();
    final bird = c.game.runBird;
    if (bird != null && bird.isLoaded && _done) {
      bird.lookComponent.scale.setValues(1, 1);
    }
  }

  // ----------------------------------------------------------- painting

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// §5.6 Tail and shell behind the bird, centred on [centre].
  static void paintBack(
    Canvas canvas,
    Offset centre, {
    double tilt = 0,
    double scale = 1,
  }) {
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(tilt)
      ..scale(scale);
    _fill.color = PartsConfig.gold.withValues(alpha: CometConfig.tailGoldAlpha);
    canvas.drawPath(
      Path()
        ..moveTo(CometConfig.tailGoldBaseX, -CometConfig.tailGoldHalf)
        ..lineTo(CometConfig.tailGoldTipX, 0)
        ..lineTo(CometConfig.tailGoldBaseX, CometConfig.tailGoldHalf)
        ..close(),
      _fill,
    );
    _fill.color = PartsConfig.pink.withValues(alpha: CometConfig.tailPinkAlpha);
    canvas.drawPath(
      Path()
        ..moveTo(CometConfig.tailPinkBaseX, -CometConfig.tailPinkHalf)
        ..lineTo(CometConfig.tailPinkTipX, 0)
        ..lineTo(CometConfig.tailPinkBaseX, CometConfig.tailPinkHalf)
        ..close(),
      _fill,
    );
    _fill.color = PartsConfig.gold;
    canvas.drawCircle(Offset.zero, CometConfig.shellR, _fill);
    _stroke
      ..strokeWidth = CometConfig.shellStroke
      ..strokeCap = StrokeCap.butt
      ..color = PartsConfig.pink;
    canvas.drawCircle(Offset.zero, CometConfig.shellR, _stroke);
    _fill.color = CometConfig.shellInner;
    canvas
      ..drawCircle(Offset.zero, CometConfig.shellInnerR, _fill)
      ..restore();
  }

  /// §5.6 The countdown ring over the bird: [left] = fraction of the boost
  /// left (1 → 0), drawn clockwise from the top, plus the soft track.
  static void paintRing(
    Canvas canvas,
    Offset centre, {
    required double left,
    double tilt = 0,
    double scale = 1,
  }) {
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(tilt)
      ..scale(scale);
    const r = CometConfig.ringR;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    if (left > 0) {
      _stroke
        ..strokeWidth = CometConfig.ringStroke
        ..strokeCap = StrokeCap.round
        ..color = PartsConfig.gold;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * left, false, _stroke);
    }
    _stroke
      ..strokeWidth = CometConfig.ringStroke
      ..strokeCap = StrokeCap.butt
      ..color = CometConfig.ringTrack.withValues(
        alpha: CometConfig.ringTrack.a * CometConfig.ringTrackOpacity,
      );
    canvas
      ..drawCircle(Offset.zero, r, _stroke)
      ..restore();
  }
}

/// Behind the bird: the tail and the shell.
class _CometBack extends Component {
  _CometBack(this.ride, {super.priority});
  final CometRide ride;

  @override
  void render(Canvas canvas) {
    if (ride.done) return;
    CometRide.paintBack(
      canvas,
      Offset(RunConfig.birdX, ride.y),
      tilt: ride.tilt,
      scale: ride.popScale,
    );
  }
}

/// Over the bird: the countdown ring and the seconds label.
class _CometFront extends Component {
  _CometFront(this.ride, {super.priority});
  final CometRide ride;

  final Map<String, TextPainter> _labels = {};

  TextPainter _label(String s) => _labels[s] ??= TextPainter(
    text: TextSpan(
      text: s,
      style: const TextStyle(
        fontFamily: Config.uiFont,
        fontSize: CometConfig.labelSize,
        color: PartsConfig.gold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void render(Canvas canvas) {
    if (ride.done) return;
    final at = Offset(RunConfig.birdX, ride.y);
    CometRide.paintRing(
      canvas,
      at,
      left: ride.remaining / CometConfig.duration,
      tilt: ride.tilt,
      scale: ride.popScale,
    );
    final tp = _label(ride.label);
    tp.paint(
      canvas,
      Offset(at.dx - tp.width / 2, at.dy + CometConfig.labelBelow - tp.height / 2),
    );
  }
}

/// The comet's speed streaks (screen space, under the hoops).
class _CometLines extends Component {
  _CometLines(this.ride, {super.priority});
  final CometRide ride;

  @override
  void render(Canvas canvas) => ride.lines.paint(canvas);
}

/// §3.8 the pop's white flash over the play area (0.7 → 0 in 0.38 s).
class _CometFlash extends Component {
  _CometFlash(this.size, {super.priority});
  final Size size;
  double _t = 0;
  final Paint _paint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= CometConfig.popLength) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = CometConfig.flashAlpha * (1 - _t / CometConfig.popLength);
    if (a <= 0) return;
    _paint.color = Color.fromRGBO(255, 255, 255, a.clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, _paint);
  }
}
