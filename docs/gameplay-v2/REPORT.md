# PRD-2 gameplay build: final report (2026-10-08)

This was an unattended build of `PRD-2-gameplay.md` on the branch `feat/gameplay-v2`, which started from `feat/menu-v4`. All commits are local; nothing was pushed.
- **Orchestration:** Opus.
- **Builders:** Opus and DeepSeek.
- **QA:** GPT-6.1 Sol.

The full timeline and every decision the orchestrator made ("call") are in `.worktrees/briefs6/RUNLOG.md`, outside the repo.

## Delivered
- **Version 2.1.0+8:**
  - The signed release APK is installed on the Pixel 8. It launches cleanly and App Check activates through Play Integrity.
  - The AAB is saved as a **DRAFT** release "2.1.0 (8)" on internal testing. It replaces the unreleased 2.0.0 (7) draft, and 8 contains all of the menu-v4 work. The owner presses release.
- **Every PRD-2 feature:**
  - core and physics: hoops, run director, rim bounce, death tumble;
  - hearts, shield, Big Hoops;
  - streak and tiers, rumble;
  - HUD, pause, revive v2 and results;
  - comet and the portal rides (5 plus the cannon);
  - special hoops: Bullseye, Train, Spring, Lucky Spin, FEVER, saw ×3, switch ×5, pairs;
  - gap items: Star Trail, Egg, Piggy, Jar;
  - capsules: Hourglass, Mini Bird, Coin Frenzy;
  - spike squeeze;
  - feathers with the balloon bonus, and puzzle pieces;
  - reminders;
  - versus with the VS intro;
  - "Delete my data".
  - 92 generated sounds, listed in `SOUNDS.md`.
- **Live backend** (`flappy-spikes-a2b55`):
  - Firestore in eur3, with rules and indexes, and a 60-day TTL;
  - functions `onPlayerRunWrite`, `deleteMyData` and `sweepPools` in europe-west1;
  - Anonymous and Play Games auth, with the PGS game-server credential published;
  - Play Integrity linked; App Check ENFORCED on Firestore, and the callable enforces it in code.
- **iOS:** only cross-platform plugins are used and `ios/` is untouched. `PORT-IOS.md` is the port checklist.

## Verification (SDLC gates)
- **Gate 1, unit and autopilot:** `flutter analyze` is clean. `flutter test` gives 1,882 passed and 3 skipped; the 3 skips are opt-in emulator or device tests. The functions suite (`npm test`) has 79 passing.
- **Gate 2, device e2e on the Pixel 8:** `integration_test/release_e2e_test.dart` passed:
  - the full journey (revive by ad and by coins, results level-up, claim);
  - a sweep of every element with screenshots;
  - all rides;
  - the reminders plan;
  - a live versus round trip (sign-in, upload, pool hit, deleteMyData).
- **Gate 3, Sol playtest on the Pixel 8:** 3 findings, all fixed and re-verified on the phone. There were no crashes or uncaught exceptions.
- **QA rounds:** P1 had 9 findings, P2 5, P3 8, P4/P5 7 and P6 3. All 32 are fixed, and each one is a regression test.
- **Frame times** (logged, not a gate): space ride on the Pixel 8 averaged 12 ms and p90 15.6 ms. Sol's small debug-build samples showed 14–28 % janky frames. Profile a release build on low-end phones before production.

## Open items and owner decisions
1. **Store screenshots** in `store/screenshots*` still show the 1.0 pipes. Regenerate them before a production release.
2. **Privacy policy:** `docs/index.html` was rewritten for versus, reminders and Delete my data. It is not published (no push), so the owner should review it. The Play data-safety form also needs updating; the list is in `SUBMISSION.md` §6.
3. **Ads:** `AdMobRewardedAds` still uses test unit IDs (same as menu-v4). Real IDs and declarations are needed before production.
4. **Sideloaded release builds** are not Play-recognised, so Play Integrity may refuse them and versus falls back to solo. Builds installed from the internal-testing track work.
5. **REQ-MATRIX** has 30 of 737 rows still marked `todo`. These are mostly aggregate or audit rows, a few §6 analytics rows, and the deferred iOS row.
6. **Calls worth a look:**
   - timer pill at y 156, and feather tray / puzzle pill at y 288 (the PRD gave 206–254), to keep them clear of the banner band;
   - Piggy / Jar / Egg HUD badges lifted 86 pt;
   - orbit ring at 50×62 overall (the mock draws it 2×);
   - VS intro about 7.3 s (from the mock's timing table);
   - equipped hoop skin and trail show in runs, with gameplay gold winning;
   - switch rings placed 70–100 pt from the ring, otherwise the slot becomes a normal hoop.
7. **Analytics:** both `rumble_toggle` and `setting_changed` are sent.
