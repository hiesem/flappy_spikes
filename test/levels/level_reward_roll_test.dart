import 'dart:math';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';

import 'package:flappy_spikes/levels/level_reward_roll.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

SkinItem byKey(String key) => allItems.firstWhere((item) => item.key == key);
Set<String> ownedExcept(bool Function(SkinItem) keep) => {
  for (final item in allItems)
    if (!keep(item)) item.key,
};

void main() {
  test('unlock excludes an otherwise eligible priced shop item', () {
    const locked = SkinItem(
      layer: SkinLayer.hat,
      id: 'test',
      name: 'Test',
      rarity: Rarity.common,
      price: 250,
      unlock: AchievementId.rankEgg,
    );
    const sold = SkinItem(
      layer: SkinLayer.hat,
      id: 'test',
      name: 'Test',
      rarity: Rarity.common,
      price: 250,
    );
    expect(isLevelRewardEligible(sold, {}, {}), isTrue);
    expect(isLevelRewardEligible(locked, {}, {}), isFalse);
  });

  test('achievement unlock items are excluded from rewards', () {
    final unlocks = allItems.where((item) => item.unlock != null).toList();
    expect(unlocks, isNotEmpty);
    final owned = ownedExcept((item) => item.unlock != null);
    expect(rollLevelReward(32, owned, {}, Random(7)).item, isNull);
  });

  test(
    'J4 preferred category and rarity, excluding free, owned and pending',
    () {
      final eligible = allItems
          .where(
            (i) =>
                i.layer == SkinLayer.hat &&
                i.rarity == Rarity.common &&
                !i.isFree,
          )
          .toList();
      final owned = {eligible.first.key};
      final pending = {eligible[1].key};
      for (var seed = 0; seed < 100; seed++) {
        final result = rollLevelReward(1, owned, pending, Random(seed));
        final item = byKey(result.item!);
        expect(item.layer, SkinLayer.hat);
        expect(item.rarity, Rarity.common);
        expect(item.isFree, isFalse);
        expect(owned.contains(item.key) || pending.contains(item.key), isFalse);
        expect(result.fallback, 'none');
        expect(result.extraCoins, 0);
      }
    },
  );

  test(
    'J4 up tries the first available higher rarity before other categories',
    () {
      for (final rarity in [Rarity.rare, Rarity.epic, Rarity.legendary]) {
        final owned = {
          for (final item in allItems)
            if (item.layer == SkinLayer.hat &&
                (item.rarity?.index ?? -1) < rarity.index)
              item.key,
        };
        final result = rollLevelReward(1, owned, {}, Random(7));
        expect(byKey(result.item!).layer, SkinLayer.hat);
        expect(byKey(result.item!).rarity, rarity);
        expect(result.fallback, 'up');
      }
    },
  );

  test('J4 other categories try same rarity then higher in order', () {
    for (final rarity in Rarity.values) {
      final owned = ownedExcept(
        (i) =>
            i.layer != SkinLayer.hat && (i.rarity?.index ?? -1) >= rarity.index,
      );
      final result = rollLevelReward(1, owned, {}, Random(7));
      expect(byKey(result.item!).layer, isNot(SkinLayer.hat));
      expect(byKey(result.item!).rarity, rarity);
      expect(result.fallback, 'other_cat');
    }
  });

  test('R9 exhausted rarity never goes lower and pays its shop price', () {
    for (final level in [1, 10, 20, 30, 31]) {
      final rarity = trackLevelDef(level)!.rarity;
      final owned = ownedExcept((i) => (i.rarity?.index ?? -1) < rarity.index);
      expect(rollLevelReward(level, owned, {}, Random(7)), (
        item: null,
        extraCoins: rarity.price,
        fallback: 'coins',
      ));
    }
  });

  test('L31 draws legendary items across every shop layer', () {
    final layers = <SkinLayer>{};
    for (var seed = 0; seed < 200; seed++) {
      final roll = rollLevelReward(31, {}, {}, Random(seed));
      final item = byKey(roll.item!);
      expect(item.rarity, Rarity.legendary);
      expect(roll.fallback, 'none');
      layers.add(item.layer);
    }
    expect(layers, {
      SkinLayer.bird,
      SkinLayer.gear,
      SkinLayer.hat,
      SkinLayer.hoop,
      SkinLayer.trail,
    });
  });

  test('seeded sequence is deterministic including a pending reward chain', () {
    List<LevelRewardRoll> sequence() {
      final random = Random(42);
      final pending = <String>{};
      return [
        for (var level = 1; level <= 60; level++)
          (() {
            final result = rollLevelReward(level, {}, pending, random);
            if (result.item != null) expect(pending.add(result.item!), isTrue);
            return result;
          })(),
      ];
    }

    expect(sequence(), sequence());
  });

  test(
    '32+ is uniform over items across rarities, excluding owned and pending',
    () {
      final owned = {'bird:sky', 'hat:crown'};
      final pending = {'gear:shades'};
      final candidates = allItems
          .where(
            (i) =>
                // PRD 2.6 F9 / O21: cards never enter level reward draws.
                i.layer != SkinLayer.card &&
                !i.isSkillOnly &&
                !i.isFree &&
                i.rarity != null &&
                !owned.contains(i.key) &&
                !pending.contains(i.key),
          )
          .toList();
      final counts = {for (final item in candidates) item.key: 0};
      final random = Random(2026);
      for (var i = 0; i < 10000; i++) {
        final result = rollLevelReward(32 + i, owned, pending, random);
        expect(result.fallback, 'none');
        expect(counts.containsKey(result.item), isTrue);
        counts[result.item!] = counts[result.item!]! + 1;
      }
      final expected = 10000 / candidates.length;
      final chiSquare = counts.values.fold<double>(
        0,
        (sum, count) => sum + pow(count - expected, 2) / expected,
      );
      expect(chiSquare, lessThan(230));
      expect(counts.values.every((n) => n > 0), isTrue);
    },
  );

  test('32+ exhausted catalogue adds no extra coins', () {
    expect(
      rollLevelReward(32, {for (final i in allItems) i.key}, {}, Random(7)),
      (item: null, extraCoins: 0, fallback: 'coins'),
    );
  });
}
