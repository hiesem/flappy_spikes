import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  AdMobAdsConsent({List<String> testDeviceIds = kAdTestDeviceIds})
    : _testDeviceIds = [
        for (final id in testDeviceIds)
          if (id.isNotEmpty && !id.startsWith('TODO')) id,
      ];

  final List<String> _testDeviceIds;

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
    await _readPrivacyStatus();
    await _refreshCanRequest();
  }

  /// Re-reads `canRequestAds` and starts the SDK the first time it is true.
  Future<void> _refreshCanRequest() async {
    var can = false;
    try {
      can = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('AdsConsent canRequestAds failed: $e');
    }
    if (can && !_sdkStarted) {
      try {
        // §7.5.3: own devices get test ads even with the real units.
        if (_testDeviceIds.isNotEmpty) {
          await MobileAds.instance.updateRequestConfiguration(
            RequestConfiguration(testDeviceIds: _testDeviceIds),
          );
        }
        await MobileAds.instance.initialize();
        _sdkStarted = true;
      } catch (e) {
        debugPrint('AdsConsent MobileAds.initialize failed: $e');
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
      debugPrint('AdsConsent privacy status failed: $e');
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
      debugPrint('AdsConsent privacy form failed: $e');
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
      debugPrint('AdsConsent isTestLab check failed: $e');
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
            debugPrint('AdsConsent consent form failed: $e');
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
      debugPrint('AdsConsent consent update failed: $e');
      if (!done.isCompleted) done.complete();
    }
    return done.future;
  }
}

/// §7.5.3: hashed AdMob device IDs that always get TEST ads, in every build
/// mode (the owner's Pixel 8 must never show or count a real ad, also not
/// with the release build from internal testing). The hash is printed by the
/// SDK in logcat ("Use RequestConfiguration.Builder().setTestDeviceIds(...)")
/// on the first ad request. Emulators are test devices automatically.
const List<String> kAdTestDeviceIds = <String>[
  // Pixel 8 (38300DLJH004SD), read from logcat 2026-10-12 (docs/p22/ADS.md).
  kPixel8AdTestDeviceId,
];

/// The owner's Pixel 8 (see [kAdTestDeviceIds]).
const String kPixel8AdTestDeviceId = '375F7680953C1B0F47A1FC3E475A9AA1';
