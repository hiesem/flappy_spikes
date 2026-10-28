// PRD-2.5 §3.5 WP-STRINGS: writes lib/services/obf_strings.g.dart.
//
// Every Dart string literal survives `--obfuscate` as plain text in
// libapp.so, so the anchor strings of the economy (prefs keys, product ids,
// callables, collections, the Remote Config key, the device channel methods,
// the Play cert) are kept here and emitted as XOR-masked `const List<int>`s
// that the app decodes once (lazy static init). This only defeats `strings`
// and AI triage of the binary; the decoder ships with the app.
//
// The output is deterministic (fixed seed + entry index): regenerate after
// any change to [kObfStrings] and commit both files. test/obf_strings_test.dart
// checks that the committed file equals a fresh generation.
//
// Regenerate: dart run tool/gen_obf_strings.dart
//
// RULE: once a value is here, no Dart file under lib/ may contain it as a
// literal any more (Dart canonicalizes identical literals; log tags count).
// tool/check_anchor_strings.sh checks the release binary.
import 'dart:io';

/// The fixed seed of the mask (changing it rewrites every entry).
const int kObfSeed = 0x5A17C3E9;

/// `{Obf field name: value}`. Order matters (the index is part of the mask);
/// append new entries at the end.
const Map<String, String> kObfStrings = {
  // shared_preferences keys (lib/game/storage.dart). The NAMES never change
  // (PRD-2.5 §2: no migration); only their literals leave the binary.
  'prefBestScore': 'bestScore',
  'prefGamesPlayed': 'gamesPlayed',
  'prefMuteSound': 'muteSound',
  'prefMusicVolume': 'musicVolume',
  'prefCoins': 'coins',
  'prefOwnedSkins': 'ownedSkins',
  'prefEquippedSkin': 'equippedSkin',
  'prefSeenSkins': 'seenSkins',
  'prefOwnedItems': 'ownedItems',
  'prefSeenItems': 'seenItems',
  'prefNoAds': 'noAds',
  'prefArmedPowerup': 'armedPowerup',
  'prefArmedPowerupDebug': 'armedPowerupDebug',
  'prefSlotHistory': 'slotHistory',
  'prefInstallDay': 'installDay',
  'prefNoAdsPopupLastDay': 'noAdsPopupLastDay',
  'prefNoAdsPopupDismissals': 'noAdsPopupDismissals',
  'prefNoAdsPopupLastMs': 'noAdsPopupLastMs',
  'prefNoAdsPopupClosedMs': 'noAdsPopupClosedMs',
  'prefNoAdsPopupShowsToday': 'noAdsPopupShowsToday',
  'prefNoAdsPopupVideos': 'noAdsPopupVideos',
  'prefLastRunMood': 'lastRunMood',
  'prefFirstSessionDone': 'firstSessionDone',
  'prefFreeCoinsDay': 'freeCoinsDay',
  'prefFreeCoinsCount': 'freeCoinsCount',
  'prefFreeCoinsLastMs': 'freeCoinsLastMs',
  'prefDebugDayOffset': 'debugDayOffset',
  'prefClaimedLevels': 'claimedLevels',
  'prefPlayerLevel': 'playerLevel',
  'prefRumble': 'rumble',
  'prefLastScore': 'lastScore',
  'prefGrantedPurchases': 'grantedPurchases',
  'prefFeathers': 'feathers',
  'prefPuzzlePieces': 'puzzlePieces',
  'prefPuzzleRound': 'puzzleRound',
  'prefLastPortalRide': 'lastPortalRide',
  'prefUnclaimedLevelReward': 'unclaimedLevelReward',
  'prefLevelRewardPayout': 'levelRewardPayout',
  'prefPuzzlePayout': 'puzzlePayout',
  'prefMetElements': 'metElements',
  'prefVersusNickname': 'versusNickname',
  'prefVersusCustomName': 'versusCustomName',
  'prefVersusCustomNameSync': 'versusCustomNameSync',
  'prefVersusCustomNameError': 'versusCustomNameError',
  'prefVersusCustomNameRead': 'versusCustomNameRead',
  'prefUploadQueue': 'uploadQueue',
  'prefUploadsToday': 'uploadsToday',
  'prefUploadsDay': 'uploadsDay',
  'prefUploadsSent': 'uploadsSent',
  'prefUploadsSentDay': 'uploadsSentDay',
  'prefNotifOrder': 'notifOrder',
  'prefNotifPosition': 'notifPosition',
  'prefAchUnlocked': 'achUnlocked',
  'prefAchReported': 'achReported',
  'prefAchReportedPlayer': 'achReportedPlayer',
  'prefAchRides': 'achRides',
  'prefAchItems': 'achItems',
  'prefAchVersusWins': 'achVersusWins',
  'prefAchDayStreak': 'achDayStreak',
  'prefAchLastPlayDay': 'achLastPlayDay',
  'prefAchJournal': 'achJournal',
  'prefAchJournalExcluded': 'achJournalExcluded',
  'prefAchPending': 'achPending',
  'prefAchItemCounts': 'achItemCounts',
  'prefAchState': 'achState',
  'prefNotifLastSent': 'notifLastSent',
  'prefNotifPermissionAsked': 'notifPermissionAsked',
  'prefLastFeatherRun': 'lastFeatherRun',
  'prefLastPieceRun': 'lastPieceRun',
  'prefFirstRunHintSeen': 'firstRunHintSeen',
  'prefPlaytimeSeconds': 'playtimeSeconds',
  'prefFirstInterstitialShown': 'firstInterstitialShown',
  'prefLastRatingRequestAt': 'lastRatingRequestAt',
  'prefHomeMode': 'homeMode',
  'prefVersusAvatar': 'versusAvatar',
  'prefSaveSeal': 'saveSeal',
  'prefEquippedItemPrefix': 'equippedItem.',
  // PRD-2.5 §3.8 WP-IAP keys (lib/services/purchase_verifier.dart; `iapFake`
  // also lib/services/integrity_guard.dart).
  'prefIapVerifyQueue': 'iapVerifyQueue',
  'prefRevokedPurchases': 'revokedPurchases',
  'prefIapNoAdsTokens': 'iapNoAdsTokens',
  'prefIapFake': 'iapFake',
  // Store product ids (lib/services/iap_service.dart; `no_ads` is also the
  // `InterstitialSkip.noAds` analytics value in lib/game/playfield.dart).
  'productCoins1000': 'coins_1000',
  'productCoins10000': 'coins_10000',
  'productCoins17000': 'coins_17000',
  'productCoins100000': 'coins_100000',
  'productNoAds': 'no_ads',
  'productGiftCoins10000': 'gift_coins_10000',
  'productGiftNoAdsCoins10000': 'gift_noads_coins_10000',
  // Cloud Functions callables.
  'fnDeleteMyData': 'deleteMyData',
  'fnSetVersusName': 'setVersusName',
  'fnGetVersusName': 'getVersusName',
  'fnVerifyPurchase': 'verifyPurchase',
  // Firestore collections (lib/services/firebase_versus_backend.dart).
  'colPlayers': 'players',
  'colPools': 'pools',
  // Remote Config key (lib/run/config/versus_config.dart).
  'rcPgSalt': 'versus_pg_salt',
  // `flappy_spikes/device` channel methods (Dart side; the native names are
  // in the dex / Mach-O anyway).
  'chIntegrity': 'integrity',
  'chSealKey': 'sealKey',
  'chSeal': 'seal',
  'chSealDrop': 'sealDrop',
  // WP-GUARD (lib/services/integrity_guard.dart).
  'playCertSha256':
      '324311eff3c0134cf41d7b82162d836f3c5e2824e65b410e6392e287667e328f',
  'appleTeamId': 'TF9VESMTKV',
  // PRD-2.6 §Appendix WP-B / FTUE storage keys.
  'prefFtueSteps': 'ftueSteps',
  'prefShowcaseSeen': 'showcaseSeen',
  'prefShowcaseAttempt': 'showcaseAttempt',
  'prefShowcaseRuns': 'showcaseRuns',
  'prefShowcaseDoneAt': 'showcaseDoneAt',
  // M1 fix-up / PRD-2.6 WP-A: real install time, lifetime best hoops and
  // the durable first_meet queue.
  'prefInstallAtMs': 'installAtMs',
  'prefBestHoops': 'bestHoops',
  'prefPendingFirstMeets': 'pendingFirstMeets',
  // region P26-S0
  // PRD-2.6 Appendix: append only; prior mask indexes stay stable.
  'prefLvlIndex': 'lvlIndex',
  'prefLvlPoints': 'lvlPoints',
  'prefLvlPending': 'lvlPending',
  'prefLvlPayout': 'lvlPayout',
  'prefBestRunHoops': 'bestRunHoops',
  'prefRecentScores': 'recentScores',
  'prefDuelStep': 'duelStep',
  'prefLifetimeCoinsEarned': 'lifetimeCoinsEarned',
  'prefLifetimeCoinsSpent': 'lifetimeCoinsSpent',
  'prefLifetimeCoinsBought': 'lifetimeCoinsBought',
  'prefVsWinStreak': 'vsWinStreak',
  'prefVsWinStreakBest': 'vsWinStreakBest',
  'prefVsBigWinsDay': 'vsBigWinsDay',
  'prefMissionDay': 'missionDay',
  'prefMissions': 'missions',
  'prefMissionTier': 'missionTier',
  'prefMissionRerollDay': 'missionRerollDay',
  'prefStreakDays': 'streakDays',
  'prefStreakLastDay': 'streakLastDay',
  'prefStreakPaidDay': 'streakPaidDay',
  'prefStreakLostDays': 'streakLostDays',
  'prefStreakLostSeenDay': 'streakLostSeenDay',
  'prefWorldsReached': 'worldsReached',
  'prefWorldsSeen': 'worldsSeen',
  'prefWeeklyBest': 'weeklyBest',
  'prefWeeklyRewards': 'weeklyRewards',
  'prefWeeklyHintDay': 'weeklyHintDay',
  'prefFirstWinDay': 'firstWinDay',
  'prefAlbumCounts': 'albumCounts',
  'prefAlbumRewardClaimed': 'albumRewardClaimed',
  'prefAlbumRewardItem': 'albumRewardItem',
  'prefGuideSeenCount': 'guideSeenCount',
  'prefStarRoadSeason': 'starRoadSeason',
  'prefStarRoadXp': 'starRoadXp',
  'prefStarRoadClaimed': 'starRoadClaimed',
  'prefStarRoadPopupDay': 'starRoadPopupDay',
  'prefHomeLevelsTag': 'homeLevelsTag',
  'prefLbQueue': 'lbQueue',
  'prefLbGroupId': 'lbGroupId',
  'prefLbGroupEnd': 'lbGroupEnd',
  'prefLbLastRank': 'lbLastRank',
  'prefLbGiftsClaimed': 'lbGiftsClaimed',
  'prefLbGiftPending': 'lbGiftPending',
  'prefLbInfoSeen': 'lbInfoSeen',
  // endregion
  // region P26-H
  'prefAbArmV1': 'abArm_v1',
  // endregion
  // region P26-F1
  'prefFirstItemBought': 'firstItemBought',
  'prefEconomyDailyDay': 'economyDailyDay',
  // endregion
  // region P26-J6
  'prefLvlRewardLog': 'lvlRewardLog',
  // endregion
  // region P26-G1b
  'prefLastVersusHadRival': 'lastVersusHadRival',
  'prefMissionJournal': 'missionJournal',
  // endregion
  // region P26-G6c
  'prefAlbumCompletionJournal': 'albumCompletionJournal',
  // endregion
};

/// The output path, relative to the package root.
const String kObfOutput = 'lib/services/obf_strings.g.dart';

/// The mask stream of entry [index]: xorshift32 seeded from [kObfSeed] and
/// the index. Must match `_d` in the generated file.
List<int> obfMask(int index, int length) {
  var x = (kObfSeed ^ ((index + 1) * 0x9E3779B1)) & 0xFFFFFFFF;
  if (x == 0) x = 0x6D2B79F5;
  final out = <int>[];
  for (var i = 0; i < length; i++) {
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    out.add(x & 0xFF);
  }
  return out;
}

/// The generated Dart source for [table].
String generateObfSource([Map<String, String> table = kObfStrings]) {
  final b = StringBuffer()
    ..writeln(
      '// GENERATED by tool/gen_obf_strings.dart (PRD-2.5 §3.5 '
      'WP-STRINGS). Do not edit.',
    )
    ..writeln('// Regenerate: dart run tool/gen_obf_strings.dart')
    ..writeln('// dart format off')
    ..writeln()
    ..writeln(
      '/// Masked anchor strings: each value is decoded once, on first '
      'use.',
    )
    ..writeln('abstract final class Obf {');
  var index = 0;
  for (final e in table.entries) {
    final units = e.value.codeUnits;
    for (final u in units) {
      if (u > 0x7F) throw ArgumentError('ASCII only: ${e.key}');
    }
    final mask = obfMask(index, units.length);
    final data = [for (var i = 0; i < units.length; i++) units[i] ^ mask[i]];
    b.writeln(
      '  static final String ${e.key} = _d(const [${data.join(', ')}], '
      '$index);',
    );
    index++;
  }
  b
    ..writeln()
    ..writeln(
      '  /// test/obf_strings_test.dart: every value in table order (never '
      'read by the app).',
    )
    ..writeln('  static List<String> get debugValues => [');
  for (final k in table.keys) {
    b.writeln('    $k,');
  }
  b
    ..writeln('  ];')
    ..writeln()
    ..writeln('  static String _d(List<int> data, int index) {')
    ..writeln(
      '    var x = ($kObfSeed ^ ((index + 1) * 0x9E3779B1)) & '
      '0xFFFFFFFF;',
    )
    ..writeln('    if (x == 0) x = 0x6D2B79F5;')
    ..writeln('    final out = List<int>.filled(data.length, 0);')
    ..writeln('    for (var i = 0; i < data.length; i++) {')
    ..writeln('      x ^= (x << 13) & 0xFFFFFFFF;')
    ..writeln('      x ^= x >> 17;')
    ..writeln('      x ^= (x << 5) & 0xFFFFFFFF;')
    ..writeln('      out[i] = data[i] ^ (x & 0xFF);')
    ..writeln('    }')
    ..writeln('    return String.fromCharCodes(out);')
    ..writeln('  }')
    ..writeln('}');
  return b.toString();
}

void main() {
  File(kObfOutput).writeAsStringSync(generateObfSource());
  stdout.writeln('wrote $kObfOutput (${kObfStrings.length} strings)');
}
