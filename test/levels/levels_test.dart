import 'dart:ui';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/level_progress.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('level table (PRD-home-v3 §4.1 / §4.2)', () {
    test('ten ranks with the PRD names, thresholds and rewards', () {
      expect(kLevels.map((l) => l.name), [
        'EGG', 'CHICK', 'FLEDGLING', 'FLAPPER', 'GLIDER', //
        'FALCON', 'HAWK', 'SPIKE ACE', 'PHOENIX', 'LEGEND',
      ]);
      expect(kLevels.map((l) => l.threshold), [
        25,
        50,
        100,
        200,
        400,
        600,
        800,
        1000,
        2000,
        5000,
      ]);
      expect(kLevels.map((l) => l.reward), [
        25,
        50,
        100,
        200,
        400,
        600,
        800,
        1000,
        2000,
        5000,
      ]);
      expect(kLevels.map((l) => l.level), List.generate(10, (i) => i + 1));
      // Owner 2026-10-17 table: 10,175 in all (lib's kLevelRewardTotal is
      // unused and still reads the old 10,350).
      expect(kLevels.fold<int>(0, (s, l) => s + l.reward), 10175);
    });

    test('emblem colours match emblem_art.js', () {
      final falcon = levelDef(6)!;
      expect(falcon.plate, const Color(0xFFFCD9EE));
      expect(falcon.rim, const Color(0xFFEC008C));
      expect(falcon.accent, const Color(0xFF7A0044));
      expect(levelDef(1)!.rim, const Color(0xFFD9C39A));
      expect(levelDef(9)!.plateGradient, [
        const Color(0xFFFFAB76),
        const Color(0xFFFFE3B8),
      ]);
      expect(levelDef(10)!.plateGradient!.first, const Color(0xFF5B2DC8));
      expect(levelDef(10)!.plateGradient!.last, const Color(0xFF120634));
      expect(levelDef(8)!.plateGradient, isNull);
    });

    test('levelFor edges (the pool level of a best; not the player level)',
        () {
      expect(levelFor(0), 0);
      expect(levelFor(24), 0);
      expect(levelFor(25), 1);
      expect(levelFor(49), 1);
      expect(levelFor(50), 2);
      expect(levelFor(599), 5);
      expect(levelFor(600), 6);
      expect(levelFor(640), 6);
      expect(levelFor(4999), 9);
      expect(levelFor(5000), 10);
      expect(levelFor(999999), 10);
      expect(levelFor(-5), 0);
    });

    test('levelDef / nextLevel', () {
      expect(levelDef(0), isNull);
      expect(levelDef(11), isNull);
      expect(levelDef(3)!.name, 'FLEDGLING');
      expect(nextLevel(0)!.name, 'EGG');
      expect(nextLevel(6)!.name, 'HAWK');
      expect(nextLevel(10), isNull);
    });
  });

  group('LevelProgress', () {
    Future<MenuState> menuWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final storage = GameStorage();
      await storage.load();
      return MenuState(storage);
    }

    test('unranked: nothing pending, claim pays nothing', () async {
      // WP-L a best past EGG without a stored level is still unranked.
      final menu = await menuWith({'bestScore': 640});
      expect(menu.levels.level, 0);
      expect(menu.levels.current, isNull);
      expect(menu.levels.next!.name, 'EGG');
      expect(menu.levels.pendingLevelUp, isNull);
      expect(await menu.levels.claim(), 0);
      expect(menu.wallet.balance, 0);
    });

    test('fresh level-up: one level, its reward', () async {
      final menu = await menuWith({
        'bestScore': 50,
        'playerLevel': 2,
        'claimedLevels': ['1'],
        'coins': 10,
      });
      expect(
        menu.levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 1, toLevel: 2, reward: 50),
      );
    });

    test('several reached-but-unclaimed levels (a reset of the claims): one '
        'popup, rewards added', () async {
      final menu = await menuWith({
        'bestScore': 640,
        'playerLevel': 6,
        'claimedLevels': ['1', '2'],
      });
      expect(
        menu.levels.pendingLevelUp,
        const PendingLevelUp(
          fromLevel: 2,
          toLevel: 6,
          reward: 100 + 200 + 400 + 600,
        ),
      );
    });

    test('catch-up: every stored level unclaimed', () async {
      final menu = await menuWith({'bestScore': 640, 'playerLevel': 6});
      final pending = menu.levels.pendingLevelUp!;
      expect(pending.fromLevel, 0);
      expect(pending.toLevel, 6);
      expect(pending.def.name, 'FALCON');
      expect(pending.reward, 25 + 50 + 100 + 200 + 400 + 600);
    });

    test('claim pays once via level_reward and persists', () async {
      final sources = <(int, CoinSource)>[];
      SharedPreferences.setMockInitialValues({
        'bestScore': 120,
        'playerLevel': 3,
        'coins': 5,
      });
      final storage = GameStorage();
      await storage.load();
      final menu = MenuState(storage, onEarned: (a, s) => sources.add((a, s)));
      var notified = 0;
      menu.levels.addListener(() => notified++);
      expect(await menu.levels.claim(), 175);
      expect(menu.wallet.balance, 180);
      expect(sources, [(175, CoinSource.levelReward)]);
      expect(CoinSource.levelReward.analyticsName, 'level_reward');
      expect(notified, 1);
      expect(menu.levels.pendingLevelUp, isNull);
      // Never twice (also not concurrently).
      expect(await menu.levels.claim(), 0);
      expect(menu.wallet.balance, 180);

      final reader = GameStorage();
      await reader.load();
      expect(reader.claimedLevels, {1, 2, 3});
      expect(MenuState(reader).levels.pendingLevelUp, isNull);
    });

    test('concurrent claims pay once', () async {
      final menu = await menuWith({'bestScore': 60, 'playerLevel': 2});
      final paid = await Future.wait([
        menu.levels.claim(),
        menu.levels.claim(),
      ]);
      expect(paid..sort(), [0, 75]);
      expect(menu.wallet.balance, 75);
    });

    test('debugForceLevelUp raises the stored level by one (the best to its '
        'threshold)', () async {
      final menu = await menuWith({
        'bestScore': 640,
        'playerLevel': 6,
        'claimedLevels': ['1', '2', '3', '4', '5', '6'],
      });
      expect(menu.levels.pendingLevelUp, isNull);
      await menu.levels.debugForceLevelUp();
      expect(menu.storage.bestScore, 800);
      expect(menu.levels.level, 7);
      expect(menu.storage.playerLevel, 7);
      expect(
        menu.levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 6, toLevel: 7, reward: 800),
      );
    });

    test('debugForceLevelUp at LEGEND re-opens the top level', () async {
      final menu = await menuWith({
        'bestScore': 6000,
        'playerLevel': 10,
        'claimedLevels': [for (var i = 1; i <= 10; i++) '$i'],
      });
      await menu.levels.debugForceLevelUp();
      expect(menu.storage.bestScore, 6000);
      expect(
        menu.levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 9, toLevel: 10, reward: 5000),
      );
    });
  });

  group('GameStorage claimedLevels / rumble', () {
    test('defaults: nothing claimed, rumble on', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      expect(storage.claimedLevels, isEmpty);
      expect(storage.rumble, isTrue);
    });

    test('round-trip across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = GameStorage();
      await writer.load();
      await writer.saveClaimedLevels({3, 1, 2});
      await writer.saveRumble(false);
      final reader = GameStorage();
      await reader.load();
      expect(reader.claimedLevels, {1, 2, 3});
      expect(reader.rumble, isFalse);
    });

    test('resetMenuState clears claimed levels and the level, keeps rumble', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      await storage.saveClaimedLevels({1, 2});
      await storage.savePlayerLevel(2);
      await storage.saveRumble(false);
      await storage.resetMenuState();
      final reader = GameStorage();
      await reader.load();
      expect(reader.claimedLevels, isEmpty);
      expect(reader.playerLevel, 0, reason: 'WP-L the stored level resets');
      expect(reader.rumble, isFalse);
    });
  });
}
