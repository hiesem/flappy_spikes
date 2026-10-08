import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flappy_spikes/run/config/physics_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/physics/death_tumble.dart';
import 'package:flutter_test/flutter_test.dart';

const double vh = 711;
const double top = 44, floor = vh - 44;
const double r = RunConfig.birdRadius;

DeathTumble tumble({
  Vector2? pos,
  Vector2? vel,
  Vector2? normal,
  double camX = 1000,
}) => DeathTumble(
  position: pos ?? Vector2(camX + 70, 355),
  velocity: vel ?? Vector2(150, 0),
  normal: normal,
  camX: camX,
  camSpeed: 150,
  top: top,
  floor: floor,
);

void run(DeathTumble t, double seconds, [void Function(DeathTumble)? each]) {
  for (var i = 0; i < (seconds * 120).round(); i++) {
    t.step(1 / 120);
    each?.call(t);
  }
}

void main() {
  group('§3.0.5 death tumble (pure)', () {
    test('§3.0.5 the world eases to a stop over 0.4 s', () {
      final t = tumble();
      run(t, .2);
      expect(t.camSpeed, closeTo(75, 1));
      run(t, .21);
      expect(t.camSpeed, 0);
      final cam = t.camX;
      // Ease-out: half of 150 × 0.4 = 30 pt.
      expect(cam - 1000, closeTo(30, 1));
      run(t, 1);
      expect(t.camX, cam);
    });

    test('§3.0.5 momentum + 180 pt/s knock along the contact normal', () {
      final t = tumble(vel: Vector2(150, 200), normal: Vector2(-1, 0));
      expect(t.velocity, Vector2(150 - 180, 200));
      final up = tumble(vel: Vector2(150, 300), normal: Vector2(0, -1));
      expect(up.velocity, Vector2(150, 300 - 180));
    });

    test('§3.0.5 a plain miss pops the bird up (vy − 140)', () {
      final t = tumble(vel: Vector2(150, 50));
      expect(t.velocity, Vector2(150, 50 - PhysicsConfig.missPop));
    });

    test('§3.0.5 spin = clamp(forward / 25 + impact, ±12) rad/s', () {
      expect(tumble().spin, closeTo(150 / 25 + 3, 1e-9));
      expect(tumble(normal: Vector2(0, -1)).spin, closeTo(150 / 25 + 4, 1e-9));
      expect(tumble(vel: Vector2(600, 0)).spin, 12);
      expect(tumble(vel: Vector2(-600, 0)).spin, -12);
    });

    test('§3.0.5 bounces 1–2 times, then rests on the floor tooth line '
        '(tooth tips − r + 2), settled flat', () {
      for (final start in [150.0, 355.0, 600.0]) {
        final t = tumble(pos: Vector2(1070, start), vel: Vector2(150, 300));
        var lands = 0;
        t.onLand = (_) => lands++;
        run(t, 4);
        expect(t.resting, isTrue, reason: 'from $start');
        expect(t.position.y, closeTo(floor - r + 2, 1e-9));
        expect(t.bounces, inInclusiveRange(1, 3), reason: 'from $start');
        expect(lands, greaterThanOrEqualTo(t.bounces));
        expect(t.settledFlat, isTrue);
        final flat = (t.angle / math.pi).roundToDouble() * math.pi;
        expect(t.angle, closeTo(flat, .02));
        expect(t.velocity.x.abs(), lessThan(1), reason: 'slid to a stop');
      }
    });

    test('§3.0.5 never leaves the screen sideways (24 pt / 30 pt edges)', () {
      for (final vx in [900.0, -900.0, 150.0]) {
        final t = tumble(vel: Vector2(vx, -200));
        run(t, 4, (t) {
          final x = t.position.x - t.camX;
          expect(x, inInclusiveRange(24 - 1e-6, 320 - 30 + 1e-6));
        });
      }
    });

    test('§3.0.5 a top-strip hit bounces the bird back down (0.3)', () {
      final t = tumble(pos: Vector2(1070, 80), vel: Vector2(150, -600));
      var hitTop = false;
      run(t, .3, (t) {
        if (t.position.y - r <= top + 1e-6) hitTop = true;
        expect(t.position.y - r, greaterThanOrEqualTo(top - 1e-6));
      });
      expect(hitTop, isTrue);
      run(t, 4);
      expect(t.resting, isTrue);
    });

    test('§3.0.5 the resting line follows a squeezed floor', () {
      final t = tumble();
      run(t, 4);
      t.floor = floor - 60;
      run(t, .1);
      expect(t.position.y, closeTo(floor - 60 - r + 2, 1e-9));
    });
  });
}
