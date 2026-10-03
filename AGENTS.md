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
- Skins: identity colour in menus and at stage 0; in runs the tint is
  `lerp(identity, stageFg, 0.35)` for every skin including the default pink —
  a pure stage modulate made all skins grey.
- Menu spike strips are drawn 44 pt (slide to 72 pt on START); visual only.
- WP7 folded into WP4–WP6: invite wiring + analytics events live where the
  actions are; audit in the Sol E2E pass.
- Linux visual checks: live capture (grim) hangs while the display is off — use
  headless screenshot tests instead; window geometry via `hyprctl`.
