import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/save_seal.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../tool/gen_obf_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'S0 keys append after the complete 2.5 / wave-1 prefix and have anchors',
    () {
      const keys = [
        'lvlIndex',
        'lvlPoints',
        'lvlPending',
        'lvlPayout',
        'bestRunHoops',
        'recentScores',
        'duelStep',
        'lifetimeCoinsEarned',
        'lifetimeCoinsSpent',
        'lifetimeCoinsBought',
        'vsWinStreak',
        'vsWinStreakBest',
        'vsBigWinsDay',
        'missionDay',
        'missions',
        'missionTier',
        'missionRerollDay',
        'streakDays',
        'streakLastDay',
        'streakPaidDay',
        'streakLostDays',
        'streakLostSeenDay',
        'worldsReached',
        'worldsSeen',
        'weeklyBest',
        'weeklyRewards',
        'weeklyHintDay',
        'firstWinDay',
        'albumCounts',
        'albumRewardClaimed',
        'albumRewardItem',
        'guideSeenCount',
        'starRoadSeason',
        'starRoadXp',
        'starRoadClaimed',
        'starRoadPopupDay',
        'homeLevelsTag',
        'lbQueue',
        'lbGroupId',
        'lbGroupEnd',
        'lbLastRank',
        'lbGiftsClaimed',
        'lbGiftPending',
        'lbInfoSeen',
        'abArm_v1',
        // F1 adds persisted markers for the PRD-2.6 F7 economy events.
        'firstItemBought',
        'economyDailyDay',
        'lvlRewardLog',
        // G1b orchestrator ruling: the mission journal and rival bit are appended.
        'lastVersusHadRival',
        'missionJournal',
        // PRD 933 / O78: G6c journals the picture completion before writes.
        'albumCompletionJournal',
        // region P26-G6eA — PRD G6 claim recovery journal.
        'starRoadJournal',
        'starRoadItems',
        // endregion
      ];
      expect(kObfStrings.values.skip(109), keys);
      final anchors = File('tool/anchor_strings.txt').readAsLinesSync();
      expect(anchors, containsAll(keys));
    },
  );

  test(
    'S0 defaults, every new key round-trips and reset preserves only streak/arm',
    () async {
      final storage = GameStorage();
      await storage.load();
      expect(storage.duelStep, -2);
      expect(storage.lvlIndex, 0);
      expect(storage.lvlPending, isEmpty);
      expect(storage.albumCounts, List.filled(8, 0));
      await storage.saveLvlIndex(17);
      await storage.saveLvlPoints(17);
      await storage.saveLvlPending([
        {'lvl': 2, 'coins': 50, 'item': 'hat:test'},
      ]);
      await storage.saveLvlPayout(17);
      await storage.saveBestRunHoops(17);
      await storage.saveRecentScores([2, 5, 8]);
      await storage.saveDuelStep(17);
      await storage.saveLifetimeCoinsEarned(17);
      await storage.saveLifetimeCoinsSpent(17);
      await storage.saveLifetimeCoinsBought(17);
      await storage.saveVsWinStreak(17);
      await storage.saveVsWinStreakBest(17);
      await storage.saveVsBigWinsDay({'2026-44': 42});
      await storage.saveMissionDay(17);
      await storage.saveMissions([
        {'lvl': 2, 'coins': 50, 'item': 'hat:test'},
      ]);
      await storage.saveMissionTier(17);
      await storage.saveMissionRerollDay(17);
      await storage.saveStreakDays(17);
      await storage.saveStreakLastDay(17);
      await storage.saveStreakPaidDay(17);
      await storage.saveStreakLostDays(17);
      await storage.saveStreakLostSeenDay(17);
      await storage.saveWorldsReached(17);
      await storage.saveWorldsSeen(17);
      await storage.saveWeeklyBest({'2026-44': 42});
      await storage.saveWeeklyRewards({2, 5});
      await storage.saveWeeklyHintDay(17);
      await storage.saveFirstWinDay(17);
      await storage.saveAlbumCounts([1, 2, 3, 4, 5, 6, 7, 8]);
      await storage.saveAlbumRewardClaimed(true);
      await storage.saveAlbumRewardItem('saved');
      await storage.saveGuideSeenCount(17);
      await storage.saveStarRoadSeason(17);
      await storage.saveStarRoadXp(17);
      await storage.saveStarRoadClaimed({2, 5});
      await storage.saveStarRoadPopupDay(17);
      await storage.saveHomeLevelsTag(true);
      await storage.saveLbQueue(['run:a', 'run:b']);
      await storage.saveLbGroupId('saved');
      await storage.saveLbGroupEnd(17);
      await storage.saveLbLastRank(17);
      await storage.saveLbGiftsClaimed({'gift:a', 'gift:b'});
      await storage.saveLbGiftPending({'id': 'gift:a', 'coins': 100});
      await storage.saveLbInfoSeen(true);
      await storage.saveAbArmV1('saved');
      final loaded = GameStorage();
      await loaded.load();
      expect(loaded.lvlIndex, 17, reason: 'lvlIndex');
      expect(loaded.lvlPoints, 17, reason: 'lvlPoints');
      expect(loaded.lvlPending, [
        {'lvl': 2, 'coins': 50, 'item': 'hat:test'},
      ], reason: 'lvlPending');
      expect(loaded.lvlPayout, 17, reason: 'lvlPayout');
      expect(loaded.bestRunHoops, 17, reason: 'bestRunHoops');
      expect(loaded.recentScores, [2, 5, 8], reason: 'recentScores');
      expect(loaded.duelStep, 17, reason: 'duelStep');
      expect(loaded.lifetimeCoinsEarned, 17, reason: 'lifetimeCoinsEarned');
      expect(loaded.lifetimeCoinsSpent, 17, reason: 'lifetimeCoinsSpent');
      expect(loaded.lifetimeCoinsBought, 17, reason: 'lifetimeCoinsBought');
      expect(loaded.vsWinStreak, 17, reason: 'vsWinStreak');
      expect(loaded.vsWinStreakBest, 17, reason: 'vsWinStreakBest');
      expect(loaded.vsBigWinsDay, {'2026-44': 42}, reason: 'vsBigWinsDay');
      expect(loaded.missionDay, 17, reason: 'missionDay');
      expect(loaded.missions, [
        {'lvl': 2, 'coins': 50, 'item': 'hat:test'},
      ], reason: 'missions');
      expect(loaded.missionTier, 17, reason: 'missionTier');
      expect(loaded.missionRerollDay, 17, reason: 'missionRerollDay');
      expect(loaded.streakDays, 17, reason: 'streakDays');
      expect(loaded.streakLastDay, 17, reason: 'streakLastDay');
      expect(loaded.streakPaidDay, 17, reason: 'streakPaidDay');
      expect(loaded.streakLostDays, 17, reason: 'streakLostDays');
      expect(loaded.streakLostSeenDay, 17, reason: 'streakLostSeenDay');
      expect(loaded.worldsReached, 17, reason: 'worldsReached');
      expect(loaded.worldsSeen, 17, reason: 'worldsSeen');
      expect(loaded.weeklyBest, {'2026-44': 42}, reason: 'weeklyBest');
      expect(loaded.weeklyRewards, {2, 5}, reason: 'weeklyRewards');
      expect(loaded.weeklyHintDay, 17, reason: 'weeklyHintDay');
      expect(loaded.firstWinDay, 17, reason: 'firstWinDay');
      expect(loaded.albumCounts, [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ], reason: 'albumCounts');
      expect(loaded.albumRewardClaimed, true, reason: 'albumRewardClaimed');
      expect(loaded.albumRewardItem, 'saved', reason: 'albumRewardItem');
      expect(loaded.guideSeenCount, 17, reason: 'guideSeenCount');
      expect(loaded.starRoadSeason, 17, reason: 'starRoadSeason');
      expect(loaded.starRoadXp, 17, reason: 'starRoadXp');
      expect(loaded.starRoadClaimed, {2, 5}, reason: 'starRoadClaimed');
      expect(loaded.starRoadPopupDay, 17, reason: 'starRoadPopupDay');
      expect(loaded.homeLevelsTag, true, reason: 'homeLevelsTag');
      expect(loaded.lbQueue, ['run:a', 'run:b'], reason: 'lbQueue');
      expect(loaded.lbGroupId, 'saved', reason: 'lbGroupId');
      expect(loaded.lbGroupEnd, 17, reason: 'lbGroupEnd');
      expect(loaded.lbLastRank, 17, reason: 'lbLastRank');
      expect(loaded.lbGiftsClaimed, {
        'gift:a',
        'gift:b',
      }, reason: 'lbGiftsClaimed');
      expect(loaded.lbGiftPending, {
        'id': 'gift:a',
        'coins': 100,
      }, reason: 'lbGiftPending');
      expect(loaded.lbInfoSeen, true, reason: 'lbInfoSeen');
      expect(loaded.abArmV1, 'saved', reason: 'abArm_v1');
      await loaded.resetVersusData();
      final prefs = await SharedPreferences.getInstance();
      final reset = GameStorage();
      await reset.load();
      expect(prefs.containsKey(Obf.prefLvlIndex), false, reason: 'lvlIndex');
      expect(reset.lvlIndex, 0, reason: 'lvlIndex');
      expect(prefs.containsKey(Obf.prefLvlPoints), false, reason: 'lvlPoints');
      expect(reset.lvlPoints, 0, reason: 'lvlPoints');
      expect(
        prefs.containsKey(Obf.prefLvlPending),
        false,
        reason: 'lvlPending',
      );
      expect(reset.lvlPending, const [], reason: 'lvlPending');
      expect(prefs.containsKey(Obf.prefLvlPayout), false, reason: 'lvlPayout');
      expect(reset.lvlPayout, 0, reason: 'lvlPayout');
      expect(
        prefs.containsKey(Obf.prefBestRunHoops),
        false,
        reason: 'bestRunHoops',
      );
      expect(reset.bestRunHoops, 0, reason: 'bestRunHoops');
      expect(
        prefs.containsKey(Obf.prefRecentScores),
        false,
        reason: 'recentScores',
      );
      expect(reset.recentScores, const [], reason: 'recentScores');
      expect(prefs.containsKey(Obf.prefDuelStep), false, reason: 'duelStep');
      expect(reset.duelStep, -2, reason: 'duelStep');
      expect(
        prefs.containsKey(Obf.prefLifetimeCoinsEarned),
        false,
        reason: 'lifetimeCoinsEarned',
      );
      expect(reset.lifetimeCoinsEarned, 0, reason: 'lifetimeCoinsEarned');
      expect(
        prefs.containsKey(Obf.prefLifetimeCoinsSpent),
        false,
        reason: 'lifetimeCoinsSpent',
      );
      expect(reset.lifetimeCoinsSpent, 0, reason: 'lifetimeCoinsSpent');
      expect(
        prefs.containsKey(Obf.prefLifetimeCoinsBought),
        false,
        reason: 'lifetimeCoinsBought',
      );
      expect(reset.lifetimeCoinsBought, 0, reason: 'lifetimeCoinsBought');
      expect(
        prefs.containsKey(Obf.prefVsWinStreak),
        false,
        reason: 'vsWinStreak',
      );
      expect(reset.vsWinStreak, 0, reason: 'vsWinStreak');
      expect(
        prefs.containsKey(Obf.prefVsWinStreakBest),
        false,
        reason: 'vsWinStreakBest',
      );
      expect(reset.vsWinStreakBest, 0, reason: 'vsWinStreakBest');
      expect(
        prefs.containsKey(Obf.prefVsBigWinsDay),
        false,
        reason: 'vsBigWinsDay',
      );
      expect(reset.vsBigWinsDay, const {}, reason: 'vsBigWinsDay');
      expect(
        prefs.containsKey(Obf.prefMissionDay),
        false,
        reason: 'missionDay',
      );
      expect(reset.missionDay, -1, reason: 'missionDay');
      expect(prefs.containsKey(Obf.prefMissions), false, reason: 'missions');
      expect(reset.missions, const [], reason: 'missions');
      expect(
        prefs.containsKey(Obf.prefMissionTier),
        false,
        reason: 'missionTier',
      );
      expect(reset.missionTier, 0, reason: 'missionTier');
      expect(
        prefs.containsKey(Obf.prefMissionRerollDay),
        false,
        reason: 'missionRerollDay',
      );
      expect(reset.missionRerollDay, -1, reason: 'missionRerollDay');
      expect(prefs.containsKey(Obf.prefStreakDays), true, reason: 'streakDays');
      expect(reset.streakDays, 17, reason: 'streakDays');
      expect(
        prefs.containsKey(Obf.prefStreakLastDay),
        true,
        reason: 'streakLastDay',
      );
      expect(reset.streakLastDay, 17, reason: 'streakLastDay');
      expect(
        prefs.containsKey(Obf.prefStreakPaidDay),
        true,
        reason: 'streakPaidDay',
      );
      expect(reset.streakPaidDay, 17, reason: 'streakPaidDay');
      expect(
        prefs.containsKey(Obf.prefStreakLostDays),
        true,
        reason: 'streakLostDays',
      );
      expect(reset.streakLostDays, 17, reason: 'streakLostDays');
      expect(
        prefs.containsKey(Obf.prefStreakLostSeenDay),
        true,
        reason: 'streakLostSeenDay',
      );
      expect(reset.streakLostSeenDay, 17, reason: 'streakLostSeenDay');
      expect(
        prefs.containsKey(Obf.prefWorldsReached),
        false,
        reason: 'worldsReached',
      );
      expect(reset.worldsReached, 0, reason: 'worldsReached');
      expect(
        prefs.containsKey(Obf.prefWorldsSeen),
        false,
        reason: 'worldsSeen',
      );
      expect(reset.worldsSeen, 0, reason: 'worldsSeen');
      expect(
        prefs.containsKey(Obf.prefWeeklyBest),
        false,
        reason: 'weeklyBest',
      );
      expect(reset.weeklyBest, const {}, reason: 'weeklyBest');
      expect(
        prefs.containsKey(Obf.prefWeeklyRewards),
        false,
        reason: 'weeklyRewards',
      );
      expect(reset.weeklyRewards, const <int>{}, reason: 'weeklyRewards');
      expect(
        prefs.containsKey(Obf.prefWeeklyHintDay),
        false,
        reason: 'weeklyHintDay',
      );
      expect(reset.weeklyHintDay, -1, reason: 'weeklyHintDay');
      expect(
        prefs.containsKey(Obf.prefFirstWinDay),
        false,
        reason: 'firstWinDay',
      );
      expect(reset.firstWinDay, -1, reason: 'firstWinDay');
      expect(
        prefs.containsKey(Obf.prefAlbumCounts),
        false,
        reason: 'albumCounts',
      );
      expect(reset.albumCounts, const [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ], reason: 'albumCounts');
      expect(
        prefs.containsKey(Obf.prefAlbumRewardClaimed),
        false,
        reason: 'albumRewardClaimed',
      );
      expect(reset.albumRewardClaimed, false, reason: 'albumRewardClaimed');
      expect(
        prefs.containsKey(Obf.prefAlbumRewardItem),
        false,
        reason: 'albumRewardItem',
      );
      expect(reset.albumRewardItem, '', reason: 'albumRewardItem');
      expect(
        prefs.containsKey(Obf.prefGuideSeenCount),
        false,
        reason: 'guideSeenCount',
      );
      expect(reset.guideSeenCount, 0, reason: 'guideSeenCount');
      expect(
        prefs.containsKey(Obf.prefStarRoadSeason),
        false,
        reason: 'starRoadSeason',
      );
      expect(reset.starRoadSeason, 0, reason: 'starRoadSeason');
      expect(
        prefs.containsKey(Obf.prefStarRoadXp),
        false,
        reason: 'starRoadXp',
      );
      expect(reset.starRoadXp, 0, reason: 'starRoadXp');
      expect(
        prefs.containsKey(Obf.prefStarRoadClaimed),
        false,
        reason: 'starRoadClaimed',
      );
      expect(reset.starRoadClaimed, const <int>{}, reason: 'starRoadClaimed');
      expect(
        prefs.containsKey(Obf.prefStarRoadPopupDay),
        false,
        reason: 'starRoadPopupDay',
      );
      expect(reset.starRoadPopupDay, -1, reason: 'starRoadPopupDay');
      expect(
        prefs.containsKey(Obf.prefHomeLevelsTag),
        false,
        reason: 'homeLevelsTag',
      );
      expect(reset.homeLevelsTag, false, reason: 'homeLevelsTag');
      expect(prefs.containsKey(Obf.prefLbQueue), false, reason: 'lbQueue');
      expect(reset.lbQueue, const [], reason: 'lbQueue');
      expect(prefs.containsKey(Obf.prefLbGroupId), false, reason: 'lbGroupId');
      expect(reset.lbGroupId, '', reason: 'lbGroupId');
      expect(
        prefs.containsKey(Obf.prefLbGroupEnd),
        false,
        reason: 'lbGroupEnd',
      );
      expect(reset.lbGroupEnd, 0, reason: 'lbGroupEnd');
      expect(
        prefs.containsKey(Obf.prefLbLastRank),
        false,
        reason: 'lbLastRank',
      );
      expect(reset.lbLastRank, 0, reason: 'lbLastRank');
      expect(
        prefs.containsKey(Obf.prefLbGiftsClaimed),
        false,
        reason: 'lbGiftsClaimed',
      );
      expect(reset.lbGiftsClaimed, const <String>{}, reason: 'lbGiftsClaimed');
      expect(
        prefs.containsKey(Obf.prefLbGiftPending),
        false,
        reason: 'lbGiftPending',
      );
      expect(reset.lbGiftPending, const {}, reason: 'lbGiftPending');
      expect(
        prefs.containsKey(Obf.prefLbInfoSeen),
        false,
        reason: 'lbInfoSeen',
      );
      expect(reset.lbInfoSeen, false, reason: 'lbInfoSeen');
      expect(prefs.containsKey(Obf.prefAbArmV1), true, reason: 'abArm_v1');
      expect(reset.abArmV1, 'saved', reason: 'abArm_v1');
    },
  );

  test('a genuine 2.5 sealed snapshot upgrades without a seal alarm', () async {
    final sealer = MemorySaveSealer();
    await sealer.ensureKey();
    final hashes = <String, String>{
      Obf.prefBestScore: sealFieldHash(80),
      Obf.prefCoins: sealFieldHash(1234),
      Obf.prefGrantedPurchases: sealFieldHash(<String>[]),
      Obf.prefNoAds: sealFieldHash(false),
      Obf.prefOwnedItems: sealFieldHash(['hat:test']),
      Obf.prefPlayerLevel: sealFieldHash(3),
      Obf.prefUploadQueue: sealFieldHash(<String>[]),
    };
    final old = SealSnapshot(hashes, untrusted: false);
    final mac = (await sealer.mac([old.payload()]))!.macs.single;
    SharedPreferences.setMockInitialValues({
      Obf.prefBestScore: 80,
      Obf.prefCoins: 1234,
      Obf.prefOwnedItems: ['hat:test'],
      Obf.prefPlayerLevel: 3,
      Obf.prefSaveSeal: SealRecord(old.withMac(mac), null).encode(),
    });
    final upgraded = GameStorage(sealer: sealer);
    await upgraded.load();
    await upgraded.sealVerified;
    expect(upgraded.sealUntrusted, isFalse);
    expect(upgraded.coins, 1234);
    expect(upgraded.ownedItems, {'hat:test'});
    expect(upgraded.lvlIndex, 0);
    final prefs = await SharedPreferences.getInstance();
    final record = SealRecord.decode(prefs.getString(Obf.prefSaveSeal)!)!;
    expect(
      record.cur.hashes.keys,
      containsAll([
        Obf.prefLvlIndex,
        Obf.prefLvlPending,
        Obf.prefLbGiftsClaimed,
      ]),
    );
    await upgraded.saveLvlIndex(2);
    await upgraded.saveLvlPending([
      {'lvl': 2, 'coins': 50},
    ]);
    await upgraded.saveLbGiftsClaimed({'gift:1'});
    final reloaded = GameStorage(sealer: sealer);
    await reloaded.load();
    await reloaded.sealVerified;
    expect(reloaded.sealUntrusted, isFalse);
    expect(reloaded.lvlIndex, 2);
    expect(reloaded.lvlPending, [
      {'lvl': 2, 'coins': 50},
    ]);
    expect(reloaded.lbGiftsClaimed, {'gift:1'});
    await reloaded.resetVersusData();
    final reset = GameStorage(sealer: sealer);
    await reset.load();
    await reset.sealVerified;
    expect(reset.sealUntrusted, isFalse);
  });

  for (final key in [
    Obf.prefLvlIndex,
    Obf.prefLvlPending,
    Obf.prefLbGiftsClaimed,
  ]) {
    test('new sealed field $key detects edits after two snapshots', () async {
      final sealer = MemorySaveSealer();
      final storage = GameStorage(sealer: sealer);
      await storage.load();
      await storage.sealVerified;
      await storage.saveLvlIndex(2);
      await storage.saveLvlPending([
        {'lvl': 2},
      ]);
      await storage.saveLbGiftsClaimed({'gift:1'});
      await storage.saveCoins(10);
      await storage.saveCoins(11);
      final prefs = await SharedPreferences.getInstance();
      if (key == Obf.prefLvlIndex) {
        await prefs.setInt(key, 99);
      } else {
        if (key == Obf.prefLvlPending) {
          await prefs.setString(
            key,
            jsonEncode([
              {'lvl': 99},
            ]),
          );
        } else {
          await prefs.setStringList(key, ['forged']);
        }
      }
      final edited = GameStorage(sealer: sealer);
      await edited.load();
      await edited.sealVerified;
      expect(edited.sealUntrusted, isTrue);
    });
  }

  test('new reward sources and placements have stable analytics names', () {
    expect(
      [
        CoinSource.mission,
        CoinSource.missionChest,
        CoinSource.streak,
        CoinSource.streakRestore,
        CoinSource.firstWinDay,
        CoinSource.leaderboardGift,
        CoinSource.starRoad,
        CoinSource.album,
      ].map((s) => s.analyticsName),
      [
        'mission',
        'mission_chest',
        'streak',
        'streak_restore',
        'first_win_day',
        'leaderboard_gift',
        'star_road',
        'album',
      ],
    );
    expect(AdPlacement.missionReroll.analyticsName, 'mission_reroll');
    expect(AdPlacement.streakRestore.analyticsName, 'streak_restore');
  });
}
