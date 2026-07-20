# Flappy Spikes — Store Submission Guide

This project is a Flutter + Flame rebuild of the 2014 iOS game Flappy Spikes.
Everything below maps a deliverable to an exact store action.

## 1. Deliverables

| Item | Location | Notes |
|---|---|---|
| Signed Android App Bundle | `build/app/outputs/bundle/release/app-release.aab` | Upload this to Play Console |
| Signed Android APK | `build/app/outputs/flutter-apk/app-release.apk` | For direct/testing installs |
| Upload keystore | `android/upload-keystore.jks` | **Back this up. Losing it = losing update rights forever** |
| Keystore credentials | `android/app/key.properties` | storePassword / keyPassword / keyAlias=upload (gitignored — keep safe with the keystore) |
| Play icon 512×512 | `store/icon_512.png` | |
| Play feature graphic 1024×500 | `store/feature_graphic_1024x500.png` | |
| Screenshots | `store/screenshots/` | Phone screenshots from the Android build |
| iOS IPA | Built by GitHub Actions (`.github/workflows/build.yml`), artifact `runner-ipa-unsigned` | See §4 for signing |
| Privacy policy | `docs/index.html` → https://hiesem.github.io/flappy_spikes/ | **Contains a placeholder contact email — replace `YOUR-CONTACT-EMAIL@example.com` (3 spots) before submitting** |
| Source repo | https://github.com/hiesem/flappy_spikes | CI runs here |

App identity: name **Flappy Spikes**, bundle/package **com.flappyspikes.flappy_spikes**,
version 1.0.0+1, portrait-only, min Android per Flutter default (24+), iOS 15+
(Firebase minimum).

## 2. Google Play Store

1. Sign up at https://play.google.com/console ($25 one-time).
2. **Create app** → name `Flappy Spikes`, default language, free game.
3. **Set up app** checklist: category *Games → Arcade*, content rating questionnaire
   (no violence/gambling — casual game), target audience 13+, privacy policy URL
   https://hiesem.github.io/flappy_spikes/ (required — the game uses Firebase
   Analytics; replace the placeholder email in `docs/index.html` first).
4. **Store listing**: upload `store/icon_512.png`, `store/feature_graphic_1024x500.png`,
   and 2–8 phone screenshots from `store/screenshots/`.
   Suggested short description: *Tap to flap. Don't touch the spikes — they're everywhere.*
5. **Production → Create release** → upload `app-release.aab`. When prompted about
   app signing, choose **Google Play App Signing** (recommended; your upload key stays
   the local `upload-keystore.jks`).
   NOTE: personal Play Console accounts created after Nov 2023 must first run a
   **closed test with 12 opted-in testers for 14 consecutive days** before
   production access unlocks. Start recruiting early.
6. **Data Safety form** (the game now collects data):
   - *App activity* (app interactions): collected, not linked to identity,
     ephemeral → Firebase Analytics.
   - *Device or other IDs* (Firebase installation ID): collected, not linked to
     identity → Firebase Analytics.
   - *Personal info → nickname*: only via the Google Play Games profile for the
     leaderboard, user-provided by Google, not collected by us. Declare per the
     form's leaderboard/gameplay wording.
   - No data shared with third parties, no ads, data encrypted in transit (yes),
     users can request deletion (yes, via the policy email).
7. Submit for review.

### Play Games Services (leaderboard) — one-time console setup

The app is already wired; only the console config is missing:

1. Play Console → your app → **Play Games Services → Setup and management →
   Configuration** → create and link the app (package
   `com.flappyspikes.flappy_spikes`; use the Play App Signing certificate when
   asked).
2. **Leaderboards → Create leaderboard**: name *Top Scores*, score format
   integer (0 decimals), ordering *Larger is better*.
3. Copy the **App ID** into `android/app/src/main/res/values/strings.xml`
   (replace `TODO_PLAY_CONSOLE_APP_ID`) and the **leaderboard ID** into
   `GameServices.androidLeaderboardId` in `lib/services/game_services.dart`
   (replace `TODO_PLAY_CONSOLE_LEADERBOARD_ID`). Rebuild the AAB.
4. Publish the Play Games Services configuration and add your testers under
   **Play Games Services → Testers**, or sign-in fails for non-tester accounts.

To build a new AAB after changes:

```bash
export PATH="/c/Program Files/Microsoft/jdk-17.0.19.10-hotspot/bin:/c/Users/kille/flutter/bin:$PATH"
cd flappy_spikes
flutter build appbundle --release   # bump version in pubspec.yaml first
```

## 3. CI (GitHub Actions)

`.github/workflows/build.yml` runs on every push: analyze + test (Ubuntu),
release AAB (Ubuntu), iOS IPA (macOS-14).

To enable **signed** AABs in CI, add these repo secrets (Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android/upload-keystore.jks` output |
| `ANDROID_KEYSTORE_PASSWORD` | the storePassword from `android/app/key.properties` |
| `ANDROID_KEY_ALIAS` | `upload` |

Without them the workflow still builds (debug-signed) artifacts.

## 4. iOS App Store

iOS requires macOS/Xcode — handled by the `ios` job in GitHub Actions (macos-14 runner).
It currently produces an **unsigned** IPA, proving the iOS build compiles.

To ship to the App Store you need an **Apple Developer Program** account ($99/yr), then one of:

**Option A — sign in CI (fully cloud, recommended):**
1. In App Store Connect → Users and Access → Integrations: create an **App Store Connect API key** (Admin role). You get a `.p8` file, Key ID, Issuer ID.
2. Create a distribution certificate + App Store provisioning profile (easiest via
   Xcode on any Mac once, or via `fastlane match` with a private git repo).
3. Extend the `ios` job with signing (fastlane or `xcodebuild -exportArchive` with the
   API key). Secrets to add: `APPLE_API_KEY_P8` (file contents), `APPLE_API_KEY_ID`,
   `APPLE_API_ISSUER_ID`, plus certificate/profile secrets if using match.
4. Upload to TestFlight/App Store via `xcrun altool` or fastlane `pilot` with the same API key.

**Option B — you have a Mac:**
1. `git clone` the project, `flutter build ipa --release` on the Mac.
2. Open `ios/Runner.xcworkspace` in Xcode → Signing & Capabilities → pick your team.
3. Xcode → Product → Archive → Distribute to App Store Connect.

In App Store Connect (either path):
1. Create the app: name `Flappy Spikes`, bundle id `com.flappyspikes.flappy_spikes`,
   SKU `flappyspikes`.
2. Enable the **Game Center capability** for the App ID (Certificates, Identifiers
   & Profiles → Identifiers → the app id → check Game Center), then in the app's
   page → **Game Center → Leaderboards**: create *Top Scores*, leaderboard ID
   `flappy_spikes_leaderboard` (must match `GameServices.iosLeaderboardId`),
   score format integer, sort high-to-low. The entitlement file
   (`ios/Runner/Runner.entitlements`) is already in the project.
3. Upload screenshots (6.7" iPhone and 12.9" iPad required — capture from the iOS
   simulator on a Mac, or reuse the Android ones at correct sizes via TestFlight first).
4. Fill in description/keywords, content rating (4+), privacy policy URL
   https://hiesem.github.io/flappy_spikes/ and the **App Privacy** labels:
   collect *App Interaction* (analytics) + *Device ID*, both not linked to the
   user's identity and not used for tracking; leaderboard data is the Game
   Center nickname/score (declare as *User Content* → gameplay content if asked).
5. Submit for review.

## 5. What this build deliberately does NOT include

The 2014 original's dead third-party SDKs were not ported: Chartboost ads,
AdMob 6.x banner, Parse push/promo (Parse shut down in 2017), Facebook SDK.
Modern equivalents now PRESENT in the build: Firebase Analytics (Google
Analytics) and Google Play Games / Game Center leaderboards (added
2026-07-20). Still absent by design: ads — when adding AdMob later, also add
the iOS ATT prompt, Google's UMP consent flow, and update both stores' data
declarations.
