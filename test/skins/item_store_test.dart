import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GameStorage, Wallet, ItemStore)> build({
    int coins = 0,
    Set<String> owned = const {},
    Map<SkinLayer, String> equipped = const {},
    Set<String> seen = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'coins': coins,
      'ownedItems': owned.toList(),
      'seenItems': seen.toList(),
      for (final entry in equipped.entries)
        'equippedItem.${entry.key.key}': entry.value,
    });
    final storage = GameStorage();
    await storage.load();
    final wallet = Wallet(storage);
    return (storage, wallet, ItemStore(storage, wallet));
  }

  group('ItemStore look', () {
    test('a fresh install equips the five free defaults', () async {
      final (_, _, items) = await build();
      expect(items.look, Look.defaults);
      expect(items.look.bird, 'classic');
      expect(items.look.gear, kNoneId);
      expect(items.look.hat, kNoneId);
      expect(items.look.hoop, 'pink');
      expect(items.look.trail, 'flame');
    });

    test('sanitises unknown ids to the layer default', () async {
      final (storage, _, items) = await build();
      storage.equippedItems = {
        ...storage.equippedItems,
        SkinLayer.bird: 'nope',
        SkinLayer.hoop: 'gone',
      };
      expect(items.look.bird, 'classic');
      expect(items.look.hoop, 'pink');
    });

    test('sanitises unowned ids to the layer default', () async {
      final (storage, _, items) = await build(
        equipped: {SkinLayer.gear: 'shades', SkinLayer.hat: 'crown'},
      );
      expect(items.look.gear, kNoneId);
      expect(items.look.hat, kNoneId);

      await storage.saveOwnedItems({'gear:shades', 'hat:crown'});
      expect(items.look.gear, 'shades');
      expect(items.look.hat, 'crown');
    });

    test('free items are always owned', () async {
      final (_, _, items) = await build();
      for (final layer in SkinLayer.values) {
        expect(items.isOwned(layer, Look.defaults.idFor(layer)), isTrue);
      }
      expect(items.isOwned(SkinLayer.gear, kNoneId), isTrue);
      expect(items.isOwned(SkinLayer.gear, 'shades'), isFalse);
      expect(items.isOwned(SkinLayer.bird, 'nope'), isFalse);
    });
  });

  group('ItemStore purchase', () {
    test('spends coins, owns and auto-equips the item', () async {
      final (_, wallet, items) = await build(coins: 150);
      expect(await items.purchase(SkinLayer.bird, 'sky'),
          ItemPurchaseResult.purchased);
      expect(wallet.balance, 0);
      expect(items.isOwned(SkinLayer.bird, 'sky'), isTrue);
      expect(items.isEquipped(SkinLayer.bird, 'sky'), isTrue);
      expect(items.look.bird, 'sky');
    });

    test('insufficient coins changes nothing', () async {
      final (_, wallet, items) = await build(coins: 100);
      expect(await items.purchase(SkinLayer.bird, 'sky'),
          ItemPurchaseResult.insufficientCoins);
      expect(wallet.balance, 100);
      expect(items.isOwned(SkinLayer.bird, 'sky'), isFalse);
      expect(items.look.bird, 'classic');
    });

    test('already owned does not spend again', () async {
      final (_, wallet, items) =
          await build(coins: 500, owned: {'bird:sky'});
      expect(await items.purchase(SkinLayer.bird, 'sky'),
          ItemPurchaseResult.alreadyOwned);
      expect(wallet.balance, 500);
    });

    test('free items report alreadyOwned without spending', () async {
      final (_, wallet, items) = await build(coins: 10);
      expect(await items.purchase(SkinLayer.gear, kNoneId),
          ItemPurchaseResult.alreadyOwned);
      expect(await items.purchase(SkinLayer.bird, 'classic'),
          ItemPurchaseResult.alreadyOwned);
      expect(wallet.balance, 10);
    });

    test('unknown id is rejected', () async {
      final (_, wallet, items) = await build(coins: 500);
      expect(await items.purchase(SkinLayer.bird, 'nope'),
          ItemPurchaseResult.unknown);
      expect(await items.purchase(SkinLayer.gear, 'classic'),
          ItemPurchaseResult.unknown);
      expect(wallet.balance, 500);
    });

    test('persists owned and equipped through GameStorage', () async {
      final (_, _, items) = await build(coins: 5000);
      await items.purchase(SkinLayer.hat, 'crown');

      final storage = GameStorage();
      await storage.load();
      expect(storage.coins, 0);
      expect(storage.ownedItems, {'hat:crown'});
      expect(storage.equippedItems[SkinLayer.hat], 'crown');

      final reloaded = ItemStore(storage, Wallet(storage));
      expect(reloaded.isOwned(SkinLayer.hat, 'crown'), isTrue);
      expect(reloaded.look.hat, 'crown');
    });
  });

  group('ItemStore equip', () {
    test('equips owned items and ignores unowned ones', () async {
      final (storage, _, items) =
          await build(owned: {'bird:sky', 'gear:shades'});

      await items.equip(SkinLayer.bird, 'sky');
      await items.equip(SkinLayer.gear, 'shades');
      expect(items.look.bird, 'sky');
      expect(items.look.gear, 'shades');

      await items.equip(SkinLayer.hat, 'crown');
      expect(items.look.hat, kNoneId);
      expect(storage.equippedItems[SkinLayer.hat], kNoneId);
    });

    test('none entries equip on gear and hat', () async {
      final (_, _, items) = await build(owned: {'gear:shades'});
      await items.equip(SkinLayer.gear, 'shades');
      expect(items.look.gear, 'shades');
      await items.equip(SkinLayer.gear, kNoneId);
      expect(items.look.gear, kNoneId);
      expect(items.isEquipped(SkinLayer.gear, kNoneId), isTrue);
    });
  });

  group('ItemStore shortfall', () {
    test('is the missing coin amount, 0 when affordable or unknown', () async {
      final (_, _, items) = await build(coins: 100);
      expect(items.shortfall(SkinLayer.bird, 'sky'), 50);
      expect(items.shortfall(SkinLayer.gear, 'jetpack'), 4900);
      expect(items.shortfall(SkinLayer.bird, 'classic'), 0);
      expect(items.shortfall(SkinLayer.bird, 'nope'), 0);
    });

    test('is 0 when affordable, and stays 0 once owned', () async {
      final (_, _, items) = await build(coins: 6000);
      expect(items.shortfall(SkinLayer.bird, 'sky'), 0);
      expect(await items.purchase(SkinLayer.bird, 'sky'),
          ItemPurchaseResult.purchased);
      expect(items.shortfall(SkinLayer.bird, 'sky'), 0);
    });
  });

  group('ItemStore counters', () {
    test('fresh install: 1/30, 0/14, 0/14, 1/15, 1/15 and 3/88', () async {
      final (_, _, items) = await build();
      expect(items.ownedCountFor(SkinLayer.bird), 1);
      expect(items.ownedCountFor(SkinLayer.gear), 0);
      expect(items.ownedCountFor(SkinLayer.hat), 0);
      expect(items.ownedCountFor(SkinLayer.hoop), 1);
      expect(items.ownedCountFor(SkinLayer.trail), 1);
      expect(items.totalFor(SkinLayer.bird), 30);
      expect(items.totalFor(SkinLayer.gear), 14);
      expect(items.totalFor(SkinLayer.hat), 14);
      expect(items.totalFor(SkinLayer.hoop), 15);
      expect(items.totalFor(SkinLayer.trail), 15);
      expect(items.ownedCount, 3);
    });

    test('the none entries never count toward the totals', () async {
      final (_, _, items) = await build(
        owned: {'gear:none', 'hat:none', 'bird:sky'},
      );
      expect(items.ownedCountFor(SkinLayer.gear), 0);
      expect(items.ownedCountFor(SkinLayer.hat), 0);
      expect(items.ownedCount, 4);
    });

    test('grantAll owns all 88 collectibles', () async {
      final (_, _, items) = await build();
      await items.grantAll();
      expect(items.ownedCount, kCollectibleTotal);
      expect(
        SkinLayer.values.map(items.ownedCountFor).reduce((a, b) => a + b),
        kCollectibleTotal,
      );
    });
  });

  group('ItemStore NEW badge', () {
    test('kNewInUpdate items are new even without coins', () async {
      final (_, _, items) = await build();
      expect(items.isNew(SkinLayer.bird, 'lemon'), isTrue);
      expect(items.isNew(SkinLayer.gear, 'windup'), isTrue);
      expect(items.isNew(SkinLayer.trail, 'echo'), isTrue);
      expect(items.hasNewBadge, isTrue);
    });

    test('affordable items are new; too-expensive ones are not', () async {
      final (_, wallet, items) = await build(coins: 150);
      expect(items.isNew(SkinLayer.bird, 'sky'), isTrue);
      expect(items.isNew(SkinLayer.bird, 'robin'), isFalse);
      expect(items.isNew(SkinLayer.bird, 'nope'), isFalse);

      await wallet.add(600, CoinSource.play);
      expect(items.isNew(SkinLayer.bird, 'robin'), isTrue);
    });

    test('owned or seen items are never new', () async {
      final (_, _, items) =
          await build(coins: 150, owned: {'bird:sky'}, seen: {'bird:lemon'});
      expect(items.isNew(SkinLayer.bird, 'sky'), isFalse);
      expect(items.isNew(SkinLayer.bird, 'lemon'), isFalse);

      expect(items.isNew(SkinLayer.bird, 'lime'), isTrue);
      await items.markSeen(SkinLayer.bird, 'lime');
      expect(items.isNew(SkinLayer.bird, 'lime'), isFalse);

      final storage = GameStorage();
      await storage.load();
      expect(storage.seenItems, contains('bird:lime'));
    });

    test('hasNewBadge clears once every new item is seen', () async {
      final (_, _, items) = await build();
      expect(items.hasNewBadge, isTrue);
      for (final key in kNewInUpdate) {
        final parts = key.split(':');
        await items.markSeen(SkinLayer.fromKey(parts.first)!, parts.last);
      }
      expect(items.hasNewBadge, isFalse);
    });
  });
}
