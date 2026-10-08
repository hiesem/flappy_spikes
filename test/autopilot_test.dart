import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The playability gate (PRD-2 §7, ARCH §7.1), rewritten for hoops by
/// WP-1a: the hoop-aware bang-bang [Autopilot] (prototype `botStep`) flies
/// the real run — director, spawner, plain-math rims / pass plane / spikes —
/// and must pass at least 12 hoops at 568 and at 711 pt.
void main() {
  for (final height in [568.0, 711.0]) {
    for (final seed in [7, 21, 1234]) {
      final tester = FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: height, seed: seed),
        gameSize: Vector2(Config.worldWidth, height),
      );
      tester.testGameWidget(
        'AUTOPILOT (${height.round()}) seed $seed: §7 the hoop-aware bot '
        'passes >= 12 hoops',
        setUp: (game, _) async {
          await game.ready();
          game.sound.enabled = false;
          await preloadImages(game);
        },
        verify: (game, _) async {
          await startRun(game);
          final flight = await flyRun(game, maxSeconds: 90, untilHoops: 30);
          expect(
            flight.hoops,
            greaterThanOrEqualTo(12),
            reason:
                'died at ${flight.hoops} hoops (${flight.cause}, '
                't=${flight.seconds.toStringAsFixed(1)} s, h=$height)\n'
                '${flight.trace.reversed.take(12).join('\n')}',
          );
          // ignore: avoid_print
          print(
            'AUTOPILOT h=$height seed=$seed: ${flight.hoops} hoops, '
            '${flight.seconds.toStringAsFixed(1)} s, cause ${flight.cause}',
          );
        },
      );
    }
  }
}
