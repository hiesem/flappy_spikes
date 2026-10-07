# Flappy Spikes rebuild — progress tracker

Contract: see SPEC.md. Loop rule: a box is checked only when code exists AND
`flutter analyze` + relevant tests are green.

## Phase 1 — scaffold & assets
- [x] Flutter project created (com.flappyspikes.flappy_spikes)
- [x] Packages: flame, flame_forge2d, flame_audio, shared_preferences, share_plus (+dev: flame_test, flutter_launcher_icons, flutter_native_splash)
- [x] Original images/fonts copied; caf→mp3 converted
- [x] Portrait lock + app name (Android + iOS)
- [x] Launcher icons + native splash generated

## Phase 2 — core gameplay
- [x] Game shell (main.dart, virtual 320×568 camera)
- [x] Bird (physics, flap, animations, death)
- [x] Scrolling spike strips (floor + ceiling)
- [x] Pipe spawner + score sensors
- [x] Collision → game over
- [x] Component tests green

## Phase 3 — UI & systems
- [x] Start / playing / gameover / replay states + fades
- [x] Score HUD (watermark) + start/gameover panels per spec
- [x] Color stage system
- [x] Audio + mute, persistence
- [x] Share button
- [x] Unit tests green (goldens skipped — render smoke + on-device screenshots instead)

## Phase 4 — calibration & hardening
- [x] Flap rise 90–110 pt calibration test green (Δv=525 → ~98 pt @60fps)
- [x] Full-loop integration test green
- [x] Multi-size render smoke test
- [x] On-device verification (Android emulator): start/playing/gameover/replay,
      persistence, tint regression fixed (gameover title), color-state regression tests

## Phase 5 — builds & CI
- [x] Release APK + AAB locally (signed with upload-keystore.jks)
- [x] GitHub Actions: test (ubuntu) + AAB (ubuntu) + IPA (macos-14) workflow
- [ ] CI verified on GitHub — needs the user to push to a repo (see SUBMISSION.md)

## Phase 6 — store deliverables
- [x] Keystore + signing config (credentials in android/app/key.properties — gitignored)
- [x] Store graphics (icon 512, feature graphic 1024×500, 3 phone screenshots)
- [x] SUBMISSION.md

## Phase 7 — gameplay feel & contrast fix (2026-07-19, user-reported issues)
- [x] Physics retuned to Flappy Bird feel: gravity 1250, flap Δv 370 (rise ~55 pt,
      ~half the final gap), terminal fall speed 500 pt/s — was 1350/525 (rise ~100 pt,
      one flap crossed nearly the whole gap)
- [x] Difficulty ramp: pipe gap 145 pt at score 0 → 105 pt from score 25 on
      (`Config.gapForScore`); spawn band adjusts per gap
- [x] Score-circle contrast: circle tinted lerp(fg, bg, 0.45) — lighter than the
      pipes (was identical grey, pipe outlines vanished)
- [x] Letterbox bars on tall screens (Pixel 8): bars now the spike/foreground tint
      via backgroundColor(); world bg drawn by in-world backdrop rect
- [x] Tests updated + new: 45–65 pt calibration band, terminal-velocity cap,
      gap ramp, sprite/gap alignment, autopilot playability gate (survives to 30)
- [x] On-device verification (emulator, 20:9): bars match spikes, circle lighter
      than pipes, big start gap, full start/playing/gameover/replay loop

## Phase 8 — full-bleed playfield & end screen (2026-07-19, user-reported)
- [x] Dynamic viewHeight: world 320 wide × 320/aspect tall, clamped [568, 730] —
      spike strips pinned to the TRUE screen edges; letterbox bars REMOVED
      (supersedes the fg-colored bars from Phase 7)
- [x] Gap band scales with playfield height (±140 jump cap retained)
- [x] End screen: title + best/games labels in UI pink #FF4FB7 (was pipe tint —
      unreadable over frozen pipes); start screen unchanged
- [x] Pointsfield: score number nudged 18 pt above the "POINTS" caption
- [x] Ads/analytics: verified none exist (2014 SDKs never ported)
- [x] Tests: tall-layout suite, accent-tint expectations, 711-pt autopilot,
      screenshot generator hardened (resize immediately before capture);
      67/67 green, analyze clean
- [x] On-device verification (20:9 emulator): edge-pinned strips pixel-checked,
      pink labels readable over pipes, full start/play/over/replay loop

## Phase 9 — analytics, leaderboards & approval prep (2026-07-20)
- [x] Packages: firebase_core, firebase_analytics, games_services 5.1.0, url_launcher
- [x] `lib/services/game_services.dart`: Firebase Analytics events (game_start,
      game_over, new_best, share_score) + Play Games/Game Center leaderboard
      (submit best on game over, show native UI) — all behind a no-op-safe wrapper
- [x] Leaderboard buttons (original gamcenter sprites at 2014 positions) on the
      start + game-over scenes; privacy-policy link on the start scene
- [x] Android: Play Games APP_ID manifest placeholder + strings.xml; iOS: Game
      Center entitlement, deployment target 15.0, bundle id aligned with Android
- [x] Privacy policy page (docs/index.html) live at
      https://hiesem.github.io/flappy_spikes/ — placeholder contact email pending
- [x] Repo created + pushed: https://github.com/hiesem/flappy_spikes (CI now active)
- [x] Tests: leaderboard/privacy-link coverage; 69/69 green, analyze clean
- [x] Emulator smoke test: buttons render, leaderboard tap no-op-safe, privacy
      link opens the browser
- [ ] Firebase project wiring (flutterfire configure, Android only) — login done,
      GCP project `flappy-spikes` exists; needs the Firebase console opened once
      in the browser (403 until then), then GA4 enablement
- [x] Play Console app created (Duo Leads, org account — no 12-tester rule)
- [x] All 10 policy declarations complete (privacy URL, no ads, no sign-in
      restrictions, IARC 3+, audience 13+, data safety w/ deletion link, no ad ID,
      no government/financial/health features)
- [x] PGS: project linked to Firebase cloud project, OAuth consent screen, two
      Android OAuth clients (upload key + Play app signing), Top Scores
      leaderboard CgkIsZz8pvUOEAIQAA, PGS app id 512525012529 — IDs in code
- [x] PGS: BOTH OAuth clients linked as credentials (app signing CgkIsZz8pvUOEAIQAQ,
      upload key CgkIsZz8pvUOEAIQAg) — done 2026-07-22 fully automated (the
      dropdown opened with a plain Playwright click after all). PGS publish +
      OAuth consent-screen publish done 2026-07-31 (see Phase 16)
- [ ] Store listing: default language stuck at zh-CN (flyout resists automation
      — user switches to English US), then descriptions + graphics upload
- [ ] Store category (Arcade) + contact email in Store settings
- [ ] AAB upload to a testing track + review submission (user clicks)
- [~] Apple: DEFERRED by user decision (2026-07-21) — no iOS changes until reopened
      (still needed later: GoogleService-Info.plist, App Store Connect Game Center)

## Phase 10 — Pixel 8 sign-in popup + leaderboard fix (2026-07-21/22)
- [x] Launch no longer requests Play Games sign-in (profile-picker popup on the
      Pixel 8): `initialize()` never calls `GameAuth.signIn()`; interactive
      sign-in only behind the leaderboard buttons
- [x] Diagnosed dead leaderboard button on the Pixel 8 via logcat:
      (1) backend calls failed UNAUTHENTICATED — no PGS credential linked and
      no OAuth test users; (2) after console fixes, games_services 5.1.0
      `GameAuth.isSignedIn` stale-cache race returned false right after a
      SUCCESSFUL sign-in, so `showLeaderboards()` bailed silently
- [x] Console: OAuth consent screen test users (all 4 device accounts) added;
      PGS credentials created for app signing + upload key (anti-piracy Off)
- [x] GameServices: sign-in state via app-lifetime `GameAuth.player` stream
      (never `isSignedIn`); completed `signIn()` counts as authenticated;
      `submitBestScore` optimistic
- [x] Score submission on EVERY game over with the local best (was: only on a
      new best — the leaderboard stayed empty for anyone whose best predated
      sign-in). PGS keeps each player's single highest score server-side.
      Spy-test coverage in leaderboard_test.dart
- [x] Verified on Pixel 8: no popup at launch; leaderboard button opens the
      native "Top Scores" UI; score 25 submitted and shown ("HiesemSurak (You),
      Rank 1"); analyze clean, 71/71 green, release APK installed

## Phase 11 — pipe-gap variance (2026-07-22)
- [x] Gap variance: each pipe draws `Config.gapForPipe(score, rng, viewHeight)`
      = gapForScore + rng × gapVarianceForScore (variance 25 pt → 10 pt on the
      same ramp schedule); the curve stays the MINIMUM gap; the draw is capped
      at `Config.maxGapFor(viewHeight)` (172 @568, 253 @730)
- [x] Spawn-band floor `Config.gapBottomMinFor(gap)` = max(202, gap+72+40): the
      TOP pipe stub is always ≥ 40 pt (a pipe never hides fully behind the
      ceiling spikes); the bottom stub stays ≥ 40 pt via `gapBottomMaxFor`
- [x] Spawner uses the new draw + band (±140 jump clamp retained);
      pipe_spawner ramp test updated from exact-curve to the band contract
- [x] New test/gap_variance_test.dart: math unit tests + 30 s in-game runs at
      568 and 711 (score swept 0→50 in clean phases; every spawned pair
      checked: gap in the variance band, both stubs ≥ 40 pt);
      83/83 green, analyze clean

## Phase 12 — background music + settings screen (2026-07-22)
- [x] BGM `HappyBeat_8-Bit_Retro_Game_Loop.mp3` (ElectroBaptist) looping
      everywhere via `FlameAudio.bgm` (lifecycle auto pause/resume);
      SoundService: `startMusic()` idempotent/guarded, `setMusicVolume`
      clamps 0..1 live; music independent of SFX mute
- [x] Storage: `musicVolume` persisted (default 0.6); game starts music after
      storage load; `FlappySpikesGame({soundEnabled})` — tests build with
      `soundEnabled: false` (plugin channel never reached from onLoad)
- [x] Settings screen: start-panel speaker button → settings GEAR opens
      `SettingsPanel` (SFX toggle row, MUSIC VolumeSlider w/ NaN-safe scrubbing,
      "Music by ElectroBaptist" credit, privacy link, back button, full-screen
      tap blocker); bird fades with the panels; taps never leak into gameplay
- [x] Icons `settings_gear/back_arrow/music_note.png` generated programmatically
      to match the existing artwork (#EC008C tile, #FCD9EE glyph, 60×60 —
      NOT uiAccent); generator `tools/gen_icons.py`
- [x] Config rename `soundButton*` → `settingsButton*`; new settings_test.dart
      (8 tests: layout 568/711, toggle+persist, slider+persist, back, no tap
      leak); 91/91 green, analyze clean

## Phase 13 — variance 2x + privacy link off the home screen (2026-07-22)
- [x] Gap variance doubled on user request ("no visible difference"): 50 pt at
      score 0 → 20 pt once ramped (was 25/10). New `Config.minPipeStub` = 20 pt
      (was 40) so the bigger gaps still fit with both stubs visible; cap
      `maxGapFor(568)` = 192. Fixed a band-inversion bug this introduced
      (gapBottomMaxFor still used 40 → empty spawn band at the cap broke the
      autopilot gate) — both band bounds now share `minPipeStub`
- [x] Privacy-policy link removed from the start panel (lives on the settings
      screen only); start panel is now title + stats + gear + leaderboard
- [x] Tests updated (gap_variance, config, layout, leaderboard start-scene);
      91/91 green, analyze clean

## Phase 14 — audio performance fix (2026-07-22)
- [x] Diagnosed on the Pixel 8 (user report: SFX stopped/delayed + jitter):
      game at ~220-266% CPU and ~1.8 GB Pss (1.1 GB "Unknown") under heavy
      device-wide memory pressure (swap full), LMK repeatedly killing the app.
      Root cause found in flame_audio 2.12.1: `FlameAudio.play` creates a NEW
      AudioPlayer (decoder + AudioTrack + focus request) PER call — 4+ audio
      focus abandons/sec while flapping
- [x] Fix: SFX now play from preloaded `FlameAudio.createPool` AudioPools
      (maxPlayers 3, warmed in `startMusic()`); bare `FlameAudio.play` only as
      a cold-start fallback. Emulator A/B: CPU 52-59% → ~36%, focus abandons
      4+/s → 7/session, memory flat
- [x] Follow-up (same day, user report: few-frame freeze on EVERY flap):
      mute-SFX test by the user proved it audio-caused. MediaPlayer-mode pools
      open+close an audio route per play (mixer reconfig stalls the frame
      thread on the Pixel 8). Switched pools to `PlayerMode.lowLatency`
      (SoundPool, decode-once warmup, stop-after-duration because
      onPlayerComplete never fires). Verified on the Pixel: 0 Choreographer
      skips, 0 codec allocs, 0 focus churn during taps
- [x] 91/91 green, analyze clean, release APK rebuilt

## Phase 15 — Play Store release prep (2026-07-23)
- [x] Internal testing: AAB 1.0.0+1 uploaded, draft release saved
      (tools/upload_aab3.js via CDP DOM.setFileInputFiles — Playwright
      setInputFiles times out on these Angular-hidden inputs)
- [x] Default language zh-CN → English (US) (user click), then listing filled
      by agent: short (62/80) + full (617) descriptions, icon, feature
      graphic, phone screenshots 3/8. Asset-widget lessons: uploads land in a
      shared asset LIBRARY; section assignment = select + Add (some
      selection/Add clicks are human-only, like the language/category
      dropdowns — user did icon, feature graphic and the last tablet file)
- [x] Tablet screenshots: generated by test/tablet_screenshot_generator_test
      (same scenes as phone, 9:16 REQUIRED by the console — first 16:10
      attempt rejected on aspect) → store/screenshots_tablet/
      (tablet7 1080x1920, tablet10 1440x2560); both sections 3/8
- [x] Store settings: contact details filled (email + website); category
      Arcade (user click) — dashboard setup complete
- [x] Production release DRAFT filled: bundle 1 (1.0.0) from library, release
      name, release notes with REQUIRED <en-US> language tags. Saved as draft.
      User reviews and presses Next → rollout themselves
- [x] AD_ID fix (2026-07-23): release review flagged
      `com.google.android.gms.permission.AD_ID` (pulled in by
      firebase_analytics' play-services-ads-identifier). Stripped via
      `tools:node="remove"` in AndroidManifest.xml (verified gone with
      `aapt dump permissions`). Version bumped to 1.0.1+2, gate 92/92 green,
      v1 draft discarded, NEW production draft saved with bundle **2 (1.0.1)**
      + tagged notes. No advertising ID declared anywhere — do NOT "answer
      yes" to the ads/ad-ID declaration; the app has no ads.

## Phase 16 — PGS publish + production sign-in hardening (2026-07-31)
- [x] Root-caused the production leaderboard outage (users asked to log in /
      dead button, developer can't reproduce): TWO independent console gates —
      the PGS configuration was never published (Draft) AND the OAuth consent
      screen was still in Testing (4-account allowlist). Investigation writeup:
      PGS_LOGIN_FIXPLAN.md (workspace root)
- [x] Console prep by agent (no publish clicks): filled the 4 blocked PGS
      properties (full description 635/4000, Arcade category, icon, feature
      graphic), verified the Publish button enabled and "Use for new installs"
      already set on the app-signing credential only. Handoff:
      PGS_PUBLISH_HANDOFF.md (workspace root). User pressed both publishes;
      verified live: OAuth consent "In production", PGS "No changes to publish"
- [x] Fix A/C (telemetry): GameServices catches PlatformException specifically
      and logs `pgs_error` (op sign_in/show_leaderboards/submit_score + code +
      message ≤90 chars) to Analytics + debugPrint — no more bare `catch`.
      Sign-in and leaderboard-UI try blocks split for attribution
- [x] Fix B (user-visible failure): `showLeaderboards()` returns
      `ShowLeaderboardResult` {opened, signInFailed, leaderboardFailed,
      unavailable, busy}; the game shows a self-timed `ServiceMessage`
      (uiAccent, ~3 s, bottom-center) on failure — a failed tap is no longer
      indistinguishable from no tap
- [x] Fix D (double-tap deadlock): `_leaderboardBusy` re-entrancy guard
      (second call returns busy) + 10 s timeout on every plugin call
      (TimeoutException → pgs_error code 'timeout'; injectable in tests)
- [x] Fix E (invisible-but-tappable button): game-over leaderboard button
      gated on opacity ≥ 0.9 — Flame hit-testing ignores opacity, so a
      death-moment flap-tap could open Play Games unintentionally
- [x] Fix F (cleanups): dead `_androidConfigured` deleted; main() no longer
      blocks the first frame on `services.initialize()` (unawaited after
      runApp); stale "placeholder" comments fixed (AndroidManifest, strings.xml);
      release debug-signing fallback kept but now warns loudly (CI relies on it)
- [x] Test seams (@visibleForTesting): plugin-call wrappers, logEvent
      recorder, markInitialized() — tests never touch plugins. New
      test/game_services_test.dart (7 tests) + leaderboard_test.dart (+4);
      103/103 green, analyze clean

## Phase 17 — 2.0 menu (PRD-1, branch `feat/menu-v2`)

Implements `PRD-1-menu.md`: 2.0 home screen, wallet, Shop, Skins, no-ads IAP +
popup, rewarded ads, IAP, powerup slot, debug panel, keyboard controls and a
Linux test target. Work lives on the `feat/menu-v2` branch — **not pushed**,
`main` untouched.

### Done (WP1–WP9)
- [x] WP1 — menu state: wallet (`Wallet`, coin sources), 12-skin catalog +
      `SkinStore`, `PowerupSlot` (BIG HOOPS/SHIELD 50/50, never a 4th repeat),
      `NoAdsPopupPolicy`, `FreeCoinsPolicy` (+40/ad, max 5/day, 5-min cooldown)
- [x] WP2 — rewarded ads (AdMob + UMP consent, Google TEST app/unit ids) and
      `in_app_purchase` IAP, both behind no-op-safe/fake layers
- [x] WP3 — menu icons rasterised from the approved mocks + 12 skins
      (stage-tinted layer + fixed-colour accessory overlay, menu previews)
- [x] WP4 — 2.0 home screen (G1 centred), START-only run start, interim coin rule
      (1 coin/point credited at game over), skins on the bird, debug panel,
      keyboard controls; WP7 folded in here (Invite = share sheet + store link)
- [x] WP5 — Shop (S1-B), no-ads popup (P1), IAP granting/restore (+1000 bonus
      coins with No ads), free coins with cap + cooldown, RESTORE PURCHASES link
      in Settings
- [x] WP6 — Skins screen (K1 grid), unlock / not-enough-coins dialog,
      featured-skin path from the Shop
- [x] WP7 — folded into WP4–WP6 (invite wiring + analytics events where the
      actions live)
- [x] WP8 — Linux runner: phone-shaped (9:19.5), non-resizable window sized to
      the monitor, Hyprland-friendly title
- [x] WP9 — docs: SPEC "2.0 menu (PRD-1) deviations" section, this TODO section,
      AGENTS.md environment/status/decisions, README Linux run instructions
- [x] Gate at WP9: `flutter analyze` clean, `flutter test` 247/247 green
- [x] WP10 — product-owner feedback: powerup slot is now "watch ad → play with
      powerup" (ad completes → run starts with it; no armed/✓ state; visible
      "TEST AD" overlay on Linux), and menu fades are 3x+ faster
      (uiFade 0.15 s, popup 0.07 s; gameplay fades unchanged)

### Pricing rule (product owner, 2026-10-05)
- In-app prices use the SAME nominal amount in every local currency, not an
  exchange-rate conversion: 0.99 USD = 0.99 EUR = 0.99 GBP, 2.99 USD = 2.99 EUR = 2.99 GBP, etc.
  coins_500 0.99 · coins_1800 2.99 · coins_5000 6.99 · coins_12000 14.99 · no_ads 2.99.

### Pending — USER-only (store / device / native config)
- [ ] Create the IAP products in Play Console with the ids `coins_500`,
      `coins_1800`, `coins_5000`, `coins_12000`, `no_ads`
- [ ] Replace the AdMob TEST app id / rewarded unit ids with the real ones
      (AndroidManifest `APPLICATION_ID` + `AdMobRewardedAds` unit ids)
- [ ] Play declarations for 2.0: tick "contains ads", complete the advertising-ID
      and data-safety updates — then remove the `AD_ID` `tools:node="remove"`
      block in `AndroidManifest.xml` (TODO comment there)
- [ ] Configure the UMP consent message in AdMob
- [ ] iOS (when it reopens): add `GADApplicationIdentifier` and switch ads from
      the Noop path to AdMob
- [ ] Sign off the generated skin art
- [ ] Install `gst-plugins-good` for Linux audio
- [ ] Real-device test on the Pixel 8

## Phase 18 — 2.0 skin shop + live home & Shop (PRD-menu-v2, branch `feat/skin-shop`)

Branch off `feat/menu-v2`, local commits only (not pushed). Built by Opus/DeepSeek
builders in worktrees, QA by GPT-6.1 Sol (max 2 fix rounds).

- [x] Shared contract `lib/skins/look.dart` (Look / SkinLayer / Rarity)
- [x] WP-A — catalogue (88 items), ItemStore, persistence + PRD-1 skin reset,
      item analytics, 15 menu SFX, debug "ALL ITEMS"
- [x] WP-B1 — Canvas port: 30 birds, 14 gear, 14 hats, LookPainter (try-on dim,
      dead pose)
- [x] WP-B2 — Canvas port: 15 hoop skins, 15 trails (pooled particles, ribbon,
      afterimage)
- [x] WP-C — skin shop screen (layout A), try-on / equip / buy / celebrations,
      featured item row, reduce motion
- [x] WP-D — LookComponent on the run bird and home bird (stage blend, dead pose)
- [x] WP-E — legacy PRD-1 skin code removed; live home & Shop (§8), GET + coin-fly
- [x] Sol QA round 1 (S1-10 … S1-15) + fixes
- [x] Sol QA round 2 (S2-10 … S2-12: continuous art clock through flaps, pool
      ready = pool + duration, contained audio errors) + fixes
- [ ] Device check on the Pixel 8 (performance of Afterimage / Black hole /
      Rainbow ribbon, Q-S7)
- [ ] Open PRD questions still pending: Q-S1 earn rate, Q-S2/Q-S3/Q-S4 (with
      PRD-2), Q-S8 random-from-owned, Q-S9 coin-fly for other rewards

## Phase 19 — home v3: emblem home, levels, purchase feedback, settings (PRD-home-v3, branch `feat/home-v3`)

Branch off `feat/skin-shop`, local commits only (not pushed). Opus/DeepSeek builders in worktrees, QA by GPT-6.1 Sol.

- [x] WP-F — levels table + LevelProgress (catch-up, claim once), storage (`claimedLevels`, `rumble`, `lastScore`),
      Rumble service (`vibration`, VIBRATE permission, knock/shake + throttle), menu knocks, CoinRewardAnimation +
      ConfettiBurst, new sounds, analytics, debug LEVEL UP
- [x] WP-G — EmblemPainter (Canvas port of `design/menu_v2/emblem_art.js`)
- [x] WP-H — home v3 layout, emblem idle, LEVELS screen, LEVEL UP popup + interim trigger (on return home) + catch-up
- [x] WP-I — coin-pack celebration, purchase cancelled/failed popup, No-ads celebration + owned flips, Settings v3
      (shared back spot, RUMBLE row), RESTORE PURCHASES removed from the Shop
- [x] Sol QA round 1 (S1-30, S2-30 … S2-33) + fixes (popup queue, late purchase results, pending toast dismissal)
- [x] Sol QA round 2 (S1-31, S1-32, S2-34, S2-35) + fixes (pill counts only its own reward, No-ads bonus only for a
      purchase started this session, reduce-motion celebration, cached unranked emblem)
- [ ] Device check on the Pixel 8 (vibration feel, 568-pt layout Q-H3, emblem performance)
- [ ] Open: Q-H1 LEVEL UP timing (interim: on return home), Q-H2 thresholds vs 1.0 scoring

## Phase 20 — skin shop v2 tweaks (branch `feat/skin-shop-v2`, off `feat/home-v3`)

- [x] WP-J1 — momentum scrolling + rubber-band bounce in every menu list (MenuScrollArea), stop-tap inside the list
      never selects; taps outside the list still act (native behaviour, orchestrator decision)
- [x] WP-J2 — tap-twice buy on skin tiles (1st tap try-on + BUY pill, 2nd tap buys; top-right BUY kept);
      bird #16 redesigned as "Rubber duck" (own shape, `bl` back anchor for the wind-up key)
- [x] Sol QA round 1 (S1-50, S1-51, S2-50, S2-51) + fixes (6 pt drag slop, fps-independent fling, preview fits tall hats)
- [x] Sol QA round 2 (S1-52, S2-52) + fixes (fallback velocity in world points, exact fling→spring handover)

## Phase 21 — coin packs, store pricing, no-ads popup schedule (PRD-menu-v4)

- [x] WP-K2 — no-ads popup schedule (§8): only at the session-start home arrival (launch / back after >= 30 min),
      4 h gap, max 2 per day, never in the first session, from install day 2 or 10 runs; videos / best / level
      triggers else 24 h fallback, never after a < 6 run; no dismissal cap; `reason` param; debug force

## Final gate (1.0)
- [x] `flutter analyze` clean
- [x] `flutter test` 103/103 green
- [x] Signed AAB/APK built with final code
