import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../achievements/ach_state.dart';
import '../menu/home_mode.dart';
// region P26-H
import '../run/config/ab_arms.dart';
import '../run/config/tuning_values.dart';
// endregion
import '../services/integrity_guard.dart';
import '../services/obf_strings.g.dart';
// region P26-F9a
import '../skins/catalog.dart';
// endregion
import '../skins/look.dart';
import 'config.dart';
import 'save_seal.dart';

/// Persistence layer for bestScore / gamesPlayed / muteSound / musicVolume /
/// rumble / homeMode and the 2.0 menu state (coins, skins, powerup slot, no-ads popup,
/// free coins, claimed level rewards).
class GameStorage {
  GameStorage({DateTime Function()? clock, SaveSealer? sealer})
    : _clock = clock ?? DateTime.now,
      _sealer = sealer ?? defaultSealer;

  /// PRD-2.5 §3.4 WP-SAVE: the sealer every new storage uses unless one is
  /// passed. main.dart sets the platform sealer on the mobile products;
  /// null (tests, Linux, FS_E2E / soak) = no sealing at all.
  static SaveSealer? defaultSealer;

  /// The preferences handle [load] resolved. The legacy API keeps every
  /// value in a memory cache that its setters update synchronously, so a
  /// settler that must win against a concurrent [load] (the level-reward
  /// claim, §3.14) goes through this handle instead of awaiting a fresh
  /// `getInstance()`.
  SharedPreferences? _prefs;
  // region P26-G6c
  Future<void>? _albumJournalGate;
  // endregion

  static final String _bestScoreKey = Obf.prefBestScore;
  static final String _gamesPlayedKey = Obf.prefGamesPlayed;
  static final String _muteSoundKey = Obf.prefMuteSound;
  static final String _musicVolumeKey = Obf.prefMusicVolume;
  static final String _coinsKey = Obf.prefCoins;
  static final String _ownedSkinsKey = Obf.prefOwnedSkins;
  static final String _equippedSkinKey = Obf.prefEquippedSkin;
  static final String _seenSkinsKey = Obf.prefSeenSkins;
  static final String _ownedItemsKey = Obf.prefOwnedItems;
  static final String _seenItemsKey = Obf.prefSeenItems;
  static final String _noAdsKey = Obf.prefNoAds;
  static final String _armedPowerupKey = Obf.prefArmedPowerup;
  // PRD-2.3.1 §12.2 (QA P2-02) the armed powerup's debug origin.
  static final String _armedPowerupDebugKey = Obf.prefArmedPowerupDebug;
  static final String _slotHistoryKey = Obf.prefSlotHistory;
  static final String _installDayKey = Obf.prefInstallDay;
  static final String _noAdsPopupLastDayKey = Obf.prefNoAdsPopupLastDay;
  static final String _noAdsPopupDismissalsKey = Obf.prefNoAdsPopupDismissals;
  static final String _noAdsPopupLastMsKey = Obf.prefNoAdsPopupLastMs;
  static final String _noAdsPopupClosedMsKey = Obf.prefNoAdsPopupClosedMs;
  static final String _noAdsPopupShowsTodayKey = Obf.prefNoAdsPopupShowsToday;
  static final String _noAdsPopupVideosKey = Obf.prefNoAdsPopupVideos;
  static final String _lastRunMoodKey = Obf.prefLastRunMood;
  static final String _firstSessionDoneKey = Obf.prefFirstSessionDone;
  static final String _freeCoinsDayKey = Obf.prefFreeCoinsDay;
  static final String _freeCoinsCountKey = Obf.prefFreeCoinsCount;
  static final String _freeCoinsLastMsKey = Obf.prefFreeCoinsLastMs;
  static final String _debugDayOffsetKey = Obf.prefDebugDayOffset;
  static final String _claimedLevelsKey = Obf.prefClaimedLevels;
  static final String _playerLevelKey = Obf.prefPlayerLevel;
  static final String _rumbleKey = Obf.prefRumble;
  static final String _lastScoreKey = Obf.prefLastScore;
  static final String _grantedPurchasesKey = Obf.prefGrantedPurchases;
  static final String _ftueStepsKey = Obf.prefFtueSteps;
  static final String _showcaseSeenKey = Obf.prefShowcaseSeen;
  static final String _showcaseAttemptKey = Obf.prefShowcaseAttempt;
  static final String _showcaseRunsKey = Obf.prefShowcaseRuns;
  static final String _showcaseDoneAtKey = Obf.prefShowcaseDoneAt;
  // PRD-2.6 WP-A: the real install time (ms since epoch), the lifetime best
  // hoop count and the first_meet records not sent yet.
  static final String _installAtMsKey = Obf.prefInstallAtMs;
  static final String _bestHoopsKey = Obf.prefBestHoops;
  static final String _pendingFirstMeetsKey = Obf.prefPendingFirstMeets;

  // region P26-S0
  // PRD-2.6 J5, G, LB and §8.3-12. Dates are local day indexes unless
  // the owning feature uses a UTC week/season identifier. Empty = unassigned.
  int lvlIndex = 0;
  int lvlPoints = 0;
  List<Map<String, Object?>> lvlPending = const [];
  int lvlPayout = 0;
  // region P26-J6
  List<Map<String, Object?>> lvlRewardLog = const [];
  // endregion
  int bestRunHoops = 0;
  List<int> recentScores = const [];
  int duelStep = -2;
  int lifetimeCoinsEarned = 0;
  int lifetimeCoinsSpent = 0;
  int lifetimeCoinsBought = 0;
  // region P26-F1
  bool firstItemBought = false;
  int economyDailyDay = -1;
  // endregion
  int vsWinStreak = 0;
  int vsWinStreakBest = 0;
  Map<String, int> vsBigWinsDay = const {};
  // region P26-G1b
  bool lastVersusHadRival = false;
  Map<String, Object?> missionJournal = const {};
  // endregion
  int missionDay = -1;
  List<Map<String, Object?>> missions = const [];
  int missionTier = 0;
  int missionRerollDay = -1;
  int streakDays = 0;
  int streakLastDay = -1;
  int streakPaidDay = -1;
  int streakLostDays = 0;
  int streakLostSeenDay = -1;
  int worldsReached = 0;
  int worldsSeen = 0;
  Map<String, int> weeklyBest = const {};
  Set<int> weeklyRewards = const {};
  int weeklyHintDay = -1;
  int firstWinDay = -1;
  List<int> albumCounts = const [0, 0, 0, 0, 0, 0, 0, 0];
  bool albumRewardClaimed = false;
  String albumRewardItem = '';
  int guideSeenCount = 0;
  // region P26-G6eB
  int starRoadRunDay = -1;
  // endregion
  int starRoadSeason = 0;
  int starRoadXp = 0;
  Set<int> starRoadClaimed = const {};
  int starRoadPopupDay = -1;
  bool homeLevelsTag = false;
  List<String> lbQueue = const [];
  String lbGroupId = '';
  int lbGroupEnd = 0;
  int lbLastRank = 0;
  Set<String> lbGiftsClaimed = const {};
  Map<String, Object?> lbGiftPending = const {};
  bool lbInfoSeen = false;
  String abArmV1 = '';
  // endregion

  // region PRD-2 keys (WP-0b; PRD-2 §7 persistence table, ARCH §5)
  static final String _feathersKey = Obf.prefFeathers;
  static final String _puzzlePiecesKey = Obf.prefPuzzlePieces;
  static final String _puzzleRoundKey = Obf.prefPuzzleRound;
  static final String _lastPortalRideKey = Obf.prefLastPortalRide;
  static final String _unclaimedLevelRewardKey = Obf.prefUnclaimedLevelReward;
  static final String _levelRewardPayoutKey = Obf.prefLevelRewardPayout;
  static final String _puzzlePayoutKey = Obf.prefPuzzlePayout;
  static final String _metElementsKey = Obf.prefMetElements;
  static final String _versusNicknameKey = Obf.prefVersusNickname;
  static final String _versusCustomNameKey = Obf.prefVersusCustomName;
  static final String _versusCustomNameSyncKey = Obf.prefVersusCustomNameSync;
  static final String _versusCustomNameErrorKey = Obf.prefVersusCustomNameError;
  static final String _versusCustomNameReadKey = Obf.prefVersusCustomNameRead;
  static final String _uploadQueueKey = Obf.prefUploadQueue;
  static final String _uploadsTodayKey = Obf.prefUploadsToday;
  static final String _uploadsDayKey = Obf.prefUploadsDay;
  static final String _uploadsSentKey = Obf.prefUploadsSent;
  static final String _uploadsSentDayKey = Obf.prefUploadsSentDay;
  static final String _notifOrderKey = Obf.prefNotifOrder;
  static final String _notifPositionKey = Obf.prefNotifPosition;
  // region P231-E — achievements (PRD-2.3.1 §12.3)
  static final String _achUnlockedKey = Obf.prefAchUnlocked;
  static final String _achReportedKey = Obf.prefAchReported;
  static final String _achReportedPlayerKey = Obf.prefAchReportedPlayer;
  static final String _achRidesKey = Obf.prefAchRides;
  static final String _achItemsKey = Obf.prefAchItems;
  static final String _achVersusWinsKey = Obf.prefAchVersusWins;
  static final String _achDayStreakKey = Obf.prefAchDayStreak;
  static final String _achLastPlayDayKey = Obf.prefAchLastPlayDay;
  // QA P2-03 the open run's provisional achievement journal.
  static final String _achJournalKey = Obf.prefAchJournal;
  static final String _achJournalExcludedKey = Obf.prefAchJournalExcluded;
  // PRD-2.3.1 §19 the pacing queue and the lifetime item catch counts.
  static final String _achPendingKey = Obf.prefAchPending;
  static final String _achItemCountsKey = Obf.prefAchItemCounts;
  // QA P19-01..03 everything above lives in ONE JSON key since 2.3.1 (21);
  // the separate keys are only read once, to migrate a 2.3.1 (20) install.
  static final String _achStateKey = Obf.prefAchState;
  // endregion P231-E
  static final String _notifLastSentKey = Obf.prefNotifLastSent;
  static final String _notifPermissionAskedKey = Obf.prefNotifPermissionAsked;
  // endregion PRD-2 keys
  // PRD-2.3 §14.2 the gamesPlayed of the run that last showed a golden
  // feather / puzzle piece (−1 = never; never in two runs in a row).
  static final String _lastFeatherRunKey = Obf.prefLastFeatherRun;
  static final String _lastPieceRunKey = Obf.prefLastPieceRun;
  // PRD-2.3 §10.3 the first-run instructions were shown (saved at that
  // run's first tap). Local progress: "Delete my data" keeps it.
  static final String _firstRunHintSeenKey = Obf.prefFirstRunHintSeen;
  // PRD-2.3 §18.3 foreground seconds since install (kept by "Delete my data").
  static final String _playtimeSecondsKey = Obf.prefPlaytimeSeconds;
  // PRD-2.3 §18.4 the one-time `first_interstitial` event has been sent.
  static final String _firstInterstitialShownKey =
      Obf.prefFirstInterstitialShown;
  // PRD-2.3 §23.2 the last rating-sheet request, in seconds since the epoch
  // (0 = never; kept by "Delete my data").
  static final String _lastRatingRequestAtKey = Obf.prefLastRatingRequestAt;
  // PRD-2.2 §2.2 the Home mode button: 'versus' (default) / 'freeFly'.
  static final String _homeModeKey = Obf.prefHomeMode;
  // PRD-2.3 §21.3 the last uploaded versus picture (WP-AV: no pictures any
  // more; the stale record is removed at load and by "Delete my data").
  static final String _versusAvatarKey = Obf.prefVersusAvatar;
  // PRD-2.5 §3.4 WP-SAVE the sealed snapshots ({cur, prev}).
  static final String _sealKey = Obf.prefSaveSeal;

  /// One preference key per equipped layer (the five-key equipped map).
  static String _equippedItemKey(SkinLayer layer) =>
      '${Obf.prefEquippedItemPrefix}${layer.key}';

  /// [slotHistory] keeps at most this many entries (most recent last).
  static const int _maxSlotHistory = 3;

  /// [grantedPurchases] keeps at most this many purchase ids (most recent
  /// last): the last 200 purchases, each with its purchaseID and its Play
  /// purchase token.
  static const int maxGrantedPurchases = 400;

  final DateTime Function() _clock;

  int bestScore = 0;
  int gamesPlayed = 0;
  bool muteSound = false;
  double musicVolume = Config.defaultMusicVolume;

  /// PRD-2.2 §2.2 the Home mode ([HomeMode.versus] on the first start and
  /// after "Delete my data").
  HomeMode homeMode = HomeMode.versus;

  int coins = 0;

  /// PRD-menu-v2 wardrobe state: owned `"layer:id"` keys, the equipped id per
  /// layer (five keys) and the NEW-badge seen set.
  Set<String> ownedItems = {};
  Map<SkinLayer, String> equippedItems = {
    for (final layer in SkinLayer.values) layer: Look.defaults.idFor(layer),
  };
  Set<String> seenItems = {};

  bool noAds = false;
  String armedPowerup = 'none';

  /// PRD-2.3.1 §12.2 (QA P2-02): [armedPowerup] came from a debug "Slot:
  /// force …" roll; written together with it.
  bool armedPowerupDebug = false;
  List<String> slotHistory = [];
  int? installDay;

  /// Wall-clock milliseconds at the first ever launch of this install (the
  /// FTUE's real `s_since_install`). Before this key existed it is migrated
  /// from the day-only [installDay] (its local midnight). A brand-new install
  /// stores the current clock, not midnight.
  int installAtMs = 0;

  /// PRD-2.6 WP-G1/G5: the most hoops passed in any non-debug run.
  int bestHoops = 0;

  /// PRD-2.6 WP-A: `first_meet` records persisted at announcement and not
  /// sent yet. A process that dies before `RunEnded` still sends them at the
  /// next launch (as not survived). Encoded as a small JSON list.
  List<Map<String, Object?>> pendingFirstMeets = [];

  /// PRD-menu-v4 §8: the local day of the latest show (with
  /// [noAdsPopupShowsToday], the per-day cap).
  int noAdsPopupLastDay = -1;

  /// Analytics only since PRD-menu-v4 §8 (no dismissal limit any more).
  int noAdsPopupDismissals = 0;

  /// Wall-clock ms of the latest show (0 = never; the 4 h gap / 24 h
  /// fallback).
  int noAdsPopupLastMs = 0;

  /// Wall-clock ms of the latest close (✕ / dim / back / Esc; 0 = never).
  /// PRD-menu-v4 §8.5: closing starts the 4 h gap, so the gap runs from
  /// the later of this and [noAdsPopupLastMs].
  int noAdsPopupClosedMs = 0;

  /// Shows on [noAdsPopupLastDay].
  int noAdsPopupShowsToday = 0;

  /// Rewarded videos completed since the popup was last shown.
  int noAdsPopupVideos = 0;

  /// The latest finished run's good moment: 'level', 'best' or '' (none);
  /// cleared when the popup shows.
  String lastRunMood = '';

  /// Whether the first session has started already (any later session is
  /// not the first one). Installs from before the flag count as done.
  bool firstSessionDone = false;
  int freeCoinsDay = -1;
  int freeCoinsCount = 0;
  int freeCoinsLastMs = 0;
  int debugDayOffset = 0;

  /// PRD-home-v3 §11: levels whose one-time reward was paid.
  Set<int> claimedLevels = {};

  /// Owner 2026-10-17 (WP-L): the stored player level (0 = unranked,
  /// 1..10). It is no longer derived from the best score: a run whose score
  /// reaches the next level's threshold raises it by exactly one.
  int playerLevel = 0;

  /// PRD-2 §3.33: the RUMBLE switch (on by default).
  bool rumble = true;

  /// PRD-home-v3 §3.1: the score of the most recent run (home LAST); null
  /// before the first run.
  int? lastScore;

  /// S1-71: store transaction ids (purchaseID / Play purchase token) of the
  /// coin packs already granted, so a store re-delivery of the same
  /// transaction never pays twice. Bounded to [maxGrantedPurchases].
  List<String> grantedPurchases = [];

  /// PRD-2.3 §14.2 the `gamesPlayed` of the run that last showed a golden
  /// feather (−1 = never): never a feather in two runs in a row.
  int lastFeatherRun = -1;

  /// PRD-2.3 §14.2 the same for the puzzle piece.
  int lastPieceRun = -1;

  /// PRD-2.3 §10.3 the first-run instructions are seen. PRD-2.3.1 §10: the
  /// full instructions write `false` when they show, and the first pass of
  /// hoop 0 saves `true`. A save without the key that has played before (a
  /// 1.x / 2.x upgrade) counts as seen: those players are not on their very
  /// first run.
  bool firstRunHintSeen = false;

  /// PRD-2.3 §18.3 foreground seconds since install (counted while the app
  /// is resumed, outside full-screen ads, until the new-player grace ends).
  /// Kept by "Delete my data".
  int playtimeSeconds = 0;

  /// PRD-2.3 §18.4: the first interstitial ever was shown (its one-time
  /// `first_interstitial` event went out).
  bool firstInterstitialShown = false;

  /// PRD-2.3 §23.2 wall-clock seconds of the last rating-sheet request
  /// (0 = never). Kept by "Delete my data".
  int lastRatingRequestAt = 0;

  /// PRD-2.6 §Appendix the reached FTUE milestones. Wave-1 only persists and
  /// resets the state; later waves define the bit meaning.
  int ftueSteps = 0;

  /// PRD-2.6 WP-B the showcase highlight bits and counters.
  int showcaseSeen = 0;
  int showcaseAttempt = 0;
  int showcaseRuns = 0;

  /// `gamesPlayed` when showcase finished (null = not finished).
  int? showcaseDoneAt;

  // region PRD-2 keys (WP-0b)
  /// §3.15 Golden feathers held (0–3).
  int feathers = 0;

  /// §3.16 Puzzle pieces of the open round (4-bit mask).
  int puzzlePieces = 0;

  /// §3.16 Puzzle round (0-based; colour = round % 8).
  int puzzleRound = 0;

  /// §3.12 The last portal ride id (never the same twice in a row, also
  /// across runs); null before the first portal.
  String? lastPortalRide;

  /// §3.14 / §5.10 Level reward coins not yet claimed (credited at the next
  /// app start if > 0).
  int unclaimedLevelReward = 0;

  /// §3.14 (call, S6-22) The wallet balance a level-reward credit is to
  /// reach: written before the credit and cleared right after, so a kill
  /// between the claim's writes and the credit is recovered at start and
  /// paid exactly once. 0 = no credit in flight.
  int levelRewardPayout = 0;

  /// §3.16 (call, S6-62) The wallet balance a completed picture's bonus is
  /// to reach: written with the mask reset + round advance and before the
  /// credit, cleared right after the credit lands, so a kill in between is
  /// paid at the next start exactly once (`PuzzleFeature.settlePayout`).
  /// 0 = no puzzle credit in flight.
  int puzzlePayout = 0;

  /// §3.0.8 Element storage ids the player has met (spawned on screen).
  Set<String> metElements = {};

  // region P231-E — achievements (PRD-2.3.1 §12.3)
  /// QA P19-01..03 the tracker's whole state (`AchState`), persisted as one
  /// JSON value by [saveAchState]. The getters below are read-only views.
  AchState ach = AchState();

  /// Unlocked achievement keys (the local truth).
  Set<String> get achUnlocked => ach.unlocked;

  /// Keys the platform confirmed for [achReportedPlayer].
  Set<String> get achReported => ach.reported;

  /// The platform player id [achReported] belongs to ('' = none yet).
  String get achReportedPlayer => ach.reportedPlayer;

  /// Portal ride ids finished (`RideId.storageId`).
  Set<String> get achRides => ach.rides;

  /// 2.3.1 (20) first-catch item keys (kept, no longer written).
  Set<String> get achItems => ach.items;

  /// QA P2-03: the staged rule ops of the open run, empty when none.
  List<String> get achJournal => ach.journal;

  /// The open run's journal is excluded (a debug assist): discard it.
  bool get achJournalExcluded => ach.journalExcluded;

  /// Versus wins since 2.3.1.
  int get achVersusWins => ach.versusWins;

  /// Current streak of consecutive local days with a counted run.
  int get achDayStreak => ach.dayStreak;

  /// [today] of the last counted run (-1 = none).
  int get achLastPlayDay => ach.lastPlayDay;

  /// PRD-2.3.1 §19.2 earned achievements waiting for a counting run's
  /// unlock slot, oldest first (FIFO). Earned for good, never reported.
  List<String> get achPending => ach.pending;

  /// PRD-2.3.1 §19.1 lifetime catches per item achievement key.
  Map<String, int> get achItemCounts => ach.itemCounts;
  // endregion P231-E

  /// §3.13 Versus nickname (generated once by WP-5b); null = not yet.
  String? versusNickname;

  /// WP-NAME the custom versus name chosen in Settings ('' = none: the
  /// player sees "You", opponents the nickname).
  String versusCustomName = '';

  /// WP-NAME what the server last confirmed, as `uid\nname` ('' = never):
  /// [versusCustomName] still has to be sent when it differs.
  String versusCustomNameSync = '';

  /// WP-NAME why the server refused a name saved offline (a
  /// `CustomNameReason` key; '' = none). The Settings card shows it once.
  String versusCustomNameError = '';

  /// WP-N2 when the server's name was last read back, as `uid\nYYYY-MM-DD`
  /// (UTC; '' = never): at most once a day per uid (also the activity
  /// ping that keeps a guest's name), at once for a new uid.
  String versusCustomNameRead = '';

  /// §3.13 Pending versus uploads (JSON run entries).
  List<String> uploadQueue = [];

  /// §3.13 Non-best uploads on [uploadsDay] (3 a day).
  int uploadsToday = 0;

  /// §3.13 'YYYY-MM-DD' of [uploadsToday]; '' = never.
  String uploadsDay = '';

  /// §3.13 (S6-60) Non-best runs *written* on [uploadsSentDay] (UTC): the
  /// server accepts 3 a day by the day it processes them, so a backlog is
  /// paced by the upload day, not the play day.
  int uploadsSent = 0;

  /// §3.13 (S6-60) 'YYYY-MM-DD' (UTC) of [uploadsSent]; '' = never.
  String uploadsSentDay = '';

  /// §3.34 Shuffled reminder message order (empty until the first schedule).
  List<int> notifOrder = [];

  /// §3.34 Position in [notifOrder].
  int notifPosition = 0;

  /// §3.34 Message number → last sent date ('YYYY-MM-DD').
  Map<int, String> notifLastSent = {};

  /// §3.34 Whether the notification permission was asked.
  bool notifPermissionAsked = false;

  /// §3.14 `levelRewardsClaimed` maps onto [claimedLevels] (call, ARCH §5):
  /// the highest claimed level, 0 when none.
  int get levelRewardsClaimed =>
      claimedLevels.isEmpty ? 0 : claimedLevels.reduce(math.max);
  // endregion PRD-2 keys

  /// Current wall-clock time (overridable for tests).
  DateTime now() => _clock();

  /// Local calendar day number (days since 1970-01-01), shifted by
  /// [debugDayOffset].
  int get today {
    final t = now();
    return DateTime.utc(
          t.year,
          t.month,
          t.day,
        ).difference(DateTime.utc(1970)).inDays +
        debugDayOffset;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    gamesPlayed = prefs.getInt(_gamesPlayedKey) ?? 0;
    muteSound = prefs.getBool(_muteSoundKey) ?? false;
    musicVolume = prefs.getDouble(_musicVolumeKey) ?? Config.defaultMusicVolume;

    // PRD-menu-v2 (product decision): the PRD-1 single-skin keys are reset on
    // sight — old skins are dropped, with no refund.
    if (prefs.containsKey(_ownedSkinsKey) ||
        prefs.containsKey(_equippedSkinKey) ||
        prefs.containsKey(_seenSkinsKey)) {
      await prefs.remove(_ownedSkinsKey);
      await prefs.remove(_equippedSkinKey);
      await prefs.remove(_seenSkinsKey);
    }
    equippedItems = {
      for (final layer in SkinLayer.values)
        layer:
            prefs.getString(_equippedItemKey(layer)) ??
            Look.defaults.idFor(layer),
    };
    seenItems = (prefs.getStringList(_seenItemsKey) ?? const []).toSet();
    armedPowerup = prefs.getString(_armedPowerupKey) ?? 'none';
    armedPowerupDebug = prefs.getBool(_armedPowerupDebugKey) ?? false;
    slotHistory = _capSlotHistory(
      prefs.getStringList(_slotHistoryKey) ?? const [],
    );
    debugDayOffset = prefs.getInt(_debugDayOffsetKey) ?? 0;
    final storedInstallDay = prefs.getInt(_installDayKey);
    if (storedInstallDay == null) {
      final day = today;
      installDay = day;
      await prefs.setInt(_installDayKey, day);
    } else {
      installDay = storedInstallDay;
    }
    final storedInstallAt = prefs.getInt(_installAtMsKey);
    if (storedInstallAt != null && storedInstallAt > 0) {
      installAtMs = storedInstallAt;
    } else {
      // Migration for installs from before the timestamp existed. The only
      // first-launch datum kept is `installDay`, a local calendar day: use
      // its local midnight (an approximation that can over-report elapsed
      // time by up to one day). A first launch writes the real
      // clock immediately.
      installAtMs = storedInstallDay == null
          ? now().millisecondsSinceEpoch
          : _localDayStartMs(installDay ?? today);
      await prefs.setInt(_installAtMsKey, installAtMs);
    }
    bestHoops = math.max(0, prefs.getInt(_bestHoopsKey) ?? 0);
    pendingFirstMeets = _decodeFirstMeets(
      prefs.getStringList(_pendingFirstMeetsKey) ?? const [],
    );
    noAdsPopupLastDay = prefs.getInt(_noAdsPopupLastDayKey) ?? -1;
    noAdsPopupDismissals = prefs.getInt(_noAdsPopupDismissalsKey) ?? 0;
    noAdsPopupLastMs = prefs.getInt(_noAdsPopupLastMsKey) ?? 0;
    noAdsPopupClosedMs = prefs.getInt(_noAdsPopupClosedMsKey) ?? 0;
    noAdsPopupShowsToday = prefs.getInt(_noAdsPopupShowsTodayKey) ?? 0;
    noAdsPopupVideos = prefs.getInt(_noAdsPopupVideosKey) ?? 0;
    lastRunMood = prefs.getString(_lastRunMoodKey) ?? '';
    firstSessionDone =
        prefs.getBool(_firstSessionDoneKey) ?? storedInstallDay != null;
    freeCoinsDay = prefs.getInt(_freeCoinsDayKey) ?? -1;
    freeCoinsCount = prefs.getInt(_freeCoinsCountKey) ?? 0;
    freeCoinsLastMs = prefs.getInt(_freeCoinsLastMsKey) ?? 0;
    // region P26-J2 — J5 legacy claims are deliberately ignored.
    claimedLevels = {};
    // endregion
    rumble = prefs.getBool(_rumbleKey) ?? true;
    lastScore = prefs.getInt(_lastScoreKey);
    lastFeatherRun = prefs.getInt(_lastFeatherRunKey) ?? -1;
    lastPieceRun = prefs.getInt(_lastPieceRunKey) ?? -1;
    firstRunHintSeen = prefs.getBool(_firstRunHintSeenKey) ?? (gamesPlayed > 0);
    playtimeSeconds = prefs.getInt(_playtimeSecondsKey) ?? 0;
    firstInterstitialShown = prefs.getBool(_firstInterstitialShownKey) ?? false;
    lastRatingRequestAt = prefs.getInt(_lastRatingRequestAtKey) ?? 0;
    ftueSteps = prefs.getInt(_ftueStepsKey) ?? 0;
    showcaseSeen = prefs.getInt(_showcaseSeenKey) ?? 0;
    showcaseAttempt = prefs.getInt(_showcaseAttemptKey) ?? 0;
    showcaseRuns = prefs.getInt(_showcaseRunsKey) ?? 0;
    showcaseDoneAt = prefs.getInt(_showcaseDoneAtKey);
    // region PRD-2 keys (WP-0b)
    feathers = (prefs.getInt(_feathersKey) ?? 0).clamp(0, 3);
    puzzlePieces = (prefs.getInt(_puzzlePiecesKey) ?? 0) & 0xF;
    puzzleRound = prefs.getInt(_puzzleRoundKey) ?? 0;
    lastPortalRide = prefs.getString(_lastPortalRideKey);
    // region P26-J2 — only the first 2.6 load may read the 2.5 payout.
    unclaimedLevelReward = 0;
    levelRewardPayout = !prefs.containsKey(Obf.prefLvlIndex) &&
            prefs.containsKey(_levelRewardPayoutKey)
        ? prefs.getInt(_levelRewardPayoutKey) ?? 0
        : 0;
    // endregion
    puzzlePayout = prefs.getInt(_puzzlePayoutKey) ?? 0;
    metElements = (prefs.getStringList(_metElementsKey) ?? const []).toSet();
    // region P231-E
    ach = AchState.decode(prefs.getString(_achStateKey)) ?? _migrateAch(prefs);
    // endregion P231-E
    versusNickname = prefs.getString(_versusNicknameKey);
    versusCustomName = prefs.getString(_versusCustomNameKey) ?? '';
    versusCustomNameSync = prefs.getString(_versusCustomNameSyncKey) ?? '';
    versusCustomNameError = prefs.getString(_versusCustomNameErrorKey) ?? '';
    versusCustomNameRead = prefs.getString(_versusCustomNameReadKey) ?? '';
    if (prefs.containsKey(_versusAvatarKey)) {
      unawaited(prefs.remove(_versusAvatarKey)); // WP-AV
    }
    uploadsToday = prefs.getInt(_uploadsTodayKey) ?? 0;
    uploadsDay = prefs.getString(_uploadsDayKey) ?? '';
    uploadsSent = prefs.getInt(_uploadsSentKey) ?? 0;
    uploadsSentDay = prefs.getString(_uploadsSentDayKey) ?? '';
    notifOrder = (prefs.getStringList(_notifOrderKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    notifPosition = prefs.getInt(_notifPositionKey) ?? 0;
    notifLastSent = _decodeIntMap(prefs.getString(_notifLastSentKey));
    notifPermissionAsked = prefs.getBool(_notifPermissionAskedKey) ?? false;
    // endregion PRD-2 keys
    // region P26-S0
    lvlPoints = prefs.getInt(Obf.prefLvlPoints) ?? 0;
    lvlPayout = prefs.getInt(Obf.prefLvlPayout) ?? 0;
    // region P26-J6
    lvlRewardLog = _p26Records(prefs.getString(Obf.prefLvlRewardLog));
    // endregion
    bestRunHoops = prefs.getInt(Obf.prefBestRunHoops) ?? 0;
    recentScores =
        prefs
            .getStringList(Obf.prefRecentScores)
            ?.map(int.tryParse)
            .whereType<int>()
            .toList() ??
        const [];
    duelStep = prefs.getInt(Obf.prefDuelStep) ?? -2;
    lifetimeCoinsEarned = prefs.getInt(Obf.prefLifetimeCoinsEarned) ?? 0;
    lifetimeCoinsSpent = prefs.getInt(Obf.prefLifetimeCoinsSpent) ?? 0;
    lifetimeCoinsBought = prefs.getInt(Obf.prefLifetimeCoinsBought) ?? 0;
    // region P26-F1
    firstItemBought = prefs.getBool(Obf.prefFirstItemBought) ?? false;
    economyDailyDay = prefs.getInt(Obf.prefEconomyDailyDay) ?? -1;
    // endregion
    vsWinStreak = prefs.getInt(Obf.prefVsWinStreak) ?? 0;
    vsWinStreakBest = prefs.getInt(Obf.prefVsWinStreakBest) ?? 0;
    vsBigWinsDay = _p26IntMap(prefs.getString(Obf.prefVsBigWinsDay));
    // region P26-G1b
    lastVersusHadRival = prefs.getBool(Obf.prefLastVersusHadRival) ?? false;
    final journalRows = _p26Records(prefs.getString(Obf.prefMissionJournal));
    missionJournal = journalRows.isEmpty ? const {} : journalRows.first;
    // endregion
    missionDay = prefs.getInt(Obf.prefMissionDay) ?? -1;
    missions = _p26Records(prefs.getString(Obf.prefMissions));
    missionTier = prefs.getInt(Obf.prefMissionTier) ?? 0;
    missionRerollDay = prefs.getInt(Obf.prefMissionRerollDay) ?? -1;
    streakDays = prefs.getInt(Obf.prefStreakDays) ?? 0;
    streakLastDay = prefs.getInt(Obf.prefStreakLastDay) ?? -1;
    streakPaidDay = prefs.getInt(Obf.prefStreakPaidDay) ?? -1;
    streakLostDays = prefs.getInt(Obf.prefStreakLostDays) ?? 0;
    streakLostSeenDay = prefs.getInt(Obf.prefStreakLostSeenDay) ?? -1;
    worldsReached = prefs.getInt(Obf.prefWorldsReached) ?? 0;
    worldsSeen = prefs.getInt(Obf.prefWorldsSeen) ?? 0;
    weeklyBest = _p26IntMap(prefs.getString(Obf.prefWeeklyBest));
    weeklyRewards = (prefs.getStringList(Obf.prefWeeklyRewards) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    weeklyHintDay = prefs.getInt(Obf.prefWeeklyHintDay) ?? -1;
    firstWinDay = prefs.getInt(Obf.prefFirstWinDay) ?? -1;
    albumCounts =
        prefs
            .getStringList(Obf.prefAlbumCounts)
            ?.map(int.tryParse)
            .whereType<int>()
            .toList() ??
        const [0, 0, 0, 0, 0, 0, 0, 0];
    // region P26-G6c
    await _recoverAlbumCompletion(prefs);
    // endregion
    albumRewardClaimed = prefs.getBool(Obf.prefAlbumRewardClaimed) ?? false;
    albumRewardItem = prefs.getString(Obf.prefAlbumRewardItem) ?? '';
    guideSeenCount = prefs.getInt(Obf.prefGuideSeenCount) ?? 0;
    // region P26-G6eB
    starRoadRunDay = prefs.getInt(Obf.prefStarRoadRunDay) ?? -1;
    // endregion
    starRoadSeason = prefs.getInt(Obf.prefStarRoadSeason) ?? 0;
    starRoadXp = prefs.getInt(Obf.prefStarRoadXp) ?? 0;
    starRoadClaimed = (prefs.getStringList(Obf.prefStarRoadClaimed) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    starRoadPopupDay = prefs.getInt(Obf.prefStarRoadPopupDay) ?? -1;
    homeLevelsTag = prefs.getBool(Obf.prefHomeLevelsTag) ?? false;
    lbQueue = prefs.getStringList(Obf.prefLbQueue) ?? const [];
    lbGroupId = prefs.getString(Obf.prefLbGroupId) ?? '';
    lbGroupEnd = prefs.getInt(Obf.prefLbGroupEnd) ?? 0;
    lbLastRank = prefs.getInt(Obf.prefLbLastRank) ?? 0;
    lbGiftPending = _p26JsonMap(prefs.getString(Obf.prefLbGiftPending));
    lbInfoSeen = prefs.getBool(Obf.prefLbInfoSeen) ?? false;
    // endregion
    // region P26-H
    abArmV1 = prefs.getString(Obf.prefAbArmV1) ?? '';
    if (abArmV1.isEmpty) {
      await saveAbArmV1(AbArms.draw());
    }
    TuningValues.current = TuningValues.current.withArm(abArmV1);
    // §8.3-12: resetVersusData deliberately keeps this device assignment.
    // endregion
    homeMode = HomeMode.parse(prefs.getString(_homeModeKey));
    // PRD-2.5 §3.4: the sealed fields last, in one synchronous block after
    // every sealed write in flight has reached the preferences (a covered
    // setter writes its value only after its seal).
    while (_sealIssuing > 0) {
      await _sealIdle.future;
    }
    _readSealedFields(prefs);
    if (_sealer != null && _sealBase == null && !_sealOff) {
      final base = _verifySeal(prefs, _sealHashes());
      _sealBase = base;
      IntegrityGuard.instance.track(base);
    }
    // region P26-G1b
    await recoverMissionJournal();
    // endregion
    // region P26-J2
    // J5: settle an interrupted 2.5 credit once; legacy ranks never migrate.
    // No Wallet exists during load. This repairs an already-earned 2.5 credit,
    // so it intentionally bypasses onEarned and the new 2.6 lifetime ledger;
    // ordinary 2.6 rewards always go through Wallet.add(levelReward).
    if (levelRewardPayout > 0) {
      if (levelRewardPayout > coins) await saveCoins(levelRewardPayout);
      await saveLevelRewardPayout(0);
    }
    if (!prefs.containsKey(Obf.prefLvlIndex) &&
        prefs.containsKey(_levelRewardPayoutKey)) {
      await saveLvlIndex(lvlIndex);
    }
    // A pending roll is durable before its index. Repair a kill in between.
    final reached = lvlPending.fold<int>(
      lvlIndex,
      (index, row) =>
          (row['lvl'] as int? ?? 0) > index ? row['lvl'] as int : index,
    );
    if (reached > lvlIndex) {
      await saveLvlPoints(0);
      await saveLvlIndex(reached);
    }
    // endregion
  }

  void _readSealedFields(SharedPreferences prefs) {
    // region P26-S0
    lvlIndex = prefs.getInt(Obf.prefLvlIndex) ?? 0;
    lvlPending = _p26Records(prefs.getString(Obf.prefLvlPending));
    lbGiftsClaimed = (prefs.getStringList(Obf.prefLbGiftsClaimed) ?? const [])
        .toSet();
    // endregion
    bestScore = prefs.getInt(_bestScoreKey) ?? 0;
    coins = prefs.getInt(_coinsKey) ?? 0;
    ownedItems = (prefs.getStringList(_ownedItemsKey) ?? const []).toSet();
    noAds = prefs.getBool(_noAdsKey) ?? false;
    // region P26-J2 — retired rank stays on disk, never read by 2.6.
    playerLevel = 0;
    // endregion
    grantedPurchases = _capGranted(
      prefs.getStringList(_grantedPurchasesKey) ?? const [],
    );
    uploadQueue = List.of(prefs.getStringList(_uploadQueueKey) ?? const []);
  }

  // region PRD-2.5 §3.4 WP-SAVE — tamper-evident save
  final SaveSealer? _sealer;

  /// The sticky flag of the seal: this save was found edited. Only "Delete
  /// my data" (or a start without the device key) clears it.
  bool get sealUntrusted => _sealUntrusted;
  bool _sealUntrusted = false;

  /// The first load's verification (null = not started: no sealing yet).
  Future<void>? _sealBase;

  /// Sealing is unavailable for this process (no key / channel error).
  bool _sealOff = false;

  /// A covered value was written before the first verification started;
  /// it cannot be judged, so the verification trusts and reseals.
  bool _unsealedWrite = false;

  /// The last stored `cur` snapshot (the next seal's `prev`).
  SealSnapshot? _sealCur;
  int _sealWanted = 0;
  int _sealDone = 0;
  Future<void>? _sealRunning;

  /// Covered setters between their seal and their value write.
  int _sealIssuing = 0;
  Completer<void> _sealIdle = Completer<void>()..complete();

  /// Tests: seal records written.
  @visibleForTesting
  int sealWrites = 0;

  /// Tests: the verification of the first [load] (null = none).
  @visibleForTesting
  Future<void>? get sealVerified => _sealBase;

  /// The covered fields (PRD §3.4), one canonical hash each.
  Map<String, String> _sealHashes() => {
    // region P26-S0
    Obf.prefLvlIndex: sealFieldHash(lvlIndex),
    Obf.prefLvlPending: sealFieldHash(lvlPending),
    Obf.prefLbGiftsClaimed: sealFieldHash(lbGiftsClaimed.toList()..sort()),
    // endregion
    Obf.prefBestScore: sealFieldHash(bestScore),
    Obf.prefCoins: sealFieldHash(coins),
    Obf.prefGrantedPurchases: sealFieldHash(List.of(grantedPurchases)..sort()),
    Obf.prefNoAds: sealFieldHash(noAds),
    Obf.prefOwnedItems: sealFieldHash(ownedItems.toList()..sort()),
    // region P26-J2 — retired rank is no longer a covered value.
    // Existing 2.5 snapshots still verify their MAC; this obsolete hash is ignored.
    // endregion
    Obf.prefUploadQueue: sealFieldHash(uploadQueue),
  };

  // region P26-S0
  bool get _sealedFieldsAtDefault =>
      bestScore == 0 &&
      coins == 0 &&
      grantedPurchases.isEmpty &&
      !noAds &&
      ownedItems.isEmpty &&
      // region P26-J2 — legacy playerLevel is deliberately excluded.
      uploadQueue.isEmpty &&
      // endregion
      lvlIndex == 0 &&
      lvlPending.isEmpty &&
      lbGiftsClaimed.isEmpty;
  // endregion

  /// Step 1 of a covered setter, right after its cache update: the seal of
  /// the new values. Null when sealing is off (the setter writes at once).
  /// A non-null gate must be followed by [_sealWritten] once the value
  /// write is issued.
  Future<void>? _sealGate() {
    final sealer = _sealer;
    if (sealer == null || _sealOff) return null;
    if (_sealBase == null) {
      _unsealedWrite = true;
      return null;
    }
    if (_sealIssuing++ == 0) _sealIdle = Completer<void>();
    return _sealUpTo(++_sealWanted);
  }

  void _sealWritten() {
    if (--_sealIssuing == 0 && !_sealIdle.isCompleted) _sealIdle.complete();
  }

  /// A covered value write: the seal first, then [write] (its value is
  /// captured by the caller at call time). Without sealing it is exactly
  /// the old `await getInstance(); await set…` ([cached]: the `_prefs`
  /// handle first, as [savePlayerLevel] always did).
  Future<void> _sealedWrite(
    Future<bool> Function(SharedPreferences prefs) write, {
    bool cached = false,
  }) async {
    final gate = _sealGate();
    if (gate == null) {
      final prefs = cached
          ? _prefs ?? await SharedPreferences.getInstance()
          : await SharedPreferences.getInstance();
      await write(prefs);
      return;
    }
    Future<bool>? issued;
    try {
      await gate;
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      issued = write(prefs);
    } finally {
      _sealWritten();
    }
    await issued;
  }

  /// Serialised: one seal in flight, the latest values win.
  Future<void> _sealUpTo(int want) async {
    await _sealBase;
    while (_sealDone < want && !_sealOff) {
      final running = _sealRunning;
      if (running != null) {
        await running;
        continue;
      }
      final target = _sealWanted;
      final f = _sealOnce();
      _sealRunning = f;
      try {
        await f;
      } finally {
        _sealRunning = null;
        if (target > _sealDone) _sealDone = target;
      }
    }
  }

  /// Writes one seal record of the current values (never throws).
  Future<void> _sealOnce() async {
    final sealer = _sealer;
    if (sealer == null || _sealOff) return;
    try {
      final next = SealSnapshot(_sealHashes(), untrusted: _sealUntrusted);
      final prev = _sealCur;
      final r = await sealer.mac([next.payload(), ?prev?.payload()]);
      if (r == null) {
        // The key stopped working: drop it, so the next start takes the
        // "key absent" path (trusted) instead of a stale seal.
        _sealOff = true;
        await sealer.drop();
        return;
      }
      final cur = next.withMac(r.macs[0]);
      _sealCur = cur;
      final record = SealRecord(cur, prev?.withMac(r.macs[1]));
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      sealWrites++;
      await prefs.setString(_sealKey, record.encode());
    } catch (_) {
      _sealOff = true;
    }
  }

  /// The once-per-process verdict (PRD §3.4 "Verdict at start"). It never
  /// resets or changes a value; an edited save only sets the sticky flag
  /// and tells the [IntegrityGuard].
  Future<void> _verifySeal(
    SharedPreferences prefs,
    Map<String, String> loaded,
  ) async {
    final sealer = _sealer!;
    try {
      final existed = await sealer.ensureKey();
      if (existed == null) {
        _sealOff = true;
        return;
      }
      var tampered = false;
      final raw = prefs.getString(_sealKey);
      if (!existed || _unsealedWrite) {
        // Fresh install / restore / transfer / lost key: trust and seal.
      } else if (raw == null) {
        tampered = !_sealedFieldsAtDefault;
      } else {
        final rec = SealRecord.decode(raw);
        if (rec == null) {
          tampered = true;
        } else {
          final prev = rec.prev;
          final r = await sealer.mac([rec.cur.payload(), ?prev?.payload()]);
          if (r == null || r.rekeyed) {
            // Cannot verify (the key broke): fail open.
          } else if (r.macs[0] != rec.cur.mac ||
              (prev != null && r.macs[1] != prev.mac)) {
            tampered = true;
          } else {
            _sealCur = rec.cur;
            if (rec.cur.untrusted) {
              tampered = true;
            } else {
              for (final e in loaded.entries) {
                final a = rec.cur.hashes[e.key];
                final b = prev?.hashes[e.key];
                // A field neither snapshot knows is not judged.
                if (a == null && b == null) continue;
                if (e.value != a && e.value != b) {
                  tampered = true;
                  break;
                }
              }
            }
          }
        }
      }
      if (tampered) {
        _sealUntrusted = true;
        IntegrityGuard.instance.markUntrusted('save');
      }
      await _sealOnce();
    } catch (_) {
      _sealOff = true;
    }
  }
  // endregion WP-SAVE

  // region PRD-2 keys (WP-0b) — setters
  static Map<int, String> _decodeIntMap(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (int.tryParse('${e.key}') != null && e.value is String)
            int.parse('${e.key}'): e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFeathers(int value) async {
    feathers = value.clamp(0, 3);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_feathersKey, feathers);
  }

  Future<void> savePuzzlePieces(int value) async {
    puzzlePieces = value & 0xF;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_puzzlePiecesKey, puzzlePieces);
  }

  Future<void> savePuzzleRound(int value) async {
    puzzleRound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_puzzleRoundKey, value);
  }

  /// §3.16 4/4: the mask goes to 0 and the round + 1 in one step (both
  /// fields set before the first await, so no reader sees half of it).
  Future<void> completePuzzleRound() async {
    puzzlePieces = 0;
    puzzleRound++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_puzzlePiecesKey, 0);
    await prefs.setInt(_puzzleRoundKey, puzzleRound);
  }

  /// §3.16 (call, S6-62) 4/4 as one recoverable step: the payout record
  /// ([puzzlePayout], the balance the bonus is to reach) and the mask
  /// reset + round advance. Every cache field is set before the first
  /// await and the platform writes go out record first, so the coin write
  /// that follows (`Wallet.add`) is always issued after the record.
  // region P26-G6c
  /// Journal absolute targets before any completion write. A reload replays
  /// them idempotently before the existing puzzle payout recovery runs.
  Future<void> beginPuzzleCompletion({required int payout}) async {
    final counts = List<int>.of(albumCounts);
    counts[puzzleRound % 8]++;
    final round = puzzleRound + 1;
    puzzlePayout = payout;
    puzzlePieces = 0;
    puzzleRound = round;
    albumCounts = counts;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final journal = jsonEncode({'round': round, 'payout': payout, 'counts': counts});
    final gate = prefs.setString(Obf.prefAlbumCompletionJournal, journal).then<void>((ok) {
      if (!ok) throw StateError('album journal write failed');
    });
    _albumJournalGate = gate;
    try {
      await gate;
    } finally {
      if (identical(_albumJournalGate, gate)) _albumJournalGate = null;
    }
    await _applyAlbumCompletion(prefs, round, payout, counts);
  }

  Future<void> _applyAlbumCompletion(SharedPreferences prefs, int round,
      int payout, List<int> counts) async {
    Future<void> checked(Future<bool> write) async {
      if (!await write) throw StateError('album completion write failed');
    }
    await checked(prefs.setInt(_puzzlePayoutKey, payout));
    await checked(prefs.setStringList(Obf.prefAlbumCounts, counts.map((n) => '$n').toList()));
    await checked(prefs.setInt(_puzzlePiecesKey, 0));
    await checked(prefs.setInt(_puzzleRoundKey, round));
    await checked(prefs.remove(Obf.prefAlbumCompletionJournal));
  }

  Future<void> _recoverAlbumCompletion(SharedPreferences prefs) async {
    final raw = prefs.getString(Obf.prefAlbumCompletionJournal);
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final round = data['round'] as int;
    final payout = data['payout'] as int;
    final counts = (data['counts'] as List).cast<int>();
    puzzleRound = round;
    puzzlePieces = 0;
    puzzlePayout = payout;
    albumCounts = List<int>.of(counts);
    await _applyAlbumCompletion(prefs, round, payout, counts);
  }
  // endregion

  /// §3.16 (call, S6-62) Settles a puzzle payout: clears the record.
  Future<void> endPuzzlePayout() async {
    puzzlePayout = 0;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(_puzzlePayoutKey, 0);
  }

  Future<void> saveLastPortalRide(String value) async {
    lastPortalRide = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPortalRideKey, value);
  }

  Future<void> saveUnclaimedLevelReward(int value) async {
    unclaimedLevelReward = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_unclaimedLevelRewardKey, value);
  }

  Future<void> saveLevelRewardPayout(int value) async {
    levelRewardPayout = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_levelRewardPayoutKey, value);
  }

  Future<void> saveMetElements(Set<String> value) async {
    metElements = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_metElementsKey, metElements.toList()..sort());
  }

  // region P231-E — achievements (PRD-2.3.1 §12.3)

  /// QA P19-01..03 THE achievement write: the whole [state] as one JSON
  /// value, one awaited setter. The cache is replaced synchronously.
  Future<void> saveAchState(AchState state) async {
    ach = state;
    final raw = state.encode();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_achStateKey, raw);
  }

  /// A 2.3.1 (20) install: the separate keys, read once (never written
  /// again; the next [saveAchState] makes `achState` the truth).
  static AchState _migrateAch(SharedPreferences prefs) => AchState()
    ..unlocked = (prefs.getStringList(_achUnlockedKey) ?? const []).toSet()
    ..reported = (prefs.getStringList(_achReportedKey) ?? const []).toSet()
    ..reportedPlayer = prefs.getString(_achReportedPlayerKey) ?? ''
    ..rides = (prefs.getStringList(_achRidesKey) ?? const []).toSet()
    ..items = (prefs.getStringList(_achItemsKey) ?? const []).toSet()
    ..versusWins = prefs.getInt(_achVersusWinsKey) ?? 0
    ..dayStreak = prefs.getInt(_achDayStreakKey) ?? 0
    ..lastPlayDay = prefs.getInt(_achLastPlayDayKey) ?? -1
    ..journal = [...?prefs.getStringList(_achJournalKey)]
    ..journalExcluded = prefs.getBool(_achJournalExcludedKey) ?? false
    ..pending = [...?prefs.getStringList(_achPendingKey)]
    ..itemCounts = {
      for (final e
          in prefs.getStringList(_achItemCountsKey) ?? const <String>[])
        if (e.contains('='))
          e.substring(0, e.lastIndexOf('=')):
              int.tryParse(e.substring(e.lastIndexOf('=') + 1)) ?? 0,
    };

  // Single-field conveniences (debug, tests): each is one whole-state write.
  Future<void> _saveAch(void Function(AchState s) change) {
    final next = ach.copy();
    change(next);
    return saveAchState(next);
  }

  Future<void> saveAchUnlocked(Set<String> value) =>
      _saveAch((s) => s.unlocked = {...value});

  Future<void> saveAchReported(Set<String> value) =>
      _saveAch((s) => s.reported = {...value});

  Future<void> saveAchReportedPlayer(String value) =>
      _saveAch((s) => s.reportedPlayer = value);

  Future<void> saveAchRides(Set<String> value) =>
      _saveAch((s) => s.rides = {...value});

  Future<void> saveAchItems(Set<String> value) =>
      _saveAch((s) => s.items = {...value});

  Future<void> saveAchVersusWins(int value) =>
      _saveAch((s) => s.versusWins = value);

  /// The daily streak and its day, written together.
  Future<void> saveAchDays(int streak, int lastDay) => _saveAch(
    (s) => s
      ..dayStreak = streak
      ..lastPlayDay = lastDay,
  );

  /// PRD-2.3.1 §19.2 the pacing queue (oldest first).
  Future<void> saveAchPending(List<String> value) =>
      _saveAch((s) => s.pending = [...value]);

  /// PRD-2.3.1 §19.1 the lifetime item catch counts.
  Future<void> saveAchItemCounts(Map<String, int> value) =>
      _saveAch((s) => s.itemCounts = {...value});

  /// Debug "Achievements: reset local" / [resetMenuState]: clears every
  /// achievement key (it cannot reset the platform).
  Future<void> resetAchievements() async {
    await saveAchState(AchState());
    // The 2.3.1 (20) keys go too, so nothing could ever migrate back.
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      _achUnlockedKey,
      _achReportedKey,
      _achReportedPlayerKey,
      _achRidesKey,
      _achItemsKey,
      _achVersusWinsKey,
      _achDayStreakKey,
      _achLastPlayDayKey,
      _achJournalKey,
      _achJournalExcludedKey,
      _achPendingKey,
      _achItemCountsKey,
    ]) {
      await prefs.remove(k);
    }
  }
  // endregion P231-E

  /// Adds one element id; no write when it was already met.
  Future<void> markElementMet(String id) async {
    if (metElements.contains(id)) return;
    await saveMetElements({...metElements, id});
  }

  /// §3.13 / §7 `versusNickname` (S6-F02): the nickname, created once per
  /// install. Reads the saved value from disk first — not just the
  /// in-memory field, which is empty until [load] ran — and only calls
  /// [generate] and saves when none is stored. Concurrent callers share one
  /// pass, so two can never save two different names.
  Future<String> ensureVersusNickname(String Function() generate) {
    final have = versusNickname;
    if (have != null && have.isNotEmpty) return Future.value(have);
    return _nicknameInit ??= _ensureVersusNickname(
      generate,
    ).whenComplete(() => _nicknameInit = null);
  }

  Future<String>? _nicknameInit;

  Future<String> _ensureVersusNickname(String Function() generate) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_versusNicknameKey);
    if (saved != null && saved.isNotEmpty) {
      versusNickname = saved;
      return saved;
    }
    final name = generate();
    await saveVersusNickname(name);
    return name;
  }

  Future<void> saveVersusNickname(String value) async {
    versusNickname = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versusNicknameKey, value);
  }

  /// WP-NAME saves the custom name ('' clears it); [syncedUid] = the
  /// server confirmed it for that uid, null = not sent yet (offline).
  Future<void> saveVersusCustomName(String name, {String? syncedUid}) async {
    versusCustomName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versusCustomNameKey, name);
    if (syncedUid != null) await saveVersusCustomNameSync(syncedUid, name);
  }

  /// WP-NAME the server confirmed [name] for [uid].
  Future<void> saveVersusCustomNameSync(String uid, String name) async {
    versusCustomNameSync = '$uid\n$name';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versusCustomNameSyncKey, versusCustomNameSync);
  }

  /// WP-NAME the name the server last confirmed for [uid] (null = none).
  String? versusCustomNameSyncedFor(String uid) {
    final s = versusCustomNameSync;
    final i = s.indexOf('\n');
    if (i < 0 || s.substring(0, i) != uid) return null;
    return s.substring(i + 1);
  }

  /// WP-N2 the server's name was read for [uid] on [day] ('' clears).
  Future<void> saveVersusCustomNameRead(String uid, String day) async {
    versusCustomNameRead = uid.isEmpty ? '' : '$uid\n$day';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versusCustomNameReadKey, versusCustomNameRead);
  }

  Future<void> saveVersusCustomNameError(String reason) async {
    versusCustomNameError = reason;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versusCustomNameErrorKey, reason);
  }

  Future<void> saveUploadQueue(List<String> value) async {
    uploadQueue = List.of(value);
    final list = uploadQueue;
    await _sealedWrite((p) => p.setStringList(_uploadQueueKey, list));
  }

  Future<void> saveUploadsToday(String day, int count) async {
    uploadsDay = day;
    uploadsToday = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uploadsDayKey, day);
    await prefs.setInt(_uploadsTodayKey, count);
  }

  /// §3.13 (S6-60) the upload-day counter of written non-best runs.
  Future<void> saveUploadsSent(String day, int count) async {
    uploadsSentDay = day;
    uploadsSent = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uploadsSentDayKey, day);
    await prefs.setInt(_uploadsSentKey, count);
  }

  Future<void> saveNotifOrder(List<int> value) async {
    notifOrder = List.of(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _notifOrderKey,
      notifOrder.map((n) => '$n').toList(),
    );
  }

  Future<void> saveNotifPosition(int value) async {
    notifPosition = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notifPositionKey, value);
  }

  Future<void> saveNotifLastSent(Map<int, String> value) async {
    notifLastSent = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notifLastSentKey,
      jsonEncode({for (final e in notifLastSent.entries) '${e.key}': e.value}),
    );
  }

  Future<void> saveNotifPermissionAsked(bool value) async {
    notifPermissionAsked = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifPermissionAskedKey, value);
  }
  // endregion PRD-2 keys

  // region WP-4c — "Delete my data" local reset (PRD-2 §3.13 Q22, ARCH §5)
  // region P26-LB2
  /// Called only after the server deleted the gifts and board identity.
  Future<void> resetLeaderboardData() async {
    lbQueue = const [];
    lbGroupId = '';
    lbGroupEnd = 0;
    lbLastRank = 0;
    lbGiftsClaimed = const {};
    lbGiftPending = const {};
    lbInfoSeen = false;
    await _sealedWrite((p) async {
      final removed = await Future.wait([
        for (final key in [
          Obf.prefLbQueue,
          Obf.prefLbGroupId,
          Obf.prefLbGroupEnd,
          Obf.prefLbLastRank,
          Obf.prefLbGiftsClaimed,
          Obf.prefLbGiftPending,
          Obf.prefLbInfoSeen,
        ])
          p.remove(key),
      ]);
      return removed.every((ok) => ok);
    }, cached: true);
  }
  // endregion

  // region P26-S0
  /// Clears versus, leaderboard and 2.6 meta/progression state, including
  /// both generations of level keys (PRD-2.6 J5 / Appendix). The streak and
  /// device A/B arm stay (§8.3-12). Coins, skins, feathers, puzzle pieces,
  /// met elements and sound/rumble settings remain local progress. Music
  /// volume returns to its default (PRD-2.2 §9.1).
  // endregion
  Future<void> resetVersusData() async {
    versusNickname = null;
    ftueSteps = 0;
    showcaseSeen = 0;
    showcaseAttempt = 0;
    showcaseRuns = 0;
    showcaseDoneAt = null;
    pendingFirstMeets = const [];
    // PRD-2.5 §3.4: "Delete my data" clears the sticky seal flag (the
    // upload-queue reset below writes the new seal).
    _sealUntrusted = false;
    // WP-NAME the custom name goes too (the server deletes its copy).
    versusCustomName = '';
    versusCustomNameSync = '';
    versusCustomNameError = '';
    versusCustomNameRead = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ftueStepsKey);
    await prefs.remove(_showcaseSeenKey);
    await prefs.remove(_showcaseAttemptKey);
    await prefs.remove(_showcaseRunsKey);
    await prefs.remove(_showcaseDoneAtKey);
    await prefs.remove(_pendingFirstMeetsKey);
    await prefs.remove(_versusNicknameKey);
    await prefs.remove(_versusCustomNameReadKey);
    await prefs.remove(_versusCustomNameKey);
    await prefs.remove(_versusCustomNameSyncKey);
    await prefs.remove(_versusCustomNameErrorKey);
    await prefs.remove(_versusAvatarKey); // WP-AV the old picture record
    // region P26-S0
    await _resetP26Data();
    // endregion
    await saveUploadQueue(const []);
    await saveUploadsToday('', 0);
    await saveUploadsSent('', 0);
    await resetMusicVolume();
    await resetHomeMode();
  }
  // endregion WP-4c

  /// Whether any of [ids] belongs to an already granted purchase.
  bool isPurchaseGranted(Iterable<String> ids) =>
      ids.any(grantedPurchases.contains);

  /// Records [ids] as granted (deduplicated, bounded, persisted).
  Future<void> saveGrantedPurchase(Iterable<String> ids) async {
    final next = [
      ...grantedPurchases,
      for (final id in ids)
        if (id.isNotEmpty && !grantedPurchases.contains(id)) id,
    ];
    grantedPurchases = _capGranted(next);
    final list = grantedPurchases;
    await _sealedWrite((p) => p.setStringList(_grantedPurchasesKey, list));
  }

  List<String> _capGranted(List<String> value) =>
      value.length > maxGrantedPurchases
      ? value.sublist(value.length - maxGrantedPurchases)
      : List.of(value);

  Future<void> saveBestScore(int value) async {
    bestScore = value;
    await _sealedWrite((p) => p.setInt(_bestScoreKey, value));
  }

  Future<void> saveFtueSteps(int value) async {
    ftueSteps = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ftueStepsKey, value);
  }

  /// PRD-2.6 WP-A the lifetime best hoop count, only ever raised (a worse
  /// later run leaves it alone). A debug run passes the same value, so it
  /// cannot lower it either.
  Future<void> saveBestHoops(int value) async {
    final next = math.max(0, value);
    if (next <= bestHoops) return;
    bestHoops = next;
    await _sealedWrite((p) => p.setInt(_bestHoopsKey, next));
  }

  /// PRD-2.6 WP-A replaces the durable queue of first-meet records. The
  /// list is written one item per string (SharedPreferences has no object
  /// lists), preserving order.
  Future<void> savePendingFirstMeets(List<Map<String, Object?>> value) async {
    pendingFirstMeets = [
      for (final record in value) Map<String, Object?>.of(record),
    ];
    final encoded = [
      for (final record in pendingFirstMeets) jsonEncode(record),
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingFirstMeetsKey, encoded);
  }

  static int _localDayStartMs(int day) {
    final utcDay = DateTime.fromMillisecondsSinceEpoch(
      day * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(
      utcDay.year,
      utcDay.month,
      utcDay.day,
    ).millisecondsSinceEpoch;
  }

  static List<Map<String, Object?>> _decodeFirstMeets(List<String> raw) {
    final out = <Map<String, Object?>>[];
    for (final line in raw) {
      try {
        final value = jsonDecode(line);
        if (value is Map) {
          out.add({
            for (final entry in value.entries) '${entry.key}': entry.value,
          });
        }
      } catch (_) {
        // A corrupt record must not prevent the game from starting.
      }
    }
    return out;
  }

  Future<void> saveShowcaseSeen(int value) async {
    showcaseSeen = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_showcaseSeenKey, value);
  }

  Future<void> saveShowcaseAttempt(int value) async {
    showcaseAttempt = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_showcaseAttemptKey, value);
  }

  Future<void> saveShowcaseRuns(int value) async {
    showcaseRuns = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_showcaseRunsKey, value);
  }

  Future<void> saveShowcaseDoneAt(int? value) async {
    showcaseDoneAt = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_showcaseDoneAtKey);
    } else {
      await prefs.setInt(_showcaseDoneAtKey, value);
    }
  }

  Future<void> saveLastScore(int value) async {
    lastScore = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastScoreKey, value);
  }

  Future<void> incrementGamesPlayed() async {
    gamesPlayed++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gamesPlayedKey, gamesPlayed);
  }

  /// PRD-2.3 §14.6 the RUN DEBUG "Runs: N (+5 / 0)" row sets it directly.
  Future<void> saveGamesPlayed(int value) async {
    gamesPlayed = value < 0 ? 0 : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gamesPlayedKey, gamesPlayed);
  }

  /// PRD-2.3 §14.2 [lastFeatherRun].
  Future<void> saveLastFeatherRun(int value) async {
    lastFeatherRun = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastFeatherRunKey, value);
  }

  /// PRD-2.3 §14.2 [lastPieceRun].
  Future<void> saveLastPieceRun(int value) async {
    lastPieceRun = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastPieceRunKey, value);
  }

  /// PRD-2.3 §10.3 / PRD-2.3.1 §10 [firstRunHintSeen].
  Future<void> saveFirstRunHintSeen(bool value) async {
    firstRunHintSeen = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstRunHintSeenKey, value);
  }

  Future<void> saveMuteSound(bool value) async {
    muteSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_muteSoundKey, value);
  }

  Future<void> saveMusicVolume(double value) async {
    musicVolume = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicVolumeKey, value);
  }

  /// PRD-2.2 §2.2 the Home mode button's choice.
  Future<void> saveHomeMode(HomeMode value) async {
    homeMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeModeKey, value.key);
  }

  /// PRD-2.2 §2.2: "Delete my data" puts the mode back to VERSUS (the key is
  /// removed, so the default applies).
  Future<void> resetHomeMode() async {
    homeMode = HomeMode.versus;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeModeKey);
  }

  /// PRD-2.2 §9.1: "Delete my data" clears the stored music volume (the key
  /// is removed, not written, so the default keeps applying).
  Future<void> resetMusicVolume() async {
    musicVolume = Config.defaultMusicVolume;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_musicVolumeKey);
  }

  Future<void> saveCoins(int value) async {
    // region P26-G1b
    // A spend while a mission payout is still settling must lower its
    // recovery target; otherwise recovery would refund the spend.
    Future<void>? journalWrite;
    final j = missionJournal;
    final before = j['balanceBefore'];
    if (j['applied'] == true && before is int && value < coins) {
      j['balanceBefore'] = before + value - coins;
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      journalWrite = prefs.setString(Obf.prefMissionJournal, jsonEncode([j])).then((_) {});
    }
    // endregion
    coins = value;
    // region P26-G1b
    if (journalWrite != null) await journalWrite;
    // endregion
    // region P26-G6c
    // Any concurrent coin write must also wait for the completion journal.
    final journalGate = _albumJournalGate;
    if (journalGate != null) await journalGate;
    // endregion
    await _sealedWrite((p) => p.setInt(_coinsKey, value));
  }

  /// Owned item keys (`"layer:id"`); the free defaults are implicit.
  Future<void> saveOwnedItems(Set<String> value) async {
    ownedItems = {...value};
    final list = ownedItems.toList();
    await _sealedWrite((p) => p.setStringList(_ownedItemsKey, list));
  }

  /// Replaces the whole equipped map (five keys).
  Future<void> saveEquippedItems(Map<SkinLayer, String> value) async {
    equippedItems = {...value};
    final prefs = await SharedPreferences.getInstance();
    for (final layer in SkinLayer.values) {
      await prefs.setString(
        _equippedItemKey(layer),
        equippedItems[layer] ?? Look.defaults.idFor(layer),
      );
    }
  }

  /// Sets the equipped item of one layer (saves immediately). For cards, an
  /// empty id resets all slots; use clearCard for a single slot.
  Future<void> saveEquippedItem(SkinLayer layer, String id) async {
    // region P26-F9a
    // Card purchases/equips replace one slot, preserving the other two. Full
    // strings (including empty for reset) are also accepted by this entry point.
    if (layer == SkinLayer.card) {
      final kind = itemById(layer, id)?.cardKind;
      id = kind == null
          ? sanitiseCard(id)
          : Look(card: sanitiseCard(equippedItems[layer]))
                .withCardItem(kind, id).card;
    }
    // endregion
    equippedItems = {...equippedItems, layer: id};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedItemKey(layer), id);
    // region P26-J6
    final key = '${layer.key}:$id';
    // region P26-POL3
    if (lvlPending.any((row) => row['item'] == key && row['equipped'] != true)) {
      await saveLvlPending([
        for (final row in lvlPending)
          if (row['item'] == key) {...row, 'equipped': true} else row,
      ]);
    }
    // endregion
    if (lvlRewardLog.any(
      (row) => row['item'] == key && row['equipped'] != true,
    )) {
      await saveLvlRewardLog([
        for (final row in lvlRewardLog)
          if (row['item'] == key) {...row, 'equipped': true} else row,
      ]);
    }
    // endregion
  }

  Future<void> saveSeenItems(Set<String> value) async {
    seenItems = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenItemsKey, seenItems.toList());
  }

  Future<void> saveNoAds(bool value) async {
    noAds = value;
    await _sealedWrite((p) => p.setBool(_noAdsKey, value));
  }

  /// The armed powerup and its debug origin (PRD-2.3.1 §12.2, QA P2-02),
  /// always written together; 'none' clears the origin.
  Future<void> saveArmedPowerup(String value, {bool debug = false}) async {
    armedPowerup = value;
    armedPowerupDebug = debug && value != 'none';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_armedPowerupDebugKey, armedPowerupDebug);
    await prefs.setString(_armedPowerupKey, value);
  }

  Future<void> saveSlotHistory(List<String> value) async {
    slotHistory = _capSlotHistory(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_slotHistoryKey, slotHistory);
  }

  Future<void> saveInstallDay(int value) async {
    installDay = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_installDayKey, value);
  }

  Future<void> saveNoAdsPopupLastDay(int value) async {
    noAdsPopupLastDay = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noAdsPopupLastDayKey, value);
  }

  Future<void> saveNoAdsPopupDismissals(int value) async {
    noAdsPopupDismissals = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noAdsPopupDismissalsKey, value);
  }

  Future<void> saveNoAdsPopupLastMs(int value) async {
    noAdsPopupLastMs = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noAdsPopupLastMsKey, value);
  }

  Future<void> saveNoAdsPopupClosedMs(int value) async {
    noAdsPopupClosedMs = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noAdsPopupClosedMsKey, value);
  }

  Future<void> saveNoAdsPopupShowsToday(int value) async {
    noAdsPopupShowsToday = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noAdsPopupShowsTodayKey, value);
  }

  Future<void> saveNoAdsPopupVideos(int value) async {
    noAdsPopupVideos = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noAdsPopupVideosKey, value);
  }

  Future<void> saveLastRunMood(String value) async {
    lastRunMood = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRunMoodKey, value);
  }

  Future<void> saveFirstSessionDone(bool value) async {
    firstSessionDone = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstSessionDoneKey, value);
  }

  Future<void> saveFreeCoinsDay(int value) async {
    freeCoinsDay = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_freeCoinsDayKey, value);
  }

  Future<void> saveFreeCoinsCount(int value) async {
    freeCoinsCount = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_freeCoinsCountKey, value);
  }

  Future<void> saveFreeCoinsLastMs(int value) async {
    freeCoinsLastMs = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_freeCoinsLastMsKey, value);
  }

  Future<void> saveDebugDayOffset(int value) async {
    debugDayOffset = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debugDayOffsetKey, value);
  }

  Future<void> saveClaimedLevels(Set<int> value) async {
    claimedLevels = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_claimedLevelsKey, _levelList(claimedLevels));
  }

  /// WP-L the stored player level (see [playerLevel]).
  Future<void> savePlayerLevel(int value) async {
    playerLevel = value;
    await _sealedWrite((p) => p.setInt(_playerLevelKey, value), cached: true);
  }

  List<String> _levelList(Set<int> levels) =>
      (levels.toList()..sort()).map((l) => '$l').toList();

  /// §3.14 (call, S6-22) One durable step for a level-reward claim: it
  /// records the wallet balance the credit is to reach *before* the
  /// claimed levels, in one preferences scope, so a kill in between is
  /// recoverable at the next start (see `LevelProgress.claim`).
  Future<void> beginLevelRewardClaim({
    required int payout,
    required Set<int> claimed,
  }) async {
    levelRewardPayout = payout;
    claimedLevels = {...claimed};
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    // Both cache updates land now (a concurrent `load()` must see the
    // claim); the platform writes go out in this order, record first.
    final record = prefs.setInt(_levelRewardPayoutKey, payout);
    final mark = prefs.setStringList(
      _claimedLevelsKey,
      _levelList(claimedLevels),
    );
    await record;
    await mark;
  }

  /// §3.14 (call, S6-22) Settles a level-reward claim: the in-flight
  /// record goes first, then the owed flag, so a record never outlives its
  /// flag and a stale one cannot be mistaken for a pending credit.
  Future<void> endLevelRewardClaim() async {
    levelRewardPayout = 0;
    unclaimedLevelReward = 0;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final record = prefs.setInt(_levelRewardPayoutKey, 0);
    final flag = prefs.setInt(_unclaimedLevelRewardKey, 0);
    await record;
    await flag;
  }

  /// PRD-2.3 §18.3 the playtime counter (written every 10 s in the
  /// foreground, on going to the background and at run end).
  Future<void> savePlaytimeSeconds(int value) async {
    playtimeSeconds = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(_playtimeSecondsKey, value);
  }

  /// PRD-2.3 §18.4 the first interstitial's one-time event went out.
  Future<void> saveFirstInterstitialShown() async {
    firstInterstitialShown = true;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(_firstInterstitialShownKey, true);
  }

  /// PRD-2.3 §23.2 the wall-clock second of a rating-sheet request.
  Future<void> saveLastRatingRequestAt(int seconds) async {
    lastRatingRequestAt = seconds;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(_lastRatingRequestAtKey, seconds);
  }

  Future<void> saveRumble(bool value) async {
    rumble = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rumbleKey, value);
  }

  /// Debug-panel reset: clears the menu economy/skin/powerup/popup state but
  /// keeps the best score, sound / rumble settings and the install day. The
  /// stored level goes back to 0 (unranked) and the claimed level rewards
  /// are cleared (they pay again when the levels are reached again).
  Future<void> resetMenuState() async {
    await saveCoins(0);
    await saveOwnedItems({});
    await saveEquippedItems({
      for (final layer in SkinLayer.values) layer: Look.defaults.idFor(layer),
    });
    await saveSeenItems({});
    await saveNoAds(false);
    await saveArmedPowerup('none');
    await saveSlotHistory(const []);
    await saveNoAdsPopupLastDay(-1);
    await saveNoAdsPopupDismissals(0);
    await saveNoAdsPopupLastMs(0);
    await saveNoAdsPopupShowsToday(0);
    await saveNoAdsPopupVideos(0);
    await saveFreeCoinsDay(-1);
    await saveFreeCoinsCount(0);
    await saveFreeCoinsLastMs(0);
    await saveClaimedLevels({});
    await savePlayerLevel(0); // WP-L
    await resetAchievements(); // PRD-2.3.1 §12.3
  }

  List<String> _capSlotHistory(List<String> value) =>
      value.length > _maxSlotHistory
      ? value.sublist(value.length - _maxSlotHistory)
      : List.of(value);
  // region P26-S0
  static List<Map<String, Object?>> _p26Records(String? raw) {
    try {
      final value = jsonDecode(raw ?? '[]');
      if (value is List) {
        return [
          for (final record in value)
            if (record is Map<String, dynamic>) Map<String, Object?>.of(record),
        ];
      }
    } catch (_) {}
    return [];
  }

  static Map<String, Object?> _p26JsonMap(String? raw) {
    try {
      final value = jsonDecode(raw ?? '{}');
      if (value is Map<String, dynamic>) return Map<String, Object?>.of(value);
    } catch (_) {}
    return {};
  }

  static Map<String, int> _p26IntMap(String? raw) => {
    for (final e in _p26JsonMap(raw).entries)
      if (e.value is int) e.key: e.value as int,
  };

  // region P26-J2
  /// One seal for a completed run's level step. The pending roll is written
  /// before points/index; either snapshot still validates a kill between them.
  Future<void> saveLevelStep({required int index, required int points,
    required List<Map<String, Object?>> pending}) async {
    lvlIndex = index;
    lvlPoints = points;
    lvlPending = [for (final row in pending) Map<String, Object?>.of(row)];
    final encoded = jsonEncode(lvlPending);
    await _sealedWrite((prefs) async {
      await prefs.setString(Obf.prefLvlPending, encoded);
      await prefs.setInt(Obf.prefLvlPoints, points);
      return prefs.setInt(Obf.prefLvlIndex, index);
    });
  }
  // endregion

  Future<void> saveLvlIndex(int value) async {
    lvlIndex = value;
    final stored = lvlIndex;
    await _sealedWrite((p) => p.setInt(Obf.prefLvlIndex, stored));
  }

  Future<void> saveLvlPoints(int value) async {
    lvlPoints = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLvlPoints, lvlPoints);
  }

  Future<void> saveLvlPending(List<Map<String, Object?>> value) async {
    lvlPending = [for (final record in value) Map<String, Object?>.of(record)];
    final stored = jsonEncode(lvlPending);
    await _sealedWrite((p) => p.setString(Obf.prefLvlPending, stored));
  }

  // region P26-J6
  Future<void> saveLvlRewardLog(List<Map<String, Object?>> value) async {
    final stored = [for (final row in value) Map<String, Object?>.of(row)];
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefLvlRewardLog, jsonEncode(stored));
    lvlRewardLog = stored;
  }
  // endregion

  Future<void> saveLvlPayout(int value) async {
    lvlPayout = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLvlPayout, lvlPayout);
  }

  Future<void> saveBestRunHoops(int value) async {
    bestRunHoops = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefBestRunHoops, bestRunHoops);
  }

  Future<void> saveRecentScores(List<int> value) async {
    recentScores = List<int>.of(value);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      Obf.prefRecentScores,
      recentScores.map((v) => '$v').toList(),
    );
  }

  Future<void> saveDuelStep(int value) async {
    duelStep = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefDuelStep, duelStep);
  }

  Future<void> saveLifetimeCoinsEarned(int value) async {
    lifetimeCoinsEarned = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLifetimeCoinsEarned, lifetimeCoinsEarned);
  }

  Future<void> saveLifetimeCoinsSpent(int value) async {
    lifetimeCoinsSpent = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLifetimeCoinsSpent, lifetimeCoinsSpent);
  }

  Future<void> saveLifetimeCoinsBought(int value) async {
    lifetimeCoinsBought = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLifetimeCoinsBought, lifetimeCoinsBought);
  }

  // region P26-F1
  Future<void> saveFirstItemBought(bool value) async {
    firstItemBought = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(Obf.prefFirstItemBought, value);
  }

  Future<void> saveEconomyDailyDay(int value) async {
    economyDailyDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefEconomyDailyDay, value);
  }
  // endregion

  Future<void> saveVsWinStreak(int value) async {
    vsWinStreak = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefVsWinStreak, vsWinStreak);
  }

  Future<void> saveVsWinStreakBest(int value) async {
    vsWinStreakBest = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefVsWinStreakBest, vsWinStreakBest);
  }

  Future<void> saveVsBigWinsDay(Map<String, int> value) async {
    vsBigWinsDay = {...value};
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefVsBigWinsDay, jsonEncode(vsBigWinsDay));
  }

  // region P26-G1b
  Future<void> saveLastVersusHadRival(bool value) async {
    lastVersusHadRival = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(Obf.prefLastVersusHadRival, value);
  }

  Future<void> saveMissionJournal(Map<String, Object?> value) async {
    missionJournal = Map.of(value);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(Obf.prefMissionJournal);
    } else {
      await prefs.setString(Obf.prefMissionJournal, jsonEncode([value]));
    }
  }

  /// Replays a journal written before either the board or wallet changed.
  Future<void> recoverMissionJournal() async {
    final j = missionJournal;
    if (j.isEmpty) return;
    final rows = j['missions'];
    final day = j['day'];
    final tier = j['tier'];
    final reroll = j['rerollDay'];
    final amount = j['amount'];
    final applied = j['applied'];
    final before = j['balanceBefore'];
    final earnedBefore = j['earnedBefore'];
    if (amount is int && applied == false && before is int && earnedBefore is int) {
      // Commit the target before crediting so recovery itself can be killed.
      await saveMissionJournal({
        ...j,
        'applied': true,
        'balanceBefore': coins,
        'earnedBefore': lifetimeCoinsEarned,
      });
    }
    final legacyBalance = j['balance'];
    final legacyEarned = j['earned'];
    final balance = amount is int && before is int && applied is bool
        ? (applied ? math.max(coins, before + amount) : coins + amount)
        : legacyBalance;
    final earned = amount is int && earnedBefore is int && applied is bool
        ? (applied ? math.max(lifetimeCoinsEarned, earnedBefore + amount) : lifetimeCoinsEarned + amount)
        : legacyEarned;
    if (rows is! List || day is! int || tier is! int || reroll is! int ||
        balance is! int || earned is! int) {
      return;
    }
    // region P26-G6eB
    final roadSeason = j['roadSeason'];
    final roadXp = j['roadXp'];
    final roadDay = j['roadDay'];
    if (roadSeason is int && roadXp is int && roadDay is int && starRoadSeason == roadSeason) {
      await saveStarRoadXp(roadXp);
      await saveStarRoadRunDay(roadDay);
    }
    // endregion
    await saveMissions([for (final row in rows) Map<String, Object?>.from(row as Map)]);
    await saveMissionTier(tier);
    await saveMissionRerollDay(reroll);
    await saveMissionDay(day);
    if (coins < balance) await saveCoins(balance);
    if (lifetimeCoinsEarned < earned) await saveLifetimeCoinsEarned(earned);
    await saveMissionJournal(const {});
  }
  // endregion

  Future<void> saveMissionDay(int value) async {
    missionDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefMissionDay, missionDay);
  }

  Future<void> saveMissions(List<Map<String, Object?>> value) async {
    missions = [for (final record in value) Map<String, Object?>.of(record)];
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefMissions, jsonEncode(missions));
  }

  Future<void> saveMissionTier(int value) async {
    missionTier = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefMissionTier, missionTier);
  }

  Future<void> saveMissionRerollDay(int value) async {
    missionRerollDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefMissionRerollDay, missionRerollDay);
  }

  Future<void> saveStreakDays(int value) async {
    streakDays = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStreakDays, streakDays);
  }

  Future<void> saveStreakLastDay(int value) async {
    streakLastDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStreakLastDay, streakLastDay);
  }

  Future<void> saveStreakPaidDay(int value) async {
    streakPaidDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStreakPaidDay, streakPaidDay);
  }

  Future<void> saveStreakLostDays(int value) async {
    streakLostDays = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStreakLostDays, streakLostDays);
  }

  Future<void> saveStreakLostSeenDay(int value) async {
    streakLostSeenDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStreakLostSeenDay, streakLostSeenDay);
  }

  Future<void> saveWorldsReached(int value) async {
    worldsReached = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefWorldsReached, worldsReached);
  }

  Future<void> saveWorldsSeen(int value) async {
    worldsSeen = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefWorldsSeen, worldsSeen);
  }

  Future<void> saveWeeklyBest(Map<String, int> value) async {
    weeklyBest = {...value};
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefWeeklyBest, jsonEncode(weeklyBest));
  }

  Future<void> saveWeeklyRewards(Set<int> value) async {
    weeklyRewards = {...value};
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      Obf.prefWeeklyRewards,
      weeklyRewards.map((v) => '$v').toList(),
    );
  }

  Future<void> saveWeeklyHintDay(int value) async {
    weeklyHintDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefWeeklyHintDay, weeklyHintDay);
  }

  Future<void> saveFirstWinDay(int value) async {
    firstWinDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefFirstWinDay, firstWinDay);
  }

  Future<void> saveAlbumCounts(List<int> value) async {
    albumCounts = List<int>.of(value);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      Obf.prefAlbumCounts,
      albumCounts.map((v) => '$v').toList(),
    );
  }

  Future<void> saveAlbumRewardClaimed(bool value) async {
    albumRewardClaimed = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(Obf.prefAlbumRewardClaimed, albumRewardClaimed);
  }

  Future<void> saveAlbumRewardItem(String value) async {
    albumRewardItem = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefAlbumRewardItem, albumRewardItem);
  }

  Future<void> saveGuideSeenCount(int value) async {
    guideSeenCount = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefGuideSeenCount, guideSeenCount);
  }

  // region P26-G6eB
  Future<void> saveStarRoadRunDay(int value) async {
    starRoadRunDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStarRoadRunDay, value);
  }
  // endregion

  Future<void> saveStarRoadSeason(int value) async {
    starRoadSeason = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStarRoadSeason, starRoadSeason);
  }

  Future<void> saveStarRoadXp(int value) async {
    starRoadXp = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStarRoadXp, starRoadXp);
  }

  Future<void> saveStarRoadClaimed(Set<int> value) async {
    starRoadClaimed = {...value};
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      Obf.prefStarRoadClaimed,
      starRoadClaimed.map((v) => '$v').toList(),
    );
  }

  Future<void> saveStarRoadPopupDay(int value) async {
    starRoadPopupDay = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefStarRoadPopupDay, starRoadPopupDay);
  }

  Future<void> saveHomeLevelsTag(bool value) async {
    homeLevelsTag = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(Obf.prefHomeLevelsTag, homeLevelsTag);
  }

  Future<void> saveLbQueue(List<String> value) async {
    lbQueue = List<String>.of(value);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(Obf.prefLbQueue, lbQueue);
  }

  Future<void> saveLbGroupId(String value) async {
    lbGroupId = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefLbGroupId, lbGroupId);
  }

  Future<void> saveLbGroupEnd(int value) async {
    lbGroupEnd = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLbGroupEnd, lbGroupEnd);
  }

  Future<void> saveLbLastRank(int value) async {
    lbLastRank = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(Obf.prefLbLastRank, lbLastRank);
  }

  Future<void> saveLbGiftsClaimed(Set<String> value) async {
    lbGiftsClaimed = {...value};
    final stored = lbGiftsClaimed.toList();
    await _sealedWrite((p) => p.setStringList(Obf.prefLbGiftsClaimed, stored));
  }

  Future<void> saveLbGiftPending(Map<String, Object?> value) async {
    lbGiftPending = {...value};
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefLbGiftPending, jsonEncode(lbGiftPending));
  }

  Future<void> saveLbInfoSeen(bool value) async {
    lbInfoSeen = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(Obf.prefLbInfoSeen, lbInfoSeen);
  }

  Future<void> saveAbArmV1(String value) async {
    abArmV1 = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(Obf.prefAbArmV1, abArmV1);
  }

  Future<void> _resetP26Data() async {
    lvlIndex = 0;
    lvlPoints = 0;
    lvlPending = const [];
    lvlPayout = 0;
    // region P26-J6
    lvlRewardLog = const [];
    // endregion
    bestRunHoops = 0;
    recentScores = const [];
    duelStep = -2;
    lifetimeCoinsEarned = 0;
    lifetimeCoinsSpent = 0;
    lifetimeCoinsBought = 0;
    // region P26-F1
    firstItemBought = false;
    economyDailyDay = -1;
    // endregion
    vsWinStreak = 0;
    vsWinStreakBest = 0;
    vsBigWinsDay = const {};
    // region P26-G1b
    lastVersusHadRival = false;
    missionJournal = const {};
    // endregion
    missionDay = -1;
    missions = const [];
    missionTier = 0;
    missionRerollDay = -1;
    worldsReached = 0;
    worldsSeen = 0;
    weeklyBest = const {};
    weeklyRewards = const {};
    weeklyHintDay = -1;
    firstWinDay = -1;
    albumCounts = const [0, 0, 0, 0, 0, 0, 0, 0];
    albumRewardClaimed = false;
    albumRewardItem = '';
    guideSeenCount = 0;
    // region P26-G6eB
    starRoadRunDay = -1;
    // endregion
    starRoadSeason = 0;
    starRoadXp = 0;
    starRoadClaimed = const {};
    starRoadPopupDay = -1;
    homeLevelsTag = false;
    lbQueue = const [];
    lbGroupId = '';
    lbGroupEnd = 0;
    lbLastRank = 0;
    lbGiftsClaimed = const {};
    lbGiftPending = const {};
    lbInfoSeen = false;
    playerLevel = 0;
    claimedLevels = {};
    unclaimedLevelReward = 0;
    levelRewardPayout = 0;
    // Seal the reset before removing its covered fields. Issue every
    // removal together so a concurrent load sees one preferences snapshot.
    await _sealedWrite((p) async {
      final removed = await Future.wait([
        for (final key in [
          Obf.prefLvlIndex,
          Obf.prefLvlPoints,
          Obf.prefLvlPending,
          Obf.prefLvlPayout,
          // region P26-J6
          Obf.prefLvlRewardLog,
          // endregion
          Obf.prefBestRunHoops,
          Obf.prefRecentScores,
          Obf.prefDuelStep,
          Obf.prefLifetimeCoinsEarned,
          Obf.prefLifetimeCoinsSpent,
          Obf.prefLifetimeCoinsBought,
          // region P26-F1
          Obf.prefFirstItemBought,
          Obf.prefEconomyDailyDay,
          // endregion
          Obf.prefVsWinStreak,
          Obf.prefVsWinStreakBest,
          Obf.prefVsBigWinsDay,
          // region P26-G1b
          Obf.prefLastVersusHadRival,
          Obf.prefMissionJournal,
          // endregion
          Obf.prefMissionDay,
          Obf.prefMissions,
          Obf.prefMissionTier,
          Obf.prefMissionRerollDay,
          Obf.prefWorldsReached,
          Obf.prefWorldsSeen,
          Obf.prefWeeklyBest,
          Obf.prefWeeklyRewards,
          Obf.prefWeeklyHintDay,
          Obf.prefFirstWinDay,
          Obf.prefAlbumCounts,
          Obf.prefAlbumRewardClaimed,
          Obf.prefAlbumRewardItem,
          // region P26-G6c
          Obf.prefAlbumCompletionJournal,
          // endregion
          Obf.prefGuideSeenCount,
          // region P26-G6eB
          Obf.prefStarRoadRunDay,
          Obf.prefStarRoadRollover,
          Obf.prefStarRoadJournal,
          Obf.prefStarRoadItems,
          // endregion
          Obf.prefStarRoadSeason,
          Obf.prefStarRoadXp,
          Obf.prefStarRoadClaimed,
          Obf.prefStarRoadPopupDay,
          Obf.prefHomeLevelsTag,
          Obf.prefLbQueue,
          Obf.prefLbGroupId,
          Obf.prefLbGroupEnd,
          Obf.prefLbLastRank,
          Obf.prefLbGiftsClaimed,
          Obf.prefLbGiftPending,
          Obf.prefLbInfoSeen,
          _playerLevelKey,
          _claimedLevelsKey,
          _unclaimedLevelRewardKey,
          _levelRewardPayoutKey,
        ])
          p.remove(key),
      ]);
      return removed.every((ok) => ok);
    }, cached: true);
  }
  // endregion
}
