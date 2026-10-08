import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// §3.8 / §7 playability gate (P3 test gate): the comet hoop forced on
/// every allowed slot from its unlock index (10), at 568 and 711 pt over
/// three seeds — the bot flies through the comet hoop (and its star), the
/// boost flies itself, and the bot takes over again after each landing.
/// ≥ 12 hoops is the PRD gate; the run must also survive two boosts and the
/// normal hoops after each landing (30 hoops).
void main() {
  for (final height in [568.0, 711.0]) {
    for (final seed in [3, 11, 29]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: height, seed: seed),
        gameSize: Vector2(320, height),
      ).testGameWidget(
        '§3.8 comet hoop on every slot from hoop 10: the autopilot passes ≥ '
        '12 hoops (${height.toInt()} pt, seed $seed)',
        setUp: (game, _) async {
          await game.ready();
          game.sound.enabled = false;
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(
            game,
            startHoopIndex: ElementId.comet.firstPossible!,
            force: [ElementId.comet],
          );
          // Every comet hoop passed has its star collected (the bot flies
          // through the star; it is touched just before the plane).
          var cometHoops = 0, stars = 0;
          run.events
            ..on<HoopPassed>((e) {
              if (e.hoop?.plan.cometHang == true) cometHoops++;
            })
            ..on<PickupCollected>((e) {
              if (e.element == ElementId.comet) stars++;
            });
          final flight = await flyRun(
            game,
            maxSeconds: 90,
            untilHoops: 30,
            onFrame: (r) {
              if (!r.director.forcedQueue.contains(ElementId.comet)) {
                r.debugForce(ElementId.comet);
              }
            },
          );
          final comet = run.features.whereType<CometFeature>().single;
          expect(
            flight.hoops,
            greaterThanOrEqualTo(30),
            reason: flight.trace.join('\n'),
          );
          expect(comet.started, greaterThanOrEqualTo(2));
          expect(stars, cometHoops);
          // A forced comet hoop planned just before a boost starts is flown
          // through by that boost: its star starts nothing.
          expect(comet.started, lessThanOrEqualTo(stars));
          expect(run.ended, isFalse);
        },
      );
    }
  }
}
