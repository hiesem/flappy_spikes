import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GameStorage> loadedStorage({int coins = 0}) async {
    SharedPreferences.setMockInitialValues({'coins': coins});
    final storage = GameStorage();
    await storage.load();
    return storage;
  }

  group('Wallet', () {
    test('balance mirrors storage.coins', () async {
      final storage = await loadedStorage(coins: 17);
      final wallet = Wallet(storage);
      expect(wallet.balance, 17);
    });

    test('add increases balance, persists, notifies and reports source',
        () async {
      final storage = await loadedStorage(coins: 10);
      final earned = <(int, CoinSource)>[];
      final wallet = Wallet(storage,
          onEarned: (amount, source) => earned.add((amount, source)));
      var notifications = 0;
      wallet.addListener(() => notifications++);

      await wallet.add(25, CoinSource.rewarded);

      expect(wallet.balance, 35);
      expect(earned, [(25, CoinSource.rewarded)]);
      expect(notifications, 1);
      final reader = GameStorage();
      await reader.load();
      expect(reader.coins, 35);
    });

    test('add ignores zero and negative amounts', () async {
      final storage = await loadedStorage(coins: 10);
      final earned = <(int, CoinSource)>[];
      final wallet = Wallet(storage,
          onEarned: (amount, source) => earned.add((amount, source)));
      var notifications = 0;
      wallet.addListener(() => notifications++);

      await wallet.add(0, CoinSource.play);
      await wallet.add(-5, CoinSource.debug);

      expect(wallet.balance, 10);
      expect(earned, isEmpty);
      expect(notifications, 0);
    });

    test('spend deducts, persists and notifies', () async {
      final storage = await loadedStorage(coins: 50);
      final wallet = Wallet(storage);
      var notifications = 0;
      wallet.addListener(() => notifications++);

      expect(await wallet.spend(20, 'skin:blue'), true);
      expect(wallet.balance, 30);
      expect(notifications, 1);
      final reader = GameStorage();
      await reader.load();
      expect(reader.coins, 30);
    });

    test('spend returns false when the balance is too low', () async {
      final storage = await loadedStorage(coins: 5);
      final wallet = Wallet(storage);
      expect(await wallet.spend(6, 'skin:blue'), false);
      expect(wallet.balance, 5);
    });

    test('spend zero is a successful no-op and negative fails', () async {
      final storage = await loadedStorage(coins: 5);
      final wallet = Wallet(storage);
      var notifications = 0;
      wallet.addListener(() => notifications++);

      expect(await wallet.spend(0, 'noop'), true);
      expect(await wallet.spend(-1, 'noop'), false);
      expect(wallet.balance, 5);
      expect(notifications, 0);
    });

    test('analytics names match the PRD', () {
      expect(CoinSource.play.analyticsName, 'play');
      expect(CoinSource.iap.analyticsName, 'iap');
      expect(CoinSource.rewarded.analyticsName, 'rewarded');
      expect(CoinSource.noadsBonus.analyticsName, 'noads_bonus');
      expect(CoinSource.debug.analyticsName, 'debug');
    });
  });
}
