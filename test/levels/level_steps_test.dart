import 'progression_fixture.dart';
// PRD-2.6 J3/J5: accumulated score, fresh keys and endless ranks.
// WP-L (owner 2026-10-17): one level at a time. The level is stored
// (`playerLevel`, default 0), steps up by exactly one when a run's score
// reaches the next threshold, pays that level's reward once through the
// existing claim flow, drives the rank achievements and resets with
// "Delete my data" / the debug menu reset.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/level_progress.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LevelTrack.step', () {
    test('one step per run, never more; ranks continue after ten', () {
      expect(LevelTrack.step(0, 0, 24).index, 0);
      expect(LevelTrack.step(0, 0, 25).index, 1);
      expect(LevelTrack.step(0, 0, 100).index, 1, reason: 'HATCHLING only');
      expect(LevelTrack.step(0, 0, 99999).index, 1);
      expect(LevelTrack.step(1, 0, 100).index, 2, reason: 'FLUFFBALL');
      expect(LevelTrack.step(2, 0, 30).index, 2, reason: '30 < NEST HOPPER 100');
      expect(LevelTrack.step(2, 0, 100).index, 3);
      expect(LevelTrack.step(9, 0, 699).index, 9);
      expect(LevelTrack.step(9, 0, 5000).index, 10);
      expect(LevelTrack.step(10, 0, 99999).index, 11, reason: 'no ten-level cap');
    });
  });

  group('LevelProgress (stored)', () {
    Future<MenuState> menuWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(trackPrefs(prefs));
      final storage = GameStorage();
      await storage.load();
      return MenuState(storage);
    }

    test('starts at 0 whatever the best (no migration); claims do not grant '
        'levels', () async {
      final menu = await menuWith({
        'bestScore': 3000,
        'claimedLevels': ['1', '2', '3'],
      });
      expect(menu.levels.level, 0);
      expect(menu.levels.next!.name, 'HATCHLING');
      expect(menu.levels.pendingLevelUp, isNull);
    });

    test('100, 100, 30: EGG, CHICK, nothing; each step pays its reward once',
        () async {
      final menu = await menuWith({});
      final levels = menu.levels;
      expect(await levels.recordRun(100), 1);
      expect(
        levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 0, toLevel: 1, reward: 50),
      );
      expect(await levels.claim(), 50);
      expect(await levels.claim(), 0);

      expect(await levels.recordRun(100), 2);
      expect(
        levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 1, toLevel: 2, reward: 50),
      );
      expect(await levels.claim(), 50);

      expect(await levels.recordRun(30), 2);
      expect(levels.pendingLevelUp, isNull);
      expect(menu.wallet.balance, 100);

      final reader = GameStorage();
      await reader.load();
      expect(reader.lvlIndex, 2);
      expect(reader.lvlPending, isEmpty);
    });

    test('the old LEGEND cap is gone: a run raises level ten', () async {
      final menu = await menuWith({
        'playerLevel': 10,
        'claimedLevels': [for (var l = 1; l <= 10; l++) '$l'],
      });
      expect(await menu.levels.recordRun(99999), 11);
      expect(menu.levels.pendingLevelUp!.toLevel, 11);
      expect(menu.storage.lvlIndex, 11);
    });

    test('reset and resetMenuState go back to unranked', () async {
      final menu = await menuWith({'playerLevel': 4});
      await menu.levels.reset();
      expect(menu.levels.level, 0);
      await menu.storage.saveLvlIndex(3);
      await menu.items.resetAll();
      final reader = GameStorage();
      await reader.load();
      expect(reader.playerLevel, 0);
    });
  });

  group('in the game', () {
    Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
      g.achievements.countDebugRuns = true;
      g.runDebug.ignoreGates = false;
    }

    Future<void> play(FlappySpikesGame g, int score) async {
      final run = await startRun(g);
      run.ctx.addScore(score);
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      for (var i = 0; i < 10; i++) {
        await Future<void>.value();
      }
    }

    Set<String> ranks(FlappySpikesGame g) => {
      for (final k in g.achievements.earned)
        if (k.startsWith('rank_')) k,
    };

    final t = FlameTester<FlappySpikesGame>(
      createRunTestGame,
      gameSize: Vector2(320, 568),
    );

    t.testGameWidget(
      'first run 100 -> EGG only (results before / after, owed 25, rank '
      'EGG); next 100 -> CHICK; 30 -> nothing',
      setUp: boot,
      verify: (g, _) async {
        await play(g, 100);
        expect(g.storage.lvlIndex, 1);
        expect(g.menu.levels.pendingLevelUp!.reward, 50);
        expect(ranks(g), {'rank_egg'});
        for (var i = 0; i < 100 && g.resultsScreen == null; i++) {
          stepGame(g, 0.1);
          await flushAndMount(g);
        }
        final model = g.resultsScreen!.model;
        expect(model.levelBefore, 0);
        expect(model.levelAfter, 1);
        expect(model.levelUp, isTrue);
        expect(model.levelReward, 50);
        expect(model.hasClaim, isTrue);
        expect(await claimLevelRewards(g, 'tap'), 50);
        expect(await claimLevelRewards(g, 'tap'), 0);

        g.replay();
        await flushAndMount(g);
        stepGame(g, 0.5);
        await play(g, 100);
        expect(g.storage.lvlIndex, 2);
        expect(g.menu.levels.pendingLevelUp!.reward, 50);
        expect(ranks(g), {'rank_egg', 'rank_chick'});
        expect(await claimLevelRewards(g, 'tap'), 50);

        g.replay();
        await flushAndMount(g);
        stepGame(g, 0.5);
        await play(g, 30);
        expect(g.storage.lvlIndex, 2);
        expect(g.menu.levels.pendingLevelUp, isNull);
        expect(g.storage.unclaimedLevelReward, 0);
        expect(ranks(g), {'rank_egg', 'rank_chick'});
        expect(g.storage.bestScore, 100);
      },
    );

    t.testGameWidget(
      'an app kill before CLAIM keeps the owed reward (paid once at the next '
      'start)',
      setUp: boot,
      verify: (g, tester) async {
        await play(g, 100);
        expect(g.storage.lvlIndex, 1);
        // "Kill": a fresh storage + menu from the persisted prefs.
        await tester.runAsync(() async {
          final storage = GameStorage();
          await storage.load();
          expect(storage.lvlIndex, 1);
          expect(storage.lvlPending.single['coins'], 50);
          expect(storage.claimedLevels, isEmpty);
          final menu = MenuState(storage);
          final before = menu.wallet.balance;
          expect(await menu.levels.claim(), 50);
          expect(await menu.levels.claim(), 0);
          expect(menu.wallet.balance, before + 50);
          expect(storage.unclaimedLevelReward, 0);
        });
      },
    );

    late FakeVersusService versus;
    FlameTester<FlappySpikesGame>(() {
      versus = FakeVersusService();
      return createRunTestGame(
        prefs: trackPrefs({
          'bestScore': 640,
          'playerLevel': 6,
          'claimedLevels': [for (var l = 1; l <= 6; l++) '$l'],
        }),
        versus: versus,
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'Delete my data resets the stored level (claims and best stay)',
      setUp: (g, t) async {
        await boot(g, t);
        g.openSettings();
        await flushAndMount(g);
        stepGame(g, 0.6);
        await flushAndMount(g);
      },
      verify: (g, _) async {
        expect(g.menu.levels.level, 6);
        g.world.children.query<SettingsPanel>().single.deleteRow!.onPressed();
        await flushAndMount(g);
        g.deleteDataPopup!.confirmButton.onPressed();
        await flushAndMount(g);
        for (var i = 0; i < 10; i++) {
          await Future<void>.value();
        }
        expect(versus.deleteCalls, 1);
        expect(g.menu.levels.level, 0);
        expect(g.storage.lvlIndex, 0);
        expect(g.storage.bestScore, 640);
        expect(g.menu.levels.pendingLevelUp, isNull);
      },
    );
  });
}
