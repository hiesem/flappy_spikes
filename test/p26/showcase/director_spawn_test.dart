import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import 'bot_highlights_test.dart' show FixedShowcase;

void main() {
  for (final height in [568.0, 711.0, 730.0]) {
    for (final attempt in [1]) {
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({});
        return FlappySpikesGame(
          worldHeight: height,
          soundEnabled: false,
          showcasePlan: FixedShowcase(ShowcaseScript.planFor(1, attempt)),
        )..runSeed = 7;
      }, gameSize: Vector2(320, height)).testGameWidget(
        'B3 Bullseye survives comet flight A=$attempt at $height',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(game);
          var comet = false;
          SlotPlan? bullseye;
          run.events.on<HighlightStarted>((e) {
            if (e.id == 'comet') comet = true;
          });
          run.events.on<HoopSpawned>((e) {
            if (e.plan.index == 14) bullseye = e.plan;
          });
          await flyRun(
            game,
            maxSeconds: 45,
            onFrame: (_) {
              if (bullseye != null) run.clock.running = false;
            },
          );
          expect(comet, isTrue);
          expect(bullseye, isNotNull);
          expect(bullseye!.kind, HoopKindId.bullseye);
          expect(bullseye!.forced, isFalse);
        },
      );
    }
  }
}
