import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/physics/bird_motion.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/physics/pass_test.dart';
import 'package:flappy_spikes/run/physics/rim_collision.dart';
import 'package:flutter_test/flutter_test.dart';

const double r = RunConfig.birdRadius;
const double opening = 118;

HoopFrame frame({double tiltDeg = 0, List<double> rings = const [0]}) =>
    HoopFrame(
      centre: Vector2(400, 355),
      tilt: tiltDeg * math.pi / 180,
      rings: rings,
      opening: opening,
    );

BirdCircle at(double x, double y) => BirdCircle(Vector2(x, y), r);

/// A pure flight (no gravity) through [f]: level at [start], forward at
/// cruise, rims and the plane test as the run does it. Returns the first
/// decision (pass / missPast) and whether a rim was touched.
(PlaneEventKind, bool) fly(HoopFrame f, Vector2 start) {
  var pos = start.clone();
  final v = Vector2(RunConfig.cruiseSpeed, 0);
  var touched = false;
  const dt = 1 / 120;
  for (var i = 0; i < 2000; i++) {
    final prev = pos.clone();
    v.x = BirdMotion.recover(v.x, RunConfig.cruiseSpeed, dt);
    pos = pos + v * dt;
    final res = collideRims(f, BirdCircle(pos, r), v);
    if (res != null) {
      touched = touched || res.bounced;
      pos = res.position;
      v.setFrom(res.velocity);
    }
    final ev = testPlane(f, BirdCircle(prev, r), BirdCircle(pos, r));
    if (ev != null) return (ev.kind, touched);
    if (isFullyPast(f, BirdCircle(pos, r))) {
      return (PlaneEventKind.missPast, touched);
    }
  }
  fail('no decision');
}

void main() {
  group('§3.0.4 5 pass test (pure)', () {
    test('§3.0.4 inside the opening scores: a forward crossing between the '
        'rim-end centres is a pass', () {
      final f = frame();
      final ev = testPlane(f, at(399, 355), at(401, 355));
      expect(ev?.kind, PlaneEventKind.pass);
      expect(ev?.ring, 0);
    });

    test('§3.0.4 the segment ends at the rim-end centres (opening/2 + 7)', () {
      final f = frame();
      final reach = opening / 2 + 7;
      expect(
        testPlane(f, at(399, 355 - reach), at(401, 355 - reach))?.kind,
        PlaneEventKind.pass,
      );
      expect(
        testPlane(f, at(399, 355 + reach), at(401, 355 + reach))?.kind,
        PlaneEventKind.pass,
      );
      expect(
        testPlane(f, at(399, 355 - reach - .1), at(401, 355 - reach - .1)),
        isNull,
      );
    });

    test('§3.0.4 crossings of the plane beside the ring decide nothing', () {
      final f = frame();
      expect(testPlane(f, at(399, 150), at(401, 150)), isNull);
      expect(testPlane(f, at(399, 600), at(401, 600)), isNull);
    });

    test('§3.0.4 a bird knocked back across the plane is not judged', () {
      final f = frame();
      expect(testPlane(f, at(401, 355), at(399, 355)), isNull);
      // ... and the next forward crossing still counts.
      expect(
        testPlane(f, at(399, 355), at(401, 355))?.kind,
        PlaneEventKind.pass,
      );
    });

    test('§3.0.4 pairs: the crossing names the ring it went through', () {
      final f = frame(rings: const [-115, 115]);
      expect(testPlane(f, at(399, 355 + 115), at(401, 355 + 115))?.ring, 1);
      expect(testPlane(f, at(399, 355 - 115), at(401, 355 - 115))?.ring, 0);
      expect(testPlane(f, at(399, 355), at(401, 355)), isNull);
    });

    test('§3.0.4 miss only when fully past: centre − r > rightmost point', () {
      final f = frame();
      final right = 400 + 7.0; // upright: centre + rim radius
      expect(f.rightmostX, closeTo(right, 1e-9));
      expect(isFullyPast(f, at(right + r - .1, 150)), isFalse);
      expect(isFullyPast(f, at(right + r + .1, 150)), isTrue);
    });

    test('§3.0.4 rightmost point of a tilted ring: centre x + |sin| × '
        '(largest offset + opening/2 + 7) + 7', () {
      for (final deg in [-20.0, -10.0, 15.0, 30.0, 45.0]) {
        final f = frame(tiltDeg: deg);
        final s = math.sin(deg * math.pi / 180).abs();
        expect(f.rightmostX, closeTo(400 + s * (opening / 2 + 7) + 7, 1e-9));
      }
    });

    test('§3.0.4 a tilted ring is never missed early (every tilt step)', () {
      for (final deg in [-20.0, -10.0, 15.0, 30.0, 45.0]) {
        final f = frame(tiltDeg: deg);
        // The end that leans right: the bird is already right of the centre
        // but has not crossed the plane there; it must not be a miss.
        final side = deg > 0 ? -1 : 1;
        final end = f.rimEnd(0, side);
        final inside = f.toWorld(Vector2(-r - 2, side * (opening / 2 - 4)));
        if (deg.abs() >= 30) {
          expect(inside.x, greaterThan(f.centre.x), reason: '$deg°');
        }
        expect(isFullyPast(f, BirdCircle(inside, r)), isFalse, reason: '$deg°');
        expect(isFullyPast(f, at(end.x + 1, end.y)), isFalse, reason: '$deg°');
        // A level path through the leaning half: it is right of the centre
        // well before its plane crossing, and still goes through.
        final through = f.toWorld(Vector2(-r - 2, side * 25.0));
        var maxX = 0.0;
        var pos = through.clone();
        while (f.toLocal(pos).x < 0) {
          maxX = math.max(maxX, pos.x);
          pos.x += 1;
        }
        if (deg.abs() >= 15) {
          expect(maxX - r, greaterThan(f.centre.x - r), reason: '$deg°');
        }
        expect(
          fly(f, through - Vector2(30, 0)).$1,
          PlaneEventKind.pass,
          reason: '$deg°',
        );
      }
    });

    test('§3.0.4 a bird pressed against the inside of a rim end passes '
        '(upright and every tilt step, both ends)', () {
      for (final deg in [0.0, -20.0, -10.0, 15.0, 30.0, 45.0]) {
        final f = frame(tiltDeg: deg);
        for (final side in const [-1, 1]) {
          // A level path 12 pt inside the rim-end centre (towards the
          // ring's centre along its axis), from 60 pt before it: the bird
          // circle overlaps the rim end from the inside.
          final end = f.rimEnd(0, side);
          final inward = (f.centre - end).normalized();
          final start = Vector2(end.x - 60, end.y + inward.y * 12);
          final (kind, touched) = fly(f, start);
          expect(kind, PlaneEventKind.pass, reason: '$deg° side $side');
          expect(touched, isTrue, reason: '$deg° side $side touches the rim');
        }
      }
    });

    test('§3.0.4 flying level outside the ring is a miss (fully past)', () {
      for (final deg in [0.0, 15.0, 45.0, -20.0]) {
        final f = frame(tiltDeg: deg);
        expect(
          fly(f, Vector2(250, 150)).$1,
          PlaneEventKind.missPast,
          reason: '$deg°',
        );
      }
    });
  });
}
