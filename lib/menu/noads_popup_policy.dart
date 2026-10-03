import '../game/storage.dart';

/// Launch-time policy for the no-ads upsell popup.
class NoAdsPopupPolicy {
  NoAdsPopupPolicy(this._storage);

  static const int maxDismissals = 3;

  final GameStorage _storage;

  /// From the day after install, once per day, until three dismissals.
  bool shouldShowOnLaunch() {
    final installDay = _storage.installDay;
    return !_storage.noAds &&
        installDay != null &&
        _storage.today > installDay &&
        _storage.noAdsPopupLastDay != _storage.today &&
        _storage.noAdsPopupDismissals < maxDismissals;
  }

  Future<void> markShown() => _storage.saveNoAdsPopupLastDay(_storage.today);

  Future<void> markDismissed() =>
      _storage.saveNoAdsPopupDismissals(_storage.noAdsPopupDismissals + 1);
}
