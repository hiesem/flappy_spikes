# Flappy Spikes 2.6 — orchestration plan (unattended build to a working 2.6.0)

Status 2026-10-26. Owner-approved setup (2026-10-26). This file is the operating manual for the orchestrator. The
spec stays `PRD-2.6-fun-progression.md`; its **§8 Build status** says what is built, what needs fixing and what is
left. The evidence per requirement (file:line, test results) is in `docs/p26/status/a1…a7-*.md`. Work-package
details (paths, acceptance criteria) live in those status files. This plan names each package, orders it and says how
it is built.

## 1. Roles

| Role | Who | Does | Never |
|---|---|---|---|
| Orchestrator | Claude Opus 5.5 (medium), the main Claude Code session | plans each wave, writes the builder brief per work package (WP), creates worktrees, starts builders and testers, runs the verify gate, merges, prunes the known-red list, decides open questions (records them in §8 / SPEC.md), deploys, device-tests, releases, reports | writes product code itself (except trivial merge-conflict resolution and infra in `scripts/`), merges a WP without a tester PASS |
| Builder | GPT-6.1 Sol (medium) via codex, one per WP, up to **4 in parallel** | implements exactly one WP in its own git worktree, adds the tests the WP names, runs `bash scripts/verify.sh` before stopping, commits on its branch | touches paths outside its WP, edits `scripts/known_red_tests.txt`, weakens assertions, deploys, uses devices |
| Tester | Claude Opus 5.5 (medium), an Agent subagent, one per build round | reviews the diff against the WP acceptance criteria, the PRD lines and SHARED_ELEMENTS.md; runs the named tests; writes a verdict PASS / FAIL with findings (blocker / major / minor) | edits product code (read + run only) |

Builder command (from the orchestrator, background):

```bash
codex exec -m gpt-6.1-sol -c model_reasoning_effort="medium" -s workspace-write \
  -c sandbox_workspace_write.network_access=true \
  --add-dir ~/flutter --add-dir ~/.pub-cache --add-dir ~/.npm --add-dir ~/.cache \
  -C .worktrees/p26-<wp> --json -o .worktrees/briefs26/logs/<wp>-r<n>.last.txt - < .worktrees/briefs26/<wp>.md \
  > .worktrees/briefs26/logs/<wp>-r<n>.jsonl 2>&1
```

(~/.codex/config.toml defaults to effort high and full access: the flags above override both. If the sandbox blocks
the toolchain, fall back to `-s danger-full-access` for that builder and note it in the RUNLOG.)

Tester: `Agent(subagent_type general-purpose, model opus, effort medium)` with the WP brief, the diff
(`git diff feat/2.6...p26/<wp>`), the builder summary and the verify tail; it answers in the verdict format of §4.

## 2. SDLC per work package

1. **Plan** — the orchestrator writes `.worktrees/briefs26/<wp>.md`: goal, PRD line ranges, approved design pages and
   text ids, shared masters to reuse, the decisions from PRD §8.3 that apply, **paths** (narrow), acceptance criteria
   (testable), tests to add, hotspot regions it may touch, and the standing rules (BUILD_NOTES.md).
2. **Build** — worktree `.worktrees/p26-<wp>` on branch `p26/<wp>` from the current `feat/2.6`; the Sol builder works and
   commits. It must run `bash scripts/verify.sh` (whole Flutter suite + functions tests when `functions/` changed).
3. **Verify** — the orchestrator re-runs `bash scripts/verify.sh` in the worktree (under the heavy lock, §5). Red →
   back to the builder with the tail (counts as a fix round).
4. **Test** — the Opus tester reviews and runs the WP's tests. PASS = no blocker/major open.
5. **Fix rounds** — FAIL → the same builder session gets the findings (resume) → verify → test. **At most 3 fix
   rounds.** Still failing → the orchestrator rewrites or splits the WP (or asks the council: one Opus + one Sol
   answer on a written brief) and starts again. **Nothing merges with a FAIL verdict or a red verify.**
6. **Merge** — rebase/merge onto the latest `feat/2.6`, re-run verify on the merge result, fast-forward `feat/2.6`,
   push. Prune `scripts/known_red_tests.txt` if listed tests now pass. Log the WP in the RUNLOG.
7. **Wave gate** — after the last WP of a wave: full `bash scripts/verify.sh` on `feat/2.6` (flutter analyze clean,
   whole flutter test, functions tests), the GitHub Actions iOS build green, and a short wave report
   (`docs/reports/p26-W<n>.md`). A red gate gets repair WPs before the next wave starts (PRD §4: later waves never start on
   a red tree).

The known-red list must be **empty** at gate W1 and stay empty.

## 3. Waves and work packages

Keys refer to the status files (`docs/p26/status/`), which hold the paths and acceptance criteria. Hot files are
serialized (§5): a WP that touches one waits for the WP before it.

### W0 — setup (orchestrator, no builders)
- RUNLOG `.worktrees/briefs26/RUNLOG.md`; brief template; heavy lock for verify; `flutter pub get` in each worktree.
- Prune the 3 passing `curve_ceiling … squeeze=true` lines from `scripts/known_red_tests.txt`.
- iOS CI on `feat/2.6`: add the branch to `.github/workflows/build.yml` triggers (a7 risk 9; O27: iOS compile per wave).
- Strike N1b ("freeze" text) from `texts.html` usage: builders build N1a only (O46; decision 8.3-9).

### W1 — finish waves 0 and 1 (FIX), then the server deploy
Server (a5) — before the deploy:
- **S1** wave-0 data-path gaps: `look.card` into pool entries, `space` in `firestore.rules`, the `exactRank` index + an index-coverage test.
- **S3** independent Opus review of the unreviewed server merges (#87, #88 r2, #89 r3, #8, #11) → findings feed S4.
- **S2** leaderboard read cost: O(1) hidden-ghost suppression, tie rank by count query (after S1).
- **S4** cleanup/settle hardening, runbook fixes (`set_ttl.sh` groups; indexes deploy enables TTL) (after S2).

Curve and bot (a3, a4) — `run_director.dart` is a hotspot, so these run strictly one after another:
- **D-SPRING** restore springs before hoop 50 (`squeezeNextSlot`), drop or limit the 568 pre-calm hack, rewrite SPEC.md:1938-1945.
- **D-R2** full-band centres + R2 asserted on the drawn Δy (decision 8.3-3; a3 WP-a3-2 option A).
- **D-POLISH** calm keys read from tuning, revive = 3 calm slots, `run_extra.downgraded`, the ≤ 15° tilt sign (a3 WP-a3-3).
- **D-TABLES** table hygiene, spawn_tables.json fixture, mirror test (a3 WP-a3-4).
- **D-SYNC** sync rails passable on one line. **D-SLALOM** slalom steps Δy 110–130 alternating (decision 8.3-4).
- **D-TESTS** small test gaps (oracle: no motion in squeeze, D6 introduction claims, vacuous test, `fourSlotHazardCost`).
- **D-BOT** a real closed-loop human-noise bot (σ and extra chance as parameters). **D-CAL** calibrate against 2.5
  out of tree, two gates (σ 90 ms baseline vs 2.5; calibrated σ ≈ 50 ms ≥ 40), SPEC DEVIATION (decision 8.3-1).
- **D-SHAPES** tune formation shapes 4–6 with the calibrated bot (after D-CAL).

Showcase (a2) and analytics/gates (a1):
- **B1** wire the showcase into production (inert in tests, e2e and soak builds; decision 8.3-6).
- **B2** showcase analytics (merges a1's B-WIRE-AN): one `highlight_seen`, real `showcase_end` values, `ftue_step showcase_done`.
- **B3** showcase course = normal mix (remove the ±7 flattening; portal theme no-repeat) (hotspot `run_director.dart`).
- **B4** run-level showcase tests (flown, not `grab()`). **B5 = E0** debug runs never upload (`countsForUpload`).
- **A1** analytics correctness + the #90 minors. **A2** analytics names/limits test.
- **C2L** budget the launch/resume Home visit. **C3R** rating minimum from tuning. **C1T** real squeeze-gate determinism test.

**Gate W1**, then **deploy wave 0** (owner-approved: deploy when tests are green): compare prod indexes first
(`firebase firestore:indexes`), then indexes → rules → functions (`npm --prefix functions run deploy`) → TTL check
(`set_ttl.sh status`) → `lb_import.ts --keep <hiesem, hiesemie uids>` preview, then `--apply`. Log every step and the
console state. Smoke-test the callables with the emulator e2e first; after the deploy, one live call from a debug
build on the Pixel 6 that is **not** signed into the owner's linked account (a `t:1` run hides a uid for good, a5 risk).

### W2 — progression model (PRD wave 2)
- **S0** all new storage + tuning keys for waves 2–4 in one WP (a6 WP-S0 merged with a7 M3-0): obf strings, anchors,
  seal hashes for `lvlIndex` / `lvlPending`, the 2.5 → 2.6 sealed-store upgrade test, Delete my data, retire `level_rewards`.
- **J1** level table + pure track + reward roll. **J2** LevelProgress rewrite, payout, run-end wiring, analytics (extract
  a `RunEndBookkeeping` helper first: the run-end block is the main hotspot).
- **E1** brackets + `plv` client + T4 line (removes `levelFor`). **E2** duel staircase client (integer tenths as the server).
- **F1** shop unlock R8 + wallet lifetime counters + economy events (decision 8.3-10).
- **K** beat your best (variant A). **J9** rank achievements on run score. **H** A/B arm plumbing (one arm; decision 8.3-12).
- **LB1** leaderboard client model + service. **LB2** submit queue + run-end submit + Delete my data. **LB3** `gift_apply`
  (server contract: `{ok, id, tier, prize}`; decision 8.3-11).
- **F2** economy budget test (after D-CAL; with a7 M4-ECON).
- Gate W2.

### W3 — daily meta (PRD wave 3)
- **G1a** missions model → **G1b** wiring + payout → **G1c** UI (strip, panel, results pips) → **G1d** chest + reroll.
- **G2a** day streak + restore model → **G2b** flame chip, streak card, COLLECT → **G2c** STREAK LOST popup + restore ad.
- **G3** state-aware notifications + decay (N1a only).
- **C2W** popup budget extended with STREAK LOST, streak reward, GO TO COLLECT, missions chest, Star Road (persisted day
  key, never in runs 1–3) (a1 C2-WAVE3; after G1d, G2c, LB3).
- Gate W3.

### W4 — long-term layer and results/levels UI (PRD wave 4; WP-J UI built here)
- Results and levels: **J3** results level bar + level-up stage → **J4** reveal sheet + payout → **J5** Home catch-up
  popup; **J6** Levels screen (hostable inside the G4 tabs); **J7** emblems in code (32 slots, painted fallback).
- Cards and skill items: **F9a** catalogue + `look.card` → **F9b/c/d** frame / name / sticker painters → **F9e** shop
  CARDS tab + fixed header → **F9f** cards in versus. **F10a** skill model → **F10b** skill UI + HOW TO EARN →
  **F10c** skill art (2 parts). **J10** the 10 new achievements + counters (Play/Game Center drafts: orchestrator; publish: owner).
- Leaderboard UI: **LB4** board screen + Home entry (trophy opens our board; medal box removed, O63) → **LB5** picture
  guide → **LB6** results climb → **LB7** GO TO COLLECT + gift opening.
- Levels tabs and goals: **G4a** tabs shell + Home NEW tag → **G4b** Worlds + SPACE FLYER; **G5a** weekly course model
  → **G5b** weekly UI; **G6a** first win of the day; **G6b** flight guide; **G6c** puzzle album; **G6d** Star Road
  model → **G6e** screen + claims → **G6f** Home popup.
- Gate W4.

### W5 — art, polish, docs, release
- **J8** 32 emblem PNGs (Sol export from `emblems.html`). **ART1** 10 achievement icons export. **GOLD** goldens at 568 / 711.
- **DOC** WP-I: SPEC deviations, ARCH module map, BUILD_NOTES, the measurement doc.
- Version `2.6.0+49` (pubspec), release notes drafted from T13 (owner may edit later).
- **Gate W5 = release gate:** known-red list empty; flutter analyze clean; whole flutter test + functions tests green;
  iOS CI build green; obfuscated release AAB built with the upload key, anchor-string check, symbols kept outside the repo.
- **Device test (Pixel 6, 24191FDF6008ZD):** install a release-like build with `--no-uninstall`; play a fresh-install path
  and an upgraded 2.5 install (fresh level start, coins and items kept, showcase runs 1–3, missions / streak / weekly
  course reachable, level-up reveal, board + gift box, beat-your-best). Phone rules: never touch the volume, never lock,
  never tap a real ad, never buy with a real card, never reset. Kill Gradle/Kotlin daemons by PID after Android builds.
- **Release:** upload the AAB to Play **Internal testing** and roll it out to internal testers only (owner-approved
  2026-10-26). Never closed/open/production, never "Send for review". Tools: `tools/browser_linux.js` (Chromium over
  CDP) + the latest `tools/upload_aab*.js`; a login wall → open the login page and notify the owner, keep working on
  anything else.
- Final report `docs/reports/p26-FINAL.md`: what was built, every decision and DEVIATION for the owner to confirm,
  test and device results, costs, and the owner actions left (§6).

## 4. Tester verdict format

```
VERDICT: PASS | FAIL
- [blocker|major|minor] <file:line> — <what is wrong> — fix: <what to do>
TESTS RUN: <files and results>
NOTES: <acceptance criteria checked, one line each>
```

Blocker/major → FAIL. Minors are collected into a "polish" WP per wave, never dropped.

## 5. Running in parallel safely (22 GB RAM)

- **Up to 4 Sol builders at once**, only on WPs whose paths and hotspot regions do not overlap.
- **Hotspots (one WP at a time each):** `lib/run/director/run_director.dart`; the run-end block of
  `lib/game/flappy_game.dart` (and `_beginHomeVisit`); `lib/game/storage.dart` + `tool/gen_obf_strings.dart` + anchors;
  `lib/run/config/tuning_defaults.dart`; `lib/run/screens/results_screen.dart`; `lib/components/home/home_screen.dart`;
  `functions/src/board_store.ts`. New code goes into new files where the WP allows; edits in hot files stay inside a
  `// region P26-<WP>` block.
- **Heavy lock:** at most 2 full Flutter suites at once — verify runs with
  `VERIFY_HEAVY_LOCKS="<lockdir>/heavy-0 <lockdir>/heavy-1"`; builders are told to run single test files while working.
  The functions emulator suite serializes itself (`functions/scripts/test.sh` flock).
- New lanes wait while MemAvailable < 4 GB.
- Never two builders in one worktree; never a second flow on a WP that is in progress.

## 6. Autonomy, stops and owner actions

The orchestrator runs every wave without asking (owner mandate 2026-10-26: build the whole PRD unattended to a working
2.6 on Play internal). It records each decision in PRD §8.3 (or SPEC.md for gameplay) and lists it in the final report.

Approved for the orchestrator (2026-10-26): commits and pushes on `feat/2.6` and `p26/*` branches; the wave-0 Firebase
deploy (indexes, rules, functions, TTL, `lb_import --apply` for the owner's two real accounts) once tests are green;
Play Console achievement drafts; the Play internal upload + internal roll-out.

Still the owner's (listed in the final report, never done by the orchestrator): closed / open / production tracks and
"Send for review"; App Store / TestFlight (2.6 is Android-only, O19; iOS = CI compile); publishing achievements;
GA4 / BigQuery console settings (A4, O10, O43); Play Data safety / App Store privacy updates (C5); the privacy-policy
page deploy (PV-10) unless the owner says otherwise; the release-blocking test-player cleanup before production (C9);
any spending.

Stops (notify the owner, keep working on anything else): a login wall; a deploy step that would delete prod indexes not
in the file; a council split on a product question with no PRD rule.

Logs: `.worktrees/briefs26/RUNLOG.md` (one line per event), builder logs in `.worktrees/briefs26/logs/`, wave reports
in `docs/reports/`.
