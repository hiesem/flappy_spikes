import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// iOS round 2 §6 (both platforms): signed out, the unlock toasts are no
/// longer lost when the player taps NEXT before the results page settled,
/// nor when a new run starts before they showed.
void main() {
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 568),
    gameSize: Vector2(320, 568),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
    g.achievements.countDebugRuns = true;
  }

  Future<void> toResults(FlappySpikesGame g) async {
    final run = await startRun(g);
    run.ctx.addScore(3);
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
    expect(g.state, GameState.results);
  }

  /// Steps until the home screen takes taps again.
  Future<void> home(FlappySpikesGame g) async {
    for (var i = 0; i < 120 && g.state != GameState.start; i++) {
      stepGame(g, 1 / 30);
      await flushAndMount(g);
    }
    expect(g.state, GameState.start);
    for (var i = 0; i < 60; i++) {
      stepGame(g, 1 / 30);
      await flushAndMount(g);
    }
  }

  tester.testGameWidget(
    'NEXT before the page settled: the queued toasts show on Home',
    setUp: boot,
    verify: (g, _) async {
      await toResults(g);
      g.achievements.toastQueue.addAll([
        AchievementId.hoops10,
        AchievementId.itemHeart,
      ]);
      // Just past the fade-in: NEXT works, the page has not settled.
      stepGame(g, ResultsConfig.pageFadeIn + .05);
      await flushAndMount(g);
      expect(g.resultsScreen!.settled, isFalse);
      expect(g.achievementToast, isNull);
      g.resultsScreen!.next();
      await home(g);
      final seen = <AchievementId?>{};
      for (var i = 0; i < 30 * 12; i++) {
        stepGame(g, 1 / 30);
        if (i % 10 == 0) await flushAndMount(g);
        final t = g.achievementToast;
        if (t != null) seen.add(t.current);
        if (seen.length == 2 && t == null) break;
      }
      expect(
        seen,
        containsAll([AchievementId.hoops10, AchievementId.itemHeart]),
      );
      expect(g.achievements.toastQueue, isEmpty);
    },
  );

  tester.testGameWidget(
    'a new run before they showed: no pill over the run, still queued after',
    setUp: boot,
    verify: (g, _) async {
      g.achievements.toastQueue.add(AchievementId.firstRevive);
      // Home shows it at once; start a run straight away.
      await startRun(g);
      await flushAndMount(g);
      expect(g.achievementToast, isNull, reason: 'never over a run');
      expect(g.achievements.toastQueue, isNotEmpty);
    },
  );
}
