import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flappy_spikes/run/config/physics_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/physics/bird_motion.dart';
import 'package:flappy_spikes/run/physics/hoop_frame.dart';
import 'package:flappy_spikes/run/physics/rim_collision.dart';
import 'package:flutter_test/flutter_test.dart';

const double r = RunConfig.birdRadius;

void main() {
  final f = HoopFrame(centre: Vector2(400, 355), opening: 118);
  final top = f.rimEnd(0, -1); // (400, 289)

  group('§3.0.4 1–3 rim-end circles (pure)', () {
    test('§3.0.4 1 two rim ends r 7 at local (0, ±(opening/2 + 7)), rotated '
        'with the tilt', () {
      expect(top, Vector2(400, 355 - 66));
      expect(f.rimEnd(0, 1), Vector2(400, 355 + 66));
      final t = HoopFrame(
        centre: Vector2(400, 355),
        opening: 118,
        tilt: math.pi / 6,
      );
      final e = t.rimEnd(0, -1);
      expect(e.x, closeTo(400 + 66 * math.sin(math.pi / 6), 1e-4));
      expect(e.y, closeTo(355 - 66 * math.cos(math.pi / 6), 1e-4));
    });

    test('no contact → null', () {
      expect(
        collideRims(f, BirdCircle(Vector2(300, 289), r), Vector2(150, 0)),
        isNull,
      );
    });

    test('§3.0.4 2 head-on: pushed out along the normal, the normal part '
        'reflected with restitution 0.85, the tangential part unchanged', () {
      final b = BirdCircle(Vector2(400 - 20, 289), r); // overlapping 1.75
      final res = collideRims(f, b, Vector2(150, 40))!;
      final c = res.contacts.single;
      expect(c.normal.x, closeTo(-1, 1e-4));
      expect(c.overlap, closeTo(r + 7 - 20, 1e-4));
      expect(res.position.distanceTo(top), closeTo(r + 7, 1e-4));
      expect(res.velocity.x, closeTo(-150 * RunConfig.rimRestitution, 1e-4));
      expect(res.velocity.y, closeTo(40, 1e-4));
      expect(c.bounced, isTrue);
    });

    test('§3.0.4 2 moving away: pushed out, velocity unchanged', () {
      final b = BirdCircle(Vector2(400 - 20, 289), r);
      final res = collideRims(f, b, Vector2(-30, 0))!;
      expect(res.velocity, Vector2(-30, 0));
      expect(res.bounced, isFalse);
      expect(res.position.distanceTo(top), closeTo(r + 7, 1e-4));
    });

    test('§3.0.4 2 relative to the rim\'s own velocity (moving rings)', () {
      final moving = HoopFrame(
        centre: Vector2(400, 355),
        opening: 118,
        velocity: Vector2(0, 100), // rim end moving down into the bird
      );
      final b = BirdCircle(Vector2(400, 289 + 20), r); // below the top end
      final res = collideRims(moving, b, Vector2.zero())!;
      expect(res.bounced, isTrue);
      // vn = (0 − 100)·(0,1) = −100 → vy += 1.85 × 100.
      expect(
        res.velocity.y,
        closeTo((1 + RunConfig.rimRestitution) * 100, 1e-4),
      );
    });

    test('§3.0.4 6 the inside half pushes the bird into the opening, the '
        'outside half away from it', () {
      final inside = collideRims(
        f,
        BirdCircle(Vector2(395, 289 + 15), r),
        Vector2(150, 0),
      )!.contacts.single;
      expect(inside.inside, isTrue);
      expect(inside.normal.y, greaterThan(0)); // down, into the opening
      final outside = collideRims(
        f,
        BirdCircle(Vector2(395, 289 - 15), r),
        Vector2(150, 0),
      )!.contacts.single;
      expect(outside.inside, isFalse);
      expect(outside.normal.y, lessThan(0)); // up, away from it
    });

    test('§3.0.4 3 the spin is one turn over 0.35 s, direction from vy', () {
      expect(
        rimSpinVelocity(-10),
        closeTo(-2 * math.pi / PhysicsConfig.rimSpinSeconds, 1e-4),
      );
      expect(
        rimSpinVelocity(10),
        closeTo(2 * math.pi / PhysicsConfig.rimSpinSeconds, 1e-4),
      );
    });

    test('§3.0.4 4 after a knock-back the forward speed recovers toward '
        'cruise at 2000 pt/s²', () {
      expect(BirdMotion.recover(-100, 150, .05), closeTo(0, 1e-4));
      expect(BirdMotion.recover(140, 150, .05), 150);
      expect(BirdMotion.recover(400, 150, .05), closeTo(300, 1e-4));
      // §3.0.1 cruise ramp: +3.5 % per minute of runClock.
      expect(BirdMotion.cruise(0), 150);
      expect(BirdMotion.cruise(60), closeTo(155.25, 1e-4));
    });
  });
}
