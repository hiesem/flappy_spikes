import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import 'bot_highlights_test.dart' show FixedShowcase;

void main() {
  for (final versus in [false, true]) {
    for (final revived in [false, true]) {
      final service = FakeVersusService(
        pool: [
          if (versus)
            OpponentRun(
              uid: 'rival',
              name: 'Rival',
              score: 3,
              best: 3,
              level: 0,
              timeline: RunTimeline()..end(10),
              runId: 'r',
            ),
        ],
      );
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({});
        return FlappySpikesGame(
          worldHeight: 711,
          soundEnabled: false,
          versus: service,
          showcasePlan: FixedShowcase(ShowcaseScript.planFor(0, 1)),
        );
      }, gameSize: Vector2(320, 711)).testGameWidget(
        'B/E showcase uploads with versus=$versus revived=$revived',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, _) async {
          final run = await startRun(game);
          expect(run.setup.opponent != null, versus);
          expect(run.setup.forced, isEmpty);
          expect(run.countsForAchievements, isTrue);
          if (revived) run.revive(ReviveKind.ad);
          // Real flight records a valid timeline; no debugPass or god mode.
          await flyRun(game, untilHoops: 3, maxSeconds: 10);
          expect(run.state.hoopsPassed, greaterThanOrEqualTo(3));
          expect(run.countsForAchievements, isTrue);
          final summary = run.endRun();
          game.endRun(summary);
          await flushAndMount(game);
          expect(service.submitted, contains(summary));
          expect(summary.revives, revived ? 1 : 0);
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
    'B showcase eligibility is permanently lost after debug assistance',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      expect(run.countsForAchievements, isTrue);
      run.markDebugAssist();
      expect(run.countsForAchievements, isFalse);
    },
  );
}
