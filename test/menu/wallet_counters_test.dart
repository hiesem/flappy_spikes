import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/run/run_end_bookkeeping.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '8.3-10: gift is earned and noadsBonus is bought; totals persist',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final wallet = Wallet(storage);
      await wallet.add(10, CoinSource.gift);
      await wallet.add(20, CoinSource.noadsBonus);
      await wallet.add(30, CoinSource.iap);
      await wallet.add(5, CoinSource.play);
      expect(await wallet.spend(12, 'revive'), isTrue);
      expect(await wallet.spend(1000, 'revive'), isFalse);
      final reload = GameStorage();
      await reload.load();
      final restored = Wallet(reload);
      expect(restored.lifetimeCoinsEarned, 15);
      expect(restored.lifetimeCoinsBought, 50);
      expect(restored.lifetimeCoinsSpent, 12);
    },
  );
  test('item_bought fields describe the successful purchase', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    final wallet = Wallet(storage);
    await wallet.add(500, CoinSource.play);
    final services = _Events();
    void track(SkinItem item, int balance, int games, int minutes, bool first) {
      services.trackItemBought(item.key, item.rarity!.name, item.price,
          balance, games, minutes, first);
    }
    final items = ItemStore(storage, wallet, onItemBought: track);
    expect(await items.purchase(SkinLayer.bird, 'sky'), ItemPurchaseResult.purchased);
    expect(services.purchases.map((e) => e.$1), ['item_bought', 'first_item_bought']);
    final expected = {'key': 'bird:sky', 'rarity': 'common', 'price': 150,
      'balance_before': 500, 'games': 0, 'minutes': 0};
    expect(services.purchases[0].$2, expected);
    expect(services.purchases[1].$2, expected);
    expect(await items.purchase(SkinLayer.bird, 'sky'), ItemPurchaseResult.alreadyOwned);
    final reload = GameStorage();
    await reload.load();
    final next = ItemStore(reload, Wallet(reload), onItemBought: track);
    expect(await next.purchase(SkinLayer.bird, 'lime'), ItemPurchaseResult.purchased);
    expect(services.purchases.map((e) => e.$1),
        ['item_bought', 'first_item_bought', 'item_bought']);
  });

  test('daily economy emits once per local day across reload', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 10, 28, 23);
    final storage = GameStorage(clock: () => now);
    await storage.load();
    final wallet = Wallet(storage);
    await wallet.add(10, CoinSource.play);
    await wallet.add(20, CoinSource.iap);
    await wallet.spend(3, 'revive');
    final services = _Events();
    await RunEndBookkeeping.economyDaily(storage, services);
    await RunEndBookkeeping.economyDaily(storage, services);
    final reload = GameStorage(clock: () => now);
    await reload.load();
    await RunEndBookkeeping.economyDaily(reload, services);
    expect(services.events, [ {'earned': 10, 'spent': 3, 'bought': 20} ]);
    now = DateTime(2026, 10, 29);
    await RunEndBookkeeping.economyDaily(reload, services);
    expect(services.events, hasLength(2));
  });

}

class _Events extends GameServices {
  final events = <Map<String, Object>>[];
  final purchases = <(String, Map<String, Object>)>[];
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    if (name == 'economy_daily') events.add(parameters!);
    if (name == 'item_bought' || name == 'first_item_bought') {
      purchases.add((name, parameters!));
    }
  }
}
