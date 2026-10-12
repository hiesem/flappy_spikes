# flappy_spikes (Flutter + Flame rebuild)

Read `../AGENTS.md` (workspace root) FIRST — it has the full project context,
cloud/store state, browser-automation notes and pending tasks. This file adds the
local environment, current status and the settled 2.1-gameplay decisions.

Quick facts:
- Gameplay contract: `SPEC.md` — follow it exactly for any behaviour change. The
  per-WP **DEVIATION** notes are the current start / run / replay and hoops flow
  (the PRD-2 sections at the end of the file).
- Module map / contracts: `docs/gameplay-v2/ARCH.md`; requirement traceability:
  `docs/gameplay-v2/REQ-MATRIX.md`; the sound pack: `docs/gameplay-v2/SOUNDS.md`;
  the versus runbook: `docs/gameplay-v2/VERSUS-BACKEND.md`.
- Gate: `flutter analyze` clean + `flutter test` all green (1871 tests, 3 skipped).
- Store guide: `SUBMISSION.md`. Task log: `TODO.md`. iOS port checklist: `PORT-IOS.md`.
- Never commit `android/upload-keystore.jks`, `android/app/key.properties`, or the
  Play Games web-client secret (only at `~/.config/flappyspikes_pgs_web_client.json`).

## Environment (Linux/Omarchy machine)

The workspace is `/home/killerhis/Projects/flappyspikes` (moved off Windows
2026-10). `flutter`, `dart` and `adb` are **not on PATH** in a fresh shell;
prefix every command (bash):

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH" \
  ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* | head -1)"
```

- Flutter stable **3.47.6** in `~/flutter`; 3.47 is now the **minimum**
  (`google_mobile_ads` pulls `webview_flutter_wkwebview`).
- JDK 17 in `~/opt/jdk-17*` (system Java is too new for Gradle); Android SDK in
  `~/Android/Sdk`; `ninja` installed via uv (Linux desktop builds).
- Linux desktop (`flutter run -d linux`, `flutter build linux --release`) is a
  **local test target only** — Android and iOS are the products.
- iOS work is paused; make no new iOS changes until the user reopens it. The
  later port checklist (do not edit `ios/`) is `PORT-IOS.md`.

### 2.1 gameplay build (PRD-2)

- **Device e2e (Pixel 8 `38300DLJH004SD`).** `--dart-define=FS_E2E=true` turns on
  the fixed seed, the fake rewarded ads (visible overlay), the App Check debug
  provider and the `E2EHooks` / debug force menu:

  ```bash
  flutter test integration_test/release_e2e_test.dart -d 38300DLJH004SD \
    --dart-define=FS_E2E=true --dart-define=FS_E2E_SEED=7 \
    --dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered token>
  ```

  Linux also runs it (`-d linux --dart-define=FS_E2E=true`); reminders and versus
  live skip there (phone-only). `FS_E2E_SEED` defaults to 7. Add
  `--dart-define=FS_LIVE_VERSUS=true` for the live Firebase round trip
  (anonymous auth → upload → pool read → `deleteMyData`); it prints the App Check
  debug token it used, so a freshly generated one can be registered in the
  Firebase console. Never set `FS_E2E` / `FS_APPCHECK_DEBUG_TOKEN` in a release
  build (release uses Play Integrity).
- **Emulator fallback.** The AVD `flappy_e2e` (API 35, Google APIs **Play**) lives
  at `~/.config/.android/avd`:

  ```bash
  ANDROID_AVD_HOME="$HOME/.config/.android/avd" \
    "$HOME/Android/Sdk/emulator/emulator" -avd flappy_e2e -gpu swiftshader_indirect &
  ```

- **Functions.** `npm --prefix functions ci` once, then `npm --prefix functions
  test` (tsc build + type-check + mocha in the Firebase Emulator Suite; Java ≥ 11,
  the Android JDK 17 works). The Dart p45 tests in `test/e2e/` load the compiled
  `functions/lib`, so run **`npm --prefix functions run build` before** the Dart
  suite — a stale/missing build gives two false failures (S6-60, S6-61).
- **Firebase CLI without gcloud.** No `gcloud` is installed; mint an access token
  from the firebase CLI login (the refresh token in
  `~/.config/configstore/firebase-tools.json`). The firebase-tools OAuth client is
  `563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com`:

  ```bash
  RT=$(python3 -c "import json;print(json.load(open('$HOME/.config/configstore/firebase-tools.json'))['tokens']['refresh_token'])")
  ACCESS_TOKEN=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d client_id=563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com \
    -d client_secret=j9iVZfS8kkCEFUPaAeJV0sAi -d refresh_token="$RT" \
    -d grant_type=refresh_token | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
  ```

  `firebase` / `firebase deploy` need no token; only raw REST calls (the TTL
  script, `serviceusage`) do.

## Status (2026-10-08) — 2.1 gameplay (PRD-2)

- `feat/gameplay-v2` (off `feat/menu-v4` 0380b4e) implements all of
  `PRD-2-gameplay.md`: hoops replace pipes, the run director, hearts / shield /
  extra life / Big Hoops, the perfect-pass streak + ring tiers, the comet boost,
  the portal roller-coaster + cannon, the special hoops (Bullseye, Ring Train,
  Spring, Lucky Spin, FEVER, saw, switch, pairs), the gap items (Star Trail, Egg,
  Piggy Bank, Firefly Jar, the four capsules), the spike squeeze, golden feathers
  + balloon bonus, puzzle pieces, the HUD / pause / revive v2 / results page,
  versus (client + Firebase backend), rumble and reminder notifications.
- **Local only.** Every WP and fix round is merged into `feat/gameplay-v2`
  (head `0f96074`); nothing is pushed — `origin` has only `main` (`c901ece`).
- Gate: `flutter analyze` clean, `flutter test` **1871 passed / 3 skipped**
  (was 247 before PRD-2). Function tests: `npm --prefix functions test`.
- QA rounds (Sol) all fixed and merged: P1 9 findings (S6-01…09, 5 major),
  P2 5 (S6-20…24, 1 major), P3 8 (S6-40…47, 2 major), P4/P5 7 (S6-60…66, 4
  major); fix rounds `Fix P1 R1`, `Fix P2 R1`, `Fix P3 R1`, `Fix P45 R1`.
- **Gate 2 passed on the Pixel 8** (`FS_E2E` + `FS_LIVE_VERSUS`): the journey and
  the §3.0.8 element sweep (76 screenshots), the portal rides, reminders and the
  live versus round trip. Frame log in the space ride: avg 12 ms / p90 15.6 ms.
  The App Check debug token "Pixel 8 e2e" is registered and App Check Play
  Integrity is **enforced on Firestore**.
- Gate 3 (Sol device playtest on the Pixel 8, `g6-qa5`) is **open** — it was
  running when the unattended batch stopped.
- **Pending user-only tasks: none.** The Play Games game-server credential was
  published by the owner on 2026-10-08; the remaining release steps (the 2.1.0+8
  AAB upload and the Play release click) are the owner's, but nothing is waiting
  on them now.
- TODO phase 22 is the WP-by-WP log and the remaining work.

## Status (2026-10-07) — 2.0 menu, skin shop, home v3

- `feat/home-v3` (off `feat/skin-shop`) implements `PRD-home-v3.md`: emblem home, 10 levels on best score, LEVELS
  screen + LEVEL UP popup, coin-pack / No-ads celebrations, purchase cancelled/failed popup, Settings v3 with RUMBLE.
  **Not pushed.** See TODO phase 19.

- `feat/skin-shop` (off `feat/menu-v2`) implements `PRD-menu-v2.md`: 5-layer
  skin shop (88 items), live home & Shop. **Not pushed.** See SPEC "2.0 skin shop
  (PRD-menu-v2) deviations" and TODO phase 18.

## Status (2026-10-03) — 2.0 menu (PRD-1)

- `feat/menu-v2` implements PRD-1 (2.0 menu): home screen, wallet, Shop, Skins
  (12), no-ads IAP + popup, rewarded ads, IAP, powerup slot, debug panel,
  keyboard controls and the Linux runner. **Branch not pushed**; `main` untouched.
- `feat/menu-v4` (PRD-menu-v4) adds the coin packs (`coins_1000` … `coins_100000`),
  the per-country store prices and the no-ads popup schedule; `feat/gameplay-v2`
  branches off it. See TODO phase 21.

## Settled decisions (future work must respect these)

### 2.1 gameplay (PRD-2)

- **Hoops replace pipes** (WP-1a). `pipe_pair.dart` is gone; the obstacle is one
  `Hoop` with a `kind`. `SPEC.md` carries the DEVIATION notes for the rim bounce,
  scoring (+1 per hoop, +1 coin), the miss rule, the death tumble, the 2.0 physics
  and the 44 pt spike strips.
- **The run director** (§3.0.3) is owned by the game and decides each hoop slot,
  gap and gap item at spawn time; its tables are data in `lib/run/config/`. Two
  seeded streams (`layout` / `cosmetic`) plus a third `timing` stream so
  clock-driven rolls never shift the slot sequence; the seed is per run (each
  player has their own course in versus). Same seed → same sequence (unit test).
- **Versus on Firebase** — project `flappy-spikes-a2b55` (Blaze): Firestore
  `(default)` in **eur3**, Cloud Functions 2nd gen in **europe-west1** (Node 22),
  Auth anonymous + optional Play Games link. Rules + indexes + TTL + functions are
  deployed. **60-day TTL** on `players.expireAt`; the daily `sweepPools` trims
  pools and old `recent` runs. **App Check is ENFORCED on Firestore**; the
  `deleteMyData` callable enforces App Check in code and is one atomic
  transaction; the ≤ 3 non-best uploads per UTC day is enforced on the server.
  Billing is Blaze with a **€5/month alert** (alerts only). Full runbook:
  `docs/gameplay-v2/VERSUS-BACKEND.md`.
- **Play Games game-server OAuth client** `512525012529-ts8djs53…` (web client
  "Flappy Spikes game server (PGS + Firebase Auth)"). Its secret lives at
  `~/.config/flappyspikes_pgs_web_client.json` (mode 600) and is **never in the
  repo**. The PGS "Game server" credential is published. On a link conflict the
  account that already owns the Play Games id wins.
- **App Check debug token** "Pixel 8 e2e" is registered in the Firebase console
  (App Check → Apps → Manage debug tokens). Debug / e2e builds pass it with
  `--dart-define=FS_APPCHECK_DEBUG_TOKEN=…`; **release builds never use the debug
  provider** (Play Integrity).
- **Sideloaded release builds play solo (PRD-2.2 §4).** A release APK/AAB that
  is not installed from Google Play fails Play Integrity, so with App Check
  enforced its versus reads and writes are refused: it always plays solo and
  nothing uploads. This is expected and is logged as `versus_solo {reason:
  app_check}` (logcat: `versus: solo (app_check, <n> reads)`). Test versus
  with builds installed from the **internal-testing track**, or with debug /
  e2e builds carrying the registered App Check debug token. Debug builds show
  the last search in the debug panel ("Versus: last search …").
- **Sounds** go through the preloaded low-latency `AudioPool` only (`Sfx` /
  `SfxLoop` in `lib/game/sound.dart`); never bare `FlameAudio.play`. The PRD-2
  pack (88 one-shots + 4 loops) is in `docs/gameplay-v2/SOUNDS.md`, made with
  `design/menu_v2/gen_sfx15.py`.
- **Look layers in runs:** equipped hoop skin + trail now show in runs;
  gameplay gold (streak tier / Big Hoops) wins while it is active. The dead pose
  and gold-tier rules are the ones in SPEC's skin-shop deviations.
- **Rumble (PRD-2 §3.33):** runs vibrate (knocks + death shake), 90 ms throttle;
  the `rumble` setting (Settings v3) applies. Menu knocks are unchanged.
- **Reminders (PRD-2 §3.34):** local only (`flutter_local_notifications` +
  `timezone`), 2 slots a day, never 22:00–09:00, next-7-days plan rescheduled on
  pause / close / start; no server and no FCM.

### 2.0 (still in force)

- The pre-2.0 uncommitted v1.0.1 tree is preserved as the baseline commit on
  `feat/menu-v2`; `main` is untouched. The lockfile was restored after `pub
  upgrade`: only the 6 SDK-pinned test deps moved (flame 1.37 / games_services
  5.1.0 kept).
- `onScreenTap()` stays the primary-action API (tests and the keyboard mean
  START); real taps no longer start runs (`TapCatcher` → `onPlayfieldTap`).
- `PowerupSlot` rolls in its constructor (= launch arrival); only `goHome()`
  re-rolls. An armed powerup is consumed on START.
- `AD_ID` permission stays removed (non-personalized ads only) until the Play ads
  declarations are updated — see the TODO comment in `AndroidManifest.xml`.
- iOS: ads route to Noop (no `GADApplicationIdentifier`; iOS paused), IAP is real.
- Menus (home/shop/skins/dialogs/popups) always render at colour stage 0; only
  runs advance the colour stage.
- Looks (2.0 skin shop): true colours in menus and at stage 0; in runs the whole
  look (bird + gear + hat) is `lerp(colour, stageFg, 0.35)` — a pure stage
  modulate made all skins grey.
- Modal popups (no-ads launch, LEVEL UP, purchase result, No-ads celebration) go through one queue: never two at
  once. Menu button presses knock when RUMBLE is on (PRD-home-v3 §10).
- Item art is drawn in code (`lib/skins/art/`, port of
  `design/menu_v2/skin_art.js`) — no skin sprite assets any more.
- Menu spike strips are drawn 44 pt (slide to 72 pt on START); visual only.
- WP7 folded into WP4–WP6: invite wiring + analytics events live where the
  actions are; audit in the Sol E2E pass.
- Linux visual checks: live capture (grim) hangs while the display is off — use
  headless screenshot tests instead; window geometry via `hyprctl`.

## In-app purchases — test setup (2026-10-05, packs revised 2026-10-07)
- Payments profile **Duo Leads (0852-6699-4116)** linked (merchant category Computer Software, support
  hello@duoleads.com, statement DUO LEADS). Bank account + 15% service-fee enrolment still open (user).
- One-time products (new model), updated 2026-10-07 (PRD-menu-v4): **Active** coins_1000 / coins_10000 /
  coins_17000 / coins_100000 / no_ads (purchase options coins-1000 … no-ads, Buy, backwards compatible); **Inactive**
  coins_500 / coins_1800 / coins_5000 / coins_12000. Prices: every one of the 174 Play countries set by hand from
  `tools/pricing/play_prices.csv` (rule: before-tax ≥ USD target, + the price editor's Tax column, rounded up to a nice
  local price; US $1.29 / $9.99 / $15.99 / $84.99 / no_ads $3.49), verified 174/174 per product
  (`tools/pricing/PLAY_VERIFY_2026-10-07.md`). Runbook: PRD-menu-v4 §7. Price editor tax column: a rate = included in
  the buyer price; "No VAT" = nothing included (incl. US/CA/ID/VN where tax is added at checkout).
- Licence testing + internal-testing tester list "Flappy Spikes internal" (killerhis@gmail.com).
  Internal testing track: 2.0.0 (6) live (versions 3-5 superseded).
- Products need a PUBLISHED bundle with BILLING permission before they can be created (draft is not enough).
- After creating products the device returned notFound for all 5 until the Play Store app's cache was
  cleared on the phone; then `[IAP] query 5: found 5`. Read IAP diagnostics with
  `adb logcat -s flutter | grep '\[IAP\]'` (release builds log them).
- Release builds need android/app/proguard-rules.pro (keeps WorkManager's Room DB; google_mobile_ads pulls
  in androidx.work) — without it the release app crashes at launch. Debug builds hide this.
- The AdMob rewarded unit + app ID are still Google's **test** IDs (see the TODO in
  `AndroidManifest.xml` and `lib/services/ads_service.dart`); swap them for the real
  IDs and update the Play "contains ads" declarations before the production release.
- AAB upload via Playwright over CDP: `setInputFiles` refuses files > 50 MB — use CDP `DOM.setFileInputFiles` on the
  upload input instead (2.0.0+7 is 56 MB). Internal testing: 2.0.0 (7) saved as DRAFT 2026-10-07 (user releases).
- Linux: no Google Chrome — tools/browser_linux.js drives /usr/bin/chromium with profile
  tools/.pw-linux-profile (optional URL arg).
