import 'package:shared_preferences/shared_preferences.dart';

/// Persistence layer for bestScore / gamesPlayed / muteSound / musicVolume and
/// the 2.0 menu state (coins, skins, powerup slot, no-ads popup, free coins).
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

  /// [slotHistory] keeps at most this many entries (most recent last).
  static const int _maxSlotHistory = 3;

  final DateTime Function() _clock;

  int bestScore = 0;
  int gamesPlayed = 0;
  bool muteSound = false;
  double musicVolume = 0.6;

  int coins = 0;
  Set<String> ownedSkins = {'pink'};
  String equippedSkin = 'pink';
  Set<String> seenSkins = {};
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
    ownedSkins = (prefs.getStringList(_ownedSkinsKey) ?? const ['pink']).toSet()
      ..add('pink');
    equippedSkin = prefs.getString(_equippedSkinKey) ?? 'pink';
    if (!ownedSkins.contains(equippedSkin)) equippedSkin = 'pink';
    seenSkins = (prefs.getStringList(_seenSkinsKey) ?? const []).toSet();
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
  }

  Future<void> saveBestScore(int value) async {
    bestScore = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestScoreKey, value);
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

  /// 'pink' is always kept in the owned set.
  Future<void> saveOwnedSkins(Set<String> value) async {
    ownedSkins = {...value, 'pink'};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ownedSkinsKey, ownedSkins.toList());
  }

  Future<void> saveEquippedSkin(String value) async {
    equippedSkin = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedSkinKey, value);
  }

  Future<void> saveSeenSkins(Set<String> value) async {
    seenSkins = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenSkinsKey, seenSkins.toList());
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

  /// Debug-panel reset: clears the menu economy/skin/powerup/popup state but
  /// keeps progression, sound settings and the install day.
  Future<void> resetMenuState() async {
    await saveCoins(0);
    await saveOwnedSkins({'pink'});
    await saveEquippedSkin('pink');
    await saveSeenSkins({});
    await saveNoAds(false);
    await saveArmedPowerup('none');
    await saveSlotHistory(const []);
    await saveNoAdsPopupLastDay(-1);
    await saveNoAdsPopupDismissals(0);
    await saveFreeCoinsDay(-1);
    await saveFreeCoinsCount(0);
    await saveFreeCoinsLastMs(0);
  }

  List<String> _capSlotHistory(List<String> value) =>
      value.length > _maxSlotHistory
          ? value.sublist(value.length - _maxSlotHistory)
          : List.of(value);
}
