# flappy_spikes (Flutter + Flame rebuild)

Read `../AGENTS.md` (workspace root) FIRST — it has the full project context,
cloud/store state, browser-automation notes and pending tasks. This file adds the
local environment, current status and the settled 2.0-menu decisions.

Quick facts:
- Gameplay contract: `SPEC.md` — follow it exactly for any behavior change; see
  its "2.0 menu (PRD-1) deviations" section for the current start/replay flow.
- Gate: `flutter analyze` clean + `flutter test` all green (247 tests).
- Store guide: `SUBMISSION.md`. Task log: `TODO.md`.
- Never commit `android/upload-keystore.jks` or `android/app/key.properties`.

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
- iOS work is paused; make no new iOS changes until the user reopens it.

## Status (2026-10-07)

- `feat/home-v3` (off `feat/skin-shop`) implements `PRD-home-v3.md`: emblem home, 10 levels on best score, LEVELS
  screen + LEVEL UP popup, coin-pack / No-ads celebrations, purchase cancelled/failed popup, Settings v3 with RUMBLE.
  **Not pushed.** See TODO phase 19.

- `feat/skin-shop` (off `feat/menu-v2`) implements `PRD-menu-v2.md`: 5-layer
  skin shop (88 items), live home & Shop. **Not pushed.** See SPEC "2.0 skin shop
  (PRD-menu-v2) deviations" and TODO phase 18.

## Status (2026-10-03)

- `feat/menu-v2` implements PRD-1 (2.0 menu): home screen, wallet, Shop, Skins
  (12), no-ads IAP + popup, rewarded ads, IAP, powerup slot, debug panel,
  keyboard controls and the Linux runner. **Branch not pushed**; `main` untouched.
- Gate: `flutter analyze` clean, `flutter test` 247/247 green.

## Settled decisions (future work must respect these)

- The pre-2.0 uncommitted v1.0.1 tree is preserved as the baseline commit on
  `feat/menu-v2`; `main` is untouched. The lockfile was restored after `pub
  upgrade`: only the 6 SDK-pinned test deps moved (flame 1.37 / games_services
  5.1.0 kept).
- `onScreenTap()` stays the primary-action API (tests and the keyboard mean
  START); real taps no longer start runs (`TapCatcher` → `onPlayfieldTap`).
- `PowerupSlot` rolls in its constructor (= launch arrival); only `goHome()`
  re-rolls. An armed powerup is consumed on START; the 1.0 game ignores the
  effect until PRD-2 lands.
- `AD_ID` permission stays removed (non-personalized ads only) until the Play ads
  declarations are updated — see the TODO comment in `AndroidManifest.xml`.
- iOS: ads route to Noop (no `GADApplicationIdentifier`; iOS paused), IAP is real.
- Menus (home/shop/skins/dialogs/popups) always render at colour stage 0; only
  runs advance the colour stage.
- Looks (2.0 skin shop): true colours in menus and at stage 0; in runs the whole
  look (bird + gear + hat) is `lerp(colour, stageFg, 0.35)` — a pure stage
  modulate made all skins grey. Hoop/Trail layers are preview-only until PRD-2.
- Modal popups (no-ads launch, LEVEL UP, purchase result, No-ads celebration) go through one queue: never two at
  once. Menu button presses knock when RUMBLE is on (PRD-home-v3 §10); nothing rumbles in runs until PRD-2.
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
- Linux: no Google Chrome — tools/browser_linux.js drives /usr/bin/chromium with profile
  tools/.pw-linux-profile (optional URL arg).
