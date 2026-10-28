import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  for (final (step, attempt, noisy, seeds) in [
    (0, 1, true, 100),
    (0, 3, true, 100),
    (0, 1, false, 50),
    (1, 1, false, 50),
    (2, 1, false, 50),
  ]) {
    final plan = ShowcaseScript.planFor(step, attempt);
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        worldHeight: 711,
        soundEnabled: false,
        showcasePlan: FixedShowcase(plan),
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'B bot step $step A=$attempt noisy=$noisy ($seeds seeds)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        var seen = 0;
        final missed = <int>[];
        for (var seed = 0; seed < seeds; seed++) {
          game.runSeed = seed;
          final run = await startRun(game);
          var highlight = false;
          run.events.on<HighlightStarted>((e) {
            if (e.id == plan.highlightId) highlight = true;
          });
          if (noisy) {
            // Vary all 100 course seeds against the helper's deterministic
            // human-noise stream (90 ms sigma and 10% extra flaps).
            await flyHumanNoiseBotToDeath(game, maxSeconds: 25);
          } else {
            await flyRun(
              game,
              maxSeconds: 30,
              onFrame: (_) {
                // Stop immediately after the real highlight event, preserving
                // the normal flight and pickup/ride path up to it.
                if (highlight) run.clock.running = false;
              },
            );
          }
          if (highlight) {
            seen++;
          } else {
            missed.add(seed);
          }
          game.replay();
          await flushAndMount(game);
          stepGame(game, .4);
          await flushAndMount(game);
        }
        expect(
          seen,
          greaterThanOrEqualTo(noisy && attempt == 1 ? 85 : seeds),
          reason: 'missed seeds $missed',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
