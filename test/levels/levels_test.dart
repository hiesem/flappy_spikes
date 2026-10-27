import 'package:flappy_spikes/versus/brackets.dart';
import 'dart:ui';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/level_progress.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'progression_fixture.dart';
// PRD-2.6 J1–J5 / §8.3-16 replaces the ten-rank progression.
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('level table (PRD-2.6 J1 / J5)', () {
    test('31 ranks with the PRD names, points and coins', () {
      expect(kTrackLevels.map((l) => l.name), ['HATCHLING', 'FLUFFBALL', 'NEST HOPPER', 'FIRST FLAP', 'FLEDGLING', 'WING WOBBLER', 'HOOP ROOKIE', 'FEATHERWEIGHT', 'SWALLOW', 'HUMMINGBIRD', 'KINGFISHER', 'RIM SKIMMER', 'STARLING', 'SHRIKE', 'SWIFT', 'TAILWIND', 'HAWKEYE', 'CANNONBALL', 'STORM PETREL', 'FEVER FINCH', 'SKYLARK', 'PEREGRINE', 'PORTAL PIGEON', 'COMET CONDOR', 'GOLDEN EAGLE', 'NIGHT OWL', 'MOONBIRD', 'ALBATROSS', 'PHOENIX', 'SPIKE LEGEND', 'THUNDERBIRD']);
      expect(kTrackLevels.map((l) => l.points), [25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600, 2800, 3000, 3500, 4000, 4500, 5000, 6000, 7000, 8000, 10000]);
      expect(kTrackLevels.map((l) => l.coins), [50, 50, 50, 50, 50, 75, 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 875, 1000, 1125, 1250, 1500, 1750, 2000, 2500]);
      expect(kTrackLevels.map((l) => l.level), List.generate(31, (i) => i + 1));
      // Owner 2026-10-17 table: 10,175 in all (lib's kLevelRewardTotal is
      // unused and still reads the old 10,350).
      expect(kTrackLevels.fold<int>(0, (s, l) => s + l.coins), 18800);
    });

    test('emblem colours match emblem_art.js', () {
      final falcon = trackLevelDef(18)!;
      expect(falcon.plate, const Color(0xFFFCD9EE));
      expect(falcon.rim, const Color(0xFFEC008C));
      expect(falcon.accent, const Color(0xFF7A0044));
      expect(trackLevelDef(1)!.rim, const Color(0xFFD9C39A));
      expect(trackLevelDef(29)!.plateGradient, [
        const Color(0xFFFFAB76),
        const Color(0xFFFFE3B8),
      ]);
      expect(trackLevelDef(31)!.plateGradient!.first, const Color(0xFF5B2DC8));
      expect(trackLevelDef(31)!.plateGradient!.last, const Color(0xFF120634));
      expect(trackLevelDef(8)!.plateGradient, isNull);
    });

    test('levelFor edges (the pool level of a best; not the player level)',
        () {
      expect(bracketFor(0), 0);
      expect(bracketFor(24), 0);
      expect(bracketFor(25), 1);
      expect(bracketFor(49), 1);
      expect(bracketFor(50), 2);
      expect(bracketFor(599), 5);
      expect(bracketFor(600), 6);
      expect(bracketFor(640), 6);
      expect(bracketFor(4999), 9);
      expect(bracketFor(5000), 10);
      expect(bracketFor(999999), 10);
      expect(bracketFor(-5), 0);
    });

    test('track definition includes endless levels', () {
      expect(trackLevelDef(0), isNull);
      expect(trackLevelDef(999)!.name, 'ETERNAL WING');
      expect(trackLevelDef(3)!.name, 'NEST HOPPER');
      expect(trackLevelDef(1)!.name, 'HATCHLING');
      expect(trackLevelDef(7)!.name, 'HOOP ROOKIE');
      expect(trackLevelDef(999)!.name, 'ETERNAL WING');
    });
  });

  group('LevelProgress', () {
    Future<MenuState> menuWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(trackPrefs(prefs));
      final storage = GameStorage();
      await storage.load();
      return MenuState(storage);
    }

    test('unranked: nothing pending, claim pays nothing', () async {
      // WP-L a best past EGG without a stored level is still unranked.
      final menu = await menuWith({'bestScore': 640});
      expect(menu.levels.level, 0);
      expect(menu.levels.current, isNull);
      expect(menu.levels.next!.name, 'HATCHLING');
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
          reward: 50 + 50 + 50 + 75,
        ),
      );
    });

    test('catch-up: every stored level unclaimed', () async {
      final menu = await menuWith({'bestScore': 640, 'playerLevel': 6});
      final pending = menu.levels.pendingLevelUp!;
      expect(pending.fromLevel, 0);
      expect(pending.toLevel, 6);
      expect(pending.def.name, 'WING WOBBLER');
      expect(pending.reward, 50 + 50 + 50 + 50 + 50 + 75);
    });

    test('claim pays once via level_reward and persists', () async {
      final sources = <(int, CoinSource)>[];
      SharedPreferences.setMockInitialValues(trackPrefs({
        'bestScore': 120,
        'playerLevel': 3,
        'coins': 5,
      }));
      final storage = GameStorage();
      await storage.load();
      final menu = MenuState(storage, onEarned: (a, s) => sources.add((a, s)));
      var notified = 0;
      menu.levels.addListener(() => notified++);
      expect(await menu.levels.claim(), 150);
      expect(menu.wallet.balance, 155);
      expect(sources, [(150, CoinSource.levelReward)]);
      expect(CoinSource.levelReward.analyticsName, 'level_reward');
      expect(notified, 1);
      expect(menu.levels.pendingLevelUp, isNull);
      // Never twice (also not concurrently).
      expect(await menu.levels.claim(), 0);
      expect(menu.wallet.balance, 155);

      final reader = GameStorage();
      await reader.load();
      expect(reader.lvlPending, isEmpty);
      expect(MenuState(reader).levels.pendingLevelUp, isNull);
    });

    test('concurrent claims pay once', () async {
      final menu = await menuWith({'bestScore': 60, 'playerLevel': 2});
      final paid = await Future.wait([
        menu.levels.claim(),
        menu.levels.claim(),
      ]);
      expect(paid..sort(), [0, 100]);
      expect(menu.wallet.balance, 100);
    });

    test('debugForceLevelUp raises the stored level by one (keeps best, new '
        'threshold)', () async {
      final menu = await menuWith({
        'bestScore': 640,
        'playerLevel': 6,
        'claimedLevels': ['1', '2', '3', '4', '5', '6'],
      });
      expect(menu.levels.pendingLevelUp, isNull);
      await menu.levels.debugForceLevelUp();
      expect(menu.storage.bestScore, 640);
      expect(menu.levels.level, 7);
      expect(menu.storage.lvlIndex, 7);
      expect(
        menu.levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 6, toLevel: 7, reward: 100),
      );
    });

    test('debugForceLevelUp advances past the old LEGEND cap', () async {
      final menu = await menuWith({
        'bestScore': 6000,
        'playerLevel': 10,
        'claimedLevels': [for (var i = 1; i <= 10; i++) '$i'],
      });
      await menu.levels.debugForceLevelUp();
      expect(menu.storage.bestScore, 6000);
      expect(
        menu.levels.pendingLevelUp,
        const PendingLevelUp(fromLevel: 10, toLevel: 11, reward: 200),
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
      // PRD-2.6 J5 keeps the legacy bytes but no longer loads claims.
      expect((await SharedPreferences.getInstance()).getStringList('claimedLevels'), ['1', '2', '3']);
      expect(reader.claimedLevels, isEmpty);
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
