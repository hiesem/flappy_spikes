# Flappy Spikes 2.6.0 (49) — build report

**Status 2026-10-29 06:55: released to Play internal testing** ("Available to internal testers", release 43, 06:49).
Source: `feat/2.6` at `60d91094` (pushed). Version commit `b7cebee0`.

## What shipped

PRD-2.6 "fun & progression" (docs/p26/PRD-2.6-fun-progression.md), built in 90 work packages: the difficulty curve and
formations (WP-D), the showcase runs (B), the 31-level track with rewards (J), brackets and duel staircase (E), the economy
gates (F), missions, day streaks and the weekly course (G1–G5), Star Road seasons with the Home popup (G6), the daily
leaderboard with gift boxes (LB), beat-your-best (K), analytics and A/B plumbing (A/H), achievements and icons (J9/ART1),
polish (POL1–POL4) and goldens (GOLD).

Built by DeepSeek V4.1 Flash builders (from 2026-10-28; GPT-6.1 Sol/Terra before that) through codex, each package checked
by an Opus tester and a full verify, orchestrated by Opus.

## Gates

| Gate | Result |
|---|---|
| Full Flutter suite (integration verify on `b7cebee0`) | green — 5813 passed, 361 skipped |
| Backend tests (`npm --prefix functions test`, Firestore emulator) | 456 passing |
| `flutter analyze` | clean |
| Anchor-string check on the release AAB (3 ABIs) | ok — 94 anchors absent (after FIX4) |
| Pixel 6 upgrade test (2.5.0 (48) → 2.6.0 (49) via Play) | pass — see below |

## Server (Firebase wave 0, project flappy-spikes-a2b55) — deployed 2026-10-29 03:29

- Firestore indexes: prod had 0 composite indexes / 0 overrides; repo adds 3 + 9 (additive only).
- Firestore + Storage rules released.
- Functions: created `lbSubmitRun`, `lbGetBoard`, `lbClaimGift`, `lbSettleGroups`; updated the 8 existing functions.
- TTL: `players`, `versusFlags` and the five lb collections (`lbPlayers`, `lbGroups`, `lbGifts`, `lbTomb`, `lbFlags`) ACTIVE.
- **Not done: the one-time leaderboard import (`functions/scripts/lb_import.ts`)** — see owner actions.

## Device test — Pixel 6 (24191FDF6008ZD), Play update over 2.5.0 (48), data kept

- Launch, no crash, no Flutter errors in logcat.
- Upgrade state: coins kept (44), Ad-free purchase kept, level track starts fresh ("?" emblem), Shop/Skins locked by the
  2.6 unlock rule.
- Versus run against the live backend (rival found), YOU LOSE result, gift-box reveal → achievement reward (Constellation
  trail, EQUIP / LATER), rank page (UNRANKED 0/25 → HATCHLING), back to Home.
- Leaderboard: first-open guide, then the empty "Your group starts with your next run" state (a 0-point run does not count;
  the server rejects runs under 3 points).
- Seen: a thin pink bar at the right edge of the first results page, at the height of EQUIP/LATER (open item).

## Fixes found during the release run (all merged)

- **FIX2** — a second Back on the Home LEVEL UP popup did nothing, so the economy probes (and players) could get stuck before
  START; Back now acts like LATER (§8.3-28).
- **FIX3** — leaderboard: numbers drawn without an app font, 30 pt title colliding with the buttons, pinned own row covering
  list rows, names centred; Star Road popup label on cream instead of the pink header. Now as the mock
  (`leaderboard.html`, `star_road_popup.html`); the tag has one shared master.
- **FIX4** — release blocker: `firstWinDay` (a `CoinSource` enum name) and the journal key `missions` were whole strings in
  the AOT snapshot. Renamed `CoinSource.firstWinBonus` (analytics still `first_win_day`) and journal key `records`.
- **POL4** — Star Road popup: CTA during a settling season no longer strands the player; the popup day is only used when
  the popup opens; the pending check is cached and cleared on season rollover, stars and claims.

## Decisions taken (PRD §8.3, numbers 24–29)

24 G1b storage keys granted · 25 gift podium stores no names (live lookup; nothing survives Delete My Data) ·
26 gift-opening rays stay R1 gold (O98 over PRD 1207) · 27 Star Road season 1 starts Monday 2026-10-26 UTC, tuning key
`star_road_epoch_day` · 28 Back on LEVEL UP = LATER · 29 rising pitch (Star Road tiles O91, LB5) ships flat: the `Sfx`
master has no per-play rate.

## Owner actions

1. **Leaderboard import** — run `! gcloud auth application-default login`, then say "go import": the orchestrator shows the
   `lb_import.ts` preview and applies it with the keep-list hiesem + hiesemie. Until then the boards hold 2.6 runs only.
2. Before production: the release-blocking test-player cleanup (C9, `lb_cleanup_test.ts --keep <owner uids>`).
3. Play Console AD_ID: every internal release is published with "Release without permission". The 2.6.0 AAB manifest does
   contain `com.google.android.gms.permission.AD_ID`; the warning comes from another active artifact. Check the advertising
   ID declaration / older tracks before production.
4. iOS was not built in this run (Android internal only).

## Open items (not blocking)

- Pink bar at the right edge of the first results page (device).
- Flaky test `test/p22/s7_s31_qa_p3_postrun_test.dart` (~1 in 10 runs on `feat/2.6`: grey post-run colour check sees cream);
  existed before FIX4.
- Tester minors logged in `.worktrees/briefs26/minors-W1.md` (e.g. multi-reward results path lacks the item tile, G1d region
  name, import order).
- Debug symbols + obfuscation map: `.worktrees/briefs26/symbols_49/` (keep for crash symbolication); AAB copy:
  `.worktrees/briefs26/flappy_spikes-2.6.0+49.aab`.
