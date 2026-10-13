import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _uploadQueueKey = 'uploadQueue';
  static const String _uploadsTodayKey = 'uploadsToday';
  static const String _uploadsDayKey = 'uploadsDay';
  static const String _uploadsSentKey = 'uploadsSent';
  static const String _uploadsSentDayKey = 'uploadsSentDay';
  static const String _notifOrderKey = 'notifOrder';
  static const String _notifPositionKey = 'notifPosition';
  static const String _notifLastSentKey = 'notifLastSent';
  static const String _notifPermissionAskedKey = 'notifPermissionAsked';
  // endregion PRD-2 keys
  // PRD-2.3 §14.2 the gamesPlayed of the run that last showed a golden
  // feather / puzzle piece (−1 = never; never in two runs in a row).
  static const String _lastFeatherRunKey = 'lastFeatherRun';
  static const String _lastPieceRunKey = 'lastPieceRun';
  // PRD-2.2 §2.2 the Home mode button: 'versus' (default) / 'freeFly'.
  static const String _homeModeKey = 'homeMode';

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

  /// §3.13 Versus nickname (generated once by WP-5b); null = not yet.
  String? versusNickname;

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
    rumble = prefs.getBool(_rumbleKey) ?? true;
    lastScore = prefs.getInt(_lastScoreKey);
    grantedPurchases = _capGranted(
      prefs.getStringList(_grantedPurchasesKey) ?? const [],
    );
    lastFeatherRun = prefs.getInt(_lastFeatherRunKey) ?? -1;
    lastPieceRun = prefs.getInt(_lastPieceRunKey) ?? -1;
    // region PRD-2 keys (WP-0b)
    feathers = (prefs.getInt(_feathersKey) ?? 0).clamp(0, 3);
    puzzlePieces = (prefs.getInt(_puzzlePiecesKey) ?? 0) & 0xF;
    puzzleRound = prefs.getInt(_puzzleRoundKey) ?? 0;
    lastPortalRide = prefs.getString(_lastPortalRideKey);
    unclaimedLevelReward = prefs.getInt(_unclaimedLevelRewardKey) ?? 0;
    levelRewardPayout = prefs.getInt(_levelRewardPayoutKey) ?? 0;
    puzzlePayout = prefs.getInt(_puzzlePayoutKey) ?? 0;
    metElements = (prefs.getStringList(_metElementsKey) ?? const []).toSet();
    versusNickname = prefs.getString(_versusNicknameKey);
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
    await prefs.setStringList(
      _metElementsKey,
      metElements.toList()..sort(),
    );
  }

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_versusNicknameKey);
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

  Future<void> saveArmedPowerup(String value) async {
    armedPowerup = value;
    final prefs = await SharedPreferences.getInstance();
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

  Future<void> saveRumble(bool value) async {
    rumble = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rumbleKey, value);
  }

  /// Debug-panel reset: clears the menu economy/skin/powerup/popup state but
  /// keeps progression, sound / rumble settings and the install day. The
  /// claimed level rewards are cleared (they pay again on the next home).
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
  }

  List<String> _capSlotHistory(List<String> value) =>
      value.length > _maxSlotHistory
      ? value.sublist(value.length - _maxSlotHistory)
      : List.of(value);
}
