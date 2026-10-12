import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// PRD-2.2 §30.4 in the real run (RunController `_stepPhysics`): every
/// moving ring becomes a fast swing (rope of a 711 pt screen, ≈ 320 pt/s
/// sideways — faster than the bird) at a random phase, and the bird is held
/// on the ring's centre line. Every such ring must be passed, none missed;
/// the pass records the crossing offset in the ring's moving frame.
void main() {
  for (final fps in const [60, 30]) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: 5),
      gameSize: Vector2(320, 711),
    );
    tester.testGameWidget(
      '§30 fast swinging rings flown through the centre are passed, never '
      'missed ($fps fps)',
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: 45,
          force: [ElementId.movingRing],
        );
        game.runDebug.god = true; // keep flying after a (buggy) miss
        final rng = math.Random(3);
        final swung = <Hoop>{};
        final passed = <Hoop>[];
        final missed = <Hoop>[];
        run.events.onAny((e) {
          switch (e) {
            case HoopPassed(:final hoop) when swung.contains(hoop):
              passed.add(hoop!);
            case HoopMissed(:final hoop) when swung.contains(hoop):
              missed.add(hoop);
            default:
              break;
          }
        });
        await flyUntil(
          game,
          (r) => passed.length + missed.length >= 10,
          maxSeconds: 60,
          dt: 1 / fps,
          flap: (r) {
            if (!r.director.forcedQueue.contains(ElementId.movingRing)) {
              r.debugForce(ElementId.movingRing);
            }
            for (final h in r.spawner.hoops) {
              if (h.motion is HoopMotion && !swung.contains(h)) {
                swung.add(h);
                h.motion = SwingMotion(
                  MotionSpec(
                    type: MotionType.swing,
                    amplitudeDeg: LayoutConfig.swing.amplitudeDeg,
                    period: LayoutConfig.swing.period,
                    rope: 711 / 2 - 44 + RunConfig.swingPivotAbove,
                    phase: rng.nextDouble() * 2 * math.pi,
                  ),
                );
                h.syncMotion(r.state.runClock);
              }
            }
            final next = r.spawner.nextHoopAhead();
            if (next != null && r.state.ride == null) {
              final f = next.frame();
              game.runBird!.setFlight(y: f.centre.y, vy: 0);
            }
            return false;
          },
        );
        expect(missed, isEmpty);
        expect(passed.length, greaterThanOrEqualTo(10));
        for (final h in passed) {
          expect(h.passOffset, isNotNull);
          expect(h.passOffset!.abs(), lessThan(8), reason: 'centred');
        }
      },
    );
  }
}
