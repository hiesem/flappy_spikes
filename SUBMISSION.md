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
version 2.0.0+7 on internal testing (2.1.0+8 is the next bump), portrait-only,
min Android 24+, iOS 15+ (Firebase minimum).

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
   - *Rewarded ads (opt-in)*: an ad is only served when the player taps to watch
     one. Declare the app **contains ads**; declare the advertising ID as *not
     collected* while the `AD_ID` permission is removed (the real AdMob IDs and
     the final declaration are a pre-release TODO — see §5).
   - No data shared with third parties, data encrypted in transit (yes),
     users can request deletion (yes, via Settings → DELETE MY ACCOUNT & DATA, or the
     policy email).
7. Submit for review.

### Play Games Services (leaderboard) — console state (2026-07-21)

Already done in Play Console (app id `4974493442709551492`):
- PGS project created and linked to the Firebase cloud project (`flappy-spikes-a2b55`).
  **PGS app ID `512525012529`** (in `android/.../res/values/strings.xml`).
- Leaderboard **Top Scores** created, ID **`CgkIsZz8pvUOEAIQAA`** (in
  `lib/services/game_services.dart`), integer, larger is better.
- OAuth consent screen configured (External, testing mode) and TWO Android OAuth
  clients created in the GCP project: `Flappy Spikes upload key` (SHA-1 of the
  local upload keystore, for local/dev builds) and `Flappy Spikes app signing`
  (SHA-1 of the Play App Signing cert `D3:D7:26:...:22`, shown in Play Console →
  Add credential → Create OAuth client).
- PGS credentials: BOTH OAuth clients linked since 2026-07-22 (app signing
  `CgkIsZz8pvUOEAIQAQ` — the "Use for new installs" credential, upload key
  `CgkIsZz8pvUOEAIQAg`). The PGS project was **published 2026-07-31** (both
  credentials + Top Scores leaderboard + properties live) and the OAuth
  consent screen moved to **In production** the same day — Play Games sign-in
  works for all players, not just testers. Testers list is now irrelevant.
- All 10 policy declarations are complete: privacy policy URL, ads (none),
  sign-in details (none), content rating (IARC 3+ everywhere), target audience
  (13-15/16-17/18+), data safety (App interactions collected, nothing shared,
  encrypted in transit, deletion link), advertising ID (no), government (no),
  financial (none), health (none).

### Play Games achievements (PRD-2.3.1 §12) — console state (2026-10-14)

- The 48 achievements were created in Play Console (Grow users → Play Games
  services → Setup and management → Achievements) in the §12.1 order: name and
  description from the catalog, the 512 px icons from
  `store/achievements/play/`, not incremental, the 7 rides Hidden, the rest
  Revealed, points 5–60 (755 of 2,000). The generated ids are in
  `lib/achievements/achievement_catalog.dart` (`androidId`).
- The Play Games configuration was **published 2026-10-14 12:53 CEST** (10:53
  UTC); published achievements can't be deleted. Live for all players within a
  few hours; Play Games testers see the drafts before that.

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
   **Game Center → Achievements** (PRD-2.3.1 §12): create the 48 achievements from
   the kit in `store/achievements/ios/` (`achievements_ios.csv` / `.json`: Reference
   Name, Achievement ID `fs_ach_<key>`, Points, Hidden, Achievable More Than Once =
   no, English (U.S.) Title / Pre-earned / Earned Description, Image = the 1024 px
   RGB `ach_<key>.png` next to it), in the kit order; attach them to the first iOS
   version; test in the sandbox (reset with `Achievements.resetAchievements()`).
   The ids must match `lib/achievements/achievement_catalog.dart` exactly
   (`test/p231/s12_ios_kit_test.dart`).
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
Analytics), Google Play Games / Game Center leaderboards (added 2026-07-20) and
**rewarded ads** (Google AdMob + the UMP consent flow, added with the 2.0 menu
and extended by PRD-2's revive / balloon placements). The Android build still
uses Google's **test** AdMob unit ID and app ID and keeps the advertising-ID
permission removed, so the Play "contains ads" / advertising-ID declarations are
**not final**: swap in the real IDs and update both stores' declarations (plus
the iOS ATT prompt and the UMP flow) before the production release. Still absent
by design: banner and interstitial ads, and push notifications (the 2.1 reminders
are local-only — no FCM, no server).

## 6. Data safety — what versus stores online (PRD-2 §3.13, WP-4c)

Versus (async duels against real players' recorded runs) is the only feature that
sends anything to a server of ours. Firebase project **`flappy-spikes-a2b55`**
(Firestore in `eur3`, Cloud Functions in `europe-west1`). Use this list to fill in
Play Console → **Data safety** (and, when iOS reopens, the App Privacy labels).

### What is collected and stored

| Firestore path | Written by | Fields | Why |
|---|---|---|---|
| `players/{uid}` | the player's own client (rules: same `auth.uid` only) | `name` (nickname or Play Games display name), `avatar` (URL or `''`), `platform` (`android`/`ios`, analytics only), `look` (`bird`/`gear`/`hat`/`hoop`/`trail` item ids), `best`, `level`, `bestRun`, `recent` (≤ 5 recent run entries), `uploads {day, count}`, `updatedAt`, `expireAt` | the duel: who you played and their run timeline |
| `pools/{level}_{shard}` | the server only (Cloud Function `onPlayerRunWrite`) | run entries: `uid`, `level`, `ts`, the run's score/best, display fields (`name`, `avatar`, `look`, `platform`) and the compressed timeline | other players' clients read a pool to find an opponent |
| `versusRate/{uid}` | the server only | `last`, upload counts | rate limit (≤ 3 non-best uploads per UTC day) |

A stored run entry holds: score, best, timestamp, `name`, `avatar`, `look` (5 ids),
the timeline (`tl`: uint16 delta stream on `runClock`) and its end, the ride/train
flags and `platform`. No free text exists anywhere (nicknames are generated from a
fixed 20 + 20 word list + 3 digits; the only user-supplied string is a Play Games
display name, ≤ 32 chars).

### Identity

- **Anonymous Firebase Auth uid** by default — no email, no phone, no password.
- **Optional** Play Games link: the Firebase account keeps the same uid, and
  `name` / `avatar` become the Play Games display name / photo URL, plus the Play
  Games player id in Firebase Auth's provider data. Sign-in is never required to play.
- **App Check**: Play Integrity (Android) / App Attest + DeviceCheck fallback (iOS,
  later) attest that the app is genuine. No personal data.
- Firebase **Analytics**: an installation id and event names only (no free text);
  see the Play data-safety answers in §2.6.

### Retention

- Firestore TTL policy on `players.expireAt` (client writes now + 60 d on every
  write) deletes an inactive player's **whole document** ~24 h after it expires;
  pool entries and `recent` runs older than **60 days** are trimmed on write and by
  the daily `sweepPools` function. Best runs stay while the player is active.
- Nothing else is stored: the server keeps no logs with player content, and no
  third party receives this data.

### "DELETE MY ACCOUNT & DATA" (Settings, PRD-2 §3.13 / Q22)

The Settings row opens a confirm dialog; DELETE calls the `deleteMyData` Cloud
Function (App Check enforced), which

- deletes `players/{uid}` and `versusRate/{uid}`,
- removes the caller's entries from all pool shards,
- deletes the Firebase Auth account (anonymous or linked), and

then the client resets the Firebase Analytics ID (`resetAnalyticsData`) and the
local versus state (`versusNickname`, upload queue, daily upload counter). A fresh
anonymous account starts on the next launch. **Coins, skins, levels, feathers,
puzzle pieces and met elements stay on the phone** — they were never uploaded.

Offline or a refused call deletes nothing and says so; the player can retry.

Note for the form: the **Play Games "Top Scores" leaderboard** is stored by Google
Play Games Services, not by us; that score is removed through the player's own Play
Games data controls, not by this button.
