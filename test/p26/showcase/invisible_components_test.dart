import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_scaled_world.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import 'bot_highlights_test.dart' show FixedShowcase;

void main() {
  for (final height in [568.0, 711.0, 730.0]) {
    for (var step = 0; step < 3; step++) {
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({});
        return FlappySpikesGame(
          worldHeight: height,
          soundEnabled: false,
          showcasePlan: FixedShowcase(ShowcaseScript.planFor(step, 1)),
        )..runSeed = 7;
      }, gameSize: Vector2(320, height)).testGameWidget(
        'O16 no showcase UI during step $step or Home at $height',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, _) async {
          void scan() {
            final names = game.descendants().map(
              (c) => c.runtimeType.toString().toLowerCase(),
            );
            expect(
              names.where(
                (n) => n.contains('showcase') || n.contains('graduation'),
              ),
              isEmpty,
            );
          }

          final run = await startRun(game);
          expect(run.setup.forced, isEmpty);
          expect(run.countsForAchievements, isTrue);
          scan();
          await flyRun(game, maxSeconds: 20);
          scan();
          // Existing RunTrack is the world column master for every pickup,
          // including scripted items; no direct unscaled child is added.
          expect(RunScaledWorld.isRunColumn(run.layers.items), isTrue);
          for (final pickup in run.spawner.pickups) {
            expect(pickup.parent, run.layers.items);
          }
          game.endRun(run.endRun());
          await flushAndMount(game);
          game.goHome();
          await flushAndMount(game);
          stepGame(game, .5);
          await flushAndMount(game);
          expect(game.state, GameState.start);
          scan();
        },
      );
    }
  }
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(
      worldHeight: 711,
      soundEnabled: false,
      showcasePlan: FixedShowcase(ShowcaseScript.planFor(0, 1)),
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'B2 a death before hoop 0 ends normally, without FREE',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.shield = false;
      run.state.invulnerable = 0;
      killRun(game);
      await flushAndMount(game);
      expect(run.state.hoopsPassed, 0);
      expect(game.state, GameState.results);
      expect(game.reviveScreen, isNull);
    },
  );
}
