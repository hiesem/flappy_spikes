import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

double _mean(List<double> x) =>
    x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;
double _sd(List<double> x) {
  if (x.length < 2) return 0;
  final m = _mean(x);
  return math.sqrt(
    x.map((e) => (e - m) * (e - m)).reduce((a, b) => a + b) / (x.length - 1),
  );
}

void main() {
  for (final height in [568.0, 711.0]) {
    FlameTester(
      () => createRunTestGame(worldHeight: height, seed: 11),
      gameSize: Vector2(Config.worldWidth, height),
    ).testGameWidget(
      'emitted flaps bracket real autopilot requests at ${height.round()} pt',
      setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      },
      verify: (game, _) async {
        // A single run can die after roughly 100 taps: at sigma 90 ms its
        // mean has a standard error near 9 ms. Keep the original +/-10 ms
        // tolerance, but measure enough independent noise streams to resolve
        // it. Hold course/history fixed so the heights are comparable.
        final offsets = <double>[];
        final emittedJitters = <double>[];
        for (var seed = 0; seed < 64; seed++) {
          game.storage
            ..gamesPlayed = 10
            ..metElements = {}
            ..lastPortalRide = null
            ..lastFeatherRun = -1
            ..lastPieceRun = -1
            ..feathers = 0
            ..puzzlePieces = 0;
          final run = await startRun(game);
          final bot = HumanNoiseBot(run, seed: seed);
          final emitted = <double>[];
          for (
            var frame = 0;
            frame < 60 * 60 && game.state.name == 'playing';
            frame++
          ) {
            final extrasBefore = bot.extraFlaps;
            if (bot.shouldFlap()) {
              emitted.add(run.state.runClock);
              if (bot.extraFlaps == extrasBefore) {
                emittedJitters.add(bot.scheduler.jitterSeconds.last * 1000);
              }
              game.onScreenTap();
            }
            game.update(1 / 60);
            if (frame % 10 == 9) await flushAndMount(game);
          }

          offsets.addAll(bot.baseFlapOffsets.map((offset) => offset * 1000));
          expect(bot.flapTimes, orderedEquals(emitted));
          expect(
            bot.flapTimes.length,
            bot.baseFlapOffsets.length + bot.extraFlaps,
          );
          expect(bot.debugRequestForecast.length, bot.debugRequestTimes.length);
          expect(bot.debugRequestForecast.any((delay) => delay > 0), isTrue);
          game.replay();
          await flushAndMount(game);
          stepGame(game, .4);
          await flushAndMount(game);
        }

        expect(offsets.length, greaterThanOrEqualTo(500));
        expect(offsets.any((offset) => offset < 0), isTrue);
        expect(_sd(offsets), closeTo(90, 10));
        expect(_mean(offsets), closeTo(0, 10));
        expect(emittedJitters.length, offsets.length);
        // Report raw draws separately from actual emitted offsets, retaining
        // frame quantization / unavailable early-tap effects in the gate.
        // ignore: avoid_print
        print(
          'REQUEST PROBE h=$height seeds=64 n=${offsets.length} '
          'mean=${_mean(offsets)}ms sd=${_sd(offsets)}ms '
          'SE=${_sd(offsets) / math.sqrt(offsets.length)}ms '
          'rawMean=${_mean(emittedJitters)}ms',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
