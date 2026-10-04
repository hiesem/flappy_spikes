import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Where a rewarded ad was requested from. Shop free coins and the home
/// powerup slot belong to the menu (PRD-1); revive and 2× coins to gameplay.
enum AdPlacement { shopFreeCoins, homeSlot, revive, doubleCoins }

extension AdPlacementName on AdPlacement {
  /// Analytics parameter value for this placement.
  String get analyticsName => switch (this) {
    AdPlacement.shopFreeCoins => 'shop_free_coins',
    AdPlacement.homeSlot => 'home_slot',
    AdPlacement.revive => 'revive',
    AdPlacement.doubleCoins => 'double_coins',
  };
}

/// Outcome of [RewardedAds.show].
enum AdResult {
  /// The ad played and the user earned the reward — grant it.
  completed,

  /// The ad was displayed but closed without the reward: it counts for the
  /// show rate, but grants nothing.
  dismissed,

  /// An ad was attempted but never displayed (failed to load, failed to
  /// show, plugin error).
  failed,

  /// No ad was ready (not loaded yet, no fill, no consent, not initialized).
  unavailable,
}

/// Rewarded-ad service. The game only ever talks to this interface, so
/// tests and desktop builds run with [NoopRewardedAds] / [FakeRewardedAds]
/// and never touch the plugin.
///
/// Frequency caps (free coins: max 5/day, 5-minute cooldown; per-hour
/// ceiling, see ADS_RESEARCH.md) are the CALLER's job — this layer only
/// loads and plays ads.
abstract class RewardedAds {
  /// Sets the ad stack up (consent, SDK init, first preload). Never throws.
  Future<void> initialize();

  /// Whether an ad is loaded and ready to [show] right now.
  bool get isAvailable;

  /// Plays a rewarded ad. Never throws. Returns [AdResult.completed] only
  /// when the reward was earned.
  ///
  /// [onShown] is called at most once, the moment the ad is actually
  /// DISPLAYED (AdMob: `onAdShowedFullScreenContent`) — before the returned
  /// future completes and independent of reward or dismissal. It is never
  /// called for an ad that fails to load or show. Impression analytics hang
  /// off it (PRD-1 §6/§8, DECISIONS #16).
  Future<AdResult> show(AdPlacement placement, {void Function()? onShown});
}

/// Calls an [RewardedAds.show] `onShown` hook, swallowing anything it
/// throws: a listener must never break ad playback.
void _notifyShown(void Function()? onShown) {
  if (onShown == null) return;
  try {
    onShown();
  } catch (e) {
    debugPrint('RewardedAds onShown listener threw: $e');
  }
}

/// Ads disabled: never available.
class NoopRewardedAds implements RewardedAds {
  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => false;

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async => AdResult.unavailable;
}

/// Behaviour of [FakeRewardedAds.show].
enum FakeAdMode { succeed, fail, unavailable }

/// Scriptable in-memory ads for tests, Linux and the debug panel.
class FakeRewardedAds implements RewardedAds {
  FakeAdMode mode = FakeAdMode.succeed;

  /// Simulated ad length.
  Duration delay = Duration.zero;

  /// Number of ads "played" (succeed and fail modes; unavailable plays
  /// nothing and is not counted).
  int shown = 0;

  /// Placements of the played ads, in order.
  final List<AdPlacement> placements = [];

  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => mode != FakeAdMode.unavailable;

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async {
    if (mode == FakeAdMode.unavailable) {
      return AdResult.unavailable;
    }
    shown++;
    placements.add(placement);
    // Succeed mode "displays" an ad for [delay]; fail mode never displays.
    if (mode == FakeAdMode.succeed) {
      _notifyShown(onShown);
    }
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return mode == FakeAdMode.succeed ? AdResult.completed : AdResult.failed;
  }
}

/// AdMob rewarded ads via `google_mobile_ads`.
///
/// [initialize] runs the UMP consent flow, initializes the SDK only when
/// consent allows ad requests, and preloads ONE rewarded ad; a new one is
/// loaded after every show and every failure (load failures back off).
/// Every plugin call is try/caught: ads must never take the game down.
///
/// TODO(before-release): the unit IDs below are Google's official TEST
/// rewarded units, and the app ID in AndroidManifest.xml is the test app ID.
/// Keep them for closed testing (ADS_RESEARCH.md checklist #1/#3); swap in
/// the real AdMob IDs only for the production release, and gate ad loading
/// on the Play pre-launch / Test Lab / monkey checks (checklist "Trigger 4",
/// needs a native method channel in MainActivity) before that.
class AdMobRewardedAds implements RewardedAds {
  // TODO(before-release): replace with the production rewarded unit IDs.
  static const String androidTestUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosTestUnitId = 'ca-app-pub-3940256099942544/1712485313';

  /// Longest wait between load retries after a failed load.
  static const Duration maxRetryDelay = Duration(minutes: 5);

  RewardedAd? _ad;
  bool _initialized = false;
  bool _canRequestAds = false;
  bool _loading = false;
  bool _showing = false;
  int _loadFailures = 0;
  Timer? _retryTimer;

  String get _unitId => defaultTargetPlatform == TargetPlatform.iOS
      ? iosTestUnitId
      : androidTestUnitId;

  @override
  bool get isAvailable => _ad != null && !_showing;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _gatherConsent();
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('AdMobRewardedAds canRequestAds failed: $e');
      _canRequestAds = false;
    }
    if (!_canRequestAds) {
      return;
    }
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdMobRewardedAds MobileAds.initialize failed: $e');
      _canRequestAds = false;
      return;
    }
    _load();
  }

  /// UMP: refresh the consent info and show the form when it is required
  /// (EEA/UK). Completes when the flow is done, whatever the outcome — a
  /// failure falls back to the previous session's consent state.
  Future<void> _gatherConsent() async {
    final done = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
              if (formError != null) {
                debugPrint(
                  'AdMobRewardedAds consent form: ${formError.message}',
                );
              }
            });
          } catch (e) {
            debugPrint('AdMobRewardedAds consent form failed: $e');
          }
          if (!done.isCompleted) done.complete();
        },
        (error) {
          debugPrint('AdMobRewardedAds consent update: ${error.message}');
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (e) {
      debugPrint('AdMobRewardedAds consent update failed: $e');
      if (!done.isCompleted) done.complete();
    }
    return done.future;
  }

  void _load() {
    if (!_canRequestAds || _loading || _ad != null) {
      return;
    }
    _loading = true;
    try {
      RewardedAd.load(
        adUnitId: _unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            _loadFailures = 0;
            _ad = ad;
            try {
              // The game hides the system bars; keep them hidden over ads.
              ad.setImmersiveMode(true);
            } catch (_) {}
          },
          onAdFailedToLoad: (error) {
            _loading = false;
            debugPrint('AdMobRewardedAds load failed: ${error.message}');
            _scheduleRetry();
          },
        ),
      ).catchError((Object e) {
        _loading = false;
        debugPrint('AdMobRewardedAds load threw: $e');
        _scheduleRetry();
      });
    } catch (e) {
      _loading = false;
      debugPrint('AdMobRewardedAds load threw: $e');
      _scheduleRetry();
    }
  }

  /// Exponential backoff (10 s, 20 s, 40 s … capped at [maxRetryDelay]) so
  /// a no-fill streak never hammers the ad server.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _loadFailures++;
    final seconds = 10 * (1 << (_loadFailures - 1).clamp(0, 5));
    final delay = Duration(seconds: seconds) < maxRetryDelay
        ? Duration(seconds: seconds)
        : maxRetryDelay;
    _retryTimer = Timer(delay, _load);
  }

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async {
    final ad = _ad;
    if (ad == null || _showing) {
      _load();
      return AdResult.unavailable;
    }
    _ad = null;
    _showing = true;
    var earned = false;
    var displayed = false;
    final result = Completer<AdResult>();
    void finish(AdResult r) {
      if (!result.isCompleted) result.complete(r);
    }

    try {
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdShowedFullScreenContent: (ad) {
          if (displayed || result.isCompleted) return;
          displayed = true;
          _notifyShown(onShown);
        },
        onAdDismissedFullScreenContent: (ad) {
          _dispose(ad);
          finish(earned ? AdResult.completed : AdResult.dismissed);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('AdMobRewardedAds show failed: ${error.message}');
          _dispose(ad);
          finish(AdResult.failed);
        },
      );
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          earned = true;
        },
      );
    } catch (e) {
      debugPrint('AdMobRewardedAds show threw: $e');
      _dispose(ad);
      finish(AdResult.failed);
    }
    final r = await result.future;
    _showing = false;
    _load();
    return r;
  }

  void _dispose(RewardedAd ad) {
    try {
      ad.dispose();
    } catch (_) {}
  }
}
