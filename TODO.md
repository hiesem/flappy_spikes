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
- [ ] Play Console: store listing + Play Games config via browser automation;
      IDs into placeholders
- [x] Contact email hello@duoleads.com in docs/index.html
- [~] Apple: DEFERRED by user decision (2026-07-21) — no iOS changes until reopened
      (still needed later: GoogleService-Info.plist, App Store Connect Game Center)

## Final gate
- [x] `flutter analyze` clean
- [x] `flutter test` 69/69 green
- [x] Signed AAB/APK built with final code
