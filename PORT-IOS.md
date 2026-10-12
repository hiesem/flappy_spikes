# PORT-IOS — checklist for the iOS port (Flappy Spikes 2.1)

Status 2026-10-08 (WP-6a). iOS is **paused** by owner decision: nothing in `ios/` has been
changed for 2.0 / 2.1. This is the list of what the port has to do once it is reopened. Every
plugin in `pubspec.yaml` supports iOS (ARCH §8); platform code sits behind the small interfaces in
`lib/services/` (`PlatformIdentity`, `Reminders`, `Rumble`, `VersusService`, `RewardedAds`).

iOS builds only happen on the GitHub Actions `macos-14` runner
(`.github/workflows/build.yml:51`, `flutter build ipa --no-codesign`). Run that job first: it shows
which of the items below are build blockers.

## 1. Project setup (`ios/`)

- [ ] **Podfile.** There is none in `ios/`. `flutter build ios` generates one on the macOS runner;
      commit it after the first green build with `platform :ios, '15.0'` (Firebase iOS SDK 12 needs
      iOS 15) and keep `use_frameworks!` as generated.
- [ ] **Deployment target.** `ios/Runner.xcodeproj/project.pbxproj:363/490/541` already say
      `IPHONEOS_DEPLOYMENT_TARGET = 15.0`. Keep Podfile, project and `AppFrameworkInfo.plist` on
      the same value (≥ 15.0 for FlutterFire 4.x / firebase_app_check / cloud_firestore).
- [ ] **`Info.plist`** (`ios/Runner/Info.plist`) has none of:
  - `GADApplicationIdentifier` (the AdMob iOS app id; the Google Mobile Ads SDK aborts at launch
    without it — that is why `Monetization.forPlatform` uses `NoopRewardedAds` on iOS, see §3);
  - `SKAdNetworkItems` (Google's list plus the partner networks, from the AdMob iOS guide);
  - `NSUserTrackingUsageDescription` (the ATT prompt text; the UMP consent flow can show the IDFA
    explainer — configure the "IDFA message" in AdMob → Privacy & messaging);
  - `UIBackgroundModes` is **not** needed (local notifications only).
- [ ] **`UIStatusBarHidden`** is `false` (`Info.plist:65`); the game hides the status bar with
      `SystemChrome.setEnabledSystemUIMode` (`lib/main.dart:32`). Set `UIStatusBarHidden = true`
      to avoid a status-bar flash at launch.
- [ ] **Firebase.** No `ios/Runner/GoogleService-Info.plist`, and
      `lib/firebase_options.dart:28` throws `UnsupportedError` for iOS. Register the iOS app in
      `flappy-spikes-a2b55` (`flutterfire configure --platforms=ios`), which writes both. Until then
      `GameServices.initialize()` (`lib/services/game_services.dart:87`) catches the throw and
      analytics is a no-op.
- [ ] **App Check.** Register the iOS app in App Check with **App Attest** (DeviceCheck as the
      fallback). The client is already wired: `lib/services/firebase_versus_backend.dart:45`
      (`AppleDebugProvider` in debug / `FS_E2E`, `AppleAppAttestWithDeviceCheckFallbackProvider` in
      release). Add the App Attest capability (`com.apple.developer.devicecheck.appattest-environment
      = production`) to `ios/Runner/Runner.entitlements`, which today only has Game Center.
      Register the iOS debug token for CI / device e2e like the Android one.
- [ ] **Notifications.** Local only, so no `aps-environment` entitlement is needed. If remote
      push is ever added: the `aps-environment` entitlement + an APNs key in Firebase.
      `flutter_local_notifications` iOS setup: in `AppDelegate.swift` set
      `UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate`
      (plugin README, "iOS setup") so reminders show while the app is in the foreground and taps
      reach `onDidReceiveNotificationResponse`.
- [ ] **Notification sound.** Add `notif_chime.caf` (convert `android/app/src/main/res/raw/
      notif_chime.ogg`; ≤ 30 s, linear PCM / IMA4 / µLaw / aLaw) to the Runner target's bundle
      resources. `lib/services/reminders.dart:813` already names it.
- [ ] **App icon / splash.** `flutter_launcher_icons` and `flutter_native_splash` have `ios: true`
      (`pubspec.yaml:113/122`); re-run both after `ios/` is touched and check
      `Assets.xcassets/AppIcon.appiconset` has no alpha in the 1024 icon.

## 2. Accounts and stores

- [ ] **Game Center ↔ Firebase Auth.** `GameCenterIdentity` (`lib/services/identity.dart:77`) is a
      stub (no player, no credential). Implement it with `GameAuth.player` (never `GameAuth.signIn()`
      at launch, never `GameAuth.isSignedIn` — CLAUDE.md) and `GameCenterAuthProvider.credential()`;
      enable the Game Center provider in Firebase Auth; pass `identity: GameCenterIdentity()` when
      building `FirebaseVersusService` (`lib/services/versus_service.dart:211` defaults to
      `PlayGamesIdentity`).
- [ ] **Leaderboard** id `flappy_spikes_leaderboard` (`lib/services/game_services.dart:66`) must
      exist in App Store Connect (it is the 2014 id).
- [ ] **In-app purchase** `no_ads` (`lib/services/iap_service.dart:18`) and the coin packs must be
      created in App Store Connect with the same product ids.
- [ ] **AdMob.** Create the iOS app + rewarded unit; replace the Google test unit
      `iosTestUnitId` (`lib/services/ads_service.dart:156`) together with the Android ids at
      release time.
- [ ] **Privacy.** App Store privacy labels = the Play data-safety form (analytics, ads id,
      versus: nickname / avatar URL / runs, `deleteMyData`). Privacy manifest
      (`PrivacyInfo.xcprivacy`) for required-reason APIs (shared_preferences → UserDefaults).
- [ ] **Store screenshots.** Only Android sets exist (`store/screenshots/`,
      `store/screenshots_tablet/`, made by `test/screenshot_generator_test.dart` and
      `test/tablet_screenshot_generator_test.dart`). App Store needs 6.9" (1320×2868) and 13" iPad
      (2064×2752) sets: add those sizes to the generator tests (same harness, new canvas sizes).

## 3. Android-only code paths (scan of `lib/`, 2026-10-08)

| Where | What | Fix for iOS |
|---|---|---|
| `lib/main.dart:63` + `:117` | Versus (`FirebaseVersusService`) only when `Platform.isAndroid`; iOS gets `NoopVersusService` | Use `_isMobile` and pass `identity: Platform.isIOS ? const GameCenterIdentity() : null` once §1 Firebase + App Check are in place |
| `lib/services/monetization.dart:35` | `Platform.isAndroid ? AdMobRewardedAds() : NoopRewardedAds()` — no ads on iOS | `AdMobRewardedAds()` on both after `GADApplicationIdentifier` + SKAdNetwork are in `Info.plist` (remove the `TODO(ios)`) |
| `lib/services/ads_service.dart:169` | iOS unit id switch exists; uses the Google test unit | Real iOS unit id at release |
| `lib/firebase_options.dart:28` | `UnsupportedError` for iOS | `flutterfire configure --platforms=ios` |
| `lib/services/firebase_versus_backend.dart:40–48` | App Check: Play Integrity / Android debug provider | Apple providers already set — only console registration (§1) |
| `lib/services/identity.dart:48`, `:77` | `PlayGamesIdentity` (Play Games auth code); Game Center stub | Implement `GameCenterIdentity` (§2) |
| `lib/services/reminders.dart:688`, `:703–711`, `:740–751` | Android notification channel `reminders`, `RawResourceAndroidNotificationSound('notif_chime')` (`res/raw/notif_chime.ogg` + `res/raw/keep.xml`), small icon `ic_notif_bird` / large icon `ic_notif_large` (`res/drawable-*`) | iOS has no channels / small icons: nothing to port; add `notif_chime.caf` (§1). Darwin settings already exist (`:726`, `:813`) |
| `lib/services/reminders.dart:726` | `DarwinInitializationSettings(request*Permission: false)` | Keep false: the game asks once through `requestPermissionIfNeeded()` (`:771`, `IOSFlutterLocalNotificationsPlugin.requestPermissions`) |
| `lib/services/reminders.dart:817` | `AndroidScheduleMode.inexactAllowWhileIdle` | Android-only parameter, ignored on iOS. iOS caps pending local notifications at 64 — the plan keeps ≤ 14, fine |
| `lib/game/rumble.dart:95` | `Vibration.vibrate(duration, amplitude)`; amplitude only when `hasAmplitudeControl` | On iOS the `vibration` plugin maps to Core Haptics where available; check knock (15 ms / 90) vs shake (45 ms / 255) feel on an iPhone. If they feel the same, put a `HapticFeedback.lightImpact()` / `heavyImpact()` path behind `Rumble` for iOS |
| `lib/main.dart:81` | Reminders already run on iOS (`_isMobile`) | Works once the AppDelegate delegate (§1) is set; verify the permission prompt timing |
| `lib/game/flappy_game.dart:208` | Debug panel on Linux / debug builds | Nothing (no Android branch) |
| `assets/audio/` | 169 mp3 + 6 wav, no ogg in the game assets | Plays on iOS (AVPlayer). Loops are wav on purpose (`docs/gameplay-v2/SOUNDS.md`) |
| `lib/main.dart` `SystemBackObserver` (PRD-2.2 §8) | Android system back (`WidgetsBindingObserver.didPopRoute`) goes to the game's back stack and is always reported as handled. The manifest keeps predictive back off (`enableOnBackInvokedCallback` unset) | iOS has no system back: `didPopRoute` is never called, so nothing to port. No `ios/` edits |
| `android/app/src/main/AndroidManifest.xml:10–22` | `AD_ID`, `VIBRATE`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`; Play Games app id meta-data; notification receivers | iOS equivalents: ATT string, notification permission at runtime, Game Center capability (already in `Runner.entitlements`) |

## 4. Verification on iOS

- `flutter analyze`, `flutter test` (platform-independent; already green).
- `integration_test/release_e2e_test.dart` on an iPhone (`-d <udid> --dart-define=FS_E2E=true`):
  the journey, element sweep and rides are platform-independent. The reminders and versus-live
  tests are Android-gated today (`_isAndroid` in the test): widen them to iOS when §1 is done.
  Screenshots land in the app's temp dir.
- Real-device checks: Game Center sign-in from the leaderboard button only, App Attest token
  accepted by Firestore / the `deleteMyData` callable, ATT + UMP order, reminder sound, rumble
  feel, notch / Dynamic Island against the 44 pt top spike strip.
