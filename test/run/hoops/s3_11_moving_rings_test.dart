import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flappy_spikes/run/hoops/motion/motion_guide.dart';
import 'package:flappy_spikes/run/hoops/motion/moving_rings_feature.dart';
import 'package:flappy_spikes/run/pickups/heart_pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_context.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const double deg = math.pi / 180;

/// A bare normal hoop kind (WP-1a's real one is not here yet).
class _Kind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.normal;
  @override
  bool get usesTierLook => true;
  @override
  void buildVisual(Hoop h, RunContext c) {}
}

/// Speed of [m] at [t] by central difference of [HoopMotion.offsetAt].
Vector2 numericVelocity(HoopMotion m, double t) {
  const h = 1e-4;
  return (m.offsetAt(t + h) - m.offsetAt(t - h)) / (2 * h);
}

SlotPlan plan({MotionSpec? motion, double tilt = 0}) => SlotPlan(
  index: 30,
  kind: HoopKindId.normal,
  element: ElementId.normalHoop,
  trackX: 500,
  centreY: 350,
  opening: 100,
  tiltDeg: tilt,
  motion: motion,
  advance: RunConfig.spacing,
);

void main() {
  group('§3.11 motion paths (HoopMotion)', () {
    test('§3.11 rail slide: constant 30–39 pt/s along the axis, ±half '
        'travel, turning round at the ends; period 4 × half / speed', () {
      const spec = MotionSpec(
        type: MotionType.rail,
        axisDeg: 20,
        halfTravel: 50,
        speed: 35,
        phase: 0.3,
      );
      final m = RailMotion(spec);
      expect(m.period, closeTo(4 * 50 / 35, 1e-3));
      final axis = Vector2(math.sin(20 * deg), math.cos(20 * deg));
      var turns = 0;
      Vector2? lastV;
      for (var t = 0.0; t < 2 * m.period; t += 0.01) {
        m.poseAt(t);
        // On the axis, within ±50.
        expect(m.offset.length, lessThanOrEqualTo(50 + 1e-6));
        expect(m.offset.x * axis.y - m.offset.y * axis.x, closeTo(0, 1e-3));
        expect(m.velocity.length, closeTo(35, 1e-3));
        expect(m.angleOffset, 0);
        if (lastV != null && lastV.dot(m.velocity) < 0) turns++;
        lastV = m.velocity.clone();
        if ((t * 100).round() % 37 == 5) {
          final n = numericVelocity(m, t);
          if ((n.length - 35).abs() < 1) {
            expect(n.x, closeTo(m.velocity.x, .05));
            expect(n.y, closeTo(m.velocity.y, .05));
          }
        }
      }
      expect(turns, 4);
    });

    test('§3.11 horizontal slide moves toward / away from the bird only; '
        'diagonals run on ±38° off horizontal', () {
      final h = HoopMotion.fromSpec(
        const MotionSpec(
          type: MotionType.horizontal,
          axisDeg: 90,
          halfTravel: 60,
          speed: 30,
        ),
      );
      for (var t = 0.0; t < 9; t += .1) {
        expect(h.offsetAt(t).y, closeTo(0, 1e-3));
        expect(h.offsetAt(t).x.abs(), lessThanOrEqualTo(60 + 1e-3));
      }
      for (final sign in [-1.0, 1.0]) {
        final d = HoopMotion.fromSpec(
          MotionSpec(
            type: MotionType.diagonal,
            axisDeg: 52 * sign,
            halfTravel: 40,
            speed: 39,
          ),
        );
        final o = d.offsetAt(0.4);
        expect(math.atan2(o.y.abs(), o.x.abs()) / deg, closeTo(38, 1e-6));
      }
    });

    test('§3.11 swing: the ring stays on the rope (pivot above), ±15°, '
        'period 1.8 s, in line with the rope', () {
      const spec = MotionSpec(
        type: MotionType.swing,
        amplitudeDeg: 15,
        period: 1.8,
        rope: 300,
        phase: 0.7,
      );
      final m = SwingMotion(spec);
      var maxA = 0.0;
      for (var t = 0.0; t < 3.6; t += 0.01) {
        m.poseAt(t);
        final fromPivot = m.offset - m.pivot;
        expect(fromPivot.length, closeTo(300, 1e-3));
        final rope = math.atan2(fromPivot.x, fromPivot.y); // from straight down
        expect(
          m.angleOffset,
          closeTo(-rope, 1e-4),
          reason: 'in line with the rope',
        );
        maxA = math.max(maxA, rope.abs());
        final n = numericVelocity(m, t);
        expect(n.x, closeTo(m.velocity.x, .05));
        expect(n.y, closeTo(m.velocity.y, .05));
      }
      expect(maxA / deg, closeTo(15, .05));
      expect(m.offsetAt(0.3).x, closeTo(m.offsetAt(0.3 + 1.8).x, 1e-6));
      expect(m.pivot.y, -300);
    });

    test('§3.11 orbit: ellipse rx × ry around home, path speed ≤ 39 pt/s, '
        'angle ±22° along the path', () {
      const spec = MotionSpec(
        type: MotionType.orbit,
        rx: RunConfig.orbitRx,
        ry: RunConfig.orbitRy,
        omega: RunConfig.orbitOmega,
        phase: 1,
      );
      final m = OrbitMotion(spec);
      var maxA = 0.0, maxV = 0.0;
      for (var t = 0.0; t < 10; t += 0.01) {
        m.poseAt(t);
        final e = math.pow(m.offset.x / 25, 2) + math.pow(m.offset.y / 31, 2);
        expect(e, closeTo(1, 1e-4));
        maxA = math.max(maxA, m.angleOffset.abs());
        maxV = math.max(maxV, m.velocity.length);
        final n = numericVelocity(m, t);
        expect(n.x, closeTo(m.velocity.x, .05));
        expect(n.y, closeTo(m.velocity.y, .05));
      }
      expect(maxA / deg, closeTo(22, .05));
      expect(maxV, lessThanOrEqualTo(39));
      expect(maxV, greaterThan(30));
    });

    test('§3.11 rock: stays in place, ±15°, period 3 s', () {
      final m = HoopMotion.fromSpec(
        const MotionSpec(
          type: MotionType.rock,
          amplitudeDeg: 15,
          period: 3,
          phase: .2,
        ),
      );
      var maxA = 0.0;
      for (var t = 0.0; t < 6; t += 0.01) {
        m.poseAt(t);
        expect(m.offset, Vector2.zero());
        expect(m.velocity, Vector2.zero());
        maxA = math.max(maxA, m.angleOffset.abs());
      }
      expect(maxA / deg, closeTo(15, .05));
      m.poseAt(1.1);
      final a = m.angleOffset;
      m.poseAt(4.1);
      expect(m.angleOffset, closeTo(a, 1e-3));
    });

    test(
      '§3.11 / §3.10 a moving ring is posed at home + offset, tilt + '
      'angle offset — both halves; the pose is a function of runClock only',
      () {
        const spec = MotionSpec(
          type: MotionType.orbit,
          rx: 25,
          ry: 31,
          omega: 1.25,
        );
        final h = Hoop(
          plan: plan(motion: spec, tilt: 30),
          kind: _Kind(),
        );
        final m = HoopMotion.fromSpec(spec);
        h.motion = m;
        m.update(h, 2);
        final o = m.offsetAt(2);
        expect(h.position.x, closeTo(500 + o.x, 1e-3));
        expect(h.position.y, closeTo(350 + o.y, 1e-3));
        expect(
          h.angle,
          closeTo(30 * deg + 22 * deg * math.sin(2 * 1.25), 1e-3),
        );
        expect(h.front.position, h.position);
        expect(h.front.angle, h.angle);
        expect(h.basePosition, Vector2(500, 350));
        // Same clock → same pose (pause / revive / tumble hold it).
        final p = h.position.clone();
        m.update(h, 2);
        expect(h.position, p);
      },
    );
  });

  group('§5.12 guide painter', () {
    test('§5.12 every motion type paints its guide (no throw), with '
        'arrowheads 13 × 12', () {
      final rec = PictureRecorder();
      final c = Canvas(rec);
      for (final spec in const [
        MotionSpec(
          type: MotionType.rail,
          axisDeg: 10,
          halfTravel: 50,
          speed: 33,
        ),
        MotionSpec(
          type: MotionType.horizontal,
          axisDeg: 90,
          halfTravel: 50,
          speed: 33,
        ),
        MotionSpec(
          type: MotionType.diagonal,
          axisDeg: -52,
          halfTravel: 50,
          speed: 33,
        ),
        MotionSpec(
          type: MotionType.swing,
          amplitudeDeg: 15,
          period: 1.8,
          rope: 300,
        ),
        MotionSpec(type: MotionType.orbit, rx: 25, ry: 31, omega: 1.25),
        MotionSpec(type: MotionType.rock, amplitudeDeg: 15, period: 3),
      ]) {
        MotionGuidePainter.paint(
          c,
          spec,
          opening: 100,
          color: const Color(0xFF828282),
        );
      }
      rec.endRecording().dispose();
    });
  });

  group('§3.10 / §3.11 / §3.3 in a run', () {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711),
      gameSize: Vector2(320, 711),
    );

    Future<void> boot(FlappySpikesGame game) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      testHoopKinds[HoopKindId.normal] = _Kind.new;
      addTearDown(testHoopKinds.clear);
      game.runDebug.god = true; // no WP-1a physics yet
    }

    test('§3.0.8 angled and moving rings and the heart are registered', () {
      expect(
        registeredElements(),
        containsAll([ElementId.angledRing, ElementId.movingRing]),
      );
      expect(registeredPickupElements(), contains(ElementId.heart));
      expect(pickupKindFor(ElementId.heart), isA<HeartPickupKind>());
    });

    tester.testGameWidget(
      '§3.11 a moving hoop gets its motion and its guide at the home '
      'position (spawned together off-screen right); it moves with '
      'runClock and the guide leaves with the hoop',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: 45,
          force: [ElementId.movingRing],
        );
        final feature = run.features.whereType<MovingRingsFeature>().single;
        final first = hoopsOf(game).first;
        expect(first.plan.motion, isNotNull);
        expect(first.motion, isA<HoopMotion>());
        expect(
          first.planeX,
          greaterThan(run.state.camX + 320),
          reason: 'off-screen right',
        );
        await flushAndMount(game);
        final guides = run.layers.back.children
            .whereType<MotionGuide>()
            .toList();
        expect(guides, hasLength(1));
        expect(guides.single.position, first.basePosition);
        expect(
          guides.single.priority,
          lessThan(first.priority),
          reason: 'under the ring',
        );

        final m = first.motion! as HoopMotion;
        final poses = <Vector2>{};
        await flyRun(
          game,
          maxSeconds: 1.5,
          onFrame: (r) {
            final want = first.basePosition + m.offsetAt(r.state.runClock);
            expect(first.position.x, closeTo(want.x, 1e-3));
            expect(first.position.y, closeTo(want.y, 1e-3));
            poses.add(first.position.clone()..add(Vector2(first.angle, 0)));
          },
        );
        expect(poses.length, greaterThan(10), reason: 'it moves');

        // Paused: the clock stops, so does the ring.
        run.pause();
        final held = first.position.clone();
        final heldA = first.angle;
        stepGame(game, .5);
        expect(first.position, held);
        expect(first.angle, heldA);
        run.resume();

        // Fly on until the first hoop is culled: its guide goes too.
        await flyRun(game, maxSeconds: 6);
        expect(first.isRemoved || first.isRemoving, isTrue);
        await flushAndMount(game);
        expect(feature.movingHoops, isNot(contains(first)));
        for (final g in run.layers.back.children.whereType<MotionGuide>()) {
          expect(g.position, isNot(first.basePosition));
        }
      },
    );

    tester.testGameWidget(
      '§3.10 an angled hoop is rotated around its centre by its tilt step '
      '(positive = top leans right), front and back halves alike',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: 35,
          force: [ElementId.angledRing],
        );
        final h = hoopsOf(game).first;
        expect(h.plan.tiltDeg, isNot(0));
        expect(h.plan.motion, isNull);
        await flyRun(game, maxSeconds: .5);
        expect(h.angle, closeTo(h.plan.tiltDeg * deg, 1e-3));
        expect(h.front.angle, h.angle);
        expect(h.position, h.basePosition);
        expect(run.layers.back.children.whereType<MotionGuide>(), isEmpty);
        // Met once it is on screen.
        await flyRun(game, maxSeconds: 1.5);
        expect(game.storage.metElements, contains('angled_ring'));
      },
    );

    tester.testGameWidget(
      '§3.3 heart placement (PRD-2.2 §19): the director\'s first heart (a '
      'random gap 5–27) becomes a heart pickup 30–70 % along its gap, ±50 pt '
      'off the straight line between the two hoops',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        final run = await startRun(game);
        game.runDebug.god = true;
        HeartPickup? heart;
        await flyRun(
          game,
          maxSeconds: 60,
          onFrame: (r) {
            heart ??= pickupsOf(
              game,
            ).whereType<HeartPickup>().firstOrNull;
          },
        );
        expect(heart, isNotNull);
        final gaps = run.spawner.gapLog
            .where((g) => g.items.any((i) => i.kind == ElementId.heart))
            .map((g) => g.index)
            .toList();
        final g = gaps.first;
        expect(g, inInclusiveRange(5, 30));
        final slots = run.spawner.slotLog;
        final a = slots.firstWhere((s) => s.index == g);
        final b = slots.firstWhere((s) => s.index == g + 1);
        final plan = heart!.plan!;
        expect(plan.kind, ElementId.heart);
        final u = (heart!.position.x - a.lastRingX) / RunConfig.spacing;
        expect(u, inInclusiveRange(.3 - 1e-6, .7 + 1e-6));
        final lineY =
            a.centreY +
            (b.centreY - a.centreY) *
                (heart!.position.x - a.lastRingX) /
                (b.trackX - a.lastRingX);
        final lo = RunConfig.stripHeight + RunConfig.itemEdgeMargin;
        final hi = 711 - RunConfig.stripHeight - RunConfig.itemEdgeMargin;
        expect(
          heart!.position.y,
          closeTo((lineY + plan.lineOffset).clamp(lo, hi), 1e-3),
        );
        expect(plan.lineOffset.abs(), lessThanOrEqualTo(50));
        expect(heart!.hitRadius, 16);
      },
    );
  });
}
