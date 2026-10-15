# PORT-IOS — checklist for the iOS port (Flappy Spikes 2.1)

Status 2026-10-15: iOS **reopened** (branch `feat/ios`). §1–§3 are done in code (marked
below); what is left needs a Mac / an iPhone / App Store Connect (§4 and the unchecked items).
App Store app "Flappy Spikes: Flap Fast" (ASC app id 6823208616), bundle id
`com.flappyspikes.flappyspikes`. Every
plugin in `pubspec.yaml` supports iOS (ARCH §8); platform code sits behind the small interfaces in
`lib/services/` (`PlatformIdentity`, `Reminders`, `Rumble`, `VersusService`, `RewardedAds`).

iOS builds only happen on the GitHub Actions `macos-14` runner
(`.github/workflows/build.yml`: `flutter build ios --config-only`, `pod install`, `xcodebuild
archive`, TestFlight upload). The plugins come in through **Swift Package Manager** (Flutter's
default; `FlutterGeneratedPluginSwiftPackage` in the pbxproj); `ios/Podfile` is the CocoaPods
fallback the workflow's `pod install` needs. Every FlutterFire plugin must pin the same
firebase-ios-sdk (12.19.0 since `firebase_analytics` ^12.6.0) or SPM resolution fails.

## 1. Project setup (`ios/`)

- [x] **Podfile.** Flutter's template with `platform :ios, '15.0'` and `use_frameworks!`; its
      `post_install` pins `IPHONEOS_DEPLOYMENT_TARGET = 15.0` on every pod. `Flutter/Debug.xcconfig`
      / `Release.xcconfig` carry the optional `#include? "Pods/…/Pods-Runner.*.xcconfig"` lines
      flutter_tools would add.
- [x] **Deployment target.** `ios/Runner.xcodeproj/project.pbxproj:363/490/541` already say
      `IPHONEOS_DEPLOYMENT_TARGET = 15.0`. Keep Podfile, project and `AppFrameworkInfo.plist` on
      the same value (≥ 15.0 for FlutterFire 4.x / firebase_app_check / cloud_firestore).
      `AppFrameworkInfo.plist` has no `MinimumOSVersion` key (current Flutter templates dropped it;
      the build sets it), so nothing there can disagree.
- [x] **`Info.plist`** (`ios/Runner/Info.plist`) now has (2026-10-15):
  - `GADApplicationIdentifier` (the AdMob iOS app id; the Google Mobile Ads SDK aborts at launch
    without it — that is why `Monetization.forPlatform` uses `NoopRewardedAds` on iOS, see §3);
  - `SKAdNetworkItems` (Google's list plus the partner networks, from the AdMob iOS guide);
  - `NSUserTrackingUsageDescription` (the ATT prompt text; the UMP consent flow can show the IDFA
    explainer — configure the "IDFA message" in AdMob → Privacy & messaging);
  - `UIBackgroundModes` is **not** needed (local notifications only).
  - also `ITSAppUsesNonExemptEncryption = false`, `UIRequiresFullScreen = true` (portrait-only
    on iPad needs it, else App Store validation asks for all four iPad orientations),
    `CFBundleDisplayName` / `CFBundleName` "Flappy Spikes".
  - `GADApplicationIdentifier` = the AdMob iOS app `ca-app-pub-2660521344509391~7451723332`.
  - `SKAdNetworkItems`: 73 ids, Google's AdMob quick-start list + Unity Ads' list. Re-check both
    lists against the current AdMob / Unity docs before release.
- [x] **`UIStatusBarHidden`** was `false` (`Info.plist:65`); the game hides the status bar with
      `SystemChrome.setEnabledSystemUIMode` (`lib/main.dart:32`). Now `true`.
      **`dart run flutter_native_splash:create` writes it back to `false`** (the splash config has
      no `fullscreen`, which would also change Android): set it to `true` again after a re-run.
- [x] **Firebase.** (Done 2026-10-15: `GoogleService-Info.plist` in the Runner resources,
      `DefaultFirebaseOptions.ios`.) Was: no `ios/Runner/GoogleService-Info.plist`, and
      `lib/firebase_options.dart:28` throws `UnsupportedError` for iOS. Register the iOS app in
      `flappy-spikes-a2b55` (`flutterfire configure --platforms=ios`), which writes both. Until then
      `GameServices.initialize()` (`lib/services/game_services.dart:87`) catches the throw and
      analytics is a no-op.
- [x] **App Check.** (App Attest registered; `Runner.entitlements` has
      `com.apple.developer.devicecheck.appattest-environment = production`; `CODE_SIGN_ENTITLEMENTS`
      is set for Debug / Release / Profile. Still to do: the iOS debug token for CI / device e2e.)
      Register the iOS app in App Check with **App Attest** (DeviceCheck as the
      fallback). The client is already wired: `lib/services/firebase_versus_backend.dart:45`
      (`AppleDebugProvider` in debug / `FS_E2E`, `AppleAppAttestWithDeviceCheckFallbackProvider` in
      release). Add the App Attest capability (`com.apple.developer.devicecheck.appattest-environment
      = production`) to `ios/Runner/Runner.entitlements`, which today only has Game Center.
      Register the iOS debug token for CI / device e2e like the Android one.
- [x] **Notifications.** (`AppDelegate.swift` sets the delegate.) Local only, so no `aps-environment` entitlement is needed. If remote
      push is ever added: the `aps-environment` entitlement + an APNs key in Firebase.
      `flutter_local_notifications` iOS setup: in `AppDelegate.swift` set
      `UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate`
      (plugin README, "iOS setup") so reminders show while the app is in the foreground and taps
      reach `onDidReceiveNotificationResponse`.
- [x] **Notification sound.** (`ios/Runner/notif_chime.caf`, 16-bit PCM, 1 s, in the Runner
      resources.) Add `notif_chime.caf` (convert `android/app/src/main/res/raw/
      notif_chime.ogg`; ≤ 30 s, linear PCM / IMA4 / µLaw / aLaw) to the Runner target's bundle
      resources. `lib/services/reminders.dart:813` already names it.
- [x] **App icon / splash.** (Re-run 2026-10-15: no change; the 1024 icon is RGB, no alpha.) `flutter_launcher_icons` and `flutter_native_splash` have `ios: true`
      (`pubspec.yaml:113/122`); re-run both after `ios/` is touched and check
      `Assets.xcassets/AppIcon.appiconset` has no alpha in the 1024 icon.
      **2.3:** the iOS app icon (`AppIcon.appiconset`, `remove_alpha_ios: true`) and the launch
      image are already the 17C icon (PRD-2.3 §9.3/9.4, owner exception to the iOS pause);
      `tool/render_app_icon.py` re-renders the sources.

## 2. Accounts and stores

- [x] **Game Center ↔ Firebase Auth.** `GameCenterIdentity` (`lib/services/identity.dart`) is
      implemented and `main.dart` builds `FirebaseVersusService(identity: GameCenterIdentity())`
      on iOS. **iOS exception to the no-launch-sign-in rule (round 2, 2026-10-15):** GameKit only
      authenticates once the app sets the local player's authenticate handler (games_services does
      that in `GameAuth.signIn()`), so without a launch sign-in a player signed in to Game Center on
      the device counted as signed out (generated name, no achievement reports, no banner) until
      the first leaderboard / achievements tap. `GameServices.authenticateAtLaunch` (called from
      `main.dart` on iOS only, after `initialize` and the UMP / ATT flow) calls `signIn` once:
      silent for a signed-in player (Apple's "Welcome back" banner), Game Center's own sheet once
      for a signed-out one. **Android keeps the rule** (CLAUDE.md: Play Games shows a profile
      picker). `FirebaseVersusService` follows the player stream from the start of `initialize`,
      so the in-game name (versus intro, results, leaderboard rows) switches to the Game Center
      alias as soon as GameKit reports the player.
      Was: a stub (no player, no credential). Implement it with `GameAuth.player` (never `GameAuth.signIn()`
      at launch, never `GameAuth.isSignedIn` — CLAUDE.md) and `GameCenterAuthProvider.credential()`;
      enable the Game Center provider in Firebase Auth; pass `identity: GameCenterIdentity()` when
      building `FirebaseVersusService` (`lib/services/versus_service.dart:211` defaults to
      `PlayGamesIdentity`).
- [x] **Leaderboard** id is **`fs_top_scores`** (`GameServices.iosLeaderboardId`; created in App
      Store Connect for the new app — no longer the 2014 `flappy_spikes_leaderboard`).
- [ ] **Game Center achievements** (PRD-2.3.1 §12). The shared Dart code already sends the
      Game Center ids (`fs_ach_<key>`, `lib/achievements/achievement_catalog.dart`); the upload kit
      is in `store/achievements/ios/`: `achievements_ios.csv` / `.json` (Reference Name,
      Achievement ID, Points, Hidden, Achievable More Than Once = no, and the English (U.S.)
      Title, Pre-earned Description, Earned Description, Image) and the 48 icons
      `ach_<key>.png` (1024×1024, RGB, no alpha, 72 dpi). Regenerate with
      `dart run tool/ach_ios_kit.dart` (fields) and `tool/export_achievement_icons.py` (icons);
      `test/p231/s12_ios_kit_test.dart` keeps the kit equal to the catalog.
  - [ ] App Store Connect → the app → **Game Center → Achievements**: create the 48 from the kit,
        in the kit order (755 of 1000 points; the 7 rides Hidden = yes).
  - [ ] Attach the 48 achievements (and the leaderboard) to the **first iOS version** before
        submitting it (the version page → Game Center).
  - [ ] Sandbox test: a sandbox Game Center account, unlock a few, check the progress of the
        counting ones (`vs_10`, `vs_50`, `ride_all`, `item_all`, `daily_7`, `daily_30`,
        `skin_all` report `percentComplete` on iOS only); reset with
        `Achievements.resetAchievements()` (a debug-only call; never ship it).
  - [x] Sign-in: as `GameCenterIdentity` above (iOS authenticates at launch, never
        `GameAuth.isSignedIn`); unlocks are stored locally and reported by
        `AchievementTracker.syncAll()` once the player stream has a player, with Apple's native
        completion banner (`showsCompletionBanner: true`; the game's own toast only while signed
        out). The 48 `fs_ach_<key>` ids and points match App Store Connect (checked over the ASC
        API 2026-10-15; none repeatable or archived). Game Center banners an achievement once,
        when it first completes; the local `achReported` set keeps already-confirmed ones from
        being re-sent. The first authenticated launch reports every earlier unlock at once (one
        banner each). Logs: `flutter: FS-GC …` / `flutter: FS-Ach …` in the device console.
- [x] **In-app purchase** (created in App Store Connect with the Android ids; the gift products
      are Play-only: never queried (`kShopProducts`) and Settings → Redeem code is hidden on iOS.
      Settings → Restore purchases exists on every platform (App Store requirement). Consumables
      use `autoConsume: true` on iOS (the StoreKit plugin asserts it).) `no_ads` (`lib/services/iap_service.dart:18`) and the coin packs must be
      created in App Store Connect with the same product ids.
- [x] **AdMob.** iOS app + rewarded / interstitial / banner units exist; `ads_service.dart` has
      `iosUnitId` (release builds) and `iosTestUnitId` (debug / profile), like Android. Still to do:
      the owner's iPhone in `kAdTestDeviceIds` (hash from the Xcode console on the first ad
      request), the Unity iOS placements in the AdMob mediation groups, and the UMP IDFA explainer
      message (AdMob → Privacy & messaging). Ads run on iOS: UMP →
      ATT prompt (`app_tracking_transparency`, after the first frame and only while active, skipped
      when UMP's IDFA message already asked) → `MobileAds.initialize`.
- [ ] **Privacy.** `ios/Runner/PrivacyInfo.xcprivacy` is in the Runner resources (UserDefaults
      CA92.1, FileTimestamp C617.1, SystemBootTime 35F9.1; collected: user id, gameplay content,
      product interaction; the plugins ship their own manifests). Still to do: App Store privacy labels = the Play data-safety form (analytics, ads id,
      versus: nickname / avatar URL / runs, `deleteMyData`). Privacy manifest
      (`PrivacyInfo.xcprivacy`) for required-reason APIs (shared_preferences → UserDefaults).
- [ ] **Store screenshots.** Only Android sets exist (`store/screenshots/`,
      `store/screenshots_tablet/`, made by `test/screenshot_generator_test.dart` and
      `test/tablet_screenshot_generator_test.dart`). App Store needs 6.9" (1320×2868) and 13" iPad
      (2064×2752) sets: add those sizes to the generator tests (same harness, new canvas sizes).

## 3. Android-only code paths (scan of `lib/`, 2026-10-08)

| Where | What | Fix for iOS |
|---|---|---|
| `lib/main.dart:63` + `:117` | Versus (`FirebaseVersusService`) only when `Platform.isAndroid`; iOS gets `NoopVersusService` | Use `_isMobile` and pass `identity: Platform.isIOS ? const GameCenterIdentity() : null` once §1 Firebase + App Check are in place **Done 2026-10-15:** Versus on `_isMobile`, `GameCenterIdentity()` on iOS. |
| `lib/services/monetization.dart:35` | `Platform.isAndroid ? AdMobRewardedAds() : NoopRewardedAds()` — no ads on iOS | `AdMobRewardedAds()` on both after `GADApplicationIdentifier` + SKAdNetwork are in `Info.plist` (remove the `TODO(ios)`) **Done 2026-10-15:** `AdMobRewardedAds` / interstitial / banner on iOS. |
| `lib/services/ads_service.dart:169` | iOS unit id switch exists; uses the Google test unit | Real iOS unit id at release **Done 2026-10-15:** real iOS units in release, test units in debug. |
| `lib/firebase_options.dart:28` | `UnsupportedError` for iOS | `flutterfire configure --platforms=ios` **Done 2026-10-15:** `DefaultFirebaseOptions.ios`. |
| `lib/services/firebase_versus_backend.dart:40–48` | App Check: Play Integrity / Android debug provider | Apple providers already set — only console registration (§1) |
| `lib/services/identity.dart:48`, `:77` | `PlayGamesIdentity` (Play Games auth code); Game Center stub | Implement `GameCenterIdentity` (§2) **Done 2026-10-15:** `GameCenterIdentity` implemented. |
| `lib/services/reminders.dart:688`, `:703–711`, `:740–751` | Android notification channel `reminders`, `RawResourceAndroidNotificationSound('notif_chime')` (`res/raw/notif_chime.ogg` + `res/raw/keep.xml`), small icon `ic_notif_bird` / large icon `ic_notif_large` (`res/drawable-*`) | iOS has no channels / small icons: nothing to port; add `notif_chime.caf` (§1). Darwin settings already exist (`:726`, `:813`) |
| `lib/services/reminders.dart:726` | `DarwinInitializationSettings(request*Permission: false)` | Keep false: the game asks once through `requestPermissionIfNeeded()` (`:771`, `IOSFlutterLocalNotificationsPlugin.requestPermissions`) |
| `lib/services/reminders.dart:817` | `AndroidScheduleMode.inexactAllowWhileIdle` | Android-only parameter, ignored on iOS. iOS caps pending local notifications at 64 — the plan keeps ≤ 14, fine |
| `lib/game/rumble.dart:95` | `Vibration.vibrate(duration, amplitude)`; amplitude only when `hasAmplitudeControl` | On iOS the `vibration` plugin maps to Core Haptics where available; check knock (15 ms / 90) vs shake (45 ms / 255) feel on an iPhone. If they feel the same, put a `HapticFeedback.lightImpact()` / `heavyImpact()` path behind `Rumble` for iOS **Done 2026-10-15:** vibration 3.2.1 has amplitude via Core Haptics; iPhones without it get `HapticFeedback.lightImpact()` (knock) / `heavyImpact()` (shake). Feel still to check on an iPhone. **Round 2 (owner on the iPhone 12 Pro: soft barely felt):** the soft rumble (knock) is a button click on both platforms through the runner's `flappy_spikes/haptics` `click`: iOS `UIImpactFeedbackGenerator(.rigid)` at intensity 1.0, Android `EFFECT_HEAVY_CLICK` (API 29+, else a 20 ms full pulse). The hard rumble (shake) is unchanged. |
| `lib/main.dart:81` | Reminders already run on iOS (`_isMobile`) | Works once the AppDelegate delegate (§1) is set; verify the permission prompt timing |
| `lib/game/flappy_game.dart:208` | Debug panel on Linux / debug builds | Nothing (no Android branch) |
| `assets/audio/` | 169 mp3 + 6 wav, no ogg in the game assets | Plays on iOS (AVPlayer). Loops are wav on purpose (`docs/gameplay-v2/SOUNDS.md`) |
| `lib/game/sfx_pool.dart`, `lib/game/sound.dart` (PRD-2.2 §22 / §33.4) | SFX voices are fixed `PlayerVoice` sets (`PlayerMode.lowLatency` = Android SoundPool, which reports no duration); stop times come from `lib/game/sound_durations.g.dart`; one global audio context (`AudioPlayer.global`, mixWithOthers); `positionUpdater = null` on SFX, loops and music. Pure Dart, no Android-side code change | iOS uses the same duration table (no reliance on `getDuration`) and the same caps. On iOS `setPlayerMode` is a no-op, so each voice is a full AVPlayer: check the live player count (≈ 30 core voices + lazy pools ≤ `Config.sfxMaxLivePools`) and first-play latency on an iPhone; lower `Config.sfxVoices*` there if needed. The global mixWithOthers context maps to the AVAudioSession category (`.ambient`/mixWithOthers) |
| `lib/game/idle_frames.dart` (PRD-2.2 §33.4 item 5) | Idle menus stop Flame's ticker between frames (30 fps) and restart it from a Dart timer; pure Dart, no Android-side code | Same on iOS. On ProMotion iPhones (120 Hz) check that the idle Home still looks smooth and that `Config.idleMenuWakeLead` lands on the right vsync |
| `lib/services/audio_focus.dart`, `MainActivity.kt` `AudioWatch` (PRD-2.2 §28.3) | Android: other apps' calls / ringtones / alarms / assistant seen through `AudioManager.registerAudioPlaybackCallback` + the audio-mode listener (no focus request); "other music playing" = an active `USAGE_MEDIA` player that is not ours (ours are tagged `USAGE_GAME`). iOS uses `NoopAudioFocus` today | iOS: an `AVAudioSession.interruptionNotification` (began / ended) stream for `interruptions`, and `AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint` for `isOtherMusicActive` and `isOtherMediaListed` (the hint never counts our own audio; plus `silenceSecondaryAudioHintNotification`). Keep the `.ambient` / mixWithOthers category so the player's music keeps playing. A small `flappy_spikes/audio` channel in the iOS runner when iOS reopens. PRD-2.3 §13 added `changes` / `snapshot` (an `AudioWatchState`; iOS can map an interruption to `interrupted` and leave `notification` / `media` false) and `log` (os_log) **Done 2026-10-15:** `AudioWatch` in `AppDelegate.swift` (interruption → `interrupted`, the silence hint → `media` / `musicActive` and both music checks; `log` → os_log category `FS-Music`); Dart uses the same `PlatformAudioFocus`; the iOS session category is `.ambient` (`SoundService.gameAudioContext`, also set in `AppDelegate` at launch). |
| `lib/game/music_backend.dart` (PRD-2.3 §16) | Android plays the 56-bar OGG through just_audio (`JustAudioMusic`) | **Done (round 2):** iOS plays the identical loop, seamlessly: `tool/make_music_loop_ios.py` encodes the same float cut as AAC-LC 192k (`ios/Runner/HappyBeat_loop_56bars.m4a`, a Runner bundle resource so Android never ships it, 2.3 MB; seam check: downbeat −0.9 ms, no extra silence, no click). The runner's `LoopMusic` (`AppDelegate.swift`, `flappy_spikes/music`, Dart `NativeLoopMusic`) schedules the segment [priming, priming + L) back to back on an `AVAudioPlayerNode` (sample-exact; AVPlayer's loop re-seeks and gaps), Hourglass via `AVAudioUnitTimePitch`. The offset (0 or 1024) comes from `AVAudioFile.length`, so it is exact whether or not Core Audio applies the MP4 edit list. The SFX loops (`SfxLoop` wavs) also moved to a native `AVAudioPlayerNode` `.loops` player (`SfxLoops`, `flappy_spikes/loops`) for the same reason. |
| `lib/main.dart` `SystemBackObserver`, `MainActivity.onCreate` (PRD-2.2 §8, S7-20) | Android system back (`WidgetsBindingObserver.didPopRoute`) goes to the game's back stack and is always reported as handled. Predictive back is on (`android:enableOnBackInvokedCallback="true"`; targetSdk 36 forces it): the engine's `OnBackInvokedCallback` is registered only while the framework claims back, so `MainActivity.onCreate` and `SystemBackObserver.install` (and every resume) call `setFrameworkHandlesBack(true)`; without it Android 14+ finished the activity. Sticky immersive mode spends the first edge swipe on revealing the bars, so the (see-through) navigation bar is shown while `game.systemBackWanted` (a menu / popup over Home) and hidden on Home and in runs | iOS has no system back: `didPopRoute` is never called and `setFrameworkHandlesBack` / the nav-bar toggle are Android-only no-ops, so nothing to port. No `ios/` edits |
| `android/app/src/main/AndroidManifest.xml:10–22` | `AD_ID`, `VIBRATE`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`; Play Games app id meta-data; notification receivers | iOS equivalents: ATT string, notification permission at runtime, Game Center capability (already in `Runner.entitlements`) |

## 3b. Audio after background / lock (round 2)

Owner: background → lock → unlock → reopen: music gone for good, some SFX dead. Fixed defensively
(no Mac, no device logs to pin the exact trigger): `AudioWatch` ignores "app was suspended"
interruptions (iOS delivers them late and never ends them; one stuck `interrupted` silences the
music and every SFX), re-activates the `.ambient` session on `didBecomeActive` and when an
interruption ends, and probes a stale interruption while the app is active; the music runs on the
native `LoopMusic`, whose state reports `stopped` when it should play but the engine is down (the
§13.4 watchdog then restarts it; AVPlayer kept saying `playing`); every SFX player is created
afresh after a media-services reset and after ≥ 20 s in the background
(`SoundService.rebuildVoices`), and a voice that failed to load retries after 5 s instead of
silencing that sound for the session. **Round 2b (device log 2026-10-15):** the real trigger
was media-services resets in the background (every ~7 s), each answered by a failed session
activation (`'!pla'`) and ~90 new AVPlayers — a loop. Now nothing is activated, built or created
while the app is not active: a reset only drops the dead players / engines (`FS-Audio rebuild
deferred (background)`), and `didBecomeActive` / `resumed` does ONE session activation, music
engine rebuild and voice rebuild however many resets came; the 5 s retry waits for the
foreground too. Device logs (Console / `idevicesyslog`): `FS-Music …`
(os_log `.default`, category FS-Music: session, interruptions, the Dart music log, the loop
player) and `flutter: FS-Audio …` (voice rebuilds, failed voices, dropped first plays).

## 4. Verification on iOS

- `flutter analyze`, `flutter test` (platform-independent; already green).
- `integration_test/release_e2e_test.dart` on an iPhone (`-d <udid> --dart-define=FS_E2E=true`):
  the journey, element sweep and rides are platform-independent. The reminders and versus-live
  tests are Android-gated today (`_isAndroid` in the test): widen them to iOS when §1 is done.
  Screenshots land in the app's temp dir.
- Real-device checks: Game Center sign-in from the leaderboard button only, App Attest token
  accepted by Firestore / the `deleteMyData` callable, ATT + UMP order, reminder sound, rumble
  feel, notch / Dynamic Island against the 44 pt top spike strip.
