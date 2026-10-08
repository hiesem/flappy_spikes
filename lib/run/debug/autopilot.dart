import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../config/run_config.dart';
import '../hoops/hoop.dart';
import '../hoops/hoop_kind.dart';
import '../hoops/kinds/saw/saw_kind.dart'; // WP-3d
import '../hoops/motion/hoop_motion.dart';
import '../physics/bird_motion.dart';
import '../physics/hoop_frame.dart';
import '../physics/pass_test.dart';
import '../physics/rim_collision.dart';
// region WP-3e — the collectables the bot steers toward (PRD-2 §3.26–§3.29)
import '../pickups/egg_pickup.dart';
import '../pickups/firefly_swarm.dart';
import '../pickups/jar_pickup.dart';
import '../pickups/piggy_coin.dart';
import '../pickups/piggy_pickup.dart';
import '../pickups/star_trail.dart';
// endregion WP-3e
import '../pickups/pickup.dart' show Pickup, PickupRadii;
import '../run_controller.dart';

/// The hoop-aware bot (ARCH §1.12, PRD-2 §7). Used by the debug bot,
/// `test/helpers.dart` and `integration_test/`.
///
/// Base behaviour is the prototype's `botStep`: aim at the next unresolved
/// hoop through `HoopKind.autopilotTarget` (switch first, nearer pair ring,
/// spring launch line, saw centre) and flap whenever the bird is more than
/// [margin] below the target and not already rising fast.
///
/// That bang-bang hover crosses a ring at a random point of its saw-tooth,
/// which an upright ring forgives but an angled (§3.10) or moving (§3.11)
/// one often does not: a ring tilted by θ only leaves a horizontal flight
/// path `reach·cosθ − (r + rimR)` of room, and the prototype's bot fails
/// most forced 45°–60° rings too. So for a plain ring the bot plans
/// (WP-P1int): it rolls the real physics (`BirdMotion`, [collideRims],
/// [testPlane], [isFullyPast], spike walls) forward for a small family of
/// controllers — hover at the ring centre + an aim offset, then from τ
/// seconds before the plane either glide or flap once — and follows the
/// cheapest one that passes (no rim touch, small offset, a good start for
/// the hoop after). The pick is re-checked every few frames and re-planned
/// when it stops passing.
class Autopilot {
  Autopilot(this.run, {this.margin = 10});

  final RunController run;
  final double margin;

  /// The prototype's "already rising" cut-off (pt/s).
  static const double risingVy = -40;

  /// Aim offsets tried along y (pt from the ring centre).
  static const List<double> aimOffsets = [
    0, -6, 6, -12, 12, -18, 18, -24, 24, -30, 30, -36, 36, -42, 42, -48, 48, //
  ];

  /// Final-phase starts tried (s before the plane; 0 = hover throughout).
  static const List<double> finalWindows = [
    0, .1, .15, .2, .25, .3, .35, .4, .5, .6, .7, //
  ];

  /// Rollout step (s) and the longest look-ahead.
  static const double simDt = 1 / 60;
  static const double horizon = 3.2;

  /// Rim clearance (pt) below which a planned pass counts as a touch.
  static const double safety = 4;

  /// Frames between re-checks of the current plan.
  static const int recheckEvery = 4;

  // region WP-3a — comet hoops (PRD-2 §3.8)
  /// Safety margin (pt) inside the comet star's reach (18 + bird r).
  static const double cometStarMargin = 6;
  // endregion WP-3a

  // region WP-3e — collectables (PRD-2 §3.26–§3.29)
  /// The bot aims at the nearest collectable ahead while the next hoop's
  /// plane is still at least this many seconds away, then hands back to the
  /// ring planner so the pass itself is planned (§7: the mock's bot is
  /// bang-bang toward the item, the planner is what makes angled / moving
  /// rings survivable).
  static const double chaseHandover = .85;

  /// The vertical band (pt from the walls) a collectable must sit inside to
  /// be chased at all — items always are; this just keeps a stray plan from
  /// diving the bird into a tooth line.
  static const double chaseClearance = 30;
  // endregion WP-3e

  _Plan? _plan;
  Hoop? _planHoop;
  int _sinceCheck = 0;

  /// The y the bot currently aims at.
  double targetY() {
    final s = run.state;
    var ty = s.viewHeight / 2;
    final bird = run.game.runBirdPosition;
    final h = run.spawner.nextHoopAhead();
    if (h != null) {
      final t = h.kind.autopilotTarget(h, s, bird?.y ?? ty);
      ty = t.preTarget != null ? t.preTarget!.y + 6 : t.y;
      // region WP-4a — a small bird (Mini Bird, §3.31) has a shorter pickup
      // reach (18 + r × 0.52): centre the ≈ 55 pt bang-bang flap arc on the
      // switch instead of letting it peak ≈ 30 pt above it (found when the
      // feather / piece rolls changed a seeded switch-ring course).
      if (t.preTarget != null && s.birdScale < 1) {
        ty += 12 * (1 - s.birdScale) / (1 - .52);
      }
      // endregion WP-4a
      // region WP-1b — moving rings: aim where the ring will be when the
      // bird reaches its plane (§3.11), not where it is now.
      final m = h.motion;
      if (t.preTarget == null && m is HoopMotion && bird != null) {
        final birdX = s.camX + bird.x;
        final v = s.forwardSpeed <= 1 ? 1.0 : s.forwardSpeed;
        final dt = ((h.position.x - birdX) / v).clamp(0.0, 3.0);
        ty += m.offsetAt(s.runClock + dt).y - m.offset.y;
      }
      // endregion WP-1b
    }
    // region WP-3e — a collectable nearer than the next hoop wins while the
    // plane is still far enough away (the mock's bot: the nearest `aim` item,
    // else the ring).
    final chase = _chaseY();
    if (chase != null && _farFromPlane()) return chase;
    // endregion WP-3e
    return ty;
  }

  bool shouldFlap() {
    final s = run.state;
    if (!run.isScrolling || s.flapLock > 0 || s.ride != null) return false;
    final bird = run.game.runBirdPosition;
    final vy = run.game.runBirdVelocityY;
    if (bird == null || vy == null) return false;
    // region WP-3e — chasing a collectable replaces the ring plan until the
    // handover (§7).
    if (_chaseY() != null && _farFromPlane()) {
      return bird.y > targetY() + margin && vy > risingVy;
    }
    // endregion WP-3e
    final planned = _plannedFlap(vy);
    if (planned != null) return planned;
    return bird.y > targetY() + margin && vy > risingVy;
  }

  // region WP-3e — collectables (PRD-2 §3.26–§3.29)
  /// The y of the nearest uncollected collectable ahead of the bird that is
  /// closer than the next hoop's plane — the mock bot's `aim` item scan
  /// (`for (it of items) if (it.aim && !it.got && it.x > BX - 6 && it.x <
  /// best) { best = it.x; aim = it.y }`). Null when there is none.
  double? _chaseY() {
    final pos = run.birdTrackPosition();
    if (pos == null) return null;
    final h = run.spawner.nextHoopAhead();
    var bestX = h == null ? double.infinity : h.planeX;
    double? best;
    for (final p in run.spawner.pickups) {
      final at = _aimAt(p, pos.x);
      if (at == null) continue;
      if (at.dx < pos.x - 6 || at.dx >= bestX) continue;
      bestX = at.dx;
      best = at.dy;
    }
    if (best == null) return null;
    final top = run.walls.top + chaseClearance;
    final floor = run.walls.floor - chaseClearance;
    if (best < top || best > floor) return null;
    return best;
  }

  /// The nearest uncollected item of [p] ahead of the bird, or null when
  /// there is nothing left to aim at (the mock marks one `aim` item).
  Offset? _aimAt(Pickup p, double birdTrackX) {
    if (p is StarTrail) {
      final items = <Offset>[
        for (var i = 0; i < p.caught.length; i++)
          if (!p.caught[i]) p.starAt(i),
      ];
      return _nearest(items, birdTrackX);
    }
    if (p is PiggyCoin) {
      final items = <Offset>[
        for (var i = 0; i < p.count; i++)
          if (!p.caught[i] && !p.missed[i]) p.coinAt(i),
      ];
      return _nearest(items, birdTrackX);
    }
    if (p is FireflySwarm) {
      final items = <Offset>[
        for (var i = 0; i < p.count; i++)
          if (!p.caught[i] && !p.escapedFly[i]) p.flyAt(i),
      ];
      return _nearest(items, birdTrackX);
    }
    if (p is EggPickup || p is PiggyPickup || p is JarPickup) {
      if (p.collected || p.escaped) return null;
      return Offset(p.position.x, p.position.y);
    }
    return null;
  }

  Offset? _nearest(Iterable<Offset> items, double birdTrackX) {
    Offset? best;
    for (final o in items) {
      if (o.dx < birdTrackX - 6) continue;
      if (best == null || o.dx < best.dx) best = o;
    }
    return best;
  }

  /// The next hoop's plane is still at least [chaseHandover] seconds away
  /// (or there is no hoop): safe to steer at an item.
  bool _farFromPlane() {
    final h = run.spawner.nextHoopAhead();
    if (h == null) return true;
    final pos = run.birdTrackPosition();
    if (pos == null) return true;
    final v = run.state.forwardSpeed <= 1 ? 1.0 : run.state.forwardSpeed;
    return (h.planeX - pos.x) / v > chaseHandover;
  }
  // endregion WP-3e

  // ---------------------------------------------------------------- planner

  /// The planned decision, or null when the next hoop is not plannable
  /// (switch / pre-target, no hoop) or no controller passes it.
  bool? _plannedFlap(double vy) {
    final h = run.spawner.nextHoopAhead();
    final pos = run.birdTrackPosition();
    if (h == null || pos == null || !h.open) {
      _plan = null;
      return null;
    }
    final s = run.state;
    final aim = h.kind.autopilotTarget(h, s, pos.y);
    if (aim.preTarget != null) {
      _plan = null;
      return null;
    }
    // The aimed ring's offset from the hoop centre (pairs: the nearer ring).
    final ringOff = aim.y - h.position.y;
    final start = _SimState(
      x: pos.x,
      y: pos.y,
      vy: vy,
      forward: s.forwardSpeed,
      clock: s.runClock,
      invulnerable: s.invulnerable,
    );
    if (!identical(h, _planHoop)) {
      _planHoop = h;
      _plan = null;
    }
    if (_plan != null && ++_sinceCheck >= recheckEvery) {
      _sinceCheck = 0;
      final again = _rollout(h, ringOff, start, _plan!.controller.copy());
      if (again == null || (again.touched && !_plan!.touched)) _plan = null;
    }
    _plan ??= _search(h, ringOff, start);
    _sinceCheck = _plan == null ? 0 : _sinceCheck;
    final p = _plan;
    if (p == null) return null;
    return p.controller.decide(start, _timeToPlane(h, start), ringOff, this, h);
  }

  _Plan? _search(Hoop h, double ringOff, _SimState start) {
    _Plan? best;
    for (final o in aimOffsets) {
      for (final tau in finalWindows) {
        for (final once in tau == 0 ? const [false] : const [false, true]) {
          final c = _Controller(offset: o, window: tau, flapOnce: once);
          final r = _rollout(h, ringOff, start, c.copy());
          if (r == null) continue;
          if (best == null || r.cost < best.cost) {
            best = _Plan(c, r.cost, r.touched);
          }
        }
      }
      // An untouched pass on the centre line needs no further search.
      if (best != null && !best.touched && best.cost < 1) break;
    }
    _sinceCheck = 0;
    return best;
  }

  /// Rolls the physics forward under [c] until [h] resolves. Returns null
  /// on a miss / spike contact / timeout.
  _Outcome? _rollout(Hoop h, double ringOff, _SimState s0, _Controller c) {
    final s = s0.copy();
    final r = RunConfig.birdRadius * run.state.birdScale;
    final top = run.walls.top, floor = run.walls.floor;
    final mode = h.kind.rimMode(h, run.state);
    var touched = h.touched;
    var clear = double.infinity;
    var t = 0.0;
    try {
      while (t < horizon) {
        if (c.decide(s, _timeToPlane(h, s), ringOff, this, h)) {
          s.vy = -Config.flapVelocity;
        }
        final prev = Vector2(s.x, s.y);
        s.clock += simDt;
        s.forward = BirdMotion.recover(
          s.forward,
          BirdMotion.cruise(s.clock),
          simDt,
        );
        s.x += s.forward * simDt;
        s.vy = math.min(Config.maxFallSpeed, s.vy + Config.gravity * simDt);
        // region WP-3d — §3.18 the Black Hole pulls toward its rim
        s.vy += SawHoopKind.pullFrom(h, Vector2(s.x, s.y), r, s.clock) * simDt;
        // endregion WP-3d
        s.y += s.vy * simDt;
        if (s.invulnerable > 0) s.invulnerable -= simDt;
        t += simDt;
        final f = _frameAt(h, s.clock);
        if (mode != RimMode.ignored && s.invulnerable <= 0) {
          final res = collideRims(
            f,
            BirdCircle(Vector2(s.x, s.y), r),
            Vector2(s.forward, s.vy),
          );
          if (res != null) {
            if (mode == RimMode.deadly) return null;
            s
              ..x = res.position.x
              ..y = res.position.y
              ..forward = res.velocity.x
              ..vy = res.velocity.y;
            if (res.bounced) touched = true;
          }
          clear = math.min(clear, _clearance(f, s, r));
        }
        final now = BirdCircle(Vector2(s.x, s.y), r);
        if (s.y - r <= top || s.y + r >= floor) return null;
        if (testPlane(f, BirdCircle(prev, r), now) != null) {
          // A graze inside [safety] is as good as a touch: the real flight
          // differs from the rollout by a point or two.
          final risky = touched || clear < safety;
          return _Outcome(
            _cost(h, c, s, risky, top, floor, r) +
                (clear < 10 ? (10 - clear) * 5 : 0),
            risky,
          );
        }
        if (isFullyPast(f, now)) return null;
      }
      return null;
    } finally {
      _restorePose(h);
    }
  }

  /// The smallest gap between the bird circle and any rim-end circle.
  double _clearance(HoopFrame f, _SimState s, double r) {
    var best = double.infinity;
    for (var ring = 0; ring < f.rings.length; ring++) {
      for (final side in const [-1, 1]) {
        final e = f.rimEnd(ring, side);
        final dx = s.x - e.x, dy = s.y - e.y;
        best = math.min(best, math.sqrt(dx * dx + dy * dy) - r - f.rimR);
      }
    }
    return best;
  }

  /// Lower is better: rim touches first, then the aim offset, then how far
  /// the bird ends up from the next hoop's centre and from the spikes.
  double _cost(
    Hoop h,
    _Controller c,
    _SimState s,
    bool touched,
    double top,
    double floor,
    double r,
  ) {
    var cost = (touched ? 1000.0 : 0.0) + c.offset.abs() * .3 + c.window * 2;
    Hoop? next;
    var found = false;
    for (final o in run.spawner.hoops) {
      if (found && !o.resolved) {
        next = o;
        break;
      }
      if (identical(o, h)) found = true;
    }
    // region WP-3c — §3.23 a spring launches the bird toward the next ring
    // (240 pt away): its crossing height does not set up the next hoop.
    final launches = h.kind.id == HoopKindId.spring && run.state.ride == null;
    // endregion WP-3c
    if (next != null && !launches) {
      cost += (s.y - next.basePosition.y).abs() * .15;
    }
    final room = math.min(s.y - r - top, floor - s.y - r);
    if (room < 40) cost += (40 - room) * 2;
    // region WP-3a — a comet hoop: cross the plane where the star hangs (it
    // is 20 pt past the plane at the hoop centre), so the pass collects it
    // (§3.8, the prototype bot flies through the hoop centre).
    if (h.plan.cometHang) {
      final reach = PickupRadii.comet + r - cometStarMargin;
      final off = (s.y - h.plan.centreY).abs();
      if (off > reach) cost += (off - reach) * 50;
    }
    // endregion WP-3a
    return cost;
  }

  /// Time until the bird reaches the hoop's centre x.
  double _timeToPlane(Hoop h, _SimState s) {
    final v = s.forward <= 1 ? 1.0 : s.forward;
    return (_frameCentreX(h, s.clock) - s.x) / v;
  }

  double _frameCentreX(Hoop h, double t) {
    final m = h.motion;
    if (m is HoopMotion) return h.basePosition.x + m.offsetAt(t).x;
    return h.position.x;
  }

  /// The aimed ring's centre y at runClock [t] ([ringOff] from the hoop
  /// centre).
  double _ringYAt(Hoop h, double ringOff, double t) {
    final m = h.motion;
    if (m is HoopMotion) return h.basePosition.y + m.offsetAt(t).y + ringOff;
    return h.position.y + ringOff;
  }

  /// [Hoop.frame] at a future runClock [t] (moving rings are a pure
  /// function of the clock).
  HoopFrame _frameAt(Hoop h, double t) {
    final m = h.motion;
    if (m is! HoopMotion) return h.frame();
    m.poseAt(t);
    return h.frame();
  }

  void _restorePose(Hoop h) {
    final m = h.motion;
    if (m is HoopMotion) m.poseAt(run.state.runClock);
  }
}

class _SimState {
  _SimState({
    required this.x,
    required this.y,
    required this.vy,
    required this.forward,
    required this.clock,
    required this.invulnerable,
  });

  double x, y, vy, forward, clock, invulnerable;

  _SimState copy() => _SimState(
    x: x,
    y: y,
    vy: vy,
    forward: forward,
    clock: clock,
    invulnerable: invulnerable,
  );
}

/// Hover at ring centre + [offset] (bang-bang, the prototype rule); from
/// [window] s before the plane: glide, or flap once ([flapOnce]) and glide.
class _Controller {
  _Controller({
    required this.offset,
    required this.window,
    required this.flapOnce,
  });

  final double offset;
  final double window;
  final bool flapOnce;
  bool _flapped = false;

  _Controller copy() =>
      _Controller(offset: offset, window: window, flapOnce: flapOnce)
        .._flapped = _flapped;

  bool decide(
    _SimState s,
    double toPlane,
    double ringOff,
    Autopilot a,
    Hoop h,
  ) {
    if (window > 0 && toPlane <= window) {
      if (flapOnce && !_flapped) {
        _flapped = true;
        return true;
      }
      return false;
    }
    final lead = toPlane.clamp(0.0, 3.0);
    final ty = a._ringYAt(h, ringOff, s.clock + lead) + offset;
    return s.y > ty + a.margin && s.vy > Autopilot.risingVy;
  }
}

class _Plan {
  _Plan(this.controller, this.cost, this.touched);
  final _Controller controller;
  final double cost;
  final bool touched;
}

class _Outcome {
  _Outcome(this.cost, this.touched);
  final double cost;
  final bool touched;
}
