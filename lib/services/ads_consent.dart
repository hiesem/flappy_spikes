import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'redact.dart';

/// PRD-2.2 §7.10: consent and SDK start-up, shared ONCE by the rewarded,
/// interstitial and banner services (it used to live inside
/// `AdMobRewardedAds`).
///
/// [initialize] runs the UMP flow, initializes the Mobile Ads SDK only when
/// consent allows ad requests, and is safe to call from every service: all
/// calls share one future. [canRequestAds] is a listenable so the services
/// can stop or start loading when the player changes their choice in the
/// privacy options form (§7.9, WP-7b).
abstract class AdsConsent {
  /// Consent + SDK init. Never throws; all callers share one run.
  Future<void> initialize();

  /// True once ads may be requested (consent given or not required, SDK up,
  /// not a Test Lab device).
  ValueListenable<bool> get canRequestAds;

  /// True on Play pre-launch / Firebase Test Lab devices: no ads at all.
  bool get isTestLab;

  /// §7.9: whether Settings must offer "Privacy options" (EEA / UK users).
  bool get privacyOptionsRequired;

  /// §7.9: shows the UMP privacy options form, then re-reads
  /// [canRequestAds]. Returns its new value. Never throws.
  Future<bool> showPrivacyOptions();
}

/// Scriptable consent for tests, Linux and E2E builds.
class FakeAdsConsent implements AdsConsent {
  FakeAdsConsent({
    bool canRequestAds = true,
    this.isTestLab = false,
    this.privacyOptionsRequired = false,
  }) : _can = ValueNotifier<bool>(canRequestAds);

  final ValueNotifier<bool> _can;

  /// Number of [showPrivacyOptions] calls.
  int privacyFormsShown = 0;

  /// What the privacy options form "chooses" (null = no change).
  bool? privacyFormResult;

  @override
  Future<void> initialize() async {}

  @override
  ValueListenable<bool> get canRequestAds => _can;

  /// Tests flip consent.
  set canRequest(bool value) => _can.value = value;

  @override
  bool isTestLab;

  @override
  bool privacyOptionsRequired;

  @override
  Future<bool> showPrivacyOptions() async {
    privacyFormsShown++;
    final r = privacyFormResult;
    if (r != null) _can.value = r;
    return _can.value;
  }
}

/// UMP + `MobileAds.initialize` via `google_mobile_ads`. Every plugin call is
/// try/caught: ads must never take the game down.
class AdMobAdsConsent implements AdsConsent {
  AdMobAdsConsent();

  static const MethodChannel _device = MethodChannel('flappy_spikes/device');

  final ValueNotifier<bool> _can = ValueNotifier<bool>(false);
  Future<void>? _init;
  bool _sdkStarted = false;
  bool _testLab = false;
  bool _privacyRequired = false;

  @override
  ValueListenable<bool> get canRequestAds => _can;

  @override
  bool get isTestLab => _testLab;

  @override
  bool get privacyOptionsRequired => _privacyRequired;

  @override
  Future<void> initialize() => _init ??= _run();

  Future<void> _run() async {
    if (await _isTestLabDevice()) {
      _testLab = true;
      return;
    }
    await _gatherConsent();
    // iOS: App Tracking Transparency after the UMP flow and before the
    // Mobile Ads SDK starts (Google's order for UMP + ATT).
    await _requestTrackingAuthorization();
    await _readPrivacyStatus();
    await _refreshCanRequest();
  }

  /// iOS only: the ATT prompt (`NSUserTrackingUsageDescription`), once.
  /// When UMP's IDFA explainer message already led to the prompt, the
  /// status is no longer `notDetermined` and nothing is shown. Never before
  /// the first frame, and only while the app is active (iOS drops a request
  /// made while it is not). Any failure means "not asked": ads then run
  /// without the IDFA. Never throws.
  Future<void> _requestTrackingAuthorization() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final binding = WidgetsBinding.instance;
      await binding.waitUntilFirstFrameRasterized;
      if (binding.lifecycleState != AppLifecycleState.resumed) {
        final resumed = Completer<void>();
        final listener = AppLifecycleListener(
          onResume: () {
            if (!resumed.isCompleted) resumed.complete();
          },
        );
        try {
          await resumed.future.timeout(const Duration(seconds: 30));
        } on TimeoutException {
          return;
        } finally {
          listener.dispose();
        }
      }
      if (await AppTrackingTransparency.trackingAuthorizationStatus !=
          TrackingStatus.notDetermined) {
        return;
      }
      // A UMP form that just closed is still animating out: the ATT alert
      // only shows once it is gone (plugin README).
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (e) {
      debugPrint('AdsConsent ATT request failed: ${redactSecrets(e)}');
    }
  }

  /// Re-reads `canRequestAds` and starts the SDK the first time it is true.
  Future<void> _refreshCanRequest() async {
    var can = false;
    try {
      can = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('AdsConsent canRequestAds failed: ${redactSecrets(e)}');
    }
    if (can && !_sdkStarted) {
      try {
        // §7.5.3: the owner's own phones get test ads through the AdMob
        // console's test-device list (run 17: no device ids in the code).
        await MobileAds.instance.initialize();
        _sdkStarted = true;
      } catch (e) {
        debugPrint('AdsConsent MobileAds.initialize failed: ${redactSecrets(e)}');
        can = false;
      }
    }
    _can.value = can;
  }

  Future<void> _readPrivacyStatus() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      _privacyRequired = status == PrivacyOptionsRequirementStatus.required;
    } catch (e) {
      debugPrint('AdsConsent privacy status failed: ${redactSecrets(e)}');
      _privacyRequired = false;
    }
  }

  @override
  Future<bool> showPrivacyOptions() async {
    final done = Completer<void>();
    try {
      await ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          debugPrint(
            'AdsConsent privacy form: ${redactSecrets(formError.message)}',
          );
        }
        if (!done.isCompleted) done.complete();
      });
    } catch (e) {
      debugPrint('AdsConsent privacy form failed: ${redactSecrets(e)}');
      if (!done.isCompleted) done.complete();
    }
    await done.future;
    await _refreshCanRequest();
    return _can.value;
  }

  /// True on Play pre-launch report / Firebase Test Lab devices (Android
  /// system setting `firebase.test.lab`). Robot taps on real ads there would
  /// count as invalid traffic, so ads stay off. Any failure means "not".
  Future<bool> _isTestLabDevice() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _device.invokeMethod<bool>('isTestLab') ?? false;
    } catch (e) {
      debugPrint('AdsConsent isTestLab check failed: ${redactSecrets(e)}');
      return false;
    }
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
            'AdsConsent consent form: ${redactSecrets(formError.message)}',
          );
              }
            });
          } catch (e) {
            debugPrint('AdsConsent consent form failed: ${redactSecrets(e)}');
          }
          if (!done.isCompleted) done.complete();
        },
        (error) {
          debugPrint(
            'AdsConsent consent update: ${redactSecrets(error.message)}',
          );
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (e) {
      debugPrint('AdsConsent consent update failed: ${redactSecrets(e)}');
      if (!done.isCompleted) done.complete();
    }
    return done.future;
  }
}
