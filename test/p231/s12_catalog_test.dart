// PRD-2.3.1 §12.1 / §12.9 the achievement catalog: 48 entries, unique keys
// and ids, the approved points (755 in total), the 7 hidden rides, an icon
// per key, and an Android id for every key once Play Console created them.
import 'dart:io';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const all = AchievementId.values;

  test('§12.9 48 entries, unique keys, iOS ids = fs_ach_<key>', () {
    expect(all, hasLength(48));
    expect(all.map((a) => a.key).toSet(), hasLength(48));
    expect(all.map((a) => a.title).toSet(), hasLength(48));
    final ios = all.map((a) => a.iosId).toSet();
    expect(ios, hasLength(48));
    for (final a in all) {
      expect(a.iosId, 'fs_ach_${a.key}');
      expect(AchievementId.fromKey(a.key), a);
    }
  });

  test('§12.9 points per group and 755 in total; multiples of 5, ≤ 100; '
      'the 7 rides plus the PRD-2.3.1 §19.3 ten hidden', () {
    int sum(AchievementGroup g) =>
        all.where((a) => a.group == g).fold(0, (s, a) => s + a.points);
    expect(sum(AchievementGroup.rank), 220);
    expect(sum(AchievementGroup.ride), 90);
    expect(sum(AchievementGroup.item), 80);
    expect(sum(AchievementGroup.mastery), 60);
    expect(sum(AchievementGroup.hoops), 75);
    expect(sum(AchievementGroup.versus), 75);
    expect(sum(AchievementGroup.more), 155);
    expect(all.fold(0, (s, a) => s + a.points), 755);
    for (final a in all) {
      expect(a.points % 5, 0, reason: a.key);
      expect(a.points, inInclusiveRange(5, 100), reason: a.key);
    }
    // PRD-2.3.1 §19.3 (changed from §12.1's rides only): the rides, the 5
    // masteries, MAGPIE, vs_10, vs_50, skin_all and daily_30.
    final hidden = all.where((a) => a.hidden).toList();
    expect(hidden, hasLength(17));
    expect(
      hidden.where((a) => a.group != AchievementGroup.ride).map((a) => a.key),
      unorderedEquals([
        'master_hatch',
        'master_jar',
        'master_stars',
        'master_picture',
        'master_jackpot',
        'item_all',
        'vs_10',
        'vs_50',
        'skin_all',
        'daily_30',
      ]),
    );
    expect(all.where((a) => a.group == AchievementGroup.ride), hasLength(7));
  });

  test('§12.1 the order and the group sizes (10 / 7 / 12 / 5 / 4 / 3 / 7)', () {
    expect(all.first, AchievementId.rankEgg);
    expect(all.last, AchievementId.daily30);
    final sizes = [
      for (final g in AchievementGroup.values)
        all.where((a) => a.group == g).length,
    ];
    expect(sizes, [10, 7, 12, 5, 4, 3, 7]);
    // Groups are contiguous, in the §12.1 order.
    final order = all.map((a) => a.group.index).toList();
    expect(order, [...order]..sort());
    expect(kRankAchievements, hasLength(kLevels.length));
    expect(kItemAchievements, hasLength(11));
  });

  test('§12.9 store texts: Play limits (name ≤ 100, description ≤ 500)', () {
    for (final a in all) {
      expect(a.title.length, lessThanOrEqualTo(100));
      expect(a.description, isNotEmpty);
      expect(a.description.length, lessThanOrEqualTo(500));
      expect(a.earned, isNotEmpty);
    }
  });

  test('§12.9 a matching 160 px icon asset exists for every key', () {
    for (final a in all) {
      final f = File('assets/images/${a.asset}');
      expect(f.existsSync(), isTrue, reason: f.path);
      expect(a.asset, 'achievements/ach_${a.key}.png');
    }
  });

  test('§12.9 every Android id is non-empty and unique (after §12.6)', () {
    final ids = all.map((a) => a.androidId).toList();
    expect(ids.where((id) => id.isEmpty), isEmpty);
    expect(ids.toSet(), hasLength(48));
  });
}
