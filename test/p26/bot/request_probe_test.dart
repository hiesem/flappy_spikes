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
    for (final seed in [23, 41, 43, 37]) {
      FlameTester(
        () => createRunTestGame(worldHeight: height, seed: 11),
        gameSize: Vector2(Config.worldWidth, height),
      ).testGameWidget('probe $seed', setUp: (game, _) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
      }, verify: (game, _) async {
        final run = await startRun(game);
        final bot = HumanNoiseBot(run, seed: seed);
        for (var f = 0; f < 60 * 240 && game.state.name == 'playing'; f++) {
          if (bot.shouldFlap()) game.onScreenTap();
          game.update(1 / 60);
          if (f % 10 == 9) await flushAndMount(game);
        }
        final hoops = run.state.hoopsPassed;
        final o = bot.baseFlapOffsets.map((e) => e * 1000).toList();
        final d = bot.debugRequestForecast.map((e) => e * 1000).toList();
        final absd = d.map((e) => e.abs()).toList()..sort();
        // ignore: avoid_print
        print('RQ h=$height seed=$seed hoops=${hoops} n=${o.length} '
            'sd=${_sd(o).toStringAsFixed(1)} reqs=${bot.debugRequestTimes.length} '
            'anticipated=${d.length} '
            'dmean=${_mean(d).toStringAsFixed(0)} '
            'dmed=${absd.isEmpty ? 0 : absd[absd.length ~/ 2].toStringAsFixed(0)} '
            'd90=${absd.isEmpty ? 0 : absd[(absd.length * .9).floor()].toStringAsFixed(0)}');
      });
    }
  }
}
