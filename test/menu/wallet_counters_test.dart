import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final events = <Map<String, Object>>[];
    final items = ItemStore(storage, wallet, onItemBought: events.add);
    expect(await items.purchase(SkinLayer.bird, 'sky'), ItemPurchaseResult.purchased);
    expect(events, [ {'key': 'bird:sky', 'rarity': 'common', 'price': 150,
      'balance_before': 500, 'games': 0, 'minutes': 0} ]);
    expect(await items.purchase(SkinLayer.bird, 'sky'), ItemPurchaseResult.alreadyOwned);
    expect(events, hasLength(1));
  });

}
