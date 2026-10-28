import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/calm_schedule.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/hazard_budget.dart';
import 'package:flappy_spikes/run/director/headline_window.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../tool/gen_obf_strings.dart';

void main() {
  test('the PRD-2.6 storage keys are appended in order', () {
    expect(kObfStrings.values.toList().sublist(101, 109), [
      'ftueSteps',
      'showcaseSeen',
      'showcaseAttempt',
      'showcaseRuns',
      'showcaseDoneAt',
      'installAtMs',
      'bestHoops',
      'pendingFirstMeets',
    ]);
    expect([
      Obf.prefFtueSteps,
      Obf.prefShowcaseSeen,
      Obf.prefShowcaseAttempt,
      Obf.prefShowcaseRuns,
      Obf.prefShowcaseDoneAt,
      Obf.prefInstallAtMs,
      Obf.prefBestHoops,
      Obf.prefPendingFirstMeets,
    ], kObfStrings.values.toList().sublist(101, 109));
  });

  test(
    'the new state round-trips and Delete my data clears run queue state',
    () async {
      SharedPreferences.setMockInitialValues({
        'ftueSteps': 3,
        'showcaseSeen': 5,
        'showcaseAttempt': 2,
        'showcaseRuns': 4,
        'showcaseDoneAt': 6,
        'installAtMs': 123,
        'bestHoops': 17,
        'pendingFirstMeets': [
          '{"element":"saw","hoop":3,"games":1,"forced":true,"survived":false}',
        ],
      });
      final storage = GameStorage();
      await storage.load();
      expect(storage.ftueSteps, 3);
      expect(storage.showcaseSeen, 5);
      expect(storage.showcaseAttempt, 2);
      expect(storage.showcaseRuns, 4);
      expect(storage.showcaseDoneAt, 6);
      expect(storage.installAtMs, 123);
      expect(storage.bestHoops, 17);
      expect(storage.pendingFirstMeets, hasLength(1));

      await storage.saveLvlIndex(0);
      await storage.saveLvlPoints(0);
      await storage.saveLvlPending(const []);
      await storage.saveLvlPayout(0);
      await storage.saveBestRunHoops(0);
      await storage.saveRecentScores(const []);
      await storage.saveDuelStep(-2);
      await storage.saveLifetimeCoinsEarned(0);
      await storage.saveLifetimeCoinsSpent(0);
      await storage.saveLifetimeCoinsBought(0);
      await storage.saveVsWinStreak(0);
      await storage.saveVsWinStreakBest(0);
      await storage.saveVsBigWinsDay(const {});
      await storage.saveMissionDay(-1);
      await storage.saveMissions(const []);
      await storage.saveMissionTier(0);
      await storage.saveMissionRerollDay(-1);
      await storage.saveStreakDays(0);
      await storage.saveStreakLastDay(-1);
      await storage.saveStreakPaidDay(-1);
      await storage.saveStreakLostDays(0);
      await storage.saveStreakLostSeenDay(-1);
      await storage.saveWorldsReached(0);
      await storage.saveWorldsSeen(0);
      await storage.saveWeeklyBest(const {});
      await storage.saveWeeklyRewards(const {});
      await storage.saveWeeklyHintDay(-1);
      await storage.saveFirstWinDay(-1);
      await storage.saveAlbumCounts(const [0, 0, 0, 0, 0, 0, 0, 0]);
      await storage.saveAlbumRewardClaimed(false);
      await storage.saveAlbumRewardItem('');
      await storage.saveGuideSeenCount(0);
      await storage.saveStarRoadSeason(0);
      await storage.saveStarRoadXp(0);
      await storage.saveStarRoadClaimed(const {});
      await storage.saveStarRoadPopupDay(-1);
      await storage.saveHomeLevelsTag(false);
      await storage.saveLbQueue(const []);
      await storage.saveLbGroupId('');
      await storage.saveLbGroupEnd(0);
      await storage.saveLbLastRank(0);
      await storage.saveLbGiftsClaimed(const {});
      await storage.saveLbGiftPending(const {});
      await storage.saveLbInfoSeen(false);
      await storage.saveAbArmV1('');
      await storage.savePlayerLevel(5);
      await storage.saveClaimedLevels({1, 2});
      await storage.saveUnclaimedLevelReward(42);
      await storage.saveLevelRewardPayout(99);
      await storage.saveLvlRewardLog([
        {"lvl": 1, "coins": 50},
      ]);
      await storage.resetVersusData();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(Obf.prefLvlRewardLog), isFalse);
      expect(storage.lvlRewardLog, isEmpty);
      expect(prefs.containsKey(Obf.prefLvlIndex), isFalse, reason: 'lvlIndex');
      expect(
        prefs.containsKey(Obf.prefLvlPoints),
        isFalse,
        reason: 'lvlPoints',
      );
      expect(
        prefs.containsKey(Obf.prefLvlPending),
        isFalse,
        reason: 'lvlPending',
      );
      expect(
        prefs.containsKey(Obf.prefLvlPayout),
        isFalse,
        reason: 'lvlPayout',
      );
      expect(
        prefs.containsKey(Obf.prefBestRunHoops),
        isFalse,
        reason: 'bestRunHoops',
      );
      expect(
        prefs.containsKey(Obf.prefRecentScores),
        isFalse,
        reason: 'recentScores',
      );
      expect(prefs.containsKey(Obf.prefDuelStep), isFalse, reason: 'duelStep');
      expect(
        prefs.containsKey(Obf.prefLifetimeCoinsEarned),
        isFalse,
        reason: 'lifetimeCoinsEarned',
      );
      expect(
        prefs.containsKey(Obf.prefLifetimeCoinsSpent),
        isFalse,
        reason: 'lifetimeCoinsSpent',
      );
      expect(
        prefs.containsKey(Obf.prefLifetimeCoinsBought),
        isFalse,
        reason: 'lifetimeCoinsBought',
      );
      expect(
        prefs.containsKey(Obf.prefVsWinStreak),
        isFalse,
        reason: 'vsWinStreak',
      );
      expect(
        prefs.containsKey(Obf.prefVsWinStreakBest),
        isFalse,
        reason: 'vsWinStreakBest',
      );
      expect(
        prefs.containsKey(Obf.prefVsBigWinsDay),
        isFalse,
        reason: 'vsBigWinsDay',
      );
      expect(
        prefs.containsKey(Obf.prefMissionDay),
        isFalse,
        reason: 'missionDay',
      );
      expect(prefs.containsKey(Obf.prefMissions), isFalse, reason: 'missions');
      expect(
        prefs.containsKey(Obf.prefMissionTier),
        isFalse,
        reason: 'missionTier',
      );
      expect(
        prefs.containsKey(Obf.prefMissionRerollDay),
        isFalse,
        reason: 'missionRerollDay',
      );
      expect(
        prefs.containsKey(Obf.prefWorldsReached),
        isFalse,
        reason: 'worldsReached',
      );
      expect(
        prefs.containsKey(Obf.prefWorldsSeen),
        isFalse,
        reason: 'worldsSeen',
      );
      expect(
        prefs.containsKey(Obf.prefWeeklyBest),
        isFalse,
        reason: 'weeklyBest',
      );
      expect(
        prefs.containsKey(Obf.prefWeeklyRewards),
        isFalse,
        reason: 'weeklyRewards',
      );
      expect(
        prefs.containsKey(Obf.prefWeeklyHintDay),
        isFalse,
        reason: 'weeklyHintDay',
      );
      expect(
        prefs.containsKey(Obf.prefFirstWinDay),
        isFalse,
        reason: 'firstWinDay',
      );
      expect(
        prefs.containsKey(Obf.prefAlbumCounts),
        isFalse,
        reason: 'albumCounts',
      );
      expect(
        prefs.containsKey(Obf.prefAlbumRewardClaimed),
        isFalse,
        reason: 'albumRewardClaimed',
      );
      expect(
        prefs.containsKey(Obf.prefAlbumRewardItem),
        isFalse,
        reason: 'albumRewardItem',
      );
      expect(
        prefs.containsKey(Obf.prefGuideSeenCount),
        isFalse,
        reason: 'guideSeenCount',
      );
      expect(
        prefs.containsKey(Obf.prefStarRoadSeason),
        isFalse,
        reason: 'starRoadSeason',
      );
      expect(
        prefs.containsKey(Obf.prefStarRoadXp),
        isFalse,
        reason: 'starRoadXp',
      );
      expect(
        prefs.containsKey(Obf.prefStarRoadClaimed),
        isFalse,
        reason: 'starRoadClaimed',
      );
      expect(
        prefs.containsKey(Obf.prefStarRoadPopupDay),
        isFalse,
        reason: 'starRoadPopupDay',
      );
      expect(
        prefs.containsKey(Obf.prefHomeLevelsTag),
        isFalse,
        reason: 'homeLevelsTag',
      );
      expect(prefs.containsKey(Obf.prefLbQueue), isFalse, reason: 'lbQueue');
      expect(
        prefs.containsKey(Obf.prefLbGroupId),
        isFalse,
        reason: 'lbGroupId',
      );
      expect(
        prefs.containsKey(Obf.prefLbGroupEnd),
        isFalse,
        reason: 'lbGroupEnd',
      );
      expect(
        prefs.containsKey(Obf.prefLbLastRank),
        isFalse,
        reason: 'lbLastRank',
      );
      expect(
        prefs.containsKey(Obf.prefLbGiftsClaimed),
        isFalse,
        reason: 'lbGiftsClaimed',
      );
      expect(
        prefs.containsKey(Obf.prefLbGiftPending),
        isFalse,
        reason: 'lbGiftPending',
      );
      expect(
        prefs.containsKey(Obf.prefLbInfoSeen),
        isFalse,
        reason: 'lbInfoSeen',
      );
      for (final key in [
        Obf.prefPlayerLevel,
        Obf.prefClaimedLevels,
        Obf.prefUnclaimedLevelReward,
        Obf.prefLevelRewardPayout,
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(storage.ftueSteps, 0);
      expect(storage.showcaseSeen, 0);
      expect(storage.showcaseAttempt, 0);
      expect(storage.showcaseRuns, 0);
      expect(storage.showcaseDoneAt, isNull);
      expect(storage.pendingFirstMeets, isEmpty);
      for (final key in [
        Obf.prefFtueSteps,
        Obf.prefShowcaseSeen,
        Obf.prefShowcaseAttempt,
        Obf.prefShowcaseRuns,
        Obf.prefShowcaseDoneAt,
        Obf.prefPendingFirstMeets,
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    },
  );

  // region P26-C3R
  test('PRD-2.6 C3: rating waits for the showcase and two later runs', () {
    // C3R editor call: PRD silent on unfinished showcase; follows C3 intent.
    expect(Config.ratingMinRunsFor(null), 7);
    expect(Config.ratingMinRunsFor(0), 5);
    expect(Config.ratingMinRunsFor(3), 5);
    expect(Config.ratingMinRunsFor(4), 6);
    expect(Config.ratingMinRunsFor(10), 12);
  });

  test('PRD-2.6 C3: rating minimum reads both tuning keys', () {
    final previous = TuningValues.current;
    addTearDown(() => TuningValues.current = previous);
    TuningValues.current = TuningValues.resolve({
      'rate_min_runs': '10',
      'showcase_max_games': '12',
    });
    expect(Config.ratingMinRunsFor(null), 13);
    expect(Config.ratingMinRunsFor(3), 10);
    expect(Config.ratingMinRunsFor(8), 10);
    expect(Config.ratingMinRunsFor(9), 11);

    TuningValues.current = TuningValues.resolve({
      'rate_min_runs': '15',
      'showcase_max_games': '8',
    });
    expect(Config.ratingMinRunsFor(null), 15);
    expect(Config.ratingMinRunsFor(6), 15);
  });
  // endregion

  test('Home moments use the C2 priority order and pass through', () {
    expect(HomeMoment.values, [
      HomeMoment.streakLost,
      HomeMoment.levelUp,
      HomeMoment.streakReward,
      HomeMoment.leaderboardCollect,
      HomeMoment.missionsChest,
      HomeMoment.starRoad,
      HomeMoment.noAds,
      HomeMoment.rating,
    ]);
    var opened = false;
    const PassthroughHomeMoments().show(HomeMoment.rating, () {
      opened = true;
    });
    expect(opened, isTrue);
  });

  test('the wave-1 model defaults and stub modules are inert', () {
    const setup = RunSetup(seed: 1, viewHeight: 711);
    expect(setup.showcase, isNull);
    expect(setup.extraStarters, isEmpty);
    final plan = const SlotPlan(
      index: 0,
      kind: HoopKindId.normal,
      element: ElementId.normalHoop,
      trackX: 0,
      centreY: 0,
      opening: 100,
      advance: 310,
    );
    expect(plan.calm, isFalse);
    expect(plan.hazardCost, 0);
    expect(plan.formation, isNull);

    final copy = plan.copyWith(
      calm: true,
      hazardCost: 2,
      formation: () => FormationId.stairs,
    );
    expect(copy.calm, isTrue);
    expect(copy.hazardCost, 2);
    expect(copy.formation, FormationId.stairs);

    expect(HazardBudget().allows(copy), isTrue);
    expect(CalmSchedule().dueAt(31), isFalse);
    expect(HeadlineWindow().allows('portal', 7), isTrue);
    expect(Formations().nextAt(150), isNull);
  });
}
