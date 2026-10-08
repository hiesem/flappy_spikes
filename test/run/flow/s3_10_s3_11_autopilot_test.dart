import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
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
          final run = await startRun(
            game,
            startHoopIndex: start,
            force: [element],
          );
          var modified = 0;
          final seen = <int>{};
          final flight = await flyRun(
            game,
            maxSeconds: 60,
            untilHoops: 12,
            onFrame: (r) {
              if (!r.director.forcedQueue.contains(element)) {
                r.debugForce(element);
              }
              for (final h in hoopsOf(game)) {
                if (!seen.add(h.plan.index)) continue;
                if (element == ElementId.angledRing
                    ? h.plan.tiltDeg != 0
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
          expect(modified, greaterThanOrEqualTo(10));
          expect(run.ended, isFalse);
        },
      );
    }
  }
}
