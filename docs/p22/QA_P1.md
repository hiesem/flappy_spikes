# PRD-2.2 QA P1

Date: 2026-10-12. Branch: `g7-qa1`. Implementation reviewed: `4f7ac89`.

Scope: §2–4, §8–11, §13–14, §29–30, §32.5 and the merged §33 soak flag.
Six findings: **3 major, 3 minor, no blockers**. Production code is unchanged.
Every finding regression was run without its skip and failed before being
committed with its finding ID as the skip reason. Green gates below therefore
do not mean these six defects are fixed.

## Findings

### S7-01 — minor — wide scores overflow the score circle (known open item)

- **PRD:** §13.2, big scores fit inside the circle.
- **Location:** `lib/components/score_hud.dart:48` (digit-count font scaling);
  `lib/game/config.dart` (`scoreCircleSize`).
- **Repro:** load the actual LVDCC font, set the run HUD score to 999, allow its
  count-up/pop to settle, compare `textWidth` with the circle width. Also inspect
  the 1000 and 12345 screenshot cases.
- **Expected:** the score fits inside the 183 pt circle; four and five digits
  retain a fitting side margin.
- **Actual:** 999 at the approved 125 pt font is **203.333 pt** wide. Shrinking
  only by digit count carries the oversized reference width into wide four- and
  five-digit values. The PNGs visibly confirm the known three-digit problem.
- **Regression:** `test/p22/s13_qa_p1_adversarial_test.dart`, three- to five-digit
  bounds, skipped `S7-01`. The existing width test compares against a
  three-digit reference rather than the circle, so it misses the overflow.
- **Disposition:** confirmed only, as instructed; no font or circle change.

### S7-02 — major — a gap bonus can make a legitimate run fail upload

- **PRD:** §13.5, bonus entries join the gap-exempt set; §13.1, in-run bonuses
  are recorded as points.
- **Location:** `functions/src/timeline.ts:174`.
- **Repro:** record `[time seconds, value, flag]` entries
  `[[2,2,0],[3.8,5,8],[4,2,0]]`: an ordinary pass, a five-point bonus, then an
  ordinary pass. Feed the Dart-generated v2 payload into the production TS
  `checkRun` function.
- **Expected:** accept this run: ordinary hoops are two seconds apart, and the
  intervening bonus is exempt. Gap pickups can legitimately precede a hoop.
- **Actual:** rejects with `gap`. Only the bonus entry's own delta is exempt;
  its timestamp still resets the interval checked for the next ordinary hoop,
  which is now 20 cs rather than 200 cs. Such runs cannot enter the versus pool.
- **Regression:** shared case “bonus before a pass with two seconds between
  hoops” in `test/fixtures/p22_qa_p1_timeline.json`; both Dart and TS skip
  `S7-02`. Preserve rejection of genuinely too-close ordinary passes when
  correcting this; the passing 89 cs rejection case covers that boundary.

### S7-03 — major — the chick does not double puzzle completion rewards

- **PRD:** §13.1 explicitly doubles every row, including bonuses, in both
  points and coins.
- **Location:** `lib/run/items/puzzle.dart:148` and `:158`.
- **Repro:** start a seeded real run, persist puzzle mask 7, activate the chick,
  emit collection of the fourth puzzle piece. Compare the actual rolled payout
  with the run's coin and point gains.
- **Expected:** a rolled 225-coin puzzle reward pays **450 coins and 450 points**
  with the chick active.
- **Actual:** pays **225 coins and 225 points**. Completion writes raw coins to
  the wallet and explicitly passes `chickX2: false` to scoring. The code retains
  the old PRD-2 puzzle exception despite the new approved rule.
- **Regression:** actual puzzle completion integration test in
  `test/p22/s13_qa_p1_adversarial_test.dart`, skipped `S7-03`.
- **Integration:** keep the recoverable/idempotent payout record intact. A
  doubled maximum puzzle reward is 500 points, exceeding the current server
  bonus cap as well; coordinate with S7-05.

### S7-04 — major — Bullseye rewards use the frame endpoint, not the crossing

- **PRD:** §11.1–2, crossing-time ring-local measurement; a Bullseye is always
  also perfect. §13.1, Bullseye bonus pays points as well as coins.
- **Location:** `lib/run/hoops/kinds/bullseye.dart:106`.
- **Repro:** force a Bullseye at hoop index 6, seed 5. Put the bird 0.1 pt
  before the hoop plane, establish its previous frame with `update(0)`, then
  advance 1/30 s. Two untouched crossings reproduce opposite errors:
  - start at ring centre +10 pt with vertical velocity +500 pt/s: recorded
    crossing offset **10.361 pt**, frame-end offset **28.056 pt**;
  - start at centre +26 pt with velocity −500 pt/s: crossing offset
    **25.694 pt**, frame-end offset **10.722 pt**.
- **Expected:** the first crossing earns the +3 Bullseye coins/points; the
  second is clean and earns no Bullseye bonus.
- **Actual:** the first loses the bonus; the second receives it despite being
  outside even the perfect zone. The run controller classifies the interpolated
  crossing correctly, but Bullseye independently remeasures the final bird
  position, making payout depend on the frame endpoint.
- **Regressions:** two real controller tests in
  `test/p22/s13_qa_p1_adversarial_test.dart`, both skipped `S7-04`.

### S7-05 — minor — server bonus cap differs from the approved contract

- **PRD:** §13.5 specifies bonus cap `2 × 40 = 80`, rejecting larger values
  with `count`.
- **Location:** `functions/src/schema.ts:50`;
  `functions/src/timeline.ts:132`.
- **Repro:** submit a valid v2 run with one bonus entry worth 81 points.
- **Expected under the literal §13.5 cap:** reject with `count`.
- **Actual:** accepts; `BONUS_CAP` is 250. Its comment chooses the old
  undoubled puzzle maximum over the explicit new cap.
- **Regression:** shared case “bonus one point above approved cap”, skipped
  `S7-05` in Dart and TS.
- **Contract conflict / integration:** §13.1 also includes puzzle bonuses and
  doubles them with the chick, while the puzzle rolls up to 250. Thus the
  literal 80 cap conflicts with legitimate puzzle rewards; this finding is a
  contract mismatch, not a claim that every value above 80 is a forged reward.
  Simply lowering the generic cap to 80 would reject normal puzzle runs, and
  retaining 250 would reject some doubled puzzle runs after S7-03 is fixed.
  The fix must reconcile validation with the approved puzzle payouts.

### S7-06 — minor — late Home search completion suppresses the next search

- **PRD:** §3, each run permits a new Home search; START never waits for it.
- **Location:** `lib/services/versus_service.dart:589` (late completion),
  `:492` (run-start cache invalidation).
- **Repro:** use a fake backend that holds its first pool read. Begin service
  initialization/Home prefetch; START while the read is pending (`takeOpponent`
  returns null and `onRunStart` clears `_searched`). Release the read and let
  the no-rival search finish during the run. Call `prefetch` on the next Home.
- **Expected:** perform a fresh search; empty-pool reads total 88 across the
  two Home searches.
- **Actual:** reads remain 44. The old search's `finally` overwrites the
  run-start invalidation with `_searched = true`, so the next Home reuses the
  stale no-rival result. Newly available opponents are missed for that visit.
- **Regression:** `test/p22/s3_qa_p1_search_test.dart`, skipped `S7-06`.

## Coverage and visual review

Read the approved PRD sections, their existing tests, and corresponding
implementation. Existing acceptance tests cover mode persistence and guarded
input, matching order/read limits/timeouts and diagnostics, menu/popup back
handling, volume defaults/reset, rumble routing, perfect zones and moving ring
crossings, point/coin accounting, results ticks, streak names/colours, fallback
prices, and soak-flag release guards/driver/counters. Those tests passed in the
full suite. No additional defect was confirmed in §9, §10, §14, §29, §30,
§32.5 or the §33 flag.

Additional passing adversarial coverage:

- FREE FLY through the real persisted upload queue and fake backend: low-score
  rejection, three non-best uploads, daily-cap rejection, new-best exception;
  no rival/versus HUD/results column and timeline sums match queued points.
- A nested debug panel closes before Settings, with back debounce and correct
  analytics; mode switching/back have no effect while START awaits a hook.
- A 52-perfect streak remains uncapped in points, a clean pass resets it, and
  the next perfect restarts at two points. The real Dart timeline validates and
  replays through compiled production TypeScript with identical score sums.
- Shared boundary fixtures exercise ordinary 90/89 cs gaps, same-time
  Bullseye bonus, chick piggy 80, pair gift 10/11, FEVER/chick values and a
  forged first-pass value above its plausibility cap.

Ran 23 existing focused screenshot cases (mode layouts at 568/640/711,
score digits and streak banners). Visually compared the generated PNGs with
headless Chromium renders of approved `screen_mode_toggle3.html` and
`screen_streak_names.html`, including the longest “KING OF BIRDS ×48” banner.
Mode buttons/layouts and the long banner fit the approved designs; score
overflow is S7-01. Review artifacts are generated under `build/`, including
`build/qa_p1/`, `build/menu_shots/` and `build/shots/run/streak/`; none are committed.
No store screenshots are committed.

## Changes and validation

Added only these seven files; no existing tests or production files changed:

- `docs/p22/QA_P1.md`
- `test/p22/s13_qa_p1_adversarial_test.dart`
- `test/p22/s2_s8_qa_p1_flow_test.dart`
- `test/p22/s3_qa_p1_search_test.dart`
- `test/p22/qa_p1_backend_probe.cjs`
- `test/fixtures/p22_qa_p1_timeline.json`
- `functions/test/p22_qa_p1.test.ts`

Validation:

- `flutter pub get`: passed before testing.
- `npm --prefix functions ci` and `npm --prefix functions run build`: passed.
- New focused Dart tests: **12 passed / 7 skipped**.
- `flutter analyze`: **clean**.
- `flutter test --concurrency=4`: **2041 passed / 10 skipped**, no failures.
  Seven skips are the new finding regressions; three were already present.
- `npm --prefix functions test`: **109 passed / 2 pending**, no failures.
  Both pending cases are new finding regressions.
- No emulator, device work, account interaction, deploy or push.

## Calls and remaining work

- Followed §13.1 literally over the previous puzzle chick exception (S7-03).
  Retained the explicit §13.5 80-point expectation in the skipped cap fixture
  and documented its puzzle conflict (S7-05); no production policy invented.
- FlameTester's skip parameter accepts only a boolean; finding widget tests
  use a surrounding Flutter group with `skip: 'S7-xx'` to retain the reason.
- Used fake services/backends and a local Node probe of compiled TS for
  cross-language checks. No live backend mutation was needed.
- Findings remain open for the fix round. Pixel gesture/rumble feel, live
  versus, native audio and the final 20-game soak remain for the authorized
  final device playtest; this round explicitly excluded device work.
- No gameplay/module contract changed, so no new SPEC DEVIATION or ARCH edit
  is required for this test-only commit.
