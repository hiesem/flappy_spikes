# PRD-2.3.1: build report

- **Release:** 2.3.1 (20), tester build (`FS_TUNING=true`), on **internal testing** only, published 2026-10-14 ~18:20 CEST.
- **Branch:** feat/2.3, release commit `39ef4d1`; not pushed.
- **Run:** unattended orchestration (owner go 2026-10-14 02:30).
  - Opus orchestrated and built WP-A, WP-B, WP-E, WP-F, WP-T and both fix rounds.
  - Haiku 5.5 (effort max) built WP-CD.
  - GPT-6.1 Sol (codex) did QA: P1 code review, P1E (§12), P2 fix check, P3 final check, then the device round.
  - The run log is in `.worktrees/briefs9/RUNLOG.md`, outside git.

## Gates
| Gate | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` at `39ef4d1` | **3085 passed**, 50 skipped, 0 failed |
| Backend `npm --prefix functions test` | 144 passed (WP-B; server code unchanged after it) |
| Sol P3 final code check | P2-01..03 fixed, **no new findings** |
| Device round (Pixel 6) | all gameplay checks pass; signed-in Play Games checks blocked (D-01) |

## What was built
| Section | WP | Result |
|---|---|---|
| §1–§4 Versus account switch | WP-B, FX1V, FX2V | Fresh server code for the switch. The guest is kept when there is no fresh code. Anonymous fallback with the guest name. `start()` self-heal. One Auth queue for every Firebase user change (start, re-auth, link, reset); a late sign-in can't replace a newer session; the UI never waits on it without a limit. |
| §5 Shop ad 75 | WP-CD | `shop_ad_coins` default 75; the row reads FREE +75 |
| §6 Bullseye +3 | WP-CD | `coin_bullseye` default 3, plus 3 points |
| §7 6-ring rides | WP-A | Portal + 5 ride rings on the same route, length and timing |
| §8 No GRAZE text | WP-CD, FX1R | Notice removed; the test renders frames |
| §9 Heart without a panel | WP-CD | Dotted outline, see-through empty part |
| §10 First-run instructions | WP-CD | Shown on every run until hoop 0 is passed |
| §11 Banner on the waiting screen | WP-CD | The banner shows when the run opens |
| §12 48 achievements | WP-E, FX1E, FX2E | Catalog, tracker, toast, Home medal, Play Games sync, iOS kit; debug runs never count; a provisional journal survives an app kill |
| §13 Shield follows the bird | WP-F | `Bird.drawnOpacity` / `drawnScale` |
| §14 No free revive for No Ads | WP-F | 250 … 8000 ladder |
| §15 FEVER rim-free = perfect | WP-F, FX1R | Points use the streak before the FEVER boost (fresh +2, streak 6 → +7) |
| §16 Comet layout | WP-A, FX1R | Even spacing, last hoop `ride_comet_tail` before the end, first hoop after ≥ end + `ride_comet_after_gap`; pickups in moved gaps dropped |
| §17 At most 2 portals | WP-A, FX1R | Monotonic per-run count; forced portals respect the cap |
| §0 Live tuning → defaults | WP-T | 45 defaults = live RC v21; PRD wins for `coin_bullseye`, `shop_ad_coins` and the new keys |

## QA findings and fixes
- **P1** (Sol code review, all but §12): 8 findings, all fixed in round 1.
  - P1-01..03: versus recovery retry, single-flight link, guest name on fallback.
  - P1-04: FEVER points before the boost.
  - P1-05: comet drops visible pickups in moved gaps.
  - P1-06: monotonic portal count (the PRD literally: every placed portal counts).
  - P1-07: debug-forced portals respect the cap.
  - P1-08: the graze test now sees painted text.
- **P1E** (§12): 3 findings, all fixed in round 1. A debug-forced starter, a god-mode toggle or a later debug action could still unlock achievements.
- **P2** (fix check): 9 of the 11 confirmed fixed; 3 new findings, all fixed in round 2.
  - P2-01: one Auth queue.
  - P2-02: a forced starter keeps its debug origin across a restart.
  - P2-03: the achievement journal survives an app kill.
- **P3** (final): all fixed, nothing new.

## Remote Config (published 2026-10-14 ~18:23, version 21 → 22)
- Only these keys changed:
  - `shop_ad_coins` 40 → **75**;
  - `coin_bullseye` 2 → **3**;
  - new in group `ride`: `ride_comet_tail` **100**, `ride_comet_after_gap` **310**, `ride_portal_max` **2**.
- Every other parameter, the conditions and the secret salt are unchanged; verified with a diff of version 21 against version 22.

## Economy notes
- **§5.2 Shop ads:** the daily maximum goes from 200 to **375 coins** (5 × 75; cap 5/day, cooldown 300 s unchanged). Next to the §14 budget: one normal 80-hoop run earns about 190 coins (2.37 coins/hoop below), so the shop's daily maximum equals about two runs.
- **§6.2 Bullseye:** the bot run (25 seeds × 80 hoops, live defaults) gives **2.366 coins/hoop** in total; the bullseye source pays **0.209 coins/hoop**, 8.8 % of coins. The same run at bullseye +2 gives 2.297 coins/hoop, so +3 adds about **+0.07 coins/hoop (+3 %)**.
  - Other sources: perfect 1.914, hoop 0.148, piggy 0.035, train 0.028/hoop.
  - Points/hoop 7.47; perfect rate 85.2 %; specials 3.70 per 10 hoops; items 2.39 per 10 hoops; rides 1.48 per run.
- **§7.3 Rides:** a portal ride goes from 12 to **6** perfect passes (the portal + 5 ride rings). Each ring still pays like a perfect pass (`coin_perfect` 2 coins, points `max(2, streak)`). A ride now pays about **12 coins instead of 24**, and about half the points. With at most 2 portals per run (§17), rides earn at most about 24 coins per run (was about 48).
- **Watch:** on the live set, the one-big-bonus rule removes 27–43 % of special hoops (PRD-2.3 target 10 %), and a forced FEVER can wait about 25 hoops (WP-T). Not changed in this release.

## §12 Achievements
- **48 achievements, 755 points.** Created in Play Console in the §12.1 order with 512 px icons; the 7 rides are hidden.
- The **Play Games configuration was published on 2026-10-14 at 12:53:50 CEST**. That was the only publish click besides the internal release; the evidence is in `tools/ach_*.png`.
- **iOS kit:** `store/achievements/ios/` (1024 px RGB icons, plus CSV and JSON for Game Center). The steps are in `PORT-IOS.md`; App Store Connect setup waits for iOS to reopen.
- Screenshots: `docs/p231/shots/s12_home_medal_568.png`, `docs/p231/shots/s12_toast_results_568.png`.

| # | Key | Name | Pts | Group | Android ID |
|---|---|---|---|---|---|
| 1 | `rank_egg` | EGG | 5 | rank | `CgkIsZz8pvUOEAIQBA` |
| 2 | `rank_chick` | CHICK | 5 | rank | `CgkIsZz8pvUOEAIQBQ` |
| 3 | `rank_fledgling` | FLEDGLING | 10 | rank | `CgkIsZz8pvUOEAIQBg` |
| 4 | `rank_flapper` | FLAPPER | 10 | rank | `CgkIsZz8pvUOEAIQBw` |
| 5 | `rank_glider` | GLIDER | 15 | rank | `CgkIsZz8pvUOEAIQCA` |
| 6 | `rank_falcon` | FALCON | 20 | rank | `CgkIsZz8pvUOEAIQCQ` |
| 7 | `rank_hawk` | HAWK | 25 | rank | `CgkIsZz8pvUOEAIQCg` |
| 8 | `rank_spike_ace` | SPIKE ACE | 30 | rank | `CgkIsZz8pvUOEAIQCw` |
| 9 | `rank_phoenix` | PHOENIX | 40 | rank | `CgkIsZz8pvUOEAIQDA` |
| 10 | `rank_legend` | LEGEND | 60 | rank | `CgkIsZz8pvUOEAIQDQ` |
| 11 | `ride_cannon` | BEAK FIRST | 10 | ride | `CgkIsZz8pvUOEAIQDg` |
| 12 | `ride_space` | SPACE TWEET | 10 | ride | `CgkIsZz8pvUOEAIQDw` |
| 13 | `ride_volcano` | FLAME-INGO | 10 | ride | `CgkIsZz8pvUOEAIQEA` |
| 14 | `ride_sea` | PENGUIN MODE | 10 | ride | `CgkIsZz8pvUOEAIQEQ` |
| 15 | `ride_pinball` | BUMPER BIRD | 10 | ride | `CgkIsZz8pvUOEAIQEg` |
| 16 | `ride_storm` | RUFFLED FEATHERS | 10 | ride | `CgkIsZz8pvUOEAIQEw` |
| 17 | `ride_all` | FREQUENT FLYER | 30 | ride | `CgkIsZz8pvUOEAIQFA` |
| 18 | `item_heart` | TWEETHEART | 5 | item | `CgkIsZz8pvUOEAIQFQ` |
| 19 | `item_shield` | TOUGH EGG | 5 | item | `CgkIsZz8pvUOEAIQFg` |
| 20 | `item_star_trail` | STARLING | 5 | item | `CgkIsZz8pvUOEAIQFw` |
| 21 | `item_hourglass` | TIME FLIES | 5 | item | `CgkIsZz8pvUOEAIQGA` |
| 22 | `item_mini_bird` | LITTLE BIRDIE | 5 | item | `CgkIsZz8pvUOEAIQGQ` |
| 23 | `item_coin_frenzy` | GOLDFINCH | 5 | item | `CgkIsZz8pvUOEAIQGg` |
| 24 | `item_egg` | EGGCELLENT! | 5 | item | `CgkIsZz8pvUOEAIQGw` |
| 25 | `item_piggy` | NEST EGG | 5 | item | `CgkIsZz8pvUOEAIQHA` |
| 26 | `item_jar` | BUG BUFFET | 5 | item | `CgkIsZz8pvUOEAIQHQ` |
| 27 | `item_feather` | LIGHT AS A FEATHER | 5 | item | `CgkIsZz8pvUOEAIQHg` |
| 28 | `item_puzzle` | PUZZLED PIGEON | 5 | item | `CgkIsZz8pvUOEAIQHw` |
| 29 | `item_all` | MAGPIE | 25 | item | `CgkIsZz8pvUOEAIQIA` |
| 30 | `master_hatch` | MOTHER HEN | 10 | mastery | `CgkIsZz8pvUOEAIQIQ` |
| 31 | `master_jar` | NIGHT OWL | 10 | mastery | `CgkIsZz8pvUOEAIQIg` |
| 32 | `master_stars` | SEEING STARS | 10 | mastery | `CgkIsZz8pvUOEAIQIw` |
| 33 | `master_picture` | BIRD'S-EYE VIEW | 15 | mastery | `CgkIsZz8pvUOEAIQJA` |
| 34 | `master_jackpot` | GOLDEN EGG | 15 | mastery | `CgkIsZz8pvUOEAIQJQ` |
| 35 | `hoops_10` | FIRST FLIGHT | 5 | hoops | `CgkIsZz8pvUOEAIQJg` |
| 36 | `hoops_25` | HOOPOE | 10 | hoops | `CgkIsZz8pvUOEAIQJw` |
| 37 | `hoops_50` | RING-NECKED | 20 | hoops | `CgkIsZz8pvUOEAIQKA` |
| 38 | `hoops_100` | FLYING COLORS | 40 | hoops | `CgkIsZz8pvUOEAIQKQ` |
| 39 | `vs_1` | BEAK TO BEAK | 10 | versus | `CgkIsZz8pvUOEAIQKg` |
| 40 | `vs_10` | PECKING ORDER | 25 | versus | `CgkIsZz8pvUOEAIQKw` |
| 41 | `vs_50` | RULES THE ROOST | 40 | versus | `CgkIsZz8pvUOEAIQLA` |
| 42 | `first_revive` | STILL TWEETING | 5 | more | `CgkIsZz8pvUOEAIQLQ` |
| 43 | `first_big_hoops` | BIG BIRD | 5 | more | `CgkIsZz8pvUOEAIQLg` |
| 44 | `first_fever` | HOT WINGS | 10 | more | `CgkIsZz8pvUOEAIQLw` |
| 45 | `skin_first` | FRESH FEATHERS | 10 | more | `CgkIsZz8pvUOEAIQMA` |
| 46 | `skin_all` | PROUD PEACOCK | 50 | more | `CgkIsZz8pvUOEAIQMQ` |
| 47 | `daily_7` | EARLY BIRD | 25 | more | `CgkIsZz8pvUOEAIQMg` |
| 48 | `daily_30` | HOMING PIGEON | 50 | more | `CgkIsZz8pvUOEAIQMw` |

## Versus (§4): log lines and Firebase Auth state
- **Pixel 6, Play build 2.3.1 (20), data cleared:**
  - The phone's account has **no Play Games profile**. The sign-in sheet asks to create one ("Een Play Games-profiel maken").
  - Log: `GameServices pgs_error: op=sign_in code=timeout`.
  - No `versus: link switched` line appeared, because there was no platform player.
- **Firebase Auth, read-only, before and after the round:** `u3nBdG6N…` last sign-in `2026-10-13T11:52:44Z`, unchanged.
- **Guest versus works:** VERSUS START found a rival (no `rules` solo) under the guest name `SwiftParrot278`, and a relaunch found a rival again under the same guest.
- **Open, for the owner (D-01):** run PRD §4 steps 2–6 on the Pixel 8 with the owner's Play Games profile:
  - the `versus: link switched` log;
  - a fresh sign-in on `u3nBdG6N…`;
  - the own name on the intro;
  - a relaunch without a new guest;
  - the network-cut retry.

  The switch logic has automated coverage only: §2/§3 tests, QA P1–P3 probes, one Auth queue.

## Device round (Pixel 6)
Full table: [`QA_DEVICE.md`](QA_DEVICE.md) (Sol, 2026-10-14). Evidence: `.worktrees/briefs9/evidence/device/`, outside git.

| Check | Result |
|---|---|
| No Ads off after the refund | PASS (already off; purchase sync 0) |
| §4 guest versus / signed-in switch | PARTIAL / **BLOCKED (D-01)** |
| §5 shop ad 75 (test ad) | PASS: wallet 0 → 75 |
| §6 bullseye +3 | PASS |
| §7 6-ring rides | PASS: cannon 6 passes; volcano and space done |
| §8 no GRAZE text | PASS |
| §9 heart without a panel | PASS |
| §10 instructions until hoop 0 | PASS (Play build) |
| §11 banner on the waiting screen | PASS (Play and debug) |
| §12 local unlocks, toasts, debug exclusion | PASS |
| §12 native Play Games list / sync | **BLOCKED (D-01)** |
| §13 shield hidden with the bird | PASS: cannon, volcano, space |
| §14 No Ads revive 250 → 500 | PASS |
| §15 rim-free FEVER 19.4 pt off centre | PASS: perfect, +2, streak 5 |
| §16 comet at hoops 10/50/150 | PASS: 5/6/6 passes, even spacing 614/548/598 pt |
| §17 portal cap | PASS: a third forced portal is discarded, count 2 |

**D-01 (setup blocker, not a code defect):** the Pixel 6's Google account has no Play Games profile, so the signed-in checks (§4.2–4.6, §12.10 native list and sync) couldn't run without changing the owner's accounts. The phone was left on Play 2.3.1 (20), with No Ads off, volume 0 and notifications denied.

## Owner notes
- The phone test ran on the **Pixel 6** (`24191FDF6008ZD`), as the owner chose; the Pixel 8 was not connected.
- The No Ads test order (GPA.3376-8876-7034-51055) was refunded with "Remove entitlement" at the start of the run.
- **Known flaky test:** `test/p22/s7_s31_qa_p3_postrun_test.dart` (a colour-fade timing check) fails now and then under load and passes alone.
- **Release-page AD_ID error:** still caused by the old production 1.0.1 build (versionCode 2); "Release without permission" was used again.
