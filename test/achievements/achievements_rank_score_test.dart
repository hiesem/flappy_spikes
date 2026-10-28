// PRD-2.6 R5: ranks measure a single counting run, not the level or best.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
  }) => FlameTester(
    () => createRunTestGame(prefs: prefs),
    gameSize: Vector2(320, 568),
  );

  Future<void> boot(FlappySpikesGame game, WidgetTester _) async {
    await game.ready();
    await preloadImages(game);
    game.runDebug.ignoreGates = false;
  }

  Future<void> finish(FlappySpikesGame game) async {
    killRunThroughSaves(game);
    await declineRevive(game);
    await flushAndMount(game);
  }

  tester().testGameWidget(
    '400 in a counting run earns five ranks',
    setUp: boot,
    verify: (game, _) async {
      game.achievements.countDebugRuns = true;
      final run = await startRun(game);
      run.ctx.addScore(400);
      await finish(game);
      expect(
        game.achievements.earned
            .where((key) => key.startsWith('rank_'))
            .toSet(),
        kRankAchievements.take(5).map((id) => id.key).toSet(),
      );
    },
  );

  tester().testGameWidget(
    'a debug run scoring 400 earns no ranks',
    setUp: boot,
    verify: (game, _) async {
      game.achievements.countDebugRuns = false;
      game.menu.slot.debugForce = Powerup.bigHoops;
      game.menu.slot.rollForArrival();
      await game.menu.slot.armOffered();
      final run = await startRun(game);
      expect(run.countsForAchievements, isFalse);
      run.ctx.addScore(400);
      await finish(game);
      expect(
        game.achievements.earned.where((key) => key.startsWith('rank_')),
        isEmpty,
      );
    },
  );

  tester(
    prefs: {
      'achUnlocked': ['rank_legend'],
    },
  ).testGameWidget(
    'a previously earned rank survives a low scoring run',
    setUp: boot,
    verify: (game, _) async {
      game.achievements.countDebugRuns = true;
      final run = await startRun(game);
      run.ctx.addScore(1);
      await finish(game);
      expect(game.storage.achUnlocked, contains('rank_legend'));
    },
  );
}
