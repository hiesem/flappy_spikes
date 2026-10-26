import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
import 'package:flappy_spikes/run/director/director_context.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  test('debug plans', () {
    for (var seed in [33]) {
      final director = RunDirector(
        seed: seed,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
      );
      double? previous;
      final plans = <String>[];
      for (var i = 0; i < 112; i++) {
        final squeeze = i >= 35 && i % 40 >= 30;
        final ctx = DirectorContext.open(
          568,
          prevCentreY: previous,
          squeezeWindow: squeeze,
          squeezeInset: squeeze ? 100 : 0,
        );
        final plan = director.nextSlot(ctx);
        director.nextGap(ctx, plan);
        previous = plan.centreY;
        plans.add(
          '$i:${plan.kind.name}@${plan.centreY.round()}'
          ' t${plan.tiltDeg.round()}'
          '${plan.motion == null ? '' : ' m${plan.motion!.type.name}'}'
          '${plan.formation == null ? '' : ' f${plan.formation!.name}'}'
          '${plan.calm ? ' CALM prev=$previous' : ''}',
        );
      }
      // ignore: avoid_print
      print('PLAN seed=$seed ${plans.join(' | ')}');
    }
  });
  for (final height in [568.0, 711.0]) {
    FlameTester(
      () => createRunTestGame(
        worldHeight: height,
        prefs: {'gamesPlayed': 10},
      ),
    ).testGameWidget(
      'debug noise height=$height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        game.runDebug.ignoreGates = false;
        for (var seed = 0; seed < 21; seed++) {
          game.runSeed = seed;
          game.storage.gamesPlayed = 10;
          await startRun(game);
          final flight = await flyHumanNoiseBotToDeath(game, seed: seed);
          // ignore: avoid_print
          print(
            'NOISE h=$height seed=$seed hoops=${flight.hoops} '
            'cause=${flight.cause} flaps=${flight.flaps} '
            'extra=${flight.extraFlaps} '
            'offsets=${flight.baseFlapOffsets.take(12).map((v) => v.toStringAsFixed(2))}',
          );
          game.replay();
          await flushAndMount(game);
          stepGame(game, .4);
          await flushAndMount(game);
        }
        expect(Config.worldWidth, greaterThan(0));
      },
    );
  }
}
