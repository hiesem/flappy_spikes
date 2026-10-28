import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/progression/star_road.dart';

Missions board(Set<MissionDifficulty> complete) => Missions(
  day: 10,
  missions: [
    for (final template in [
      MissionTemplate.m01,
      MissionTemplate.m03,
      MissionTemplate.m11,
    ])
      MissionProgress(
        template: template,
        target: 1,
        progress: complete.contains(template.difficulty) ? 1 : 0,
      ),
  ],
);

void main() {
  test('first run and each mission award at most eleven stars in a day', () {
    var road = StarRoad(season: 1);
    road = road.finishRun(
      before: board({}),
      after: board({MissionDifficulty.easy}),
      firstFinishedRun: true,
    );
    expect(road.xp, 3);
    road = road.finishRun(
      before: board({MissionDifficulty.easy}),
      after: board(MissionDifficulty.values.toSet()),
      firstFinishedRun: false,
    );
    expect(road.xp, 11);
    road = road.finishRun(
      before: board(MissionDifficulty.values.toSet()),
      after: board(MissionDifficulty.values.toSet()),
      firstFinishedRun: false,
    );
    expect(road.xp, 11);
    expect(road.tier, 1);
    expect(road.starsIntoTier, 3);
  });

  test(
    'tier claims, cap and season rollover return unclaimed rewards once',
    () {
      final road = StarRoad(season: 1, xp: 200, claimed: {1, 10});
      expect(road.tier, 25);
      expect(road.claimable.length, 23);
      final claimed = road.claim(2);
      expect(claimed.reward!.coins, 25);
      expect(claimed.state.claim(2).reward, isNull);
      final end = claimed.state.rollover(3);
      expect(end.endedSeason, 1);
      expect(end.rewards.length, 22);
      expect(end.rewards.last.kind, StarRoadRewardKind.legendary);
      expect(end.state.xp, 0);
      expect(end.state.claimable, isEmpty);
      expect(end.state.rollover(3).rewards, isEmpty);
      expect(StarRoad().rollover(3).rewards, isEmpty);
    },
  );

  test('calendar and names repeat on 28 and 364 days', () {
    expect(starRoadSeasonForDay(127, epochDay: 100), 1);
    expect(starRoadDaysLeft(127, epochDay: 100), 1);
    expect(starRoadSeasonForDay(128, epochDay: 100), 2);
    expect(starRoadDaysLeft(128, epochDay: 100), 28);
    expect(starRoadSeasonName(1), 'SPIKE SPRING');
    expect(starRoadSeasonName(13), 'SPIKE NIGHT');
    expect(starRoadSeasonName(14), 'SPIKE SPRING');
  });

  test('popup day survives reconstruction and excludes early runs', () {
    final road = StarRoad(season: 1, xp: 8);
    expect(road.shouldShowPopup(today: 10, runNumber: 3), isFalse);
    final shown = road.markPopupShown(today: 10, runNumber: 4);
    final restored = StarRoad(
      season: shown.season,
      xp: shown.xp,
      claimed: shown.claimed,
      popupDay: shown.popupDay,
    );
    expect(restored.shouldShowPopup(today: 10, runNumber: 4), isFalse);
    expect(restored.shouldShowPopup(today: 11, runNumber: 4), isTrue);
  });
}
