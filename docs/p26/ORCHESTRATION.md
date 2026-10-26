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
| Builder | GPT-6.1 Sol (medium) via codex, one per WP, up to **6 in parallel** | implements exactly one WP in its own git worktree, adds the tests the WP names, runs the scoped verify before stopping, commits on its branch | touches paths outside its WP, edits `scripts/known_red_tests.txt`, weakens assertions, deploys, uses devices |
| Tester | Claude Opus 5.5 (medium), a detached `claude -p` process, one per build round | reviews the diff against the WP acceptance criteria, the PRD lines and SHARED_ELEMENTS.md; runs the named tests; writes a verdict PASS / FAIL with findings (blocker / major / minor) | edits product code (read + run only) |

Every builder and tester runs as a **detached process** started with `scripts/orch/spawn.sh` (it survives the Claude
session; its pid, log and exit code live in `.worktrees/briefs26/workers/<id>/`). Builder (worker id `<wp>-b<round>`,
cap 90 min):

```bash
scripts/orch/spawn.sh <wp>-b<n> 90 /home/killerhis/Projects/flappyspikes/.worktrees/p26-<wp> -- \
  codex exec -m gpt-6.1-sol -c model_reasoning_effort="medium" -s danger-full-access \
    --json -o /home/killerhis/Projects/flappyspikes/.worktrees/briefs26/<wp>.b<n>.last.txt \
    "$(cat /home/killerhis/Projects/flappyspikes/.worktrees/briefs26/<wp>.md)"
```

A fix round resumes the builder's codex session (`codex exec resume <session-id> "<findings>"`, same flags) so it keeps
its context. Full access is required: the smoke test of 2026-10-26 showed `workspace-write` blocks `git commit`
(index.lock) and Flutter's cache even with `--add-dir`; the brief's rules (paths, no secrets, no devices, no deploys)
bound the builder instead. ~/.codex/config.toml defaults to effort high: `-c model_reasoning_effort="medium"` overrides it.

Tester (worker id `<wp>-t<round>`, cap 45 min), in the WP's worktree:

```bash
scripts/orch/spawn.sh <wp>-t<n> 45 /home/killerhis/Projects/flappyspikes/.worktrees/p26-<wp> -- \
  claude -p --model claude-opus-5-5 --effort medium --permission-mode bypassPermissions --output-format json \
    "$(cat /home/killerhis/Projects/flappyspikes/.worktrees/briefs26/<wp>.t<n>.md)"
```

The tester prompt holds the WP brief, the diff range (`feat/2.6...p26/<wp>`), the builder summary, the verify tail,
the read-only rule and the verdict format of §4; the verdict is the `result` field of the worker's JSON log
(`--output-format json` also gives the token usage for the benchmark, §8).

## 2. SDLC per work package (pipelined: nobody waits on anybody)

1. **Plan** — the orchestrator writes `.worktrees/briefs26/<wp>.md`: goal, PRD line ranges, approved design pages and
   text ids, shared masters to reuse, the decisions from PRD §8.3 that apply, **paths** (narrow), acceptance criteria
   (testable), tests to add, hotspot regions it may touch, and the standing rules (BUILD_NOTES.md). Briefs for the next
   WPs are written while builders run, so a free lane is filled at once.
2. **Build** — worktree `.worktrees/p26-<wp>` on branch `p26/<wp>` from the latest green `feat/2.6`; the Sol builder
   works and commits. While working it runs single test files; before it stops it runs the **scoped** verify
   (`VERIFY_BASE=feat/2.6 VERIFY_SCOPED=1 bash scripts/verify.sh`: analyze + the changed/matching tests + the playability
   core, ~1–3 min), not the whole suite.
3. **Verify + test in parallel** — when the builder exits, the orchestrator starts, at the same moment, the **full**
   verify (`<wp>-v<n>` worker, heavy lock) AND the Opus tester (`<wp>-t<n>`). A red verify stops the tester and goes
   straight back to the builder with the tail (counts as a fix round). PASS needs both: verify green and no
   blocker/major.
4. **Fix rounds** — FAIL → the same codex session gets the findings + verify tail at once (resume) → step 3 again.
   **At most 3 fix rounds.** Still failing → the orchestrator rewrites or splits the WP (or asks the council: one
   Opus + one Sol answer on a written brief). **Nothing merges with a FAIL verdict or a red verify.**
5. **Merge (fast, never blocks a lane)** — see §5.2: the WP joins the merge queue; a merge takes ~1–3 min (rebase,
   analyze + the WP's tests + the core tests, fast-forward, push), not a full suite. The full suite runs in the background
   on `feat/2.6` (rolling integration verify). The lane is free for the next WP the moment the WP enters the queue.
6. **Wave gate (rolling)** — a wave is "done" when its last WP merged and the integration verify on that head is green,
   plus the GitHub Actions iOS build and a short wave report (`docs/reports/p26-W<n>.md`). WPs of the next wave do NOT
   wait for the gate: each starts as soon as its own dependencies are merged and the latest integration verify is
   green (PRD §4: never start on a red tree).

The known-red list must be **empty** from the end of W1 and stay empty.

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
  CDP) + the latest `tools/upload_aab*.js`; a login wall → open the login page and tell the owner in the chat, keep working on
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

## 5. Maximum parallelism (22 GB RAM, 20 cores)

### 5.1 Lanes
- **Up to 6 Sol builders at once** (owner: as much parallel as possible), filled from a ready queue: every WP whose
  dependencies are merged, across waves, highest priority first (W1 fixes and the deploy path, then the longest
  dependency chains: WP-J → results/levels UI, F9 → cards/board rows, G1 → missions UI/Star Road).
- **Testers are not limited by lanes:** one Opus tester per finished build round, running next to the builders.
- Two WPs run together only when their paths and hotspot regions do not overlap. **Hotspots (one WP at a time each):**
  `lib/run/director/run_director.dart`; the run-end block of `lib/game/flappy_game.dart` (and `_beginHomeVisit`);
  `lib/game/storage.dart` + `tool/gen_obf_strings.dart` + anchors; `lib/run/config/tuning_defaults.dart`;
  `lib/run/screens/results_screen.dart`; `lib/components/home/home_screen.dart`; `functions/src/board_store.ts`.
  To keep lanes full, the first WP of a chain that needs a hotspot extracts a seam (e.g. J2's `RunEndBookkeeping`,
  S0 adds all keys at once) so later WPs work in new files.
- **Full-suite slots:** at most **3** full Flutter suites at once (`VERIFY_HEAVY_LOCKS`, lock files in
  `.worktrees/briefs26/locks/`); builders' scoped checks and single test files do not take a slot. The functions
  emulator suite serializes itself (`functions/scripts/test.sh` flock).
- **Memory guard:** no new builder or full suite while MemAvailable < 4 GB; then lanes drop to what fits (never kill a
  running verify to start a builder).
- Never two builders in one worktree; never a second flow on a WP that is in progress.

### 5.2 Merge queue (merging never slows the build)
- One merge at a time (seconds of git work), in the order WPs pass, run as a background worker `merge-<wp>`:
  1. rebase `p26/<wp>` on the latest `feat/2.6`; a conflict → back to the WP's builder (resume) as a fix round;
  2. **fast check:** `flutter analyze` + the WP's own tests + the files the rebase touched + the core tests (scoped
     verify against the WP's base), and the functions tests only when `functions/` changed — ~1–3 min;
  3. fast-forward `feat/2.6`, push, log, start the next WP in that lane.
- **Rolling integration verify:** a background worker always runs the full `scripts/verify.sh` on the newest
  `feat/2.6` head (one at a time; if more merges land meanwhile, the next run takes the newest head). Green → that head
  is the base for new worktrees. Red → the culprit is among the merges since the last green head: the orchestrator
  reruns the failing tests on each of those merge commits, reverts the culprit on `feat/2.6`, and sends it back to its
  builder as a fix round. New WPs branch from the last green head meanwhile, so nobody waits.
- Prune `scripts/known_red_tests.txt` after a green integration run that shows listed tests passing.

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

Things the orchestrator cannot finish alone (say so in the chat, keep building everything else): a login wall; a deploy step that would delete prod indexes not
in the file; a council split on a product question with no PRD rule.

Logs: `.worktrees/briefs26/RUNLOG.md` (one line per event), worker logs in `.worktrees/briefs26/workers/<id>/log`, state in `.worktrees/briefs26/STATE.md`, wave reports
in `docs/reports/`.

## 7. Heartbeat, stuck workers and recovery (the orchestrator never waits blind)

All state lives on disk, so any orchestrator (this chat session or a headless pass) can pick up the build:
`.worktrees/briefs26/STATE.md` (wave, every WP with status / round / worker id / next step — the orchestrator rewrites
it after every action), `RUNLOG.md` (one line per event), `workers/<id>/` (pid, log, exit), `lease` (who orchestrates,
since when). Scripts: `scripts/orch/` — `spawn.sh`, `status.sh`, `stop.sh`, `watch.sh`, `lease.sh`, `tick.sh`.

### 7.1 In-session heartbeat (the normal case)
- While workers run, the orchestrator always has `scripts/orch/watch.sh 10` running in the background. It refreshes
  the lease every 30 s and exits — waking the orchestrator — when a worker finishes, dies, stalls or passes its cap,
  or after 10 minutes.
- On every wake the orchestrator: runs `status.sh`, acts on every DONE / STALLED / OVERCAP / DEAD worker, starts ready
  WPs up to the parallel limit, updates STATE.md, posts the chat update (§7.4) and **starts the next `watch.sh` before
  ending its turn**. A turn never ends with workers running and no watcher, or with idle lanes while WPs are ready.
- If the lease shows `headless-…` and `.worktrees/briefs26/headless.lock` is held, a headless pass is working: the
  session waits for it to finish (watch only), then takes the lease back.

### 7.2 External heartbeat (the session died)
- systemd user timer `orch-tick.timer` (every 30 min; units in `scripts/orch/`, installed at W0) runs `tick.sh`.
- `tick.sh` does nothing unless `.worktrees/briefs26/ORCH_ACTIVE` exists and `ORCH_STOP` does not. If the lease is
  older than 45 min and no headless pass runs, it starts ONE headless orchestrator pass:
  `claude -p --model claude-opus-5-5 --effort medium --permission-mode bypassPermissions` with
  `scripts/orch/headless_prompt.md` (max 75 min). The pass does the same as a wake in §7.1 (without waiting on
  workers), logs every action with `[headless]`, and exits; the next tick continues.
- When the owner next talks to the chat session, it reads STATE.md / RUNLOG.md and summarises what happened meanwhile.

### 7.3 Stuck rules
- **Builder:** no log output for 20 min (STALLED) or more than 90 min running (OVERCAP) → read the log tail, decide
  (a slow full test run under the heavy lock is not a stall: check the verify process first), then `stop.sh` and resume
  the same codex session with a nudge ("you stalled at …; continue from …, keep to the brief"). A second stall on the
  same WP → restart it fresh from the brief (new worktree state kept). Each counts as a fix round.
- **Tester:** STALLED 20 min or more than 45 min → `stop.sh` and start a new tester with the same prompt (once); a
  second failure → the orchestrator splits the review into smaller parts.
- **DEAD** (no exit file, process gone) → treat as a crash: read the log, restart once, then escalate as a stall.
- **Verify / merge** steps the orchestrator runs itself also go through `spawn.sh` (worker id `<wp>-v<n>`, cap 30 min)
  when they take longer than a turn should.
- Memory: no new worker while MemAvailable < 4 GB; then the lowest-priority running builder may be paused (stop +
  resume later).

### 7.4 What the owner sees in the chat
- One line per **merge** (WP, rounds, tests added).
- One line per **real problem or steer** (a split after 3 failed rounds, a stall restart that failed, a deploy step,
  a login wall, a red wave gate).
- A **status update every 10 minutes** (the heartbeat): wave, WPs running / waiting / merged, anything stuck.
- Wave done, release done, and the final report. Nothing is sent outside the chat.

### 7.5 Start and stop
- Start (W0): `touch .worktrees/briefs26/ORCH_ACTIVE`; install and enable the timer
  (`cp scripts/orch/orch-tick.{service,timer} ~/.config/systemd/user/ && systemctl --user daemon-reload &&
  systemctl --user enable --now orch-tick.timer`).
- Owner says stop: `touch .worktrees/briefs26/ORCH_STOP`, `stop.sh` every running worker, disable the timer, write
  STATE.md. Resume: remove `ORCH_STOP`, enable the timer, continue from STATE.md.
- Done (after the final report): remove `ORCH_ACTIVE`, disable the timer.

## 8. Benchmark logging (required; compared with df4 afterwards)

Every orchestrator (session or headless) writes append-only JSON Lines to `bench/events.jsonl` in the `feat/2.6`
checkout (one object per line, ISO timestamps with timezone, never rewrite a line) through `scripts/orch/bench.py`, and
commits `bench/` with each merge. Event types and when they are written:

| Event | Written when | How |
|---|---|---|
| `run_start` | W0, once: base SHA, branch, scope, machine, max parallel agents | `bench.py ev run_start base_sha=… scope:='["W1",…]' …` |
| `plan` | each wave's briefs are written: ts_start/ts_end, tasks (task_id, title, req_ids, deps, planned_paths) | `bench.py ev plan …` |
| `turn` | every finished builder / tester worker (model, effort, role build/fix/review, duration, outcome, error, tokens) | `bench.py worker <id> --task T --role R --wave W` (parses codex `turn.completed` usage / `claude -p` JSON usage) |
| `turn` (orchestrate) | end of every orchestrator wake: tokens from the Claude transcript between wake and sleep; headless passes too | `bench.py orch-turn --from <wake ISO>` |
| `test` | every verify / test run: cmd, scope targeted/full, where task-worktree/integration, exit, failures, seconds | verify workers run as `bench.py test … -- bash scripts/verify.sh`, or `bench.py worker <id>` |
| `review` | every tester verdict: verdict, findings with severity / file / issue | written by `bench.py worker <id> --role review` |
| `merge` | every merge: sha, conflict, resolved_by, files_changed, lines ±, ts_start/ts_end | `bench.py ev merge …` (numbers from `git diff --shortstat`) |
| `wait` | a ready WP waited for a slot / dependency / merge / provider: ts_start (ready) → ts_end (started) | `bench.py ev wait …` (ready time kept in STATE.md) |
| `milestone_done` | a wave gate: full_suite {exit, failures, seconds}, main_red_minutes, reverts | `bench.py ev milestone_done …` |
| `human` | every owner message that changes the build (feedback, stop, decision) | `bench.py ev human what=…` |
| `incident` | capacity / rate-limit / timeout / crash / other, with detail | `bench.py ev incident what=… detail=…` |
| `final_check` / `run_end` | after W5 | see below |

Task ids are the WP keys of §3; `wave` (W1…W5) stands in for df4's milestone. At the end:
`bash scripts/verify.sh` UNSCOPED (VERIFY_BASE and VERIFY_SCOPED unset — the same unscoped path df4 ran with
DF4_VERIFY_BASE unset) on the final commit, full log in `bench/final-verify.log`, failures listed against
`scripts/known_red_tests.txt` (event `final_check`); `bench/acceptance.md` (PRD acceptance criteria per wave: met yes/no +
the proving test, from the briefs and tester verdicts); then `bench.py summary` writes `bench/summary.md` (wall time per
wave and total, tasks, turns and tokens per model, full-suite runs, fix-round distribution, final check, acceptance,
human interventions and incidents). Never change `scripts/verify.sh` or tests to make the final check pass.
