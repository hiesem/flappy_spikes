# PRD-2.3 QA P1 — Sol

2026-10-13. Branch `p23-qa1`, baseline `e608b38`. Tested merged §§2–5, 9–16, 19–22 and 25. §§17, 18, 23, 24 and 26 are deliberately excluded. No device sessions, deployments, account changes, purchases, messages or notifications.

Eight findings: six major, two minor. S8-01 is fixed in this QA commit; the seven application/visual findings remain open. Six failing Dart cases are preserved with `skip: 'S8-xx'`; the backend retention case uses Mocha `it.skip` with its finding ID. Each skipped case was first run unskipped and failed for the stated reason.

## Findings

### S8-01 — major — Share-card goldens silently pass pixel mismatches (fixed)

- **PRD:** §6.1, §§4.2–4.5.
- **Location:** `test/share/share_card_golden_test.dart:138` (baseline).
- **Repro:** change `spotlight_l0_1digit` from score 7 to 8, leave its reference PNG unchanged, run `flutter test test/share/share_card_golden_test.dart --plain-name '§6.1 golden spotlight_l0_1digit'`.
- **Expected:** golden mismatch fails the test and command.
- **Actual:** exit 0, `+1: All tests passed!`. Flutter's `ui.Image` matcher calls `binding.runAsync`; its comparator throws `FlutterError`, which the binding captures and returns as null. A plain `test()` never drains the binding's pending exception, and null means matcher success.
- **Fix:** encode PNG bytes before `matchesGoldenFile`, avoiding that binding path. A new negative-control test proves a changed score has different pixels and a comparator rejection propagates. All ten unchanged golden references pass with the corrected harness. No goldens updated.

### S8-02 — major — Slow tuning startup changes values during a run

- **PRD:** §15.1, §15.2, §15.6.
- **Location:** `lib/main.dart:92`; `lib/services/tuning.dart:112`.
- **Repro:** delay `activate()`, invoke the app's unawaited initialization, begin a run with defaults, then finish activation with `curve_speed = [[0,222],[150,250]]`. Regression: `test/p23/s15_qa_startup_test.dart`, skip S8-02.
- **Expected:** startup activation finishes before a run can start; a begun run retains its values for its entire lifetime.
- **Actual:** `RunConfig.cruise(0)` switches from 150 to 222 after `beginRun()`. Initialization directly replaces the global set, and config getters still read it dynamically. Existing tests await initialization before beginning their run, so miss the actual main.dart ordering.
- **Integration:** synchronize startup/readiness, or pin each run's full resolved set. Merely delaying background fetch does not fix activation.

### S8-03 — major — A held opponent becomes a self-match after sign-in/account switch

- **PRD:** §21.4, §21.5.
- **Location:** `lib/services/versus_service.dart:580`, `:671`.
- **Repro:** prefetch `owner/ghost` while signed in as anonymous, then receive Play Games identity whose hash equals that run's `pg`. Alternatively link and switch the Firebase uid to `owner`. Both cases are in `test/p23/s21_qa_held_identity_test.dart`, skip S8-03.
- **Expected:** invalidate or revalidate the held opponent when either own uid or pg changes; never give out one's own run.
- **Actual:** `takeOpponent()` returns `ghost` in both cases. `_identityChanged()` only updates pg/avatar, and `takeOpponent()` never rechecks identity. The pure Dart/reference matchers agree and guard correctly; the service cache bypasses them after an identity change.
- **Integration:** invalidate cached/held candidates and handle searches already in flight when identity changes. Matching a candidate correctly at prefetch time is insufficient.

### S8-04 — major — A 1.9-second MEDIA ding latches music off mid-run

- **PRD:** §13.4 (notification recovery and current-state rechecks), §13.5.
- **Location:** `lib/game/music_guard.dart:226`.
- **Repro:** start music during a run, list a MEDIA notification player, stop it at 1.9 s without a list callback (finished player stays listed), and continue the 0.5 s polling. `test/p23/s13_qa_poll_boundary_test.dart`, skip S8-04.
- **Expected:** transient music pause; resume within 1 s of the ding ending; never classify that short ding as own music.
- **Actual:** the two-second promotion uses the previous snapshot before polling the player's inactive state. It sets `ownMusicSkipped=true`; the following poll clears the notification hold, but music stays off for the rest of the run. Log sequence: `notify → pause → skip → notify-end`, no resume.
- **Integration:** confirm current playback before promotion, with the required two real yes answers. Retest around the polling boundary, not only the existing 1.5 s example.

### S8-05 — major — A launch gift can be consumed without any coin grant

- **PRD:** §22.2 items 2–3, §22.6.
- **Location:** `lib/services/iap_service.dart:726`, `:740`, `:755`; startup ordering `lib/main.dart:208` and `lib/game/flappy_game.dart:671`.
- **Repro:** initialize the real store adapter before `Purchases.start()` subscribes, and emit a `gift_coins_10000` purchase from the plugin stream. `test/p23/s22_qa_early_delivery_test.dart`, skip S8-05.
- **Expected:** keep or buffer the receipt until a listener has credited and persisted the grant; then consume.
- **Actual:** the broadcast event has no receiver. With `hasListener=false`, the grant wait is skipped, but the gift is consumed anyway. The later launch sync cannot recover a consumed receipt, losing the 10,000 coins. Main initializes monetization concurrently with game loading, which subscribes only after storage/progress initialization.
- **Integration:** require positive persisted-grant confirmation before consuming/acknowledging; include the no-listener startup case. Grant timeout also currently falls through to completion.

### S8-06 — major — Uploaded profile pictures outlive the live privacy policy's retention promise

- **PRD:** §5.5 (accurate policy and ≈60-day versus retention), §21.3.
- **Location:** `functions/src/pools.ts:110`; `functions/src/index.ts:28`; `hosting/src/privacy_src.html:129`.
- **Repro:** store `avatars/{uid}.jpg`, delete `players/{uid}` as Firestore TTL does, then run the write trigger's `processPlayerWrite(db, uid, before, undefined)` path. `functions/test/p23_qa_p1.test.ts`, skipped S8-06. The unskipped emulator run fails because the file still exists.
- **Expected:** the picture (part of versus data) is removed around the promised retention deadline, or the published retention text accurately describes its separate lifetime.
- **Actual:** the deletion handler returns immediately. Only explicit `deleteMyData` deletes Storage pictures; TTL and the daily pool sweep never do. The public-read picture can remain indefinitely. [Live privacy policy](https://flappyspikes.com/privacy) says “Versus data” is automatically deleted about 60 days after the last run and includes the profile picture in that data.
- **Integration:** make TTL cleanup cover the avatar, preserving retry/idempotency semantics. Do not silently narrow the policy's meaning to just the player document.

### S8-07 — minor — First-run top warning is covered by HUD controls

- **PRD:** §10.3 approved design D (both warning chevrons and full text), §10.1 HUD.
- **Location:** `lib/run/hud/first_run_hint.dart:98`; `lib/run/config/first_run_config.dart:31`; `lib/run/hud/pause_button.dart:16`; `lib/run/hud/heart_indicator.dart:21`.
- **Repro:** show the fresh-install waiting screen at 568 or 711 pt. Compare `test/p23/goldens/s10_first_run_568.png` with design D's `v4` canvas in `design/onboarding_v23/first_run.html`.
- **Expected:** readable AVOID THE SPIKES band and both upward chevrons, with the pause button usable.
- **Actual:** the top band is y50–90 and HUD controls occupy y52–90. The heart box covers the left chevron; pause covers the right chevron and the end of SPIKES. The bottom warning has both chevrons and remains readable. This is visible in the committed golden, independent of animation phase.
- **Evidence:** `app_onboarding.png` and `design_onboarding.png` in the evidence directory below. Keep the HUD usable while resolving the warning's overlap; simply painting the warning over the buttons would create another defect.

### S8-08 — minor — Valid generated names lose their identifying digits

- **PRD:** §21.2 explicit “generated nicknames are shown in full, digits included”.
- **Location:** `lib/run/hud/name_chip.dart:15`; `lib/run/config/hud_config.dart:35`, `:56`, `:63`.
- **Repro:** `NameChip('HappyToucan999', 0)` with bundled Fredoka; enumerate the actual adjective/bird tables with three digits. `test/p23/s21_qa_generated_names_test.dart`, skip S8-08.
- **Expected:** all valid generated names retain all three digits, fitting at no less than 70% font size.
- **Actual:** many real generated names still exceed the 82 pt text room at the minimum font size and ellipsize away digits, including HappyToucan999, MightyParrot999 and BouncyFlappy999. Existing “generated name” UI test uses `SparklyFlappy1234` (four digits, outside the generator's contract) and checks width but never whole-name retention.
- **Integration:** fit the longest valid generated names by adjusting usable room/base typography while preserving the shared rule and minimum scale.

## Coverage and validation

- Added waiting/loading interplay for held, delayed and no-rival cases: intro taps inert, waiting/reminder count begins after the intro, pause and nested Settings freeze it, back-arrow/desktop back restores the wait, first flap and `RunStarted` occur once. Android system back remains inert during all run states, as PRD-2.2 §8 requires.
- Added all seven actual controller gate thresholds with `ignoreGates=false` and no force queue. Existing seeded director tests cover the spawned sets and first-meet rules.
- Added real off-centre FEVER + chick, centred Bullseye + chick and off-centre Bullseye + chick passes. Streak, points, coins and chick analytics agree; no chick multiplication of bonus coins.
- Added whole-set immutability check across a background fetch with both remote and `default*` values. Existing defaults/type/fallback tests pass; late startup activation is separately captured as S8-02.
- Read Dart matching and TypeScript reference and their shared fixture; existing fixture tests and met-list preference/parallel-read/timeout tests pass. Service identity invalidation is separately captured as S8-03.
- Existing gift grant-once, second code, restore/reinstall, consume, hidden products, 5 s sync throttle and popup queue tests pass. Launch delivery without a subscriber is separately captured as S8-05.
- Existing share data test confirms only the sharer's result/look/name, and a best counting the run, after versus. Corrected all ten image goldens, with no reference regeneration.
- Corrected `test/p23/s21_names_test.dart` to give its waiting run the first playfield tap before injecting death. Previously its results screenshots retained the full first-run hint and used the pre-run fallback death path. No expected application behavior was changed.
- Viewed share, onboarding, Settings (568/711/options/off), versus long-name/avatar/loading captures and the 60-item JS/Flutter skin contact sheet. Share matches approved composition; official badge shapes differ intentionally under §0. Settings' Rate row is replaced by Redeem under the explicit PRD changes. The skin sheet has the documented browser/Flutter blur/random-particle differences; no additional static shape defect found. Runtime frame budget/seam/audio-focus measurements require the later device round.
- Read-only `curl` of live `/support`, `/privacy` and `/delete-data`: gift redemption, restore, audio tiles and profile-picture/deletion descriptions match the merged app paths, except the retention issue S8-06. Support already describes the future §18 grace and §26 locks; those unmerged sections were excluded from correctness testing in this round.
- `python3 hosting/build.py`: 10 pages pass all static checks; generated output unchanged.
- `flutter analyze`: clean.
- `npm --prefix functions ci` and `npm --prefix functions run build`: completed before Dart testing. Final `unset JAVA_HOME; npm --prefix functions test`: **140 passing / 1 pending** (S8-06).
- Focused pre-existing `test/p23` + share suite: **220 passing / 20 skipped** before additions. Added interplay/controller/scoring tests and corrected name journey: **22 passing** in the focused verification. Corrected share harness: **12 passing**, including its negative control.
- Final `flutter test --concurrency=3`: **2,743 passing / 29 skipped** (23 pre-existing skips + 6 QA reproductions), all tests passed; autopilot and forced-element gates included.
- Changes are in `b1b1bee` (tests/harness) and the following `P23-QA1` report commit. New Dart cases: **21** (15 passing, 6 deliberately skipped); new backend case: **1** (deliberately skipped). No application expectations or golden references changed.

## Calls, limits and integration notes

- Used root `/home/killerhis/Projects/flappyspikes/AGENTS.md`: `../AGENTS.md` does not exist from this worktree. All changes remain in the named worktree, except explicitly requested external evidence.
- QA fixes only test harnesses; gameplay, platform code, designs, goldens, storage contracts and SPEC/ARCH remain unchanged. No new Config knob or storage key.
- S8-06 uses Mocha `it.skip`, the backend equivalent of Dart's `skip: 'S8-xx'`.
- No phone work, emulator device, public deployment, account/settings write or review/release click. Functions tests use local Firebase service emulators; Java is the system ≥21 runtime (`unset JAVA_HOME`).
- Full-suite success intentionally does not resolve the six skipped Dart reproductions or one skipped backend reproduction. Fix owners should remove each skip and run its case, then the required gates.
- Evidence (not in git): `/home/killerhis/Projects/flappyspikes/.worktrees/briefs8/evidence/qa1/`. Includes raw live pages, approved-design captures, app captures, negative-control output and failure logs. No secret or code lists.

## Fixes (P23-FIX1, branch `p23-fix1`)

- **S8-02:** `main.dart` awaits tuning activation (bounded to 3 s, since `Firebase.initializeApp` has no timeout); `Tuning.beginRun` pins the set and a late activation never replaces `TuningValues.current` once a run began (it reaches the next run).
- **S8-03:** `FirebaseVersusService` keeps the held run's pool entry and drops it when its uid or `pg` matches the current identity: after every identity change (once the new pg is known), at `searchForStart` and at `takeOpponent`; another match is then picked from the loaded pool with the current identity.
- **S8-04:** the 2 s media promotion runs the two-"yes" confirmation against the current playback (first check at 1 s, second at 2 s), so a ding that ended before the second check never latches "own music".
- **S8-05:** `StoreIapService` consumes / acknowledges a purchase only after the listener confirmed a successful grant; no listener, a timeout or a failed grant leave it with the store for the launch sync. `Purchases` completes the grant with an error when the grant throws.
- **S8-06:** `onPlayerRunWrite` deletes `avatars/{uid}.jpg` when `players/{uid}` is deleted (TTL or Delete my data) and still gone; the daily `sweepPools` also deletes pictures not updated for 60 days whose player doc is gone (retry). The client uploads an unchanged picture again after 30 days (`VersusConfig.avatarRefresh`). Needs a functions redeploy (owner / deploy step).
- **S8-07:** the top AVOID THE SPIKES band sits 6 pt under the HUD row (y 96) in solo, under the name chips (y 120) in versus; goldens updated.
- **S8-08:** HUD name chips use 14 pt, no letter spacing, 2 pt padding; the VS intro plate names use Fredoka SemiBold 18 pt. Every valid generated nickname now fits whole (digits included) on chips, plates, results and the share card.
