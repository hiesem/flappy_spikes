import 'package:shared_preferences/shared_preferences.dart';

import '../skins/look.dart';

/// Persistence layer for bestScore / gamesPlayed / muteSound / musicVolume /
/// rumble and the 2.0 menu state (coins, skins, powerup slot, no-ads popup,
/// free coins, claimed level rewards).
class GameStorage {
  GameStorage({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

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
  static const String _freeCoinsDayKey = 'freeCoinsDay';
  static const String _freeCoinsCountKey = 'freeCoinsCount';
  static const String _freeCoinsLastMsKey = 'freeCoinsLastMs';
  static const String _debugDayOffsetKey = 'debugDayOffset';
  static const String _claimedLevelsKey = 'claimedLevels';
  static const String _rumbleKey = 'rumble';
  static const String _lastScoreKey = 'lastScore';

  /// One preference key per equipped layer (the five-key equipped map).
  static String _equippedItemKey(SkinLayer layer) =>
      'equippedItem.${layer.key}';

  /// [slotHistory] keeps at most this many entries (most recent last).
  static const int _maxSlotHistory = 3;

  final DateTime Function() _clock;

  int bestScore = 0;
  int gamesPlayed = 0;
  bool muteSound = false;
  double musicVolume = 0.6;

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
  int noAdsPopupLastDay = -1;
  int noAdsPopupDismissals = 0;
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

  /// Current wall-clock time (overridable for tests).
  DateTime now() => _clock();

  /// Local calendar day number (days since 1970-01-01), shifted by
  /// [debugDayOffset].
  int get today {
    final t = now();
    return DateTime.utc(t.year, t.month, t.day)
            .difference(DateTime.utc(1970))
            .inDays +
        debugDayOffset;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    bestScore = prefs.getInt(_bestScoreKey) ?? 0;
    gamesPlayed = prefs.getInt(_gamesPlayedKey) ?? 0;
    muteSound = prefs.getBool(_muteSoundKey) ?? false;
    musicVolume = prefs.getDouble(_musicVolumeKey) ?? 0.6;

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
        layer: prefs.getString(_equippedItemKey(layer)) ??
            Look.defaults.idFor(layer),
    };
    seenItems = (prefs.getStringList(_seenItemsKey) ?? const []).toSet();
    noAds = prefs.getBool(_noAdsKey) ?? false;
    armedPowerup = prefs.getString(_armedPowerupKey) ?? 'none';
    slotHistory = _capSlotHistory(
        prefs.getStringList(_slotHistoryKey) ?? const []);
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
    freeCoinsDay = prefs.getInt(_freeCoinsDayKey) ?? -1;
    freeCoinsCount = prefs.getInt(_freeCoinsCountKey) ?? 0;
    freeCoinsLastMs = prefs.getInt(_freeCoinsLastMsKey) ?? 0;
    claimedLevels = (prefs.getStringList(_claimedLevelsKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    rumble = prefs.getBool(_rumbleKey) ?? true;
    lastScore = prefs.getInt(_lastScoreKey);
  }

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
    await prefs.setStringList(
      _claimedLevelsKey,
      (claimedLevels.toList()..sort()).map((l) => '$l').toList(),
    );
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
