import '../game/storage.dart';
import '../run/config/tuning_values.dart';

/// Rewarded-ad free coins: +75 per ad (PRD-2.3.1 §5, was 40), max 5/day,
/// 5-minute cooldown (PRD-2.3 §14.2; tunable `shop_ad_coins`,
/// `shop_ad_per_day`, `shop_ad_cooldown_s`).
class FreeCoinsPolicy {
  FreeCoinsPolicy(this._storage);

  static int get reward => TuningValues.current.i('shop_ad_coins');
  static int get maxPerDay => TuningValues.current.i('shop_ad_per_day');
  static Duration get cooldown =>
      Duration(seconds: TuningValues.current.i('shop_ad_cooldown_s'));

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
