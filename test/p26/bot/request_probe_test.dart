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
        final run = await startRun(game);
        final bot = HumanNoiseBot(run, seed: 37);
        for (
          var frame = 0;
          frame < 60 * 240 && game.state.name == 'playing';
          frame++
        ) {
          if (bot.shouldFlap()) game.onScreenTap();
          game.update(1 / 60);
          if (frame % 10 == 9) await flushAndMount(game);
        }

        final offsets = bot.baseFlapOffsets
            .map((offset) => offset * 1000)
            .toList();
        expect(offsets.length, greaterThan(20));
        expect(offsets.any((offset) => offset < 0), isTrue);
        expect(_sd(offsets), closeTo(90, 10));
        expect(_mean(offsets), closeTo(0, 10));
        expect(
          bot.flapTimes.length,
          bot.baseFlapOffsets.length + bot.extraFlaps,
        );
        expect(bot.debugRequestForecast.length, bot.debugRequestTimes.length);
      },
    );
  }
}
