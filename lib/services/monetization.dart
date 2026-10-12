import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'ads_service.dart';
import 'iap_service.dart';

/// Ads (rewarded, interstitial, banner — PRD-2.2 §7.10) + in-app purchases,
/// bundled so the game takes one object.
///
/// The default constructor uses the in-memory fakes ([FakeRewardedAds],
/// [FakeInterstitialAds] (unavailable), [FakeBannerAds] (off),
/// [FakeIapService]) — tests never touch a plugin. Only
/// [Monetization.forPlatform] (called from main()) picks the real AdMob and
/// store implementations, and only on Android/iOS.
class Monetization {
  Monetization({
    RewardedAds? ads,
    InterstitialAds? interstitial,
    BannerAds? banner,
    IapService? iap,
    AdsConsent? consent,
  }) : ads = ads ?? FakeRewardedAds(),
       interstitial = interstitial ?? FakeInterstitialAds(),
       banner = banner ?? FakeBannerAds(),
       consent = consent ?? FakeAdsConsent(),
       iap = iap ?? FakeIapService();

  /// Real plugins on Android/iOS; fakes everywhere else (Linux desktop test
  /// target, web), where neither plugin has an implementation. Both the
  /// target platform AND the host OS must be mobile, so a test that overrides
  /// `debugDefaultTargetPlatformOverride` still gets the fakes.
  ///
  /// [bannerWidthDp] is the screen width in dp: the anchored adaptive banner
  /// size is worked out for it (§7.5.1).
  factory Monetization.forPlatform({double bannerWidthDp = 360}) {
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (Platform.isAndroid || Platform.isIOS);
    if (mobile) {
      // iOS is paused and Info.plist has no GADApplicationIdentifier yet (the
      // iOS ads SDK aborts at launch without it): no ads there until reopened.
      // TODO(ios): add GADApplicationIdentifier, then use AdMob on iOS too.
      if (!Platform.isAndroid) {
        return Monetization(
          ads: NoopRewardedAds(),
          interstitial: NoopInterstitialAds(),
          banner: NoopBannerAds(),
          consent: FakeAdsConsent(canRequestAds: false),
          iap: StoreIapService(),
        );
      }
      // §7.10: consent + MobileAds.initialize ONCE, shared by all three.
      final consent = AdMobAdsConsent();
      return Monetization(
        ads: AdMobRewardedAds(consent: consent),
        interstitial: AdMobInterstitialAds(consent: consent),
        banner: AdMobBannerAds(consent: consent, widthDp: bannerWidthDp),
        consent: consent,
        iap: StoreIapService(),
      );
    }
    return Monetization();
  }

  final RewardedAds ads;

  /// PRD-2.2 §7.6: the video ad after each run.
  final InterstitialAds interstitial;

  /// PRD-2.2 §7.5: the gameplay banner.
  final BannerAds banner;

  /// PRD-2.2 §7.10: consent / SDK start-up shared by the three ad services
  /// (the privacy options entry, §7.9, reads it too).
  final AdsConsent consent;

  final IapService iap;

  /// Show a visible stand-in ad (FakeAdOverlay: "TEST AD", 3 s countdown)
  /// when the fakes are in use. Off by default so tests keep the instant
  /// fake; the app shell turns it on for non-mobile platforms (Linux).
  bool showFakeAdOverlay = false;

  /// True when both services are the in-memory fakes (the debug panel uses
  /// this to offer its fake-mode switches).
  bool get isFake => ads is FakeRewardedAds && iap is FakeIapService;

  /// Initializes every service. Never throws, so it is safe to call
  /// unawaited; the store is set up independently of (and concurrently
  /// with) the ads consent flow, which the three ad services share.
  Future<void> initialize() async {
    await Future.wait([
      _guard(ads.initialize),
      _guard(interstitial.initialize),
      _guard(banner.initialize),
      _guard(iap.initialize),
    ]);
  }

  static Future<void> _guard(Future<void> Function() init) async {
    try {
      await init();
    } catch (e) {
      debugPrint('Monetization initialize failed: $e');
    }
  }
}
