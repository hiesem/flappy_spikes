# a5-server — PRD 2.6 server side (WP-E server, WP-LB server, F9/G4 server parts, wave-0 deploy readiness)

Tree: `.worktrees/p26` @ a57a7fb (feat/2.6). Read-only audit, 2026-10-26.

## 1. Summary

- The wave-0 server code (M0 + M1F fix-ups #87–#89) is **almost complete and green**: `npm --prefix functions test`
  (full suite, run under `functions.lock`) = **433 passing, 0 failing** (log: `audit/a5-functions-test.log`).
- E4 brackets + `plv`, E5 reference staircase + shared fixture, E6 `passHist` + soft `jump` + `curves.test.ts`, the F9
  `validCard` (schema + rules), all LB3 callables / scheduler / Delete My Data / name hooks / import / cleanup exist and
  have tests for every PRD-named case.
- The **#88 open major (TODAY shows a hidden ghost from a stale group read) is FIXED in the code**: `readTodayGroup`
  (`functions/src/board_store.ts:1250-1262`) reads the group and every ghost owner's `lbPlayers` doc in one transaction;
  regression `board_store.test.ts:652` passes. It was never reviewed by a tester (round-2 verify red on Flutter flakes).
- **Three server gaps must be fixed before the wave-0 deploy** (deploy is "one functions + rules deploy before any app
  build"): (a) pool entries drop `look.card`, so opponents never see versus-card cosmetics; (b) `firestore.rules`
  does not allow a `space` field on `players/{uid}`, so the G4 flag can never reach the server (a client that writes it
  gets every player write denied); (c) `exactRank` runs `hidden == false && bestShadow > x` (count), which needs a
  composite index that `firestore.indexes.json` does not declare — the declared `(hidden, bestShadow, best desc)` index
  is used by no query. The emulator does not enforce indexes, so tests cannot catch (c).
- Two cost/perf issues break the PRD cost model ("one read per board open"): up to ~49 ghost-owner reads per board open
  and per submit (#88 fix), and an unbounded tie read in `exactRank`.
- Client parts of WP-E / WP-LB (lib/, UI) are TODO (waves 2/4); only `lib/versus/brackets.dart` and
  `lib/services/leaderboard_limits.dart` exist.
- No deploy, TTL, import or cleanup has run (owner actions). Runbook `docs/gameplay-v2/VERSUS-BACKEND.md` §3a exists;
  two small doc errors there (TTL command, see §5).

## 2. Requirement table

Status key: DONE / FIX / TODO / OWNER / DEFER?. Evidence = file:line or test name (all functions tests passed in my run).

### WP-E (server parts)

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| E4.1 | `functions/src/levels.ts` → `brackets.ts` with `BEST_BRACKETS`, `bracketFor`, same numbers | DONE | `functions/src/brackets.ts:7-18`; levels.ts gone | — |
| E4.2 | `brackets.test.ts` parses `kBestBrackets` in `lib/versus/brackets.dart`, boundaries | DONE | `functions/test/brackets.test.ts:23-44`; `lib/versus/brackets.dart:6` | — |
| E4.3 | `pools.ts` files by `bracketFor(playerBest)`; pool ids and `level` field name unchanged | DONE | `pools.ts:142-144, :246` ; test `pools.test.ts:35` | — |
| E4.4 | each new pool entry gets `plv` = clamp(player `level`, 0, 9999) | DONE | `pools.ts:146-149, :247`; `pools.test.ts:35` | — |
| E4.5 | `schema.ts` `MAX_LEVEL`→`MAX_BRACKET` 10; `PoolEntry.plv?` | DONE | `schema.ts:9-11, :167` (deprecated alias `MAX_LEVEL` kept) | optional: drop alias once nothing uses it |
| E4.6 | `matching.ts` `level`→`bracket` (same logic), never reads player level | DONE | `matching.ts:21, :78-101`; tester #4 PASS | — |
| E4.7 | rules `players.level` 0–9999 (9999 ok, 10000 rejected) | DONE | `firestore.rules:126`; `rules.test.ts:106, :132` | — |
| E4.8 | fixture `test/fixtures/versus_matching.json` renamed + "level 25 / best 80 → bracket 2" | DONE | file exists; #4 builder summary; `matching.test.ts:33` | Dart reader update is wave 2 |
| E4.9 | Dart side: `bracketFor` everywhere, `MatchTier.bracket`, `maxBracket`, emblem from `plv`, `levelFor` removed | TODO (wave 2) | `lib/versus/matcher.dart:56,73,75` still `myLevel`/`MatchTier.level`; `run_entry.dart:236,310` still `levelFor`; `lib/levels/levels.dart:156` `levelFor` | wave-2 client WP |
| E5.1 | reference duel staircase in `matching.ts` (step −2, clamp [−4,+8], +1/−2/0, T band, pick tiers) | DONE | `functions/test/matching_duel.test.ts:55-131` (fixture, step/target/pick, 67 % ± 3 pp sim); #6 float-boundary major fixed (round 3 PASS) | — |
| E5.2 | shared fixture `test/fixtures/versus_duel.json` | DONE | file exists; used by `matching_duel.test.ts` | Dart `matcher_duel_test` wave 2 |
| E5.3 | client `duelStep`, `recentScores`, `versus_result` analytics | TODO (wave 2) | no `duelStep`/`recentScores` in `lib/` | wave-2 client WP |
| E6.1 | `curves.test.ts`: PASS_MAX_SPEED = top of `curve_speed`; PASS_SPACING = `RunConfig.spacing`; PACE bound | DONE | `functions/test/curves.test.ts:28-43` | breaks if WP-D changes `curve_speed` top — intended guard |
| E6.2 | server-only `versusRate.passHist` (last 10, accepted runs only, chronological in a batch) | DONE | `pools.ts:181-184, :213-229`; `passhist.test.ts:31-207` (#7 batch-order major fixed) | — |
| E6.3 | soft `jump`: passes ≥ 150 and > 4 × median of ≥ 5 earlier counts | DONE | `anomaly.ts:19-27`; `anomaly.test.ts:90, :191` ("honest 20 → 60 → 140" not flagged) | — |
| E-T | `pools.test.ts` (entry gets `plv`, pool id from bracket), rules test level, `anomaly.test.ts` | DONE | see above | — |

### F9 / G4 server parts

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| F9.1 | `schema.ts` `Look.card?` + `validLook`/`validCard`: exactly 2 `|`, slot allow-lists incl. skill ids, ≤ 48 chars | DONE | `functions/src/card.ts:82-102`, `schema.ts:94-121`; `card.test.ts:69-164`; ids match `design/approvals_v26/versus_cards.html` (17 + 3 per kind, checked) | — |
| F9.2 | `firestore.rules` `validCard` in player look and run look; 2.5 five-key look valid | DONE | `firestore.rules:42-59, :83`; `rules_card.test.ts:66-98` | — |
| F9.3 | the card reaches the opponent (VS intro card frame/name/sticker on **both** cards) | **FIX** | `pools.ts:256-262` builds the pool entry `look` from bird/gear/hat/hoop/trail only — `card` is dropped; no test covers it. (LB group members do keep `card`: `board_store.ts:384-396`, `board.ts:110`) | copy `look.card` (validated) into the pool entry; test in `pools.test.ts`; check `mergePool` size budget still holds |
| G4.1 | pool entries carry `space: true` copied by the server like `plv`; old entries none | DONE (server copy) | `pools.ts:145, :150, :248`; `pools.test.ts:35` | — |
| G4.2 | the player doc can actually carry `space` | **FIX** | `firestore.rules:116-117` `validPlayer` `keys().hasOnly([...])` has no `space`; a wave-4 client writing it is denied on every write. No rules test for `space`. | add `'space'` to hasOnly + `(!('space' in d) \|\| d.space is bool)`; rules test accept bool / reject non-bool; must be in the wave-0 rules deploy |

### WP-LB server (LB2 / LB3)

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| LB3.c | 9 server-only collections, names/fields per table | DONE | `schema.ts:393-416`; `skeleton_lb.test.ts:111` | `cleanupPending` on `lbPlayers` (added by #88) is not in the PRD LB3 table → record in PRD addendum |
| LB3.r | rules: no new allow; header comment; `rules.test.ts` denies every `lb*` | DONE | `firestore.rules:9-10`; `rules.test.ts:222-243` | — |
| LB3.i1 | composite index `lbGroups (settled, end)` | DONE | `firestore.indexes.json:3-9`; used `board_store.ts:1456-1458` | — |
| LB3.i2 | composite index `lbPlayers (hidden, bestShadow, best desc)` | **FIX** | declared `indexes.json:11-18` but **no query uses it**; the real query `board_store.ts:1295-1296` (`hidden == false` + `bestShadow > best`, `.count()`) needs `(hidden ASC, bestShadow ASC)` and is undeclared → FAILED_PRECONDITION on prod, `lbGetBoard` throws (no try/catch around `exactRank`). Emulator does not enforce indexes. | declare the index the query needs (keep or drop the unused one, update PRD table + `skeleton_lb.test.ts:81`); add a static test that every composite query in `board_store.ts` has a declared index |
| LB3.t | TTL on `expireAt` for lbPlayers/lbGroups/lbGifts/lbTomb/lbFlags; exemptions members/ghosts/entries/rows | DONE | `indexes.json:52-103`; `set_ttl.sh:27-29`; `skeleton_lb.test.ts:92-101` | note: the indexes deploy (step 1) already turns TTL on (`"ttl": true`) |
| LB3.k | constants (`LB_GROUP_SIZE` 50 … `LB_PRIZE_PLACES` 3, `LB_HIST_FROM` 20 000, `LB_GIFTS`) | DONE | `schema.ts:337-391`; `skeleton_lb.test.ts:37` | — |
| LB3.o | callables `onCall({enforceAppCheck:true})`, auth required, europe-west1, maxInstances 10, tombstone refused | DONE | `index.ts:47-58, :224-240`; `skeleton_lb.test.ts:127,154`; `board_store.test.ts:380` | stale "stub" doc comments `index.ts:223,229,235` |
| LB3.s1 | `lbSubmitRun` shape/dedupe/time/overlap/Σcs/old/bounds/timeline-when-notable/clamp 2×best (min 500)/shadow best/daily cap 400/`t:1` hidden/join-or-create in tx (start ≥ now−6 h, ghosts chosen then) | DONE | `board.ts:1061-1274`; tests `board.test.ts:731-1120`, `board_store.test.ts:175-245`; #8/#24/#87 majors fixed and covered (score-only bonus room `board.ts:960-970`, malformed ordering `:1085`, chronological best `:1074`, old-BEST intervals `:1160`) | #87 had **no tester verdict** → independent review |
| LB3.s2 | response `{accepted, dropped, group, rank{before,after}, board?, gifts?}` | DONE | `board.ts:95-102`; `board_store.ts:1156-1174` | — |
| LB3.g | `lbGetBoard {tab}`: opaque `rid`, no uid/ghost marker, `me`, best, gift stubs, lazy settle, `lbBest/global` cache 60 s | DONE | `board_store.ts:1355-1405`; `board.ts:104-115, :593-620`; `board_store.test.ts:294, :394`; TODAY rows have no `best` (O62) `board.test.ts:417` | cost: see LB3.cost |
| LB3.g2 | BEST tab exact rank; approximate from `lbBest/hist` above ≈ 20 k | DONE (logic) / FIX (index, cost) | `board_store.ts:1264-1306`; `board.test.ts:585` | index (LB3.i2); tie read `board_store.ts:1297` fetches **every** player with the same best (thousands at low scores) → replace with a count on `(hidden, bestShadow, bestAt)` |
| LB3.cl | `lbClaimGift {id}`: roll at first claim with `crypto.randomInt`, stored, idempotent, other uid refused | DONE | `board_store.ts:1410-1443`; `board_store.test.ts:360, :817` | result shape is `{ok,id,tier,prize:{kind,coins,item?,rarity?,seed}}`, not PRD `{tier,kind,coins,seed}` → client must follow the code; record in addendum |
| LB2.1 | prize = board places 1–3 only, real non-hidden; ghost/hidden keeps the place; 0–3 boxes | DONE | `board.ts:703-733`; `board.test.ts:472-506`; `board_store.test.ts:331` | deviation (from #88): a ghost whose owner turned hidden/deleted is **removed** at settlement and places shift (`board_store.ts:800-817`) — consistent with "never hidden players as ghosts", record in addendum |
| LB2.2 | gift table bronze 25–100, silver 50–200, gold 50/20/20/10 + pre-rolled 100–300 fallback, item ≤ 750 common 70/rare 30, step 5 | DONE | `schema.ts:375-391`; `board.ts:811-848`; `board.test.ts:599-699` (20 k rolls ± 1.5 pp) | — |
| LB2.3 | `test/fixtures/lb_gifts.json` == `LB_GIFTS`; `LB_MAX_SCORE` == `kLeaderboardMaxScore` | DONE | `limits_mirror.test.ts:10-17` | — |
| LB2.4 | gold item pool = shop items ≤ 750, versus-card and skill items excluded | DONE now / FIX later | `board_store.ts:98-110` + mirror test `board_store.test.ts:809-815` (regex on `catalog.dart`) | when F9/F10 add card / skill-unlock `SkinItem`s at 250/750 the mirror regex will include them and the server list will diverge → wave-4 WP must exclude `SkinLayer.card` and `unlock != null` in both |
| LB3.set | scheduled `lbSettleGroups` every 10 min Etc/UTC: prizes, ghost-pool days, TOP BIRD record, settled, idempotent; `lbSettle` log incl. `gifts_lost_to_ghosts` | DONE | `index.ts:242-248`; `board_store.ts:779-910`; `board_store.test.ts:265, :294, :835` | minor: pool merge filter `entry.day < lastDay` (`board_store.ts:885`) drops newer ghost days if a later group of the same bracket settled first (scheduler outage); add a test or use `day <= today` |
| LB3.n | names server-derived; `setCustomName`, `releaseGuestName`, lost-name path update lb name | DONE | `pools.ts:554, :662`; lost path `pools.ts:622` → `setCustomName`; `board_delete.ts:356-393` (reads `versusNames` in tx); `board_delete.test.ts:523-605` | minor: ghost days already in pools/groups keep the old name ≤ 14 d |
| LB3.d | `deleteMyData` → `deleteBoardData` after `clearPurchaseUid`, before players tx; tombstone; groups (member+ghost), 44 pools, gifts, flags, player, lbBest; idempotent | DONE | `index.ts:121-136`; `board_delete.ts:341-353`; `board_delete.test.ts:280-505` (#10 races fixed: gift sweep, ghost copy, late flags `board_store.ts:704-716`) | — |
| LB3.im | `lb_import.ts`: verified `bestRun` else max verified `recent`, never client `best`; `src:'import'`, +400 d; rebuild `lbBest`; `lbMeta/import` with `keepUids`; dry run default | DONE | `functions/scripts/lb_import.ts` (`--apply` required, tombstones `:295-298`, cleanedAt invalidation `:310, :582, :628`); `lb_import.test.ts:368-850` | #89 round 3 never reviewed → independent review |
| LB3.cu | `lb_cleanup_test.ts --keep` dry-run default; deletes imported non-kept rows + gifts, ghost-pool entries, group rows; only lb*; sets `cleanedAt`; prints top 50; resumable | DONE / FIX (minor) | `lb_cleanup_test.ts:151-300`; `lb_import.test.ts:864-1059` | group/pool rewrites in `applyCleanup` (`:251-277`) are read-then-`set` outside a transaction: a live submit during closed testing can be lost. Use per-doc transactions. Also: imported players who later played keep `src:'import'` → deleted unless on the keep-list (owner must list every real closed tester) |
| LB3.gate | `SUBMISSION.md` gate "lbMeta/import.cleanedAt set" | DONE | `SUBMISSION.md:109-115` | — |
| LB3.cost | cost ≈ PRD model (one group read per board open) | **FIX** | `hiddenGhostOwnerUids` (`board_store.ts:271-284`) reads every ghost owner (≤ 49 docs) on each `lbGetBoard` (`:1250-1262`) and each submit (`:1036`) | cheaper suppression: e.g. one `lbMeta/hidden` doc of uids hidden/deleted in the last 14 d (+ keep the tx-consistent read of that one doc); keep the #88 race tests green |
| LB-T | functions tests named in PRD (board, board_store, lb_import, rules, limits_mirror) | DONE | all present and green (433 passing) | — |
| LB-hide | `t:1` → hidden | DONE (note) | `board_store.ts:425` hidden is **sticky** (`doc.hidden \|\| input.hidden`) | owner awareness: one FS_TESTER / FS_E2E / profile run on the owner's linked uid hides that account on the board forever (see §5) |

### §4 wave-0 deploy readiness

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| W0.1 | `npm --prefix functions test` green | DONE | 433 passing, my run today | — |
| W0.2 | every wave-0 server item built (E4, F9, G4, E6, E5 ref, curves, WP-LB) | FIX | F9.3, G4.2, LB3.i2 above | WP S1 below |
| W0.3 | unreviewed merges re-reviewed (#87, #88 round 2, #89 round 3, #11, #8 merged on red verify) | FIX (review) | issue comments: no tester verdict on the final rounds | WP S3 |
| W0.4 | deploy order indexes → rules → functions → TTL → import (owner OK) | OWNER | runbook `docs/gameplay-v2/VERSUS-BACKEND.md:57-90` | see §5 command list |
| W0.5 | consoles: achievement drafts (J9 + 6 board/versus), GA4/BigQuery EU 14 m, A4 dimensions | OWNER | M0 report "User actions" | — |
| W0.6 | 4th Cloud Scheduler job (≈ $0.10/month) accepted | OWNER | `index.ts:242`; schedulers: releaseGuestNames, sweepPools, sweepVoidedPurchases, lbSettleGroups | — |
| C9 | release-blocking cleanup before production | OWNER | `SUBMISSION.md:115` | — |

### Client parts (TODO, other auditor covers UI detail)

- E1 upload rules + `upload_rules_test` (E1, wave 2) · E3 empty-pool line O31 · E4 Dart rename table (`brackets` use in
  `versus_service.dart`, `matcher.dart`, `versus_config.dart` `maxBracket`, `run_entry.dart` emblem from `plv`,
  `levelFor` removal) + `matcher_bracket_test` · E5 `duelStep`/`recentScores` + `matcher_duel_test` + `versus_result`
  analytics · F9 client `look.card` write + painters · G4 client `space` write (needs rules fix G4.2) ·
  LB4 `lib/leaderboard/` (models, `lb_queue`, `lb_service` Noop/Fake/Firebase, `gift_apply`, `lb_config`), run-end
  submit, `main.dart` wiring, Delete My Data `resetLocal`, storage keys `lbQueue … lbInfoSeen`, `CoinSource.leaderboardGift`,
  tuning `lb_results_min_games`/`lb_results_wait_ms`/`lb_queue_cap` (wave 2) · `lib/components/leaderboard/` board,
  rows, podium, info sheet, results climb, gift popup, Home without medal box (wave 4) · Dart tests listed in LB4.

## 3. Open findings from the issues (checked against the code)

| Issue | Finding | Still present? |
|---|---|---|
| #88 (major, test1) | TODAY can show a hidden ghost (stale group read) | **No** — fixed by `readTodayGroup` (`board_store.ts:1250`), submit path `:1036`; test `board_store.test.ts:652` green. Unreviewed. |
| #88 builder note | BEST cache per instance can show a newly hidden player ≤ 60 s on other instances | Yes (accepted by PRD's 60 s cache; minor) |
| #88 builder note | hidden ghost removed at settle (places shift) vs O65 wording | Yes — deliberate; record as DEVIATION |
| #88 builder note | `cleanupPending` field not in PRD LB3 table | Yes — record in PRD |
| #88 builder note | owner with no verified best gets `rank: 0` | Yes — client must show "no rank" for 0 (wave 4) |
| #89 round 2 (major ×1, minor ×1) | no-op rerun clears cleanedAt; race tests mis-targeted | Fixed per round-3 summary; tests `lb_import.test.ts:584, :728` green. Unreviewed. |
| #24 round 2 (→ #87) | batch uses unchanged best; old BEST runs don't reserve intervals; O68 test weak | Fixed (`board.ts:1074, :1160`; tests `board.test.ts:972-1023, :670`). #87 never had a tester. |
| #26 round 1–2 | interrupted import / keep-list change / tombstones / concurrent live writes / resumable cleanup | Fixed (`lb_import.ts:269-335, :582-628`; `lb_cleanup_test.ts` deletes artifacts before players; tests `lb_import.test.ts:510-982`) |
| #26 minor | runbook import command lacks `--apply` | Fixed in `VERSUS-BACKEND.md:72-75`; **still wrong in `docs/reports/M0.md:50`** (historic report; just don't follow it) |
| #10 round 2 | late lbFlags after deletion; delayed lbSyncName overwrite | Fixed (`board_store.ts:704-716`; `board_delete.ts:356-393`; tests `board_delete.test.ts:505, :605`) |
| #9 rounds 1–2 | totals carried across groups, hidden→BEST row, shadow best, gold items never awarded, TOP BIRD erased, lazy settle not logged, duplicate namesake | Fixed (tests `board_store.test.ts:461-835`) |
| #4/#5/#7 | out-of-scope file edits | Process only; no code impact |
| new (this audit) | pool entry drops `look.card` | **Yes** — F9.3 |
| new | rules reject `players.space` | **Yes** — G4.2 |
| new | missing composite index for `exactRank` | **Yes** — LB3.i2 (UNVERIFIED on prod; follows Firestore's equality+range index rule) |
| new | per-ghost owner reads / tie reads cost | **Yes** — LB3.cost, LB3.g2 |
| new | cleanup writes not transactional | **Yes** — LB3.cu |
| new | ghost-pool merge `day < lastDay` filter | Suspected (minor), untested |

## 4. Proposed work packages (server; order S1 → S4, all before the wave-0 deploy)

**S1 — Wave-0 data-path gaps (card, space, index)** · PRD F9, G4, E4/R4, LB3 indexes · paths:
`functions/src/pools.ts`, `functions/src/schema.ts` (PoolEntry look type), `firestore.rules`, `firestore.indexes.json`,
`functions/test/pools.test.ts`, `functions/test/rules_card.test.ts` (or `rules.test.ts`), `functions/test/skeleton_lb.test.ts`.
Deps: none. Acceptance: (1) a run whose look has a valid `card` lands in the pool entry with that `card`; an invalid one
is rejected by `checkRun` (already) and a 2.5 look stays card-less; shard 900 KB test still green. (2) Rules accept a
player doc with `space: true/false`, reject `space: 'x'`, and accept docs without it. (3) `firestore.indexes.json`
declares `lbPlayers (hidden ASC, bestShadow ASC)` (or whatever the exact `exactRank`/tie queries need) and a new static
test lists every `.where(...)`+range/orderBy combination in `functions/src/*.ts` against the declared indexes.
(4) Full functions suite green.

**S2 — Leaderboard read cost** · PRD LB3 costs, LB1 ghosts · paths: `functions/src/board_store.ts`,
`functions/src/board_delete.ts`, `functions/test/board_store.test.ts`. Deps: S1 (index). Acceptance: `lbGetBoard` and
`lbSubmitRun` read O(1) docs for hidden-ghost suppression (e.g. one `lbMeta/hidden` doc of recently hidden/deleted uids,
read inside the same transaction as the group), all #88 race tests (`board_store.test.ts:560, :609, :652`) still
green; `exactRank` ties counted with a count query on `(hidden, bestShadow, bestAt)` instead of a full read (index
declared); a test with 300 tied players asserts the rank and that no full collection read happens (spy on `get`).
Record `cleanupPending` / the new doc in the PRD addendum.

**S3 — Independent review of the unreviewed M0/M1F server merges** (Opus tester, read + test only, findings → S4) ·
#87 (`board.ts` batch chronology), #88 round 2 (`board_store.ts` hidden ghosts / private best), #89 round 3
(`lb_import.ts`), #8/#11 (merged on red verify). Acceptance: written verdict per issue with file:line; mutation check of
the three #88 regressions.

**S4 — Cleanup/settle hardening + doc fixes** · PRD LB3 cleanup (C9), LB3 settle · paths:
`functions/scripts/lb_cleanup_test.ts`, `functions/src/board_store.ts` (ghost-pool merge filter only),
`functions/src/index.ts` (comments), `docs/gameplay-v2/VERSUS-BACKEND.md`, `functions/test/lb_import.test.ts`,
`functions/test/board_store.test.ts`. Deps: S2 (same file `board_store.ts`; serialize). Acceptance: cleanup rewrites
each group / ghost-pool doc in its own transaction (test: a live `lbSubmitRun` between plan and apply keeps its member
points); settling an older group after a newer one of the same bracket keeps both ghost days (test); stale "stub"
comments removed; runbook step 4 lists `set_ttl.sh enable <group>` for all five lb groups (the script defaults to
`players`) and says the indexes deploy already enables TTL.

(Wave-2/4 client WPs are for the client auditors; the server contract they must follow: `lbClaimGift` returns
`{ok,id,tier,prize}`; BEST `me.rank` 0 = not ranked; TODAY rows have no `best`; group `start/end` arrive as serialized
Firestore Timestamps.)

## 5. Deploy commands / scripts that exist (NOT run) and what they would change

All target `flappy-spikes-a2b55` (eur3). Order per PRD §4: indexes → rules → functions → TTL → import.

1. `firebase deploy --only firestore:indexes --project flappy-spikes-a2b55` — creates composite indexes
   `lbGroups(settled,end)` and `lbPlayers(hidden,bestShadow,best desc)`; field overrides: TTL on `expireAt` for
   players, versusFlags, lbPlayers, lbGroups, lbGifts, lbTomb, lbFlags (so **TTL for lb* turns on here**, not at step 4);
   index exemptions players.bestRun/recent, pools.entries, versusFlags.signals, lbGroups.members/ghosts,
   lbGhostPool.entries, lbBest.rows. If prod holds indexes/overrides not in the file the CLI offers to delete them
   (UNVERIFIED what prod holds — compare first with `firebase firestore:indexes --project …`, owner side).
2. `firebase deploy --only firestore:rules --project flappy-spikes-a2b55` — not comment-only: adds `validCard` /
   optional `look.card` to player and run looks, routes run looks through `validLook`, widens `players.level` to 0–9999,
   lb* comment. Backward compatible for 2.5 clients. (Needs S1's `space` change first.)
3. `npm --prefix functions run deploy` (= `firebase deploy --only functions --project flappy-spikes-a2b55`, predeploy
   `npm run build`) — updates every existing function (`onPlayerRunWrite` with brackets/`plv`/`space`/`passHist`/soft
   `jump`, `deleteMyData` + `deleteBoardData`, `setVersusName`/`releaseGuestNames` + `lbSyncName`, `getVersusName`,
   `sweepPools`, `verifyPurchase`, `sweepVoidedPurchases`) and creates `lbSubmitRun`, `lbGetBoard`, `lbClaimGift`
   (callables, App Check enforced, europe-west1, max 10) and scheduled `lbSettleGroups` (4th Cloud Scheduler job).
   Runbook also documents the combined `firebase deploy --only firestore:rules,firestore:indexes,functions … [--dry-run]`.
4. `functions/scripts/set_ttl.sh enable <group>` (REST PATCH `ttlConfig` + index exemption on `expireAt`;
   needs `ACCESS_TOKEN` or gcloud) — **default group is `players`**; must be run once per lb group, or skipped because
   step 1 already applies TTL. `status` / `disable` also exist.
5. `npx --prefix functions tsx functions/scripts/lb_import.ts --project flappy-spikes-a2b55 --keep <uids> [--apply]` —
   preview by default; `--apply` writes `lbPlayers/{uid}` (`src:'import'`, expireAt +400 d), `lbBest/global`,
   `lbMeta/import {ranAt,count,keepUids}`, clears `cleanedAt` when imported rows change. Owner OK on the day (C8). Urgent:
   source `players` docs expire 60 d after their last write (the owner's two real accounts — UNVERIFIED whether still
   present).
6. `npx --prefix functions tsx functions/scripts/lb_cleanup_test.ts --project flappy-spikes-a2b55 --keep <uids> [--apply]`
   — preview by default; `--apply` deletes imported non-kept `lbPlayers`, their `lbGifts`, ghost-pool entries and
   group member/ghost rows, rebuilds `lbBest/global`, sets `lbMeta/import.cleanedAt`, prints top 50. Release-blocking
   for production (C9).
7. `npx --prefix functions tsx functions/scripts/list_flags.ts` — read-only versusFlags review (2.5).

## 6. Risks / conflicts

- **Sticky hidden flag:** `t:1` hides a uid permanently (`board_store.ts:425`). Owner e2e on the Pixel
  (`FS_E2E`, `FS_LIVE_VERSUS`) or any FS_TESTER/profile build signed into the owner's linked account would hide
  hiesem/hiesemie from the board forever (no unhide path except a manual Firestore edit). Owner should know; possibly
  an `unhide` admin script.
- **Shop-catalog mirror** (`board_store.ts:98-110` + regex test `board_store.test.ts:809`) will break or silently
  include card/skill items when wave 4 adds F9/F10 `SkinItem`s — the F9/F10 builder must touch the server list.
- `curves.test.ts` parses `lib/run/config/tuning_defaults.dart` and `run_config.dart` by regex: a WP-D/WP-J refactor of
  `TuningDef('curve_speed', TuningType.curve, …)` formatting breaks the functions suite; a `curve_speed` top change
  needs a server `PASS_MAX_SPEED` change + functions deploy (and `fl` policy R1).
- `functions/test/brackets.test.ts` parses `lib/versus/brackets.dart` (wave 2 owner of that file must keep the literal).
- `lbSettleGroups` handles ≤ 100 groups per 10-min tick (`board_store.ts:1459`) — fine now, a ceiling at scale.
- `lbGetBoard` returns gifts `where uid == … limit 50` unordered — a player with > 50 boxes could miss unclaimed ones
  (400-day TTL); low risk.
- Cost model in PRD LB3 (≈ $250–300/month at 100 k DAU) does not hold with the current ghost-owner reads (≈ 50 reads
  per board open/submit) — S2.
- PRD wording vs code to record in the addendum: hidden-ghost removal at settle; `cleanupPending`; claim result shape;
  rules change is not "comment only"; TTL is enabled by the indexes deploy.
