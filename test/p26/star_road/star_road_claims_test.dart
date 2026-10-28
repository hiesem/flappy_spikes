import 'dart:math';

import 'package:flappy_spikes/game/save_seal.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/progression/star_road_claims.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrashStorage extends GameStorage {
  CrashStorage({super.sealer});
  String? crash;
  void stop(String point) {
    if (crash == point) throw StateError(point);
  }

  @override
  Future<void> saveStarRoadClaimed(Set<int> value) async {
    await super.saveStarRoadClaimed(value);
    stop('claim');
  }

  @override
  Future<void> saveCoins(int value) async {
    await super.saveCoins(value);
    stop('coins');
  }

  @override
  Future<void> saveLifetimeCoinsEarned(int value) async {
    await super.saveLifetimeCoinsEarned(value);
    stop('earned');
  }

  @override
  Future<void> saveOwnedItems(Set<String> value) async {
    await super.saveOwnedItems(value);
    stop('item');
  }
}

StarRoadClaims claims(GameStorage storage, {List<CoinSource>? sources}) {
  final wallet = Wallet(storage, onEarned: (_, source) => sources?.add(source));
  return StarRoadClaims(
    storage,
    wallet,
    ItemStore(storage, wallet),
    random: Random(7),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'reached coins pay once; locked and duplicate tiers do not pay',
    () async {
      final storage = GameStorage();
      await storage.load();
      await storage.saveStarRoadSeason(1);
      await storage.saveStarRoadXp(8);
      final sources = <CoinSource>[];
      final c = claims(storage, sources: sources);
      expect(await c.claim(2), isNull);
      expect((await c.claim(1))!.coins, 25);
      expect(await c.claim(1), isNull);
      expect(storage.coins, 25);
      expect(storage.lifetimeCoinsEarned, 25);
      expect(sources, [CoinSource.starRoad]);
    },
  );

  for (final point in ['claim', 'coins', 'earned', 'item']) {
    test('kill after $point recovers once on launch', () async {
      final sealer = MemorySaveSealer();
      final seed = GameStorage(sealer: sealer);
      await seed.load();
      await seed.sealVerified;
      await seed.saveStarRoadSeason(1);
      await seed.saveStarRoadXp(80);
      final crashing = CrashStorage(sealer: sealer);
      await crashing.load();
      await crashing.sealVerified;
      crashing.crash = point;
      final tier = point == 'item' ? 10 : 1;
      await expectLater(claims(crashing).claim(tier), throwsStateError);
      final restarted = GameStorage(sealer: sealer);
      await restarted.load();
      await restarted.sealVerified;
      expect(restarted.sealUntrusted, isFalse);
      final recovered = claims(restarted);
      await recovered.recover();
      await recovered.recover();
      expect(restarted.starRoadClaimed, contains(tier));
      expect(await recovered.claim(tier), isNull);
      if (tier == 1) {
        expect(restarted.coins, 25);
        expect(restarted.lifetimeCoinsEarned, 25);
      } else {
        expect(restarted.ownedItems, hasLength(1));
      }
    });
  }

  test(
    'reveal interrupted after item settlement remains granted once',
    () async {
      final sealer = MemorySaveSealer();
      final before = GameStorage(sealer: sealer);
      await before.load();
      await before.sealVerified;
      await before.saveStarRoadSeason(2);
      await before.saveStarRoadXp(80);
      final result = (await claims(before).claim(10))!;
      expect(result.kind, 'item');
      expect(before.ownedItems, contains(result.item));
      // The process dies with J4's sheet still visible, before LATER/EQUIP.
      final after = GameStorage(sealer: sealer);
      await after.load();
      await after.sealVerified;
      await claims(after).recover();
      expect(after.ownedItems, {result.item});
      expect(await claims(after).claim(10), isNull);
    },
  );
  test('capped feather and puzzle rewards pay 50 coins each', () async {
    final storage = GameStorage();
    await storage.load();
    await storage.saveStarRoadSeason(1);
    await storage.saveStarRoadXp(120);
    await storage.saveFeathers(3);
    await storage.savePuzzlePieces(7);
    final c = claims(storage);
    expect((await c.claim(5))!.coins, 50);
    expect((await c.claim(15))!.coins, 50);
    expect(storage.feathers, 3);
    expect(storage.puzzlePieces, 7);
    expect(storage.coins, 100);
  });

  test('exhausted item catalogue falls back to tier coins once', () async {
    final storage = GameStorage();
    await storage.load();
    await storage.saveStarRoadSeason(1);
    await storage.saveStarRoadXp(200);
    await storage.saveOwnedItems(allItems.map((i) => i.key).toSet());
    final c = claims(storage);
    expect((await c.claim(10))!.coins, 250);
    expect((await c.claim(20))!.coins, 500);
    expect((await c.claim(25))!.coins, 1000);
    expect(await c.claim(25), isNull);
    expect(storage.coins, 1750);
  });
}
