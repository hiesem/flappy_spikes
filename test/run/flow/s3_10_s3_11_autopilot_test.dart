import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.10 / §3.11 / §7 playability gate for angled and moving rings (WP-1b):
/// the hoop-aware autopilot passes ≥ 12 hoops at 568 and 711 pt with the
/// modifier forced on every slot from its unlock index.
///
/// Needs WP-1a's normal hoop (physics, pass test, `Hoop.frame()`): skipped
/// until the normal hoop is registered, then it runs by itself.
void main() {
  // Skipped: 'needs WP-1a' (no normal hoop registered yet).
  final needsWp1a = hoopKindFor(HoopKindId.normal) == null;

  for (final height in [568.0, 711.0]) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, seed: 11),
      gameSize: Vector2(320, height),
    );

    for (final (element, start, label) in [
      (ElementId.angledRing, 10, '§3.10 angled rings from hoop 10'),
      (ElementId.angledRing, 35, '§3.10 angled rings from hoop 35 (45° steps)'),
      (
        ElementId.movingRing,
        20,
        '§3.11 moving rings from hoop 20 (rail, swing)',
      ),
      (ElementId.movingRing, 45, '§3.11 moving rings from hoop 45 (all types)'),
    ]) {
      tester.testGameWidget(
        '$label on every slot: the autopilot passes ≥ 12 hoops '
        '(${height.toInt()} pt)',
        skip: needsWp1a,
        setUp: (game, _) async {
          await game.ready();
          game.sound.enabled = false;
          await preloadImages(game);
        },
        verify: (game, _) async {
          // Two forces: the first two slots are planned at once (PRD-2.2
          // §15 one slot ahead), before the first onFrame refill.
          final run = await startRun(
            game,
            startHoopIndex: start,
            force: [element, element],
          );
          var modified = 0, eligible = 0;
          final seen = <int>{};
          final flight = await flyRun(
            game,
            maxSeconds: 60,
            untilHoops: 12,
            onFrame: (r) {
              // Two in the queue (PRD-2.3: the faster cruise can plan two
              // slots in one frame), so every slot takes the modifier.
              while (r.director.forcedQueue.where((e) => e == element).length <
                  2) {
                r.debugForce(element);
              }
              for (final h in hoopsOf(game)) {
                if (!seen.add(h.plan.index)) continue;
                // PRD-2.3 §14.5 a comet may come on any hoop (2 %): its
                // star hoop and the ride's hoops stay plain, as do special
                // kinds (a first-meet).
                if (h.plan.cometHang ||
                    h.plan.duringRide ||
                    h.plan.kind != HoopKindId.normal) {
                  continue;
                }
                eligible++;
                // §3.11 a swinging ring hangs upright: a forced tilt that a
                // swing replaced still counts (PRD-2.3 §14.4 moves more
                // hoops from hoop 20).
                if (element == ElementId.angledRing
                    ? h.plan.tiltDeg != 0 ||
                          h.plan.motion?.type == MotionType.swing
                    : h.plan.motion != null) {
                  modified++;
                }
              }
            },
          );
          expect(
            flight.hoops,
            greaterThanOrEqualTo(12),
            reason: flight.trace.join('\n'),
          );
          // Every plain slot takes the modifier (one may be stripped when an
          // activity starts, PRD-2.2 §27.3).
          expect(eligible, greaterThanOrEqualTo(6));
          expect(modified, greaterThanOrEqualTo(eligible - 1));
          expect(run.ended, isFalse);
        },
      );
    }
  }
}
