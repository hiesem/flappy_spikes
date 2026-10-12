import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/physics_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/physics/pass_test.dart';
import 'package:flappy_spikes/run/physics/rim_collision.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.2 §30: moving rings — a clean pass must never count as a miss.
/// Pure physics: the run's per-step order (rims, plane test, miss rule)
/// against a [HoopMotion] driven by the clock, as `RunController`
/// `_stepPhysics` does it.

const double r = RunConfig.birdRadius;
const double speed = RunConfig.cruiseSpeed;

/// The spike strip height (the top tooth line without a squeeze).
const double strip = 44;

HoopFrame frameAt(HoopMotion m, Vector2 home, double opening, double t) {
  m.poseAt(t);
  return HoopFrame(
    centre: home + m.offset,
    tilt: m.angleOffset,
    opening: opening,
    velocity: m.velocity.clone(),
    angularVelocity: m.angularVelocity * math.pi / 180,
  );
}

class Flight {
  Flight(this.kind, this.touched, this.event);
  final PlaneEventKind kind;
  final bool touched;
  final PlaneEvent? event;
}

/// Flies the bird level at [speed] from [start] (t = 0) through [m] with
/// steps of [dt] until the hoop resolves. [legacy] = the 2.1 test (both
/// bird positions in the ring's current pose, no rim sweep).
Flight fly(
  HoopMotion m,
  Vector2 home,
  double opening,
  Vector2 start,
  double dt, {
  bool legacy = false,
}) {
  var pos = start.clone();
  final v = Vector2(speed, 0);
  var touched = false;
  var t = 0.0;
  var pf = frameAt(m, home, opening, t);
  for (var i = 0; i < 1200; i++) {
    final prev = pos.clone();
    t += dt;
    pos = pos + v * dt;
    final f = frameAt(m, home, opening, t);
    final res = legacy
        ? collideRims(f, BirdCircle(pos, r), v)
        : collideRimsSwept(pf, f, BirdCircle(prev, r), BirdCircle(pos, r), v);
    if (res != null) {
      touched = true;
      pos = res.position;
      v.setFrom(res.velocity);
    }
    final ev = legacy
        ? testPlane(f, BirdCircle(prev, r), BirdCircle(pos, r))
        : testPlane(
            f,
            BirdCircle(prev, r),
            BirdCircle(pos, r),
            prevFrame: pf,
          );
    if (ev != null) return Flight(ev.kind, touched, ev);
    if (isFullyPast(f, BirdCircle(pos, r))) {
      return Flight(PlaneEventKind.missPast, touched, null);
    }
    pf = f;
  }
  // A rim bounce can send the bird away for good (no plane, no gravity).
  if (touched) return Flight(PlaneEventKind.missPast, true, null);
  fail('no decision');
}

/// The six motion types (§3.11) at the strongest table values, phase [ph]
/// (0..1 of a cycle), for a hoop centred on a [viewHeight] screen.
Map<String, HoopMotion> motions(double ph, double viewHeight) {
  final centre = viewHeight / 2;
  final rail = LayoutConfig.rail;
  final half = rail.halfTravel.$2, v = rail.speed.$2;
  return {
    'vertical rail': RailMotion(
      MotionSpec(
        type: MotionType.rail,
        axisDeg: rail.axisDeg.$2,
        halfTravel: half,
        speed: v,
        phase: ph,
      ),
    ),
    'horizontal rail': RailMotion(
      MotionSpec(
        type: MotionType.horizontal,
        axisDeg: RunConfig.horizontalAxisDeg,
        halfTravel: half,
        speed: v,
        phase: ph,
      ),
    ),
    'diagonal rail +': RailMotion(
      MotionSpec(
        type: MotionType.diagonal,
        axisDeg: RunConfig.diagonalAxisDeg,
        halfTravel: half,
        speed: v,
        phase: ph,
      ),
    ),
    'diagonal rail −': RailMotion(
      MotionSpec(
        type: MotionType.diagonal,
        axisDeg: -RunConfig.diagonalAxisDeg,
        halfTravel: half,
        speed: v,
        phase: ph,
      ),
    ),
    'swing': SwingMotion(
      MotionSpec(
        type: MotionType.swing,
        amplitudeDeg: LayoutConfig.swing.amplitudeDeg,
        period: LayoutConfig.swing.period,
        rope: math.max(
          RunConfig.swingMinRope,
          centre - strip + RunConfig.swingPivotAbove,
        ),
        phase: ph * 2 * math.pi,
      ),
    ),
    'orbit': OrbitMotion(
      MotionSpec(
        type: MotionType.orbit,
        rx: RunConfig.orbitRx,
        ry: RunConfig.orbitRy,
        omega: RunConfig.orbitOmega,
        phase: ph * 2 * math.pi,
      ),
    ),
    'rock': RockMotion(
      MotionSpec(
        type: MotionType.rock,
        amplitudeDeg: RunConfig.rockAmplitudeDeg,
        period: RunConfig.rockPeriod,
        phase: ph * 2 * math.pi,
      ),
    ),
  };
}

/// Starts the bird so that it is at the ring centre + [dy] (local ring
/// line, screen y) at run time [tc], flying level at [speed].
Vector2 startFor(HoopMotion m, Vector2 home, double tc, double dy) {
  final c = home + m.offsetAt(tc);
  return Vector2(c.x - speed * tc, c.y + dy);
}

/// A swing at its maximum sideways speed toward the bird at t = 1 s (rope
/// of a 711 pt screen: ≈ 320 pt/s, faster than the bird).
SwingMotion fastSwing() {
  final w = 2 * math.pi / LayoutConfig.swing.period;
  return SwingMotion(
    MotionSpec(
      type: MotionType.swing,
      amplitudeDeg: LayoutConfig.swing.amplitudeDeg,
      period: LayoutConfig.swing.period,
      rope: 711 / 2 - strip + RunConfig.swingPivotAbove,
      // cos(w·1 + phase) = −1: moving left (toward the bird) at full speed.
      phase: math.pi - w,
    ),
  );
}

void main() {
  final home = Vector2(400, 355);

  group('PRD-2.2 §30.4 confirm first', () {
    test('§30 a swing ring at its maximum sideways speed toward the bird, '
        'the bird straight through the centre: the 2.1 single-pose test '
        'misses it at most step alignments; the relative test always '
        'passes', () {
      const dt = 1 / 60;
      var legacyMisses = 0;
      for (var k = 0; k < 20; k++) {
        final tc = 1 + k / 20 * dt;
        final m = fastSwing();
        expect(m.offsetAt(tc).x, lessThan(0.5), reason: 'near home');
        final start = startFor(m, home, tc, 0);
        final old = fly(m, home, 100, start, dt, legacy: true);
        if (old.kind == PlaneEventKind.missPast) legacyMisses++;
        final now = fly(fastSwing(), home, 100, start, dt);
        expect(now.kind, PlaneEventKind.pass, reason: 'alignment $k');
        expect(now.touched, isFalse, reason: 'alignment $k');
        expect(now.event!.offset.abs(), lessThan(2), reason: 'centred');
      }
      // The bug (PRD-2.2 §30 cause, confirmed 2026-10-12: 13 / 20).
      expect(legacyMisses, greaterThan(5));
    });
  });

  group('PRD-2.2 §30.4 phase sweep', () {
    for (final h in const [568.0, 711.0]) {
      for (final fps in const [60, 30]) {
        test('§30 every motion type × 200 phases, bird through the centre at '
            'the crossing: 100 % passes ($h pt, $fps fps)', () {
          final dt = 1 / fps;
          final hm = Vector2(400, h / 2);
          final fails = <String>[];
          for (final opening in const [92.0, 118.0]) {
            for (var i = 0; i < 200; i++) {
              final ph = i / 200;
              // Vary the step alignment of the crossing too.
              final tc = 1.5 + ((i * .618) % 1) * dt;
              for (final e in motions(ph, h).entries) {
                final start = startFor(e.value, hm, tc, 0);
                final fl = fly(e.value, hm, opening, start, dt);
                if (fl.kind != PlaneEventKind.pass || fl.touched) {
                  fails.add(
                    '${e.key} phase $i opening $opening: '
                    '${fl.kind.name} touched ${fl.touched}',
                  );
                }
              }
            }
          }
          expect(fails, isEmpty);
        });
      }
    }
  });

  group('PRD-2.2 §30.4 still misses', () {
    for (final h in const [568.0, 711.0]) {
      for (final fps in const [60, 30]) {
        test('§30 the same sweep with the bird outside the opening: a miss '
            'or a rim touch at every phase, never a clean pass ($h pt, $fps '
            'fps)', () {
          final dt = 1 / fps;
          final hm = Vector2(400, h / 2);
          final bad = <String>[];
          const opening = 92.0;
          const reach = opening / 2 + RunConfig.rimRadius;
          for (var i = 0; i < 200; i++) {
            final ph = i / 200;
            final tc = 1.5 + ((i * .618) % 1) * dt;
            for (final dy in const [reach + 3, -(reach + 3), reach + 40]) {
              for (final e in motions(ph, h).entries) {
                final start = startFor(e.value, hm, tc, dy);
                final fl = fly(e.value, hm, opening, start, dt);
                if (fl.kind == PlaneEventKind.pass && !fl.touched) {
                  bad.add('${e.key} phase $i dy $dy');
                }
              }
            }
          }
          expect(bad, isEmpty);
        });
      }
    }
  });

  group('PRD-2.2 §30.2 relative crossing (pure)', () {
    test('§30 the previous bird position is measured in the previous pose: '
        'a plane that jumps over the bird in one step is a pass', () {
      const reach = 100 / 2 + RunConfig.rimRadius;
      final pf = HoopFrame(centre: Vector2(400, 355), opening: 100);
      final f = HoopFrame(centre: Vector2(397, 355), opening: 100);
      final prev = BirdCircle(Vector2(398, 355), r);
      final now = BirdCircle(Vector2(400, 355), r);
      // 2.1: the ring's current pose for both → already past, no crossing.
      expect(testPlane(f, prev, now), isNull);
      final ev = testPlane(f, prev, now, prevFrame: pf);
      expect(ev?.kind, PlaneEventKind.pass);
      expect(ev?.offset, closeTo(0, 1e-9));
      expect(reach, 57);
    });

    test('§30 edge: a crossing exactly at the reach counts as a pass '
        '(both sides)', () {
      const reach = 100 / 2 + RunConfig.rimRadius;
      final pf = HoopFrame(centre: Vector2(400, 355), opening: 100);
      final f = HoopFrame(centre: Vector2(397, 355), opening: 100);
      for (final dy in const [reach, -reach]) {
        final ev = testPlane(
          f,
          BirdCircle(Vector2(398, 355 + dy), r),
          BirdCircle(Vector2(400, 355 + dy), r),
          prevFrame: pf,
        );
        expect(ev?.kind, PlaneEventKind.pass, reason: 'dy $dy');
        expect(ev!.offset, closeTo(dy, 1e-9));
      }
      expect(
        testPlane(
          f,
          BirdCircle(Vector2(398, 355 + reach + .1), r),
          BirdCircle(Vector2(400, 355 + reach + .1), r),
          prevFrame: pf,
        ),
        isNull,
      );
    });

    test('§30 the local y is interpolated to the crossing; the offset is '
        'measured from the crossed ring (pairs: per ring)', () {
      final pf = HoopFrame(
        centre: Vector2(400, 355),
        rings: const [-60, 60],
        opening: 80,
      );
      final f = HoopFrame(
        centre: Vector2(400, 355),
        rings: const [-60, 60],
        opening: 80,
      );
      // Crossing at u = 0.25: y = 415 + .25 · 8 = 417 → ring 1 offset 2.
      final ev = testPlane(
        f,
        BirdCircle(Vector2(399, 415), r),
        BirdCircle(Vector2(403, 423), r),
        prevFrame: pf,
      );
      expect(ev?.ring, 1);
      expect(ev!.offset, closeTo(2, 1e-9));
    });

    test('§30 backward crossings (a ring overtaking the bird) stay '
        'ignored', () {
      final pf = HoopFrame(centre: Vector2(398, 355), opening: 100);
      final f = HoopFrame(centre: Vector2(410, 355), opening: 100);
      expect(
        testPlane(
          f,
          BirdCircle(Vector2(400, 355), r),
          BirdCircle(Vector2(402, 355), r),
          prevFrame: pf,
        ),
        isNull,
      );
    });

    test('§30 still rings: one step, exactly the 2.1 result', () {
      final f = HoopFrame(centre: Vector2(400, 355), opening: 100);
      expect(
        HoopFrame.sweepSteps(
          f,
          f,
          BirdCircle(Vector2(399, 355)),
          BirdCircle(Vector2(401, 355)),
        ),
        1,
      );
      final a = testPlane(
        f,
        BirdCircle(Vector2(399, 355), r),
        BirdCircle(Vector2(401, 355), r),
      );
      final b = testPlane(
        f,
        BirdCircle(Vector2(399, 355), r),
        BirdCircle(Vector2(401, 355), r),
        prevFrame: f,
      );
      expect(a?.kind, PlaneEventKind.pass);
      expect(b?.kind, a?.kind);
    });

    test('§30 sub-steps: only for a ring that moves more than 2 pt (or a rim '
        'end swept that far) and only near the bird', () {
      final a = HoopFrame(centre: Vector2(400, 355), opening: 100);
      final slow = HoopFrame(centre: Vector2(401.5, 355), opening: 100);
      final fast = HoopFrame(centre: Vector2(404, 355), opening: 100);
      final turn = HoopFrame(
        centre: Vector2(400, 355),
        tilt: .05, // rim end: 57 × .05 ≈ 2.9 pt
        opening: 100,
      );
      final near = BirdCircle(Vector2(390, 355));
      final far = BirdCircle(Vector2(100, 355));
      expect(HoopFrame.sweepSteps(a, slow, near, near), 1);
      expect(
        HoopFrame.sweepSteps(a, fast, near, near),
        PhysicsConfig.sweepSubsteps,
      );
      expect(
        HoopFrame.sweepSteps(a, turn, near, near),
        PhysicsConfig.sweepSubsteps,
      );
      expect(HoopFrame.sweepSteps(a, fast, far, far), 1);
    });
  });

  group('PRD-2.2 §30.4 rims', () {
    test('§30 a fast-swinging rim end that crosses the bird within one step '
        'registers a touch (no tunnelling)', () {
      // A rocking ring whose bottom rim end sweeps from 30 pt left of the
      // bird to 30 pt right of it in one step (the bird sits on its path).
      const opening = 100.0;
      const reach = opening / 2 + RunConfig.rimRadius;
      final c = Vector2(400, 355);
      const a = 30 / reach; // ≈ ±30 pt at the rim end
      final pf = HoopFrame(centre: c, tilt: a, opening: opening);
      final f = HoopFrame(centre: c, tilt: -a, opening: opening);
      final bird = BirdCircle(Vector2(400, 355 + reach), r);
      final v = Vector2(0, 0);
      // Neither pose overlaps the bird…
      expect(collideRims(pf, bird, v), isNull);
      expect(collideRims(f, bird, v), isNull);
      // …but the sweep between them does.
      final res = collideRimsSwept(pf, f, bird, bird, v);
      expect(res, isNotNull);
      expect(res!.contacts.first.ring, 0);
      expect(res.contacts.first.side, 1);
    });

    test('§30 the current pose decides first: still / slow rings get '
        'exactly the 2.1 contact', () {
      final f = HoopFrame(centre: Vector2(400, 355), opening: 100);
      final bird = BirdCircle(Vector2(400, 355 + 57 + 10), r);
      final v = Vector2(150, 0);
      final a = collideRims(f, bird, v)!;
      final b = collideRimsSwept(f, f, bird, bird, v)!;
      expect(b.position, a.position);
      expect(b.velocity, a.velocity);
      expect(collideRimsSwept(null, f, bird, bird, v)!.position, a.position);
    });
  });
}
