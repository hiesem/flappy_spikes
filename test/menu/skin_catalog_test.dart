import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/skin_catalog.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GameStorage, Wallet, SkinStore)> build({
    int coins = 0,
    List<String> owned = const ['pink'],
    String equipped = 'pink',
  }) async {
    SharedPreferences.setMockInitialValues({
      'coins': coins,
      'ownedSkins': owned,
      'equippedSkin': equipped,
    });
    final storage = GameStorage();
    await storage.load();
    final wallet = Wallet(storage);
    return (storage, wallet, SkinStore(storage, wallet));
  }

  group('SkinDef catalogue', () {
    test('has the 12 skins in display order with prices and names', () {
      expect(kSkins.map((skin) => skin.id).toList(), [
        'pink', 'blue', 'green', 'purple', 'grey', 'sand',
        'crown', 'tophat', 'sunglasses', 'headband', 'partyhat', 'ghost',
      ]);
      expect(kSkins.map((skin) => skin.price).toList(),
          [0, 100, 150, 200, 300, 800, 1000, 600, 500, 700, 450, 900]);
      expect(kSkins.map((skin) => skin.name).toList(), [
        'Pink', 'Sky', 'Lime', 'Grape', 'Stone', 'Sand',
        'King', 'Gentleman', 'Cool', 'Ninja', 'Party', 'Ghost',
      ]);
      expect(
        kSkins.where((skin) => skin.accessory).map((skin) => skin.id).toSet(),
        {'crown', 'tophat', 'sunglasses', 'headband', 'partyhat'},
      );
    });

    test('sprite paths: legacy pink files, skins/ folder for the rest', () {
      final pink = skinById('pink')!;
      expect(pink.normal, 'bird.png');
      expect(pink.flap, 'bird_flap.png');
      expect(pink.dead, 'bird_dead.png');
      expect(pink.overlay, isNull);

      final crown = skinById('crown')!;
      expect(crown.normal, 'skins/crown.png');
      expect(crown.flap, 'skins/crown_flap.png');
      expect(crown.dead, 'skins/crown_dead.png');
      expect(crown.overlay, 'skins/crown_acc.png');

      expect(skinById('blue')!.overlay, isNull);
      expect(skinById('nope'), isNull);
    });
  });

  group('SkinStore purchases', () {
    test('purchase: spending coins owns and auto-equips the skin', () async {
      final (storage, wallet, skins) = await build(coins: 120);

      expect(await skins.purchase('blue'), SkinPurchaseResult.purchased);
      expect(wallet.balance, 20);
      expect(skins.isOwned('blue'), true);
      expect(skins.isEquipped('blue'), true);
      expect(skins.equippedSkin.id, 'blue');

      final reader = GameStorage();
      await reader.load();
      expect(reader.coins, 20);
      expect(reader.ownedSkins, unorderedEquals(['pink', 'blue']));
      expect(reader.equippedSkin, 'blue');
    });

    test('purchase: insufficient coins changes nothing', () async {
      final (storage, wallet, skins) = await build(coins: 50);

      expect(await skins.purchase('blue'),
          SkinPurchaseResult.insufficientCoins);
      expect(wallet.balance, 50);
      expect(skins.isOwned('blue'), false);
      expect(storage.equippedSkin, 'pink');
    });

    test('purchase: already owned does not spend again', () async {
      final (_, wallet, skins) = await build(coins: 500, owned: ['pink', 'blue']);

      expect(await skins.purchase('blue'), SkinPurchaseResult.alreadyOwned);
      expect(wallet.balance, 500);
    });

    test('purchase: unknown id', () async {
      final (_, wallet, skins) = await build(coins: 500);
      expect(await skins.purchase('nope'), SkinPurchaseResult.unknown);
      expect(wallet.balance, 500);
    });
  });

  group('SkinStore equip', () {
    test('equip ignores unowned ids', () async {
      final (storage, _, skins) = await build(coins: 1000);
      await skins.equip('ghost');
      expect(skins.equipped, 'pink');
      expect(storage.equippedSkin, 'pink');
    });

    test('equip switches between owned skins and persists', () async {
      final (_, _, skins) = await build(
          coins: 0, owned: ['pink', 'blue', 'ghost'], equipped: 'pink');
      await skins.equip('ghost');
      expect(skins.isEquipped('ghost'), true);
      expect(skins.equippedSkin.name, 'Ghost');

      final reader = GameStorage();
      await reader.load();
      expect(reader.equippedSkin, 'ghost');
    });
  });

  group('SkinStore NEW badge', () {
    test('isNew tracks affordability, ownership and seen state', () async {
      final (storage, wallet, skins) = await build(coins: 150);

      expect(skins.isNew('pink'), false);
      expect(skins.isNew('blue'), true);
      expect(skins.isNew('green'), true);
      expect(skins.isNew('purple'), false);
      expect(skins.isNew('nope'), false);
      expect(skins.hasNewBadge, true);

      await skins.markAllSeen();
      expect(skins.isNew('blue'), false);
      expect(skins.isNew('green'), false);
      expect(skins.hasNewBadge, false);

      final reader = GameStorage();
      await reader.load();
      expect(reader.seenSkins, unorderedEquals(['blue', 'green']));

      await wallet.add(150, CoinSource.play);
      expect(skins.isNew('purple'), true);
      expect(skins.hasNewBadge, true);

      await skins.purchase('purple');
      expect(skins.isNew('purple'), false);
    });
  });
}
