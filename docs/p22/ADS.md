# PRD-2.2 §7 ads — build log (WP-7a)

## Model (§7.5.2 / §7.5.4)
- App shell: `Column(Expanded(RepaintBoundary(GameWidget)), BannerSlot)`
  (`lib/main.dart`, `lib/components/banner_slot.dart`). The share capture uses
  the `RepaintBoundary` around the game only.
- `game.setPlayfieldHeight(visible, {stripDrop})` is the only resize entry
  point. It is called at START (before the VS intro and the run scene, only
  when the banner is on for that player, §7.5.6) and in `replay()` on the Home
  arrival (before `_setupStartScene`).
- In a run with a banner, `viewHeight = visible + Config.bannerStripDrop` (20),
  and the camera (`PlayfieldViewport`, a FixedResolutionViewport with a
  settable resolution) shows only the top `visible` points. So every run
  layout keeps its 44 pt bottom-strip arithmetic. The strip's lowest 20 pt lie
  under the view's bottom edge, 18 pt of teeth and 6 pt of base show, and the
  deadly tooth line is 24 pt above the visible bottom
  (`game.bottomStripInset`). The approved mock frames were rendered the same
  way (20 pt taller, then cropped).
- Visible run height: `clamp(screen − banner, Config.minRunViewHeight 500, 730)`.
  The banner height in pt is `heightDp × 320 / widthDp`. On the Pixel 8 the
  adaptive banner is 64 dp at 411.4 dp width, which gives 49.8 pt and a
  visible height of 661 pt.
- Banner state (`game.bannerState`): `off` on Home → `reservedEmpty` at START
  (and during the VS intro) → `showing` on the first `playing` frame → `off` on
  the Home arrival (after the interstitial). The used banner is disposed 0.1 s
  later and the next one is preloaded on Home.

## `viewHeight` audit (every reader in `lib/`)
**Persistent: they survive a resize and re-lay out through `PlayfieldResizable`.**
- `components/spike_strip.dart`: the ground body moves to `viewHeight − 22`.
  The ceiling never moves.
- `components/tap_catcher.dart`: its size.
- `components/bird.dart`: the waiting bird (gravity off) moves to the new
  middle.
- `game/flappy_game.dart` backdrop (size) and `ScoreHud` (`scoreHudPositionFor`):
  a game-owned `PlayfieldResizeCallback`.
- The coin pill and the corner gear box are top-anchored and independent of
  the height, so they need no hook.

**Built per scene, after the resize.** These read `viewHeight` when they are
built, so they are correct by construction:
- Run (built after START): `run/run_setup.dart`, `run_state.dart`,
  `run_geometry.dart`, `run_controller.dart`, `run_context.dart`,
  `director/*`, `config/{run,squeeze,pair,portal,hud,revive}_config.dart`,
  `hoops/kinds/*`, `items/*`, `rides/*`, `debug/autopilot.dart`,
  `hud/run_hud.dart` (`ensureFor` per run).
- Screens: `screens/{pause,revive,phoenix_rise,bonus,results,shop_overlay,versus_intro}.dart`.
  The VS intro is built after the shrink.
- Menus (built at the Home arrival, after the grow):
  `home/home_screen.dart`, `menu_screen_chrome.dart`, `settings_panel.dart`,
  `shop/shop_screen.dart`, `skins/skin_shop_screen.dart`,
  `levels/*`, `noads_popup.dart`, `ui/p1_popup.dart`.
- Transient: `ui/coin_reward.dart` (flash), `fake_ad_overlay.dart`, the
  `ScreenFlash` / white fades in `flappy_game.dart`, service toasts (placed on
  show), `debug_panel.dart` (built on open).
- `game/config.dart`: pure `*For(viewHeight)` helpers.

**Places that reserve 44 pt for the bottom strip (§7.5.4 list).** They all use
`viewHeight − 44`, which already sits at `visible − 24` in a run with a banner,
so no code change was needed. This covers: the hoop / pickup spawn bands
(`RunGeometry`, `director_context.dart`), the autopilot floor, the death tumble
floor and the revive phoenix band (`phoenix_rise.dart`), the bonus layout
(`BonusRules.layoutFor`, `strips = 44`, `bandShiftFor`), results (NEXT), the
pause card and the squeeze walls. Tests: `test/p22/s7_banner_layout_test.dart`.

## IDs
- Banner `ca-app-pub-2660521344509391/8797133596`, interstitial
  `ca-app-pub-2660521344509391/1357627279`, rewarded `/3758032081`. These are
  used in release builds only. Debug and profile builds use Google's test units.
- Test devices (§7.5.3): the Pixel 8's hashed ID `375F7680953C1B0F47A1FC3E475A9AA1`
  is in `kAdTestDeviceIds` (`lib/services/ads_consent.dart`). It is applied in
  every build mode, so the owner's phone gets test ads with the real units too.
  Emulators are test devices automatically.

## §7.5.7 performance gate (Pixel 8, profile build, Google test banner)
Harness: `integration_test/ads_banner_perf_main.dart`
(`flutter run --profile -t …`). The autopilot flies 120 s without the banner
(baseline: no strip, no platform view), then 120 s with the AdWidget (default
composition in google_mobile_ads 9.1.0).

Run 2026-10-12. Pixel 8, profile build. The banner is 64 dp at 411.4 dp width,
which is 49.8 pt, so the visible run height is 661 pt:

| Phase (120 s each) | Frames | build p50 / p90 / p99 ms | raster p50 / p90 / p99 ms | worst ms | janky (> 16.7 ms) | bursts ≥ 3 |
|---|---|---|---|---|---|---|
| Baseline, no banner (run A) | 7058 | 3.81 / 5.42 / 7.29 | 5.06 / 7.20 / 11.45 | 27.98 | 8 (0.11 %) | 0 |
| Baseline, no banner (run A, 2nd phase: the banner never mounted) | 7166 | 3.75 / 5.73 / 7.86 | 4.79 / 6.52 / 9.70 | 16.68 | 0 | 0 |
| **Banner showing** (run B; banner-showing ticks 14 555) | 7099 | 3.35 / 5.00 / 6.53 | 4.76 / 6.83 / 10.64 | 23.25 | 6 (0.08 %) | 0 |

**Gate: passed.** No regression with the banner: no dropped-frame bursts on
flaps and no hitch during the 120 s with the banner on screen (the AdMob
refresh included). The default composition is kept; no Texture Layer fallback
was needed.

**Device checks (§7.12, test units, 2026-10-12).** A profile build of the
harness with `--dart-define=ADSPERF_INTERSTITIAL=true` was used:
- The banner appears when the bird flies and stays up on the results page
  (screenshot: the lowered strip, 6 pt grey base, Google's "Test Ad" adaptive
  banner right under it).
- On NEXT the test interstitial plays over the results page while the banner
  stays up. Closing it with its × goes Home at full height (711 pt), the
  banner is off, and `lastFullScreenAdClosedAt` is set.
- Logcat confirms the hashed test-device ID above
  ("Use RequestConfiguration…setTestDeviceIds(…375F7680953C1B0F47A1FC3E475A9AA1…)").
- Not done on the device: the 60 s / first-3-runs guards (covered by
  `test/p22/s7_ads_test.dart` with the fakes) and the consent-form logo check
  (it needs a consent reset with the UMP debug geography EEA, which would
  change the owner's consent state).

# WP-7b: NO ADS, bonus offer, privacy options, revive, audio (§7.7–§7.9, §7.15, §24, §28)

## §7.7 NO ADS in 2.2 (as built)
| Spot | NO ADS owner (2.2) | Where |
|---|---|---|
| Gameplay banner | not shown (WP-7a, §7.5.6) | `FlappySpikesGame._reserveRunBanner` |
| Video ad after run | not shown (guard `no_ads`, WP-7a) | `interstitialSkipReason` |
| Revive | 1st revive of a game FREE (`ReviveOffer.free`, `ReviveKind.free`), then 250, 500 … | `revive_ladder.dart`, `revive_screen.dart` |
| Shop 40 free coins | watch the ad (▶ GET chip with its video icon, dimmed when no ad) | `claimFreeCoins`, `FreeCoinsRow` |
| Home power-up slot | unchanged: free | `tapPowerupSlot` |
| Balloon bonus feather ×3 | watch the ad, once (no free button) | `BonusRules.offerFor` |

The celebration no longer shrinks the Shop chip's video icon (the home slot's
still shrinks). Copy check: "NO FORCED ADS — or banners, ever" (popup) and "No
more forced ads." (celebration) stay true; no text promises free rewards without
ads. Analytics: `revive_offered.offer` = `ad` / `coins` / `free`,
`revive_free_used {revive_index}`.

## §7.8 bonus offer
`RewardedAds` already reloads right after every show and every failure
(`_AdMobFullScreenLoader.show` → `_load()`; verified). The bonus asks
`ensureLoaded()` (no wait inside the service) when the offer opens without a
loaded ad and polls `isAvailable` in game time for `Config.bonusAdWait` (5 s):
game time keeps the wait deterministic in tests and stops while the app is in
the background. `bonus_offer_shown {wait_ms, outcome: ad|timeout}`.

## §7.9 privacy options
`AdsConsent.privacyOptionsRequired` (WP-7a) gates a 14 pt "Privacy options"
link at `Config.settingsPrivacyOptionsPositionFor` (485 at 568); "Privacy
Policy" lifts 18 pt while it shows (458 at 568), RESTORE PURCHASES stays at 510,
DELETE MY DATA at 416. Tap → `privacy_options_opened`,
`consent.showPrivacyOptions()`; the consent helper re-reads `canRequestAds`,
the loaders follow it (withdrawn: no new loads, banner / interstitial off from
the next START; granted: SDK start + preload). Shots:
`build/menu_shots/p22_s7_9_privacy_options_{568,711}.png`.

## §28 audio focus (chosen approach)
**Constraint:** the game must keep mixing with the player's own music
(Spotify), so it can never *request* audio focus — and on Android only a focus
holder receives `OnAudioFocusChangeListener` callbacks (a `GAIN_TRANSIENT_MAY_DUCK`
request would duck Spotify while held; `audio_session`'s interruption stream
is built on the same focus request). So the game **observes** instead:
- `AudioManager.registerAudioPlaybackCallback` (API 26+): on every change the
  active playback configurations are read. Their `AudioAttributes` are visible
  for other apps' players (anonymised uid only). An active player with usage
  `ALARM`, `NOTIFICATION_RINGTONE`, `VOICE_COMMUNICATION(_SIGNALLING)` or
  `ASSISTANT`, or the audio mode `RINGTONE` / `IN_CALL` / `IN_COMMUNICATION`
  (`addOnModeChangedListener`, API 31+), is a transient interruption: the game
  pauses its music and mutes its SFX (loops at volume 0) until it ends.
- "Other music playing" = an active `USAGE_MEDIA` / `UNKNOWN` player that is
  not the game's. To tell them apart, the game's global audio context and the
  music player now use usage `USAGE_GAME` (still mixWithOthers, no focus).
  Checked at launch (before the music starts), on foreground (before the
  music comes back — the game owns the music lifecycle now, no Bgm observer)
  and at scene changes while the music is skipped. Below API 26:
  `AudioManager.isMusicActive()`. The check is skipped for 3 s after a
  full-screen ad (`Config.adAudioSettle`): the ad's own player may still be
  listed.
- A video in another app puts the game in the background (lifecycle pause),
  which already pauses the run and the music.
- Code: `MainActivity.kt` (`AudioWatch`, channels `flappy_spikes/audio` and
  `flappy_spikes/audio_interruptions`), `lib/services/audio_focus.dart`,
  `SoundService.setInterrupted / setOtherMusicActive / setBackground /
  suspend / resume`. iOS equivalents in `PORT-IOS.md`.
- Debug builds register `com.flappyspikes.DEBUG_RINGTONE` (`adb shell am
  broadcast -a com.flappyspikes.DEBUG_RINGTONE`): plays the default ringtone
  for 6 s with ringtone usage, to drive the interruption path without a call.
