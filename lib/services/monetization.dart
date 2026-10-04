import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'ads_service.dart';
import 'iap_service.dart';

/// Rewarded ads + in-app purchases, bundled so the game takes one object.
///
/// The default constructor uses the in-memory fakes ([FakeRewardedAds],
/// [FakeIapService]) — tests never touch a plugin. Only
/// [Monetization.forPlatform] (called from main()) picks the real AdMob and
/// store implementations, and only on Android/iOS.
class Monetization {
  Monetization({RewardedAds? ads, IapService? iap})
    : ads = ads ?? FakeRewardedAds(),
      iap = iap ?? FakeIapService();

  /// Real plugins on Android/iOS; fakes everywhere else (Linux desktop test
  /// target, web), where neither plugin has an implementation. Both the
  /// target platform AND the host OS must be mobile, so a test that overrides
  /// `debugDefaultTargetPlatformOverride` still gets the fakes.
  factory Monetization.forPlatform() {
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (Platform.isAndroid || Platform.isIOS);
    if (mobile) {
      // iOS is paused and Info.plist has no GADApplicationIdentifier yet (the
      // iOS ads SDK aborts at launch without it): no ads there until reopened.
      // TODO(ios): add GADApplicationIdentifier, then use AdMob on iOS too.
      return Monetization(
        ads: Platform.isAndroid ? AdMobRewardedAds() : NoopRewardedAds(),
        iap: StoreIapService(),
      );
    }
    return Monetization();
  }

  final RewardedAds ads;
  final IapService iap;

  /// Show a visible stand-in ad (FakeAdOverlay: "TEST AD", 3 s countdown)
  /// when the fakes are in use. Off by default so tests keep the instant
  /// fake; the app shell turns it on for non-mobile platforms (Linux).
  bool showFakeAdOverlay = false;

  /// True when both services are the in-memory fakes (the debug panel uses
  /// this to offer its fake-mode switches).
  bool get isFake => ads is FakeRewardedAds && iap is FakeIapService;

  /// Initializes both services. Never throws, so it is safe to call
  /// unawaited; the store is set up independently of (and concurrently
  /// with) the ads consent flow.
  Future<void> initialize() async {
    await Future.wait([_guard(ads.initialize), _guard(iap.initialize)]);
  }

  static Future<void> _guard(Future<void> Function() init) async {
    try {
      await init();
    } catch (e) {
      debugPrint('Monetization initialize failed: $e');
    }
  }
}
