import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
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

  // PRD-2.6 WP-D: the shared 90 ms / 10% extra-flap bot is the
  // "after 10 games ≈40" proxy. Keep all runs ordinary and unassisted.
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, prefs: {'gamesPlayed': 10}),
      gameSize: Vector2(Config.worldWidth, height),
    ).testGameWidget(
      'D human-noise median >=40 from hoop 0 gamesPlayed 10 h=$height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        final scores = <int>[];
        final outcomes = <String>[];
        game.runDebug.ignoreGates = false;
        for (var seed = 0; seed < 21; seed++) {
          game.runSeed = seed;
          game.storage.gamesPlayed = 10;
          final run = await startRun(game);
          expect(run.setup.showcase, isNull);
          expect(run.setup.ignoreGates, isFalse);
          final flight = await flyHumanNoiseBotToDeath(game, seed: seed);
          scores.add(flight.hoops);
          outcomes.add(
            'seed=$seed hoops=${flight.hoops} cause=${flight.cause} '
            'seconds=${flight.seconds.toStringAsFixed(1)}',
          );
          game.replay();
          await flushAndMount(game);
          stepGame(game, .4);
          await flushAndMount(game);
        }
        scores.sort();
        expect(
          scores[scores.length ~/ 2],
          greaterThanOrEqualTo(40),
          reason: 'h=$height scores=$scores\n${outcomes.join('\n')}',
        );
      },
    );
  }
}
