import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/save_seal.dart';
import 'package:flappy_spikes/leaderboard/gift_apply.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Services extends GameServices {
  final events = <(String, Map<String, Object>?)>[];
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }
}

/// Throw after durable writes to model actual process death at each boundary.
class _CrashStorage extends GameStorage {
  _CrashStorage({super.sealer});
  String? crash;
  void stop(String point) {
    if (crash == point) throw StateError('kill at $point');
  }

  @override
  Future<void> saveLbGiftPending(Map<String, Object?> value) async {
    await super.saveLbGiftPending(value);
    stop(value['applied'] == false ? 'journal' : 'applied');
  }

  @override
  Future<void> saveLbGiftsClaimed(Set<String> value) async {
    await super.saveLbGiftsClaimed(value);
    stop('seal');
  }

  @override
  Future<void> saveCoins(int value) async {
    expect(lbGiftsClaimed, contains('gift_canonical'));
    await super.saveCoins(value);
    stop('coins');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameStorage storage;
  late _Services services;
  late GiftApply apply;
  late List<CoinSource> sources;
  late List<Map<String, Object?>> requests;
  var kind = 'coins';
  String? item;
  var ok = true;

  GiftApply build(GameStorage store) => GiftApply(
    storage: store,
    wallet: Wallet(store, onEarned: (_, source) => sources.add(source)),
    services: services,
    leaderboard: FakeLeaderboardService(
      onCall: (name, data) async {
        expect(name, 'lbClaimGift');
        requests.add(data);
        return {
          'ok': ok,
          if (ok) ...{
            'id': 'gift_canonical',
            'tier': 'gold',
            'prize': {
              'kind': kind,
              'coins': 175,
              'item': ?item,
              'rarity': 'common',
              'seed': '123',
            },
          },
        };
      },
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = GameStorage();
    await storage.load();
    services = _Services();
    sources = [];
    requests = [];
    kind = 'coins';
    item = null;
    ok = true;
    apply = build(storage);
  });

  test(
    'coins, canonical/request dedupe, source and analytics payload',
    () async {
      final gift = (await apply.claim('group'))!;
      expect(gift.coins, 175);
      expect(storage.coins, 175);
      expect(storage.lbGiftsClaimed, containsAll(['group', 'gift_canonical']));
      expect(sources, [CoinSource.leaderboardGift]);
      expect(services.events, hasLength(1));
      expect(services.events.single.$1, 'lb_gift_collect');
      expect(services.events.single.$2, {
        'tier': 'gold',
        'kind': 'coins',
        'coins': 175,
        'rarity': 'none',
        'fallback': 0,
      });
      await apply.markShown(gift.id);
      expect(await apply.claim('group'), isNull);
      expect(await apply.claim('gift_canonical'), isNull);
      expect(requests, hasLength(1));
      expect(storage.coins, 175);
    },
  );

  for (final point in ['journal', 'seal', 'coins', 'applied']) {
    test(
      'credited once after kill at $point; result survives restart',
      () async {
        final sealer = MemorySaveSealer();
        final seed = GameStorage(sealer: sealer);
        await seed.load();
        await seed.sealVerified;
        await seed.saveCoins(40);
        final crashing = _CrashStorage(sealer: sealer);
        await crashing.load();
        await crashing.sealVerified;
        crashing.crash = point;
        await expectLater(build(crashing).claim('group'), throwsStateError);
        final restarted = GameStorage(sealer: sealer);
        await restarted.load();
        await restarted.sealVerified;
        expect(restarted.sealUntrusted, isFalse);
        final recovered = build(restarted);
        final gift = (await recovered.recover())!;
        expect(gift.id, 'gift_canonical');
        expect(restarted.coins, 215);
        expect(restarted.lbGiftsClaimed, contains('gift_canonical'));
        expect((await recovered.recover())!.coins, 175);
        expect(restarted.coins, 215);
        await recovered.markShown(gift.id);
        expect(await recovered.claim('group'), isNull);
        expect(requests, hasLength(1));
      },
    );
  }

  for (final held in [0, 2, 3]) {
    test('feather at $held held resolves with capacity', () async {
      kind = 'feather';
      await storage.saveFeathers(held);
      final gift = (await apply.claim('group'))!;
      expect(gift.kind, held == 3 ? 'piece' : 'feather');
      expect(gift.fallback, held == 3);
      expect(storage.feathers, held == 3 ? 3 : held + 1);
      expect(storage.puzzlePieces, held == 3 ? 1 : 0);
      expect(storage.coins, 0);
    });
  }

  for (final rolled in ['feather', 'piece']) {
    test('$rolled falls back to pre-rolled coins at both limits', () async {
      kind = rolled;
      await storage.saveFeathers(3);
      // PRD-2.6 LB2/O68, G1 and G6d: a meta gift stops at three held.
      await storage.savePuzzlePieces(11);
      final gift = (await apply.claim('group'))!;
      expect(gift.kind, 'coins');
      expect(gift.fallback, isTrue);
      expect(storage.coins, 175);
      expect(storage.feathers, 3);
      expect(storage.puzzlePieces, 11);
    });
  }

  for (final mask in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]) {
    test('piece capacity uses held count for mask $mask', () async {
      kind = 'piece';
      await storage.savePuzzlePieces(mask);
      final round = storage.puzzleRound;
      final gift = (await apply.claim('group'))!;
      final count = [1, 2, 4, 8].where((bit) => mask & bit != 0).length;
      if (count >= 3) {
        // PRD-2.6 LB2/O68: meta gifts never complete the run puzzle;
        // the three-held limit matches G1's chest and G6d's Star Road.
        expect(gift.kind, 'coins');
        expect(gift.fallback, isTrue);
        expect(storage.puzzlePieces, mask);
        expect(storage.coins, 175);
      } else {
        final missing = [1, 2, 4, 8].firstWhere((bit) => mask & bit == 0);
        expect(gift.kind, 'piece');
        expect(gift.fallback, isFalse);
        expect(storage.puzzlePieces, mask | missing);
        expect(storage.coins, 0);
      }
      expect(storage.puzzleRound, round);
    });
  }

  for (final key in ['bird:sky', 'bird:robin']) {
    test('unowned eligible $key granted without auto equip', () async {
      kind = 'item';
      item = key;
      final gift = (await apply.claim('group'))!;
      expect(gift.kind, 'item');
      expect(gift.item, key);
      expect(gift.rarity, key == 'bird:sky' ? 'common' : 'rare');
      expect(storage.ownedItems, contains(key));
      expect(
        storage.equippedItems.values,
        isNot(contains(key.split(':').last)),
      );
      expect(storage.coins, 0);
      expect(services.events.single.$2!['rarity'], gift.rarity);
    });
  }

  for (final key in [
    null,
    'bird:unknown',
    'bird:classic',
    'bird:robo',
    'bird:golden',
    'card:basic',
    'card:f_bubblegum',
    'card:pecking',
    'frame:pecking',
    'bird:magpie',
  ]) {
    test('ineligible $key becomes pre-rolled coins', () async {
      kind = 'item';
      item = key;
      final gift = (await apply.claim('group'))!;
      expect(gift.kind, 'coins');
      expect(gift.fallback, isTrue);
      expect(gift.item, isNull);
      expect(storage.coins, 175);
      expect(storage.ownedItems, isNot(contains(key)));
    });
  }

  test(
    'F9 cards and skill entries are excluded from gift owned requests',
    () async {
      await storage.saveOwnedItems({
        'bird:sky',
        'card:f_bubblegum',
        'card:pecking',
      });
      await apply.claim('group');
      expect(requests.single['owned'], contains('bird:sky'));
      expect(
        (requests.single['owned'] as List).where(
          (key) => (key as String).startsWith('card:'),
        ),
        isEmpty,
      );
    },
  );

  test('owned item becomes coins and ownership sent to service', () async {
    kind = 'item';
    item = 'bird:sky';
    await storage.saveOwnedItems({'bird:sky'});
    expect((await apply.claim('group'))!.kind, 'coins');
    expect(requests.single['owned'], containsAll(['bird:sky', 'bird:classic']));
    expect(storage.coins, 175);
  });

  test(
    'unshown prize blocks another claim and stale reveal cannot clear it',
    () async {
      await apply.claim('group');
      await apply.markShown('wrong');
      expect((await apply.claim('another'))!.id, 'gift_canonical');
      expect(requests, hasLength(1));
      expect(storage.lbGiftPending, isNotEmpty);
    },
  );

  test('concurrent claims serialize to one credit', () async {
    await Future.wait([apply.claim('group'), apply.claim('group')]);
    expect(requests, hasLength(1));
    expect(storage.coins, 175);
  });

  test('failed service response leaves no local claim', () async {
    ok = false;
    expect(await apply.claim('group'), isNull);
    expect(storage.lbGiftPending, isEmpty);
    expect(storage.lbGiftsClaimed, isEmpty);
    expect(storage.coins, 0);
    expect(services.events, isEmpty);
  });
}
