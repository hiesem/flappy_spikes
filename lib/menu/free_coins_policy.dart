import '../game/storage.dart';

/// Rewarded-ad free coins: +40 per ad, max 5/day, 5-minute cooldown.
class FreeCoinsPolicy {
  FreeCoinsPolicy(this._storage);

  static const int reward = 40;
  static const int maxPerDay = 5;
  static const Duration cooldown = Duration(minutes: 5);

  final GameStorage _storage;

  int get claimedToday =>
      _storage.freeCoinsDay == _storage.today ? _storage.freeCoinsCount : 0;

  int get remainingToday => maxPerDay - claimedToday;

  Duration get cooldownRemaining {
    if (_storage.freeCoinsLastMs == 0) return Duration.zero;
    final remainingMs = _storage.freeCoinsLastMs +
        cooldown.inMilliseconds -
        _storage.now().millisecondsSinceEpoch;
    return remainingMs > 0
        ? Duration(milliseconds: remainingMs)
        : Duration.zero;
  }

  bool get canClaim => remainingToday > 0 && cooldownRemaining == Duration.zero;

  /// Records one claim, resetting the daily counter when the day changed.
  Future<void> recordClaim() async {
    final today = _storage.today;
    final count =
        _storage.freeCoinsDay == today ? _storage.freeCoinsCount + 1 : 1;
    await _storage.saveFreeCoinsDay(today);
    await _storage.saveFreeCoinsCount(count);
    await _storage.saveFreeCoinsLastMs(_storage.now().millisecondsSinceEpoch);
  }
}
