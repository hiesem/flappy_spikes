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

App identity: name **Flappy Spikes**, bundle/package **com.flappyspikes.flappy_spikes**,
version 1.0.0+1, portrait-only, min Android per Flutter default (21+), iOS 13+.

## 2. Google Play Store

1. Sign up at https://play.google.com/console ($25 one-time).
2. **Create app** → name `Flappy Spikes`, default language, free game.
3. **Set up app** checklist: category *Games → Arcade*, content rating questionnaire
   (no violence/gambling — casual game), target audience 13+, privacy policy URL
   (required even if no data collection — any free policy generator works; the game
   itself collects nothing).
4. **Store listing**: upload `store/icon_512.png`, `store/feature_graphic_1024x500.png`,
   and 2–8 phone screenshots from `store/screenshots/`.
   Suggested short description: *Tap to flap. Don't touch the spikes — they're everywhere.*
5. **Production → Create release** → upload `app-release.aab`. When prompted about
   app signing, choose **Google Play App Signing** (recommended; your upload key stays
   the local `upload-keystore.jks`).
6. Complete the Data Safety form: no data collected, no third-party SDKs.
7. Submit for review.

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
2. Upload screenshots (6.7" iPhone and 12.9" iPad required — capture from the iOS
   simulator on a Mac, or reuse the Android ones at correct sizes via TestFlight first).
3. Fill in description/keywords, content rating (4+), privacy (no data collected).
4. Submit for review.

## 5. What this build deliberately does NOT include

The 2014 original's third-party SDKs were not ported (all dead or obsolete):
Chartboost ads, AdMob 6.x banner, Parse push/promo (Parse shut down in 2017),
Facebook SDK, Google Analytics, Game Center. If you want a modern AdMob banner or
Play Games/Game Center leaderboards later, that's a small add-on — ask and provide
your AdMob / Play Console IDs.
