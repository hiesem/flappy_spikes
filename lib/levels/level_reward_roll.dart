import 'dart:math';

import '../skins/catalog.dart';
import '../skins/look.dart';
import 'level_track.dart';

/// A persisted J4 outcome. [fallback] is the analytics tag from J10.
typedef LevelRewardRoll = ({String? item, int extraCoins, String fallback});

// F10 adds SkinItem.unlock. An instance getter takes precedence over this
// compatibility extension when that package merges; no reflection is needed.
extension _PreSkillCatalogue on SkinItem {
  Object? get unlock => null;
}

/// PRD-2.6 J4 / R9 / O21. Selection order is catalogue order and the supplied
/// random stream is the only randomness. Pending entries are item keys.
LevelRewardRoll rollLevelReward(
  int level,
  Set<String> owned,
  Set<String> pending,
  Random random,
) {
  final def = trackLevelDef(level);
  if (def == null) throw ArgumentError.value(level, 'level');
  const shopLayers = {
    SkinLayer.bird,
    SkinLayer.hat,
    SkinLayer.gear,
    SkinLayer.hoop,
    SkinLayer.trail,
  };
  final available = allItems
      .where(
        (item) =>
            shopLayers.contains(item.layer) &&
            !item.isFree &&
            item.rarity != null &&
            item.unlock == null &&
            !owned.contains(item.key) &&
            !pending.contains(item.key),
      )
      .toList();

  LevelRewardRoll pick(List<SkinItem> candidates, String fallback) => (
    item: candidates[random.nextInt(candidates.length)].key,
    extraCoins: 0,
    fallback: fallback,
  );

  if (level >= 32) {
    return available.isEmpty
        ? (item: null, extraCoins: 0, fallback: 'coins')
        : pick(available, 'none');
  }

  final reward = def.item;
  // First exhaust the named category, starting at the promised rarity.
  for (var r = reward.rarity.index; r < Rarity.values.length; r++) {
    final candidates = available
        .where(
          (item) =>
              (reward.layer == null || item.layer == reward.layer) &&
              item.rarity == Rarity.values[r],
        )
        .toList();
    if (candidates.isNotEmpty) {
      return pick(candidates, r == reward.rarity.index ? 'none' : 'up');
    }
  }
  if (reward.layer != null) {
    for (var r = reward.rarity.index; r < Rarity.values.length; r++) {
      final candidates = available
          .where(
            (item) =>
                item.layer != reward.layer && item.rarity == Rarity.values[r],
          )
          .toList();
      if (candidates.isNotEmpty) return pick(candidates, 'other_cat');
    }
  }
  return (item: null, extraCoins: reward.rarity.price, fallback: 'coins');
}
