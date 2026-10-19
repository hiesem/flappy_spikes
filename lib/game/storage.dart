import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../achievements/ach_state.dart';
import '../menu/home_mode.dart';
import '../skins/look.dart';
import 'config.dart';

/// Persistence layer for bestScore / gamesPlayed / muteSound / musicVolume /
/// rumble / homeMode and the 2.0 menu state (coins, skins, powerup slot, no-ads popup,
/// free coins, claimed level rewards).
class GameStorage {
  GameStorage({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// The preferences handle [load] resolved. The legacy API keeps every
  /// value in a memory cache that its setters update synchronously, so a
  /// settler that must win against a concurrent [load] (the level-reward
  /// claim, §3.14) goes through this handle instead of awaiting a fresh
  /// `getInstance()`.
  SharedPreferences? _prefs;

  static const String _bestScoreKey = 'bestScore';
  static const String _gamesPlayedKey = 'gamesPlayed';
  static const String _muteSoundKey = 'muteSound';
  static const String _musicVolumeKey = 'musicVolume';
  static const String _coinsKey = 'coins';
  static const String _ownedSkinsKey = 'ownedSkins';
  static const String _equippedSkinKey = 'equippedSkin';
  static const String _seenSkinsKey = 'seenSkins';
  static const String _ownedItemsKey = 'ownedItems';
  static const String _seenItemsKey = 'seenItems';
  static const String _noAdsKey = 'noAds';
  static const String _armedPowerupKey = 'armedPowerup';
  // PRD-2.3.1 §12.2 (QA P2-02) the armed powerup's debug origin.
  static const String _armedPowerupDebugKey = 'armedPowerupDebug';
  static const String _slotHistoryKey = 'slotHistory';
  static const String _installDayKey = 'installDay';
  static const String _noAdsPopupLastDayKey = 'noAdsPopupLastDay';
  static const String _noAdsPopupDismissalsKey = 'noAdsPopupDismissals';
  static const String _noAdsPopupLastMsKey = 'noAdsPopupLastMs';
  static const String _noAdsPopupClosedMsKey = 'noAdsPopupClosedMs';
  static const String _noAdsPopupShowsTodayKey = 'noAdsPopupShowsToday';
  static const String _noAdsPopupVideosKey = 'noAdsPopupVideos';
  static const String _lastRunMoodKey = 'lastRunMood';
  static const String _firstSessionDoneKey = 'firstSessionDone';
  static const String _freeCoinsDayKey = 'freeCoinsDay';
  static const String _freeCoinsCountKey = 'freeCoinsCount';
  static const String _freeCoinsLastMsKey = 'freeCoinsLastMs';
  static const String _debugDayOffsetKey = 'debugDayOffset';
  static const String _claimedLevelsKey = 'claimedLevels';
  static const String _playerLevelKey = 'playerLevel';
  static const String _rumbleKey = 'rumble';
  static const String _lastScoreKey = 'lastScore';
  static const String _grantedPurchasesKey = 'grantedPurchases';

  // region PRD-2 keys (WP-0b; PRD-2 §7 persistence table, ARCH §5)
  static const String _feathersKey = 'feathers';
  static const String _puzzlePiecesKey = 'puzzlePieces';
  static const String _puzzleRoundKey = 'puzzleRound';
  static const String _lastPortalRideKey = 'lastPortalRide';
  static const String _unclaimedLevelRewardKey = 'unclaimedLevelReward';
  static const String _levelRewardPayoutKey = 'levelRewardPayout';
  static const String _puzzlePayoutKey = 'puzzlePayout';
  static const String _metElementsKey = 'metElements';
  static const String _versusNicknameKey = 'versusNickname';
  static const String _versusCustomNameKey = 'versusCustomName';
  static const String _versusCustomNameSyncKey = 'versusCustomNameSync';
  static const String _versusCustomNameErrorKey = 'versusCustomNameError';
  static const String _versusCustomNameReadKey = 'versusCustomNameRead';
  static const String _uploadQueueKey = 'uploadQueue';
  static const String _uploadsTodayKey = 'uploadsToday';
  static const String _uploadsDayKey = 'uploadsDay';
  static const String _uploadsSentKey = 'uploadsSent';
  static const String _uploadsSentDayKey = 'uploadsSentDay';
  static const String _notifOrderKey = 'notifOrder';
  static const String _notifPositionKey = 'notifPosition';
  // region P231-E — achievements (PRD-2.3.1 §12.3)
  static const String _achUnlockedKey = 'achUnlocked';
  static const String _achReportedKey = 'achReported';
  static const String _achReportedPlayerKey = 'achReportedPlayer';
  static const String _achRidesKey = 'achRides';
  static const String _achItemsKey = 'achItems';
  static const String _achVersusWinsKey = 'achVersusWins';
  static const String _achDayStreakKey = 'achDayStreak';
  static const String _achLastPlayDayKey = 'achLastPlayDay';
  // QA P2-03 the open run's provisional achievement journal.
  static const String _achJournalKey = 'achJournal';
  static const String _achJournalExcludedKey = 'achJournalExcluded';
  // PRD-2.3.1 §19 the pacing queue and the lifetime item catch counts.
  static const String _achPendingKey = 'achPending';
  static const String _achItemCountsKey = 'achItemCounts';
  // QA P19-01..03 everything above lives in ONE JSON key since 2.3.1 (21);
  // the separate keys are only read once, to migrate a 2.3.1 (20) install.
  static const String _achStateKey = 'achState';
  // endregion P231-E
  static const String _notifLastSentKey = 'notifLastSent';
  static const String _notifPermissionAskedKey = 'notifPermissionAsked';
  // endregion PRD-2 keys
  // PRD-2.3 §14.2 the gamesPlayed of the run that last showed a golden
  // feather / puzzle piece (−1 = never; never in two runs in a row).
  static const String _lastFeatherRunKey = 'lastFeatherRun';
  static const String _lastPieceRunKey = 'lastPieceRun';
  // PRD-2.3 §10.3 the first-run instructions were shown (saved at that
  // run's first tap). Local progress: "Delete my data" keeps it.
  static const String _firstRunHintSeenKey = 'firstRunHintSeen';
  // PRD-2.3 §18.3 foreground seconds since install (kept by "Delete my data").
  static const String _playtimeSecondsKey = 'playtimeSeconds';
  // PRD-2.3 §18.4 the one-time `first_interstitial` event has been sent.
  static const String _firstInterstitialShownKey = 'firstInterstitialShown';
  // PRD-2.3 §23.2 the last rating-sheet request, in seconds since the epoch
  // (0 = never; kept by "Delete my data").
  static const String _lastRatingRequestAtKey = 'lastRatingRequestAt';
  // PRD-2.2 §2.2 the Home mode button: 'versus' (default) / 'freeFly'.
  static const String _homeModeKey = 'homeMode';
  // PRD-2.3 §21.3 the last uploaded versus picture (WP-AV: no pictures any
  // more; the stale record is removed at load and by "Delete my data").
  static const String _versusAvatarKey = 'versusAvatar';

  /// One preference key per equipped layer (the five-key equipped map).
  static String _equippedItemKey(SkinLayer layer) =>
      'equippedItem.${layer.key}';

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
    bestScore = prefs.getInt(_bestScoreKey) ?? 0;
    gamesPlayed = prefs.getInt(_gamesPlayedKey) ?? 0;
    muteSound = prefs.getBool(_muteSoundKey) ?? false;
    musicVolume = prefs.getDouble(_musicVolumeKey) ?? Config.defaultMusicVolume;

    coins = prefs.getInt(_coinsKey) ?? 0;
    // PRD-menu-v2 (product decision): the PRD-1 single-skin keys are reset on
    // sight — old skins are dropped, with no refund.
    if (prefs.containsKey(_ownedSkinsKey) ||
        prefs.containsKey(_equippedSkinKey) ||
        prefs.containsKey(_seenSkinsKey)) {
      await prefs.remove(_ownedSkinsKey);
      await prefs.remove(_equippedSkinKey);
      await prefs.remove(_seenSkinsKey);
    }
    ownedItems = (prefs.getStringList(_ownedItemsKey) ?? const []).toSet();
    equippedItems = {
      for (final layer in SkinLayer.values)
        layer:
            prefs.getString(_equippedItemKey(layer)) ??
            Look.defaults.idFor(layer),
    };
    seenItems = (prefs.getStringList(_seenItemsKey) ?? const []).toSet();
    noAds = prefs.getBool(_noAdsKey) ?? false;
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
    claimedLevels = (prefs.getStringList(_claimedLevelsKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    playerLevel = prefs.getInt(_playerLevelKey) ?? 0;
    rumble = prefs.getBool(_rumbleKey) ?? true;
    lastScore = prefs.getInt(_lastScoreKey);
    grantedPurchases = _capGranted(
      prefs.getStringList(_grantedPurchasesKey) ?? const [],
    );
    lastFeatherRun = prefs.getInt(_lastFeatherRunKey) ?? -1;
    lastPieceRun = prefs.getInt(_lastPieceRunKey) ?? -1;
    firstRunHintSeen = prefs.getBool(_firstRunHintSeenKey) ?? (gamesPlayed > 0);
    playtimeSeconds = prefs.getInt(_playtimeSecondsKey) ?? 0;
    firstInterstitialShown = prefs.getBool(_firstInterstitialShownKey) ?? false;
    lastRatingRequestAt = prefs.getInt(_lastRatingRequestAtKey) ?? 0;
    // region PRD-2 keys (WP-0b)
    feathers = (prefs.getInt(_feathersKey) ?? 0).clamp(0, 3);
    puzzlePieces = (prefs.getInt(_puzzlePiecesKey) ?? 0) & 0xF;
    puzzleRound = prefs.getInt(_puzzleRoundKey) ?? 0;
    lastPortalRide = prefs.getString(_lastPortalRideKey);
    unclaimedLevelReward = prefs.getInt(_unclaimedLevelRewardKey) ?? 0;
    levelRewardPayout = prefs.getInt(_levelRewardPayoutKey) ?? 0;
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
    uploadQueue = List.of(prefs.getStringList(_uploadQueueKey) ?? const []);
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
    homeMode = HomeMode.parse(prefs.getString(_homeModeKey));
  }

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
  Future<void> beginPuzzleCompletion({required int payout}) async {
    puzzlePayout = payout;
    puzzlePieces = 0;
    puzzleRound++;
    final round = puzzleRound;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final record = prefs.setInt(_puzzlePayoutKey, payout);
    final mask = prefs.setInt(_puzzlePiecesKey, 0);
    final next = prefs.setInt(_puzzleRoundKey, round);
    await record;
    await mask;
    await next;
  }

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
    for (final k in const [
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_uploadQueueKey, uploadQueue);
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
  /// Q22: "Delete my data" resets the versus install state — the generated
  /// nickname (cleared; a new one is made at the next use), the upload queue
  /// and the daily upload counter. Progress kept only on the phone (coins,
  /// skins, levels, feathers, puzzle pieces, met elements) and the mute /
  /// rumble settings are not touched. The music volume goes back to its
  /// default (PRD-2.2 §9.1).
  Future<void> resetVersusData() async {
    versusNickname = null;
    // WP-NAME the custom name goes too (the server deletes its copy).
    versusCustomName = '';
    versusCustomNameSync = '';
    versusCustomNameError = '';
    versusCustomNameRead = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_versusNicknameKey);
    await prefs.remove(_versusCustomNameReadKey);
    await prefs.remove(_versusCustomNameKey);
    await prefs.remove(_versusCustomNameSyncKey);
    await prefs.remove(_versusCustomNameErrorKey);
    await prefs.remove(_versusAvatarKey); // WP-AV the old picture record
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_grantedPurchasesKey, grantedPurchases);
  }

  List<String> _capGranted(List<String> value) =>
      value.length > maxGrantedPurchases
      ? value.sublist(value.length - maxGrantedPurchases)
      : List.of(value);

  Future<void> saveBestScore(int value) async {
    bestScore = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestScoreKey, value);
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
    coins = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_coinsKey, value);
  }

  /// Owned item keys (`"layer:id"`); the free defaults are implicit.
  Future<void> saveOwnedItems(Set<String> value) async {
    ownedItems = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ownedItemsKey, ownedItems.toList());
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

  /// Sets the equipped item of one layer (saves immediately).
  Future<void> saveEquippedItem(SkinLayer layer, String id) async {
    equippedItems = {...equippedItems, layer: id};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedItemKey(layer), id);
  }

  Future<void> saveSeenItems(Set<String> value) async {
    seenItems = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenItemsKey, seenItems.toList());
  }

  Future<void> saveNoAds(bool value) async {
    noAds = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_noAdsKey, value);
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
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(_playerLevelKey, value);
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
}
