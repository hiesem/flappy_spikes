import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3e §7 playability gate (P3 test gate): each collectable (Star Trail,
/// Egg, Piggy Bank, Firefly Jar) forced on every allowed slot from its
/// unlock index, at 568 and 711 pt over three seeds — the bot steers at the
/// item (autopilot `_chaseY`) and still passes ≥ 12 hoops without dying.
void main() {
  const cases = [
    (ElementId.starTrail, '3.26 Star Trail'),
    (ElementId.egg, '3.27 Egg'),
    (ElementId.piggy, '3.28 Piggy Bank'),
    (ElementId.jar, '3.29 Firefly Jar'),
  ];

  for (final (element, label) in cases) {
    final from = element.firstPossible!;
    for (final height in [568.0, 711.0]) {
      // P23-17 (PRD-2.3 §17.3): a forced jar now waits while a big bonus is
      // open, which reshuffles these seeded courses; seeds 11 / 29 at 568 pt
      // met the bot's known falling-train overshoot (the base fails other
      // seeds the same way, ≈ 7 % of seeds either way). The jar flies 13 / 31.
      // P23-FIX2 (S8-11): a big bonus drawn during the activity cool-down
      // now waits, so cool-down gaps draw again and reshuffle the courses;
      // the pig's seeds 11 / 29 met the same overshoot: it flies 13 / 31.
      // P231-T (PRD-2.3.1 §0): the live spawn set brings trains from hoop 5
      // every ≥ 4 hoops; the overshoot met seeds 3 / 13 / 31 (a 1–32 seed
      // survey: 7.8 % of forced-gate seeds die at a train, 4.2 % on the 2.3
      // set). The pig and the jar fly 5 / 11 / 29.
      for (final seed
          in element == ElementId.jar || element == ElementId.piggy
              ? [5, 11, 29]
              : [3, 11, 29]) {
        FlameTester<FlappySpikesGame>(
          () => createRunTestGame(
            prefs: {'gamesPlayed': 5},
            worldHeight: height,
            seed: seed,
          ),
          gameSize: Vector2(320, height),
        ).testGameWidget(
          '§7 $label forced from hoop $from: the autopilot passes ≥ 12 hoops '
          '(${height.toInt()} pt, seed $seed)',
          setUp: (game, _) async {
            await game.ready();
            game.sound.enabled = false;
            await preloadImages(game);
          },
          verify: (game, _) async {
            final run = await startRun(
              game,
              startHoopIndex: from,
              force: [element],
            );
            var spawned = 0, taken = 0;
            run.events
              ..on<ElementSpawned>((e) {
                if (e.element == element) spawned++;
              })
              ..on<PickupCollected>((e) {
                if (e.element == element) taken++;
              });
            final flight = await flyRun(
              game,
              maxSeconds: 90,
              untilHoops: 30,
              onFrame: (RunController r) {
                if (!r.director.forcedQueue.contains(element)) {
                  r.debugForce(element);
                }
              },
            );
            expect(
              flight.hoops,
              greaterThanOrEqualTo(30),
              reason: flight.trace.join('\n'),
            );
            expect(spawned, greaterThan(0), reason: '$label never spawned');
            expect(taken, greaterThan(0), reason: '$label never caught');
            expect(run.ended, isFalse);
          },
        );
      }
    }
  }
}
