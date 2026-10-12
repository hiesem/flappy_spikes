import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_consent.dart';

export 'ads_consent.dart';

/// Where a rewarded ad was requested from. Shop free coins and the home
/// powerup slot belong to the menu (PRD-1); revive and the balloon bonus to
/// gameplay (PRD-2; the results-page 2× coins ad was removed, §3.14).
enum AdPlacement {
  shopFreeCoins,
  homeSlot,
  revive,
  // PRD-2 §3.15 balloon bonus extra pops (WP-0b).
  bonusFeathers,
}

extension AdPlacementName on AdPlacement {
  /// Analytics parameter value for this placement.
  String get analyticsName => switch (this) {
    AdPlacement.shopFreeCoins => 'shop_free_coins',
    AdPlacement.homeSlot => 'home_slot',
    AdPlacement.revive => 'revive',
    AdPlacement.bonusFeathers => 'bonus_feathers',
  };
}

/// Outcome of [RewardedAds.show] / [InterstitialAds.show].
enum AdResult {
  /// The ad played and the user earned the reward — grant it. For an
  /// interstitial: it was displayed and closed.
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

// ---------------------------------------------------------------------------
// Unit IDs (PRD-2.2 §7.3)
// ---------------------------------------------------------------------------

/// Release builds use the real Android unit; debug / profile builds and iOS
/// (paused, unused) always use Google's official TEST units, so development
/// taps never hit real ads (PRD-2.2 §7.3 item 5).
@visibleForTesting
String pickAdUnit({
  required String release,
  required String test,
  required String iosTest,
  bool? releaseMode,
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.iOS) return iosTest;
  return (releaseMode ?? kReleaseMode) ? release : test;
}

/// Exponential backoff (10 s, 20 s, 40 s … capped at [max]) so a no-fill
/// streak never hammers the ad server.
Duration _retryDelay(int failures, Duration max) {
  final seconds = 10 * (1 << (failures - 1).clamp(0, 5));
  final d = Duration(seconds: seconds);
  return d < max ? d : max;
}

/// Calls an `onShown` hook, swallowing anything it throws: a listener must
/// never break ad playback.
void _notifyShown(void Function()? onShown) {
  if (onShown == null) return;
  try {
    onShown();
  } catch (e) {
    debugPrint('Ads onShown listener threw: $e');
  }
}

// ---------------------------------------------------------------------------
// Rewarded
// ---------------------------------------------------------------------------

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

  /// PRD-2.2 §7.8: starts a load if none is running and waits up to
  /// [timeout] for an ad. Returns [isAvailable] at the end. Never throws.
  Future<bool> ensureLoaded({Duration timeout});

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

/// Ads disabled: never available.
class NoopRewardedAds implements RewardedAds {
  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => false;

  @override
  Future<bool> ensureLoaded({Duration timeout = Duration.zero}) async => false;

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async => AdResult.unavailable;
}

/// Behaviour of the fakes' `show`.
enum FakeAdMode { succeed, fail, unavailable }

/// Scriptable in-memory ads for tests, Linux and the debug panel.
class FakeRewardedAds implements RewardedAds {
  FakeAdMode mode = FakeAdMode.succeed;

  /// Simulated ad length.
  Duration delay = Duration.zero;

  /// §7.8 tests: while [mode] is [FakeAdMode.unavailable], an
  /// [ensureLoaded] call "loads" an ad after this long (null = never).
  Duration? loadsAfter;

  /// Number of [ensureLoaded] calls.
  int loadRequests = 0;

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
  Future<bool> ensureLoaded({Duration timeout = Duration.zero}) async {
    loadRequests++;
    if (isAvailable) return true;
    final after = loadsAfter;
    if (after == null || after > timeout) {
      if (timeout > Duration.zero) await Future<void>.delayed(timeout);
      return isAvailable;
    }
    if (after > Duration.zero) await Future<void>.delayed(after);
    mode = FakeAdMode.succeed;
    loadsAfter = null;
    return true;
  }

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

/// One preloaded full-screen AdMob ad (rewarded or interstitial): load on
/// demand, reload after every show and every failure (failures back off),
/// never two loads at once. Stops loading while consent is withdrawn.
abstract class _AdMobFullScreenLoader<T extends AdWithoutView> {
  _AdMobFullScreenLoader(this.consent);

  final AdsConsent consent;

  /// Longest wait between load retries after a failed load.
  static const Duration maxRetryDelay = Duration(minutes: 5);

  T? _ad;
  bool _initialized = false;
  bool _loading = false;
  bool _showing = false;
  int _loadFailures = 0;
  Timer? _retryTimer;
  final List<Completer<void>> _waiters = [];

  String get unitId;
  String get logName;

  /// Starts the platform load; calls [_loaded] / [_failed].
  Future<void> startLoad(String unitId);

  bool get _can => consent.canRequestAds.value && !consent.isTestLab;

  bool get isAvailable => _ad != null && !_showing;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await consent.initialize();
    consent.canRequestAds.addListener(_onConsent);
    _load();
  }

  void _onConsent() {
    if (_can) {
      _load();
    } else {
      // §7.9: consent withdrawn → stop loading new ads.
      _retryTimer?.cancel();
    }
  }

  void _load() {
    if (!_can || _loading || _ad != null) return;
    _loading = true;
    try {
      startLoad(unitId).catchError((Object e) {
        _failed('load threw: $e');
      });
    } catch (e) {
      _failed('load threw: $e');
    }
  }

  void _loaded(T ad) {
    _loading = false;
    _loadFailures = 0;
    _ad = ad;
    try {
      // The game hides the system bars; keep them hidden over ads.
      switch (ad) {
        case RewardedAd a:
          a.setImmersiveMode(true);
        case InterstitialAd a:
          a.setImmersiveMode(true);
      }
    } catch (_) {}
    _wake();
  }

  void _failed(String message) {
    _loading = false;
    debugPrint('$logName $message');
    _retryTimer?.cancel();
    _loadFailures++;
    _retryTimer = Timer(_retryDelay(_loadFailures, maxRetryDelay), _load);
  }

  void _wake() {
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete();
    }
    _waiters.clear();
  }

  Future<bool> ensureLoaded({Duration timeout = Duration.zero}) async {
    if (isAvailable) return true;
    if (!_can) return false;
    if (!_loading) {
      // An explicit request skips the backoff wait.
      _retryTimer?.cancel();
      _load();
    }
    if (isAvailable) return true;
    if (timeout <= Duration.zero) return false;
    final w = Completer<void>();
    _waiters.add(w);
    try {
      await w.future.timeout(timeout);
    } on TimeoutException {
      _waiters.remove(w);
    }
    return isAvailable;
  }

  void _dispose(AdWithoutView ad) {
    try {
      ad.dispose();
    } catch (_) {}
  }
}

/// AdMob rewarded ads via `google_mobile_ads`.
///
/// Consent and SDK start-up come from the shared [AdsConsent]; this class
/// preloads ONE rewarded ad and loads a new one right after every show and
/// every failure (load failures back off). Every plugin call is try/caught:
/// ads must never take the game down.
///
/// Release builds use the production AdMob unit (Unity Ads bids on it
/// through AdMob mediation, `gma_mediation_unity`); debug/profile builds keep
/// Google's official TEST units so development taps never hit real ads.
/// Nothing loads on Play pre-launch / Firebase Test Lab devices.
class AdMobRewardedAds extends _AdMobFullScreenLoader<RewardedAd>
    implements RewardedAds {
  AdMobRewardedAds({AdsConsent? consent})
    : super(consent ?? AdMobAdsConsent());

  /// Production rewarded unit "Rewarded - all placements" (app
  /// `ca-app-pub-2660521344509391~8153764631`). iOS has no production unit
  /// yet (iOS paused) and only ever runs [NoopRewardedAds].
  static const String androidUnitId = 'ca-app-pub-2660521344509391/3758032081';
  static const String androidTestUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosTestUnitId = 'ca-app-pub-3940256099942544/1712485313';

  /// Longest wait between load retries after a failed load.
  static const Duration maxRetryDelay = _AdMobFullScreenLoader.maxRetryDelay;

  @override
  String get unitId => pickAdUnit(
    release: androidUnitId,
    test: androidTestUnitId,
    iosTest: iosTestUnitId,
  );

  @override
  String get logName => 'AdMobRewardedAds';

  @override
  Future<void> startLoad(String unitId) => RewardedAd.load(
    adUnitId: unitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: _loaded,
      onAdFailedToLoad: (error) => _failed('load failed: ${error.message}'),
    ),
  );

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
    // §7.8: the next ad starts loading right after every show.
    _load();
    return r;
  }
}

// ---------------------------------------------------------------------------
// Interstitial (PRD-2.2 §7.6)
// ---------------------------------------------------------------------------

/// The video ad after each run (PRD-2.2 §7.6). One loaded ad at a time;
/// the GAME owns the guards (NO ADS, first runs, rewarded this run, the
/// 60 s gap, background) — this layer only loads and plays.
abstract class InterstitialAds {
  /// Shares the consent / SDK start-up. Never throws. Does not load: the
  /// game preloads when the bird starts flying ([preload]).
  Future<void> initialize();

  /// Whether an ad is loaded and ready to [show] right now.
  bool get isAvailable;

  /// Starts a load unless one is loaded or loading. Never throws.
  void preload();

  /// Plays the loaded ad. [onShown] fires once when it is displayed.
  /// Returns [AdResult.completed] when it was displayed and closed,
  /// [AdResult.failed] when it failed to show, [AdResult.unavailable] when
  /// none was loaded. Reloads afterwards. Never throws.
  Future<AdResult> show({void Function()? onShown});
}

/// Interstitials disabled (iOS, Test Lab).
class NoopInterstitialAds implements InterstitialAds {
  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => false;

  @override
  void preload() {}

  @override
  Future<AdResult> show({void Function()? onShown}) async =>
      AdResult.unavailable;
}

/// Scriptable in-memory interstitial for tests, Linux and E2E builds.
/// Unavailable by default ([mode] = unavailable), so tests that do not ask
/// for one never get an interstitial between NEXT and Home.
class FakeInterstitialAds implements InterstitialAds {
  FakeInterstitialAds({this.mode = FakeAdMode.unavailable});

  FakeAdMode mode;

  /// Simulated ad length.
  Duration delay = Duration.zero;

  /// While set, [show] waits for this future (tests hold the ad open).
  Future<void>? hold;

  int preloads = 0;
  int shown = 0;

  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => mode != FakeAdMode.unavailable;

  @override
  void preload() => preloads++;

  @override
  Future<AdResult> show({void Function()? onShown}) async {
    if (mode == FakeAdMode.unavailable) return AdResult.unavailable;
    shown++;
    if (mode == FakeAdMode.succeed) _notifyShown(onShown);
    final h = hold;
    if (h != null) await h;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return mode == FakeAdMode.succeed ? AdResult.completed : AdResult.failed;
  }
}

/// AdMob interstitial "Interstitial - after run" via `google_mobile_ads`.
class AdMobInterstitialAds extends _AdMobFullScreenLoader<InterstitialAd>
    implements InterstitialAds {
  AdMobInterstitialAds({AdsConsent? consent})
    : super(consent ?? AdMobAdsConsent());

  /// §7.3: "Interstitial - after run" (text/image/rich media + video;
  /// mediation group 5294815708, Unity `Interstitial_Android`).
  static const String androidUnitId = 'ca-app-pub-2660521344509391/1357627279';
  static const String androidTestUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosTestUnitId = 'ca-app-pub-3940256099942544/4411468910';

  @override
  String get unitId => pickAdUnit(
    release: androidUnitId,
    test: androidTestUnitId,
    iosTest: iosTestUnitId,
  );

  @override
  String get logName => 'AdMobInterstitialAds';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await consent.initialize();
    consent.canRequestAds.addListener(_onConsent);
    // No load here: §7.6 preloads when the bird starts flying.
  }

  @override
  void _onConsent() {
    if (!_can) _retryTimer?.cancel();
  }

  @override
  void preload() => _load();

  @override
  Future<void> startLoad(String unitId) => InterstitialAd.load(
    adUnitId: unitId,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: _loaded,
      onAdFailedToLoad: (error) => _failed('load failed: ${error.message}'),
    ),
  );

  @override
  Future<AdResult> show({void Function()? onShown}) async {
    final ad = _ad;
    if (ad == null || _showing) return AdResult.unavailable;
    _ad = null;
    _showing = true;
    var displayed = false;
    final result = Completer<AdResult>();
    void finish(AdResult r) {
      if (!result.isCompleted) result.complete(r);
    }

    try {
      ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
        onAdShowedFullScreenContent: (ad) {
          if (displayed || result.isCompleted) return;
          displayed = true;
          _notifyShown(onShown);
        },
        onAdDismissedFullScreenContent: (ad) {
          _dispose(ad);
          finish(AdResult.completed);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('AdMobInterstitialAds show failed: ${error.message}');
          _dispose(ad);
          finish(AdResult.failed);
        },
      );
      await ad.show();
    } catch (e) {
      debugPrint('AdMobInterstitialAds show threw: $e');
      _dispose(ad);
      finish(AdResult.failed);
    }
    final r = await result.future;
    _showing = false;
    // §7.6: load again after each show.
    _load();
    return r;
  }
}

// ---------------------------------------------------------------------------
// Banner (PRD-2.2 §7.5)
// ---------------------------------------------------------------------------

/// The gameplay banner under the playfield (PRD-2.2 §7.5). The game decides
/// WHEN it is shown (`BannerState`); this layer knows the strip size, loads
/// one banner at a time and builds the widget for the app shell's slot.
abstract class BannerAds {
  /// Works the anchored adaptive size out once and shares the consent /
  /// SDK start-up. Never throws.
  Future<void> initialize();

  /// Banner height in dp (null until known, or when there is no banner).
  double? get heightDp;

  /// Screen width in dp the size was worked out for (dp → pt factor:
  /// 320 / [widthDp]).
  double get widthDp;

  /// §7.5.6: whether a banner may be used at all right now (consent, not a
  /// Test Lab device, size known). The game adds NO ADS and E2E.
  bool get canShow;

  /// Whether a banner is loaded and may be mounted.
  ValueListenable<bool> get loaded;

  /// Starts loading one banner (invisible) unless one is loaded / loading.
  void preload();

  /// The ad widget for the slot while [loaded] (null otherwise).
  Widget? buildAd();

  /// Drops the current banner (after a run). The next [preload] loads anew.
  void dispose();

  /// §7.11: called at each `onAdImpression`.
  set onImpression(void Function()? callback);
}

/// No banner (iOS, Test Lab).
class NoopBannerAds implements BannerAds {
  final ValueNotifier<bool> _loaded = ValueNotifier<bool>(false);

  @override
  Future<void> initialize() async {}

  @override
  double? get heightDp => null;

  @override
  double get widthDp => 320;

  @override
  bool get canShow => false;

  @override
  ValueListenable<bool> get loaded => _loaded;

  @override
  void preload() {}

  @override
  Widget? buildAd() => null;

  @override
  void dispose() {}

  @override
  set onImpression(void Function()? callback) {}
}

/// Scriptable in-memory banner for tests, Linux and E2E builds. Off by
/// default ([enabled] false), so tests that do not ask for it keep the
/// full-height playfield.
class FakeBannerAds implements BannerAds {
  FakeBannerAds({
    this.enabled = false,
    this.heightDp = 50,
    this.widthDp = 320,
    this.fill = true,
  });

  /// Whether the banner may be used (consent etc.).
  bool enabled;

  @override
  double? heightDp;

  @override
  double widthDp;

  /// Whether [preload] "fills" (false = no fill: the strip stays empty).
  bool fill;

  int preloads = 0;
  int disposals = 0;
  void Function()? _onImpression;

  final ValueNotifier<bool> _loaded = ValueNotifier<bool>(false);

  @override
  Future<void> initialize() async {}

  @override
  bool get canShow => enabled && heightDp != null;

  @override
  ValueListenable<bool> get loaded => _loaded;

  @override
  void preload() {
    if (!canShow || _loaded.value) return;
    preloads++;
    if (fill) _loaded.value = true;
  }

  /// Tests: the ad network reports an impression.
  void impression() => _onImpression?.call();

  @override
  Widget? buildAd() => _loaded.value ? const FakeBannerWidget() : null;

  @override
  void dispose() {
    disposals++;
    _loaded.value = false;
  }

  @override
  set onImpression(void Function()? callback) => _onImpression = callback;
}

/// The Linux stand-in banner: a light grey strip with "TEST BANNER".
class FakeBannerWidget extends StatelessWidget {
  const FakeBannerWidget({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFE6E6E6),
    alignment: Alignment.center,
    child: const Text(
      'TEST BANNER',
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: Color(0xFF7A6670),
        fontSize: 12,
        letterSpacing: 1.5,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

/// AdMob anchored adaptive banner "Banner - gameplay" via
/// `google_mobile_ads` (PRD-2.2 §7.5.1).
class AdMobBannerAds implements BannerAds {
  AdMobBannerAds({AdsConsent? consent, required this.widthDp})
    : consent = consent ?? AdMobAdsConsent();

  final AdsConsent consent;

  /// §7.3: "Banner - gameplay" (mediation group 7736442819, Unity
  /// `Banner_Android`).
  static const String androidUnitId = 'ca-app-pub-2660521344509391/8797133596';
  static const String androidTestUnitId =
      'ca-app-pub-3940256099942544/9214589741';
  static const String iosTestUnitId = 'ca-app-pub-3940256099942544/2435281174';

  static const Duration maxRetryDelay = Duration(minutes: 5);

  @override
  final double widthDp;

  AdSize? _size;
  BannerAd? _ad;
  BannerAd? _loadedAd;
  bool _initialized = false;
  int _loadFailures = 0;
  Timer? _retryTimer;
  void Function()? _onImpression;
  final ValueNotifier<bool> _loaded = ValueNotifier<bool>(false);

  String get _unitId => pickAdUnit(
    release: androidUnitId,
    test: androidTestUnitId,
    iosTest: iosTestUnitId,
  );

  @override
  double? get heightDp => _size?.height.toDouble();

  @override
  bool get canShow =>
      _size != null && consent.canRequestAds.value && !consent.isTestLab;

  @override
  ValueListenable<bool> get loaded => _loaded;

  @override
  set onImpression(void Function()? callback) => _onImpression = callback;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // The size first, so the strip height is known before the first run
    // even while the consent form is still up.
    await _workOutSize();
    await consent.initialize();
    if (_size == null) await _workOutSize();
    consent.canRequestAds.addListener(_onConsent);
    // §7.5.1: preload on Home as soon as ads may be requested.
    preload();
  }

  Future<void> _workOutSize() async {
    try {
      // PRD-2.2 §7.5.1 names this size (50–62 dp on phones); the newer
      // "large" anchored size is taller and would eat more playfield.
      // ignore: deprecated_member_use
      _size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
        widthDp.truncate(),
      );
    } catch (e) {
      debugPrint('AdMobBannerAds size failed: $e');
    }
  }

  void _onConsent() {
    if (canShow) {
      preload();
    } else {
      _retryTimer?.cancel();
    }
  }

  @override
  void preload() {
    final size = _size;
    if (!canShow || size == null || _ad != null) return;
    _retryTimer?.cancel();
    late final BannerAd ad;
    ad = BannerAd(
      size: size,
      adUnitId: _unitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!identical(_ad, ad)) return;
          _loadFailures = 0;
          _loadedAd = ad;
          _loaded.value = true;
        },
        onAdFailedToLoad: (_, error) {
          debugPrint('AdMobBannerAds load failed: ${error.message}');
          try {
            ad.dispose();
          } catch (_) {}
          if (!identical(_ad, ad)) return;
          _ad = null;
          _loadFailures++;
          _retryTimer = Timer(
            _retryDelay(_loadFailures, maxRetryDelay),
            preload,
          );
        },
        onAdImpression: (_) {
          try {
            _onImpression?.call();
          } catch (_) {}
        },
      ),
    );
    _ad = ad;
    try {
      ad.load().catchError((Object e) {
        debugPrint('AdMobBannerAds load threw: $e');
      });
    } catch (e) {
      debugPrint('AdMobBannerAds load threw: $e');
    }
  }

  @override
  Widget? buildAd() {
    final ad = _loadedAd;
    if (ad == null || !_loaded.value) return null;
    return AdWidget(key: ObjectKey(ad), ad: ad);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    final ad = _ad;
    _ad = null;
    _loadedAd = null;
    _loaded.value = false;
    if (ad != null) {
      try {
        ad.dispose();
      } catch (_) {}
    }
  }
}
