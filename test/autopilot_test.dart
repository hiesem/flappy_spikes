import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The playability gate (PRD-2 §7, ARCH §7.1), rewritten for hoops by
/// WP-1a: the hoop-aware bang-bang [Autopilot] (prototype `botStep`) flies
/// the real run — director, spawner, plain-math rims / pass plane / spikes —
/// and must pass at least 12 hoops at 568 and at 711 pt — with and without
/// the Big Hoops boost (WP-2a, §3.6).
void main() {
  for (final height in [568.0, 711.0]) {
    for (final seed in [7, 21, 1234]) {
      for (final big in [false, true]) {
        final tester = FlameTester<FlappySpikesGame>(
          () => createRunTestGame(worldHeight: height, seed: seed),
          gameSize: Vector2(Config.worldWidth, height),
        );
        tester.testGameWidget(
          'AUTOPILOT (${height.round()}) seed $seed${big ? ' Big Hoops' : ''}: '
          '§7 the hoop-aware bot passes >= 12 hoops',
          setUp: (game, _) async {
            await game.ready();
            game.sound.enabled = false;
            await preloadImages(game);
          },
          verify: (game, _) async {
            final run = await startRun(
              game,
              starter: big ? Powerup.bigHoops : Powerup.none,
            );
            // §3.6 / §7 the gate with the Big Hoops boost on.
            expect(run.state.bigHoops != null, big);
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
              'AUTOPILOT h=$height seed=$seed big=$big: ${flight.hoops} hoops, '
              '${flight.seconds.toStringAsFixed(1)} s, cause ${flight.cause}',
            );
          },
        );
      }
    }
  }
}
