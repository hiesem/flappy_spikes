import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

// PRD-2.6 WP-D Tests: fly the real ceiling course, including D7 formations.
void main() {
  for (final start in [150, 250]) {
    for (final height in [568.0, 711.0]) {
      for (final seed in [7, 21, 1234]) {
        final tester = FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: height, seed: seed),
          gameSize: Vector2(Config.worldWidth, height),
        );
        tester.testGameWidget(
          'D7 ceiling autopilot start $start height $height seed $seed',
          setUp: (game, _) async {
            await game.ready();
            await preloadImages(game);
          },
          verify: (game, _) async {
            await startRun(game, startHoopIndex: start);
            final flight = await flyRun(game, untilHoops: 40);
            expect(
              flight.hoops,
              greaterThanOrEqualTo(40),
              reason:
                  '${flight.cause} at ${flight.seconds}s\n'
                  '${flight.trace.reversed.take(12).join('\n')}',
            );
          },
        );
      }
    }
  }
}
