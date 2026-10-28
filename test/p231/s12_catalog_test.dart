// PRD-2.3.1 §12.1 / §12.9 the achievement catalog: 58 entries, unique keys
// and ids, the approved points (965 in total), the 7 hidden rides, an icon
// per key, and an Android id for every key once Play Console created them.
import 'dart:io';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/achievements/achievements.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/game_services.dart';

void main() {
  const all = AchievementId.values;

  test('§12.9 58 entries, unique keys, iOS ids = fs_ach_<key>', () {
    expect(all, hasLength(58));
    expect(all.map((a) => a.key).toSet(), hasLength(58));
    expect(all.map((a) => a.title).toSet(), hasLength(58));
    final ios = all.map((a) => a.iosId).toSet();
    expect(ios, hasLength(58));
    for (final a in all) {
      expect(a.iosId, 'fs_ach_${a.key}');
      expect(AchievementId.fromKey(a.key), a);
    }
  });

  test('§12.9 points per group and 965 in total; multiples of 5, ≤ 100; '
      'the 7 rides plus the PRD-2.3.1 §19.3 ten hidden', () {
    int sum(AchievementGroup g) =>
        all.where((a) => a.group == g).fold(0, (s, a) => s + a.points);
    expect(sum(AchievementGroup.rank), 220);
    expect(sum(AchievementGroup.ride), 90);
    expect(sum(AchievementGroup.item), 80);
    expect(sum(AchievementGroup.mastery), 100);
    expect(sum(AchievementGroup.hoops), 125);
    expect(sum(AchievementGroup.versus), 170);
    expect(sum(AchievementGroup.more), 180);
    expect(all.fold(0, (s, a) => s + a.points), 965);
    for (final a in all) {
      expect(a.points % 5, 0, reason: a.key);
      expect(a.points, inInclusiveRange(5, 100), reason: a.key);
    }
    // PRD-2.3.1 §19.3 (changed from §12.1's rides only): the rides, the 5
    // masteries, MAGPIE, vs_10, vs_50, skin_all and daily_30.
    final hidden = all.where((a) => a.hidden).toList();
    expect(hidden, hasLength(18));
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
        'bird_of_prey',
      ]),
    );
    expect(all.where((a) => a.group == AchievementGroup.ride), hasLength(7));
  });

  test('§12.1 the order and the group sizes (10 / 7 / 12 / 5 / 4 / 3 / 7)', () {
    expect(all.first, AchievementId.rankEgg);
    expect(all.last, AchievementId.birdwatcher);
    final sizes = [
      for (final g in AchievementGroup.values)
        all.where((a) => a.group == g).length,
    ];
    expect(sizes, [10, 7, 12, 6, 5, 10, 8]);
    // Groups are contiguous, in the §12.1 order.
    final order = all.map((a) => a.group.index).toList();
    expect(order, [...order]..sort());
    expect(kRankAchievements, hasLength(10));
    expect(kItemAchievements, hasLength(11));
  });

  test('PRD 2.6 versus streak, daily wins and threshold rules', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    final tracker = AchievementTracker(
      storage: storage,
      services: GameServices(),
    );
    for (var i = 0; i < 5; i++) {
      tracker.onVersusResult(
        win: true,
        score: 1000,
        rivalScore: 500,
        deficit: 100,
        streak: 20,
        revives: 0,
      );
    }
    await tracker.flush();
    expect(storage.vsWinStreak, 5);
    expect(storage.vsWinStreakBest, 5);
    for (final id in [
      AchievementId.birdOfPrey,
      AchievementId.secondWind,
      AchievementId.albatross,
      AchievementId.threeLittleBirds,
      AchievementId.ironBeak,
      AchievementId.flawless,
    ]) {
      expect(tracker.isPending(id), isTrue, reason: id.key);
    }
    tracker.onVersusResult(
      win: false,
      score: 1,
      rivalScore: 2,
      deficit: 0,
      streak: 0,
      revives: 0,
    );
    expect(storage.vsWinStreak, 0);
    expect(storage.vsWinStreakBest, 5);
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
    // PRD 2.6 J10: new icons are exported in wave 5.
    for (final a in all.where((a) => a.androidId.isNotEmpty)) {
      final f = File('assets/images/${a.asset}');
      expect(f.existsSync(), isTrue, reason: f.path);
      expect(a.asset, 'achievements/ach_${a.key}.png');
    }
  });

  test('§12.9 every Android id is non-empty and unique (after §12.6)', () {
    // PRD 2.6 C6: the ten new Play IDs await console drafts.
    final ids = all
        .where((a) => a.androidId.isNotEmpty)
        .map((a) => a.androidId)
        .toList();
    expect(ids.where((id) => id.isEmpty), isEmpty);
    expect(ids.toSet(), hasLength(48));
    expect(all.where((a) => a.androidId.isEmpty), hasLength(10));
  });
}
