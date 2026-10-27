import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'J5 2.5 level 7 starts at zero; coins, items and old keys kept',
    () async {
      const old = <String, Object>{
        'playerLevel': 7,
        'claimedLevels': ['1', '2', '3', '4', '5', '6', '7'],
        'unclaimedLevelReward': 800,
        'levelRewardPayout': 0,
        'coins': 1234,
        'ownedItems': ['hat:cap'],
      };
      SharedPreferences.setMockInitialValues(old);
      final storage = GameStorage();
      await storage.load();
      final menu = MenuState(storage);
      expect(menu.levels.level, 0);
      expect(menu.levels.points, 0);
      expect(menu.levels.pending, isEmpty);
      expect(await menu.levels.payPending(), 0);
      expect(menu.wallet.balance, 1234);
      expect(storage.ownedItems, {'hat:cap'});
      final prefs = await SharedPreferences.getInstance();
      for (final entry in old.entries) {
        expect(prefs.get(entry.key), entry.value, reason: entry.key);
      }
      await menu.levels.recordRun(24, counts: false);
      expect(menu.levels.points, 0);
      await menu.levels.recordRun(24);
      expect(menu.levels.level, 0);
      expect(menu.levels.points, 24);
      await menu.levels.recordRun(1);
      expect(menu.levels.level, 1);
      expect(menu.levels.points, 0);
      expect(prefs.getInt('playerLevel'), 7);
      expect(prefs.getStringList('claimedLevels'), old['claimedLevels']);
    },
  );

  for (final balance in [100, 125, 150]) {
    test(
      'J5 interrupted 2.5 credit at balance $balance finishes once on load',
      () async {
        SharedPreferences.setMockInitialValues({
          'coins': balance,
          'playerLevel': 7,
          'claimedLevels': ['1'],
          'levelRewardPayout': 125,
          'unclaimedLevelReward': 25,
        });
        final storage = GameStorage();
        await storage.load();
        expect(storage.coins, balance < 125 ? 125 : balance);
        expect(storage.levelRewardPayout, 0);
        expect(storage.lvlIndex, 0);
        expect(storage.lvlPending, isEmpty);
        // The cleared record, even if old flags remain, cannot credit again.
        await storage.saveCoins(1);
        await storage.load();
        expect(storage.coins, 1);
        await (await SharedPreferences.getInstance()).setInt(
          'levelRewardPayout',
          9999,
        );
        await storage.load();
        expect(
          storage.coins,
          1,
          reason: 'J5 never re-reads the retired record after migration',
        );
        expect(
          (await SharedPreferences.getInstance()).getInt(
            'unclaimedLevelReward',
          ),
          25,
        );
        expect(
          (await SharedPreferences.getInstance()).getStringList(
            'claimedLevels',
          ),
          ['1'],
        );
      },
    );
  }
}
