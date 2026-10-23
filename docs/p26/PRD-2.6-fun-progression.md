# PRD 2.6 — Fun first, harder with mastery, far for the best

Run 20 · 2026-10-20 · integrator: Opus 5.5. This PRD merges five specialist reports (curves, onboarding, progression, economy, systems; `.worktrees/briefs20/REPORT_*.md`) and resolves the conflicts between them.
Code baseline: `.worktrees/p25-merge` (feat/2.5 = 2.5.0+48). Every `file:line` below refers to that tree.
Real-player evidence is limited to the owner's two accounts (hiesem, hiesemie): 13 uploaded runs. Every other Firestore record is generated test data and was not used.
**Revised 2026-10-21** to the owner's binding decisions (`.worktrees/briefs20/OWNER_DECISIONS_2026-10-21.md`; §0.4). Gaps those decisions left are resolved as **EDITOR rules R1–R9** (§0.2).
**Revised 2026-10-22 (round 21)** to the owner's review of the 2.6 approval pages (`design/approvals_v26/`, `.worktrees/briefs21/`): decisions **O29–O45** (§0.4, round 7). Biggest changes: worlds map, flight guide and puzzle album become **tabs of the Levels screen** (no Home tile); the **weekly leaderboard is dropped** on both platforms (the in-game week runs Monday 00:00 UTC); **no stars on any card**; Star Road gets its full rules and a Home popup; versus-card cosmetics grow to **51 items**, skill-only cosmetics to **18 items**; four new achievements (proposed).
**Revised 2026-10-22 (round 22)** to the owner's streak-restore and own-leaderboard decisions (`.worktrees/briefs21/ROUND22.md`, its "Owner answers after the server analysis" binding): decisions **O46–O58** (§0.4, round 8). Biggest changes: **streak freezes are removed**; a broken streak gets a **STREAK LOST** popup with RESTORE (rewarded video, or 500 coins for No-Ads owners), pending across days; a new **WP-LB own leaderboard** (daily group of 50 per best-score bracket with live-replayed ghosts, an all-time BEST RUN tab, a results-page climb, free gold / silver / bronze **gift boxes** for the top 3 real players in the top 10 — prize rule replaced by O65 in round 23: board places 1–3 only) with a wave-0 server deploy, an import of verified best runs and a **release-blocking test-player cleanup** before production.
**Revised 2026-10-23 (round 22b)**: decisions **O59–O61** (§0.4, round 8b): the board's text info sheet becomes a 4-step **picture guide** that opens by itself on the first board open (`lbInfoSeen`) and later from the i box; gift-box odds are **not shown to players** (boxes stay free and never sold).
**Revised 2026-10-23 (round 23)** to the owner's second review of the approval pages (`.worktrees/briefs23/ROUND23.md` binding; designer reports `CHANGES_board23.md`, `CHANGES_hub23.md`, `CHANGES_daily23.md`, `CHANGES_cards23.md`): decisions **O62–O82** (§0.4, round 9). Biggest changes: the TODAY tab shows **only total points** (no BEST n line); the Home **medal button is gone**, and the board gets an **ACHIEVEMENTS tab** that opens the native Play Games / Game Center screen; there is **no visible link to the native leaderboards** any more (scores and unlocks are still submitted); **only board places 1–3 win a gift box** (replaces O54's "top 3 real in the top 10"); a new group takes no joiner with **< 3 h** left; the Levels tabs move **under the title, without icons**, and Home gets a gold **NEW** tag; STREAK LOST shows for **every** lost streak and restores **only the last streak**; no difficulty / rarity labels on mission rows and the Star Road; **themed season names** (list to approve); **6 new skill-only card items** (3 name styles, 3 stickers; achievements proposed); no 2.5 grandfathering for skill items and PROUD PEACOCK counts the card items. New questions **Q26–Q31**.

**Revised 2026-10-23 (round 24)** to the owner's third look at the approval pages (red-box notes, label app26; report `.worktrees/briefs21/CHANGES_round24.md`): decisions **O83–O87** (§0.4, round 10). Every open question (Q4, Q16, Q25–Q31) is decided as recommended, the GO TO COLLECT ghost line LG-6 is dropped, all 9 skill **card** items show **"? ? ?"** in the shop instead of how to earn them, Thunderstruck gets its own storm-violet look, and the WORLDS tab runs **1 → 10 from top to bottom**. One new question **Q32**.

**Revised 2026-10-23 (round 25)** to the owner's fourth set of red-box notes (label app26; report `.worktrees/briefs21/CHANGES_round25.md`): decisions **O88–O91** (§0.4, round 11). Q32 is approved as recommended, so **every** skill item in every shop tab is secret ("? ? ?"); the ACHIEVEMENTS tab loses its "opens outside" mark; any drawing of the run (also the small picture-guide pictures) shows the real spike strips pinned to the edges; the Star Road Home popup gets the same confetti, motion and sound polish as the other reward popups. **No open questions are left.**
**Revised 2026-10-23 (design approval)**: the owner approved **every design page** in `design/approvals_v26/` (owner: "All designs are now approved"): decisions **O92–O96** (§0.4, round 12) and **O97–O100** (round 13: reuse existing game elements, rays, one box master): §7.1 designs and the §7.2 texts approved; release notes go to the marketing agent; achievement icons get an approval page first; the privacy update deploys with 2.6 internal; the 10 new achievement icons are approved (O96).

---

## §0 Summary

### 0.1 The plan on one page

The game gets **two lifetime layers and a level track** on top of **one in-run curve for everyone**:

| Layer | When | What the player gets | Counts for |
|---|---|---|---|
| **SHOWCASE** | Runs 1–3. It advances by highlight seen and ends at the latest after 6 games. | A run on the **normal curve** (normal mix of hard elements by hoop index) with a guaranteed highlight placed early (run 1 the portal roller-coaster, run 2 the comet ride + power-ups, run 3 FEVER + a portal ride in another theme), Big Hoops + shield armed at start and one FREE revive. **Invisible to the player** (O16): it looks like a lucky normal run, with no framing, popup, ribbon or practice loop. Mode, ads and system dialogs as today. | **Everything**: versus uploads, leaderboard, levels, coins, achievements. |
| **TWO LIFETIME GATES** | Saw from game 4, squeeze from game 6 (by `gamesPlayed`). | Silent: they simply start appearing, with no card, sticker or animation (O16). Tilt, moving and switch rings and big height jumps are on from run 1 and appear by in-run hoop index. | — |
| **LEVELS** (WP-J) | From run 1, for life. | 31 named levels (HATCHLING → THUNDERBIRD), then endless numbered levels 32, 33, … named ETERNAL WING. Every finished run adds its score; at most one level per run, surplus dropped. Each level pays coins + one random unowned item. Replaces the 10 ranks. | — |

VERSUS is available from the start and stays the default mode (as in 2.5). All runs except debug runs count for versus uploads (2.5 rules), the leaderboard (`bestScore`) and levels.

**In-run curve (one for everyone):**
- Introductions are staggered: one new dimension at a time, at least 5 hoops apart.
- The ceiling is at **hoop 150** and is hard but doable (O1). Speed stays pinned at 187.5 pt/s, so the leaderboard cap and the server checks do not change.
- Tilts of 20° and more lean along the bird's path.
- Height jumps (Δy) are capped in points (max 270 pt), so screen height no longer changes the difficulty.
- A hazard budget per 4 slots and calm stretches. The squeeze schedule stays as in 2.5 (O18).
- Past hoop 150 only variety grows (formations).
- **In-run goal (WP-K):** in Free Fly a "BEST 42" chip (no colon, O31) and a gold line where the best run ended; passing the best gives a NEW BEST! moment mid-run.

**Economy:**
- Points and coins are unchanged (O13: lucky spin, pair coin gift, Coin Frenzy and puzzle completion keep paying points).
- Coin revives stay as in 2.5, also in versus (O5).
- Ad timing is unchanged (O2: grace 5 runs or 300 s, interstitial gap 60 s).
- Level rewards (18,800 coins + 31 items over 31 levels) replace the 10 rank rewards (10,175 coins).

**Retention and long-term goals (also 2.6, O20):** daily missions, a visible day streak (no freezes; the last lost streak can be restored, O46–O49, O72–O74), **our own daily leaderboard with gift boxes for places 1–3** and an ACHIEVEMENTS tab that opens the native screen (WP-LB, O50–O58, O62–O68), and notifications that react to the player's state; a worlds map, a flight guide and a puzzle album as **tabs of the Levels screen** (O29, O69); a weekly course (no weekly leaderboard, O30); the Star Road free season with themed season names (O75); versus-card cosmetics (51 items) and skill-only cosmetics (24 items, O80); the duel staircase and baked A/B arms.

**Release order:**
- **2.6.0 — one release, one build (O20):** everything in this PRD — analytics, the invisible showcase, the two lifetime gates, the curve with all 6 formations, levels (WP-J), beat-your-best (WP-K), versus best-score brackets + duel staircase, missions, day streak (+ streak restore), notifications, Levels-screen tabs (worlds, guide, album), weekly course, Star Road, cosmetics, A/B arms, **our own leaderboard + gift boxes (WP-LB)**. Built in waves (§4); server deploy first (incl. the leaderboard functions and the import of verified best runs). The `fl` byte stays 2 (R1).
- **2.6.x:** tuning only.
- Owner approvals still needed for designs, texts and console actions: §7.

### 0.2 Decisions

**Integrator decisions that still stand** (run 20; the ones the owner overruled on 2026-10-21 are removed: old D1, D2, D5, D6, D9, D12):

| # | Decision | Why |
|---|---|---|
| D3 | **The hardest variants are gated by in-run hoop**, never by best: 30° tilts from hoop 50, 45° from 60, slides from 70, orbit/rock from 90, saw inside a squeeze from 100, moving + 30° tilt from 150. | Gating by best would give two players different rules at the same hoop number. Only skilled players reach those hoops anyway. |
| D4 | **The showcase advances by highlight seen**, with a hard end at `gamesPlayed ≥ 6` and a fast track (any showcase run that passes 40 hoops ends it). | A player who dies at hoop 2 has not seen the "wow" yet. |
| D7 | **Lifetime-only profiles.** Baked A/B arms ship in 2.6 (O20) with one arm until the install threshold, limited to lifetime keys by a test. **No remote switch** (O11). | PRD-2.5 §2: no behaviour-changing config is downloaded. A/B tests need about 1,500 installs per arm. |
| D8 | **About 180 coins a day of meta** (missions 20/35/55 + a 40-coin chest = 150; streak 200 a week ≈ 29). No single meta reward above 750. Level rewards are separate (WP-J, F5). | Easy to raise later, hard to lower. |
| D10 | **Accept the softer ceiling at hoop 150** (O1). "Harder the more you play" comes from in-run depth plus the saw/squeeze unlocks; "far for the best" needs a ceiling that can be beaten. | Today's wall at hoop 100 contains rings that cannot be passed clean (a 45° ring leaning the wrong way at opening 66). All values are baked and re-tuned from 2.6 data in 2.6.x. |
| D11 | **At most one big game popup per Home visit** (C2). There is no graduation popup and no unlock card (O16). | PRD-2.3.1 pacing spirit. System sheets (UMP / ATT / notifications / Game Center) are not part of this budget; they stay at launch (O3). |
| D13 | **Analytics ships in the 2.6 build itself.** | There are no public players yet; 2.6 is the baseline. |
| D14 | **Hazard budget in 2.6 (must). All 6 formations in 2.6 (should; O20).** Batch every curve change before the public launch. | After launch, each curve change bumps `fl` (R1). |

**EDITOR rules (2026-10-21)** — gaps left by the owner decisions, resolved here:

| # | Rule | Why |
|---|---|---|
| R1 | **The `fl` byte stays 2 in 2.6.** From the public launch on, every change to the curve, gates or points per hoop bumps it (batched per release). With O20 all six formations and every other curve change ship in 2.6, before the public launch, so **no extra bump is needed** for them (the old "formations 3/5/6 + `fl` bump in 2.8" is gone). | Points per hoop are unchanged (O13), and only the curve moves. The owner keeps the test runs in the pools (O7). A bump to 3 would make every existing entry undecodable (`timeline.dart:142`) and empty the pools before launch. A ghost from the 2.5 curve is slightly harder past hoop 60 and slightly easier at hoops 10–20. That is acceptable for test data, and no public player has run on it. |
| R2 | **Versus fairness = one curve.** Everything that changes death risk or points per hoop is a function of in-run hoop index and in-run state. There are three accepted lifetime exceptions: the saw gate (games 1–3), the squeeze gate (games 1–5) and the showcase safety net (runs 1–3: Big Hoops + shield at start, one free revive, scripted highlight). First-meet pulls stay as in 2.5. | The owner made showcase runs normal versus runs. They are short and land in the lowest best-score brackets, where saw (hoop 30) and squeeze (hoop 35+) are rarely reached anyway. |
| R3 | **Matching keys on best-score brackets, decoupled from levels.** The 11 pool brackets keep today's thresholds [25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000]. Only the source moves from the level table to a new bracket table, so pool ids `{b}_{s}`, every pool doc and every stored entry stay valid (E4). | Pools are *already* filed by `levelFor(best)` on the server (`pools.ts:136`), not by the stored level. What breaks is the coupling to `kLevels` (`levels.test.ts` parses it) once the level table becomes 31 time-played levels. |
| R4 | **The opponent's emblem shows their real level.** The server copies the player doc's `level` (0–9999) into each new pool entry as `plv`. Old entries without it show the UNRANKED emblem. Firestore rules allow `players.level` 0–9999 (levels are endless, round 3). | `run_entry.dart:236` derives the emblem from `levelFor(run.best)`. That would show a pool bracket under a level emblem. |
| R5 | **The 10 rank achievements become single-run score achievements** (rank_egg = score 25 in one run … rank_legend = 5000), exactly as their live console descriptions already say ("Score 25 points in one run"). They no longer follow the level. Earned ones stay earned. | No console edit is needed, and IDs are kept. Owner confirmed (Q1, 2026-10-21). |
| R6 | **Showcase layout = the normal curve.** The showcase Δy row and the opening floor 110 are dropped. The showcase keeps scripted fun items (Big Hoops starter, Coin Frenzy, hearts, star trails, feather, puzzle piece) because they are fun elements, not hard ones. | O15: "use the NORMAL MIX of hard elements"; the old row stripped big jumps. |
| R7 | **Beat-your-best in VERSUS only when there is no opponent** (solo / offline / empty pool). | With an opponent, the race bar already is the target. Two targets compete for the same HUD space. |
| R8 | **Skins/Shop open at `best ≥ 25` OR `gamesPlayed ≥ 3` OR level ≥ 1.** | Level 1 (25 points) pays an item in run 1–2; the player must be able to equip it. |
| R9 | **Level item fallbacks never go down in rarity.** "Category owned" = no unowned item in that category at rarity ≥ the table's. The next try is other categories at the same rarity, then higher. ETERNAL WING items (levels 32+) are uniform over all unowned items. | It makes the owner's fallback order total and never gives less than the table. |

### 0.3 What every report missed (added here)

1. **Rule-set versioning discipline.** From the public launch on, every change that affects death risk or points per hoop bumps `fl` (R1). These changes are batched per release.
2. **Tester entries on the leaderboard and in the pools stay** (O4, O7). Play Games and Game Center already hold easy-run scores from testers, and the pools hold test runs. Accepted; they act as early ghosts. **Exception (round 22, O52):** our own leaderboard (WP-LB) imports existing best runs, which include generated test players; they must be removed by the release-blocking cleanup C9 before production (versus pools untouched, O7).
3. **The early pool can place a tilted ring at hoops 4–9** (`director_tables.dart:416-425`), against every report's "tilt from hoop 10". The angled pick is removed.
4. **A shared "human-noise bot"** (flap-timing σ 90 ms, 10 % extra flaps) validates the showcase *and* the ceiling. Today's autopilot is too perfect to prove "doable".
5. **Owner evidence.** hiesemie's first day on a fresh iPhone ended at 2/4/2/8 hoops, so even the developer dies early on a new device. The free revive therefore applies from the first death after hoop 0, not from hoop 6. (The run-20 hoop-0 practice loop was removed by the owner, O16.)
6. **Pool brackets were never the player level** (R3). They were already best-score brackets; 2.6 only decouples the table.

### 0.4 Owner decisions (2026-10-21)

Binding (`.worktrees/briefs20/OWNER_DECISIONS_2026-10-21.md`).

| # | Decision | Effect in this PRD |
|---|---|---|
| Perfect band | Hoops 0–40 stay as 2.5.0+46, including the drop at hoop 20→25; then [50,11.8] … [150,10]. Big Hoops growth ×1.5 unchanged. | D2, Appendix. |
| O1 | Softer ceiling at hoop 150: **yes**. | D2 as written. |
| O2 | Ad timing **as today** (grace 5 runs or 300 s; gap 60 s). | Old F4 removed; no new ad knobs, no `unlock_moment` / `run_spacing` skips. The game-popup budget (C2) stays. |
| O3 | UMP, ATT, notifications and Game Center **at launch, as today**. | Old B6 L2–L4 and `launch_ask` removed. |
| O4 | Leaderboard: **all runs count** (`bestScore`), no store-board reset. | No `rankedBest`. |
| O5 | Versus keeps **coin revives as today**. | Old F2 removed; no "unranked" runs. |
| O6 | Versus uploads: **all runs, as today** (first 3 a day + new bests, score ≥ 3). | E1. |
| O7 | **No pool purge.** | Old E7 removed; R1. |
| O8 | First launch starts on **Home**, as today. | Old B6 L1 removed. |
| O9 | **No graduation gift**. | Round 2 (O16) also removes the "YOU'RE READY!" moment: no graduation at all. |
| O10 | **Yes:** BigQuery daily export, GA4 retention 14 months, Google signals off, $5 budget alert. The orchestrator sets these up in the console when the owner is signed in. | A4, §5. |
| O11 | **No** remote profile switch. | WP-H. |
| O12 | Highlights: run 1 = portal roller-coaster **early**, run 2 = comet ride + power-ups, run 3 = FEVER + a portal ride (other theme). | B3. |
| O13 | **No points purity**: luck sources keep paying points. | Old F1 removed. |
| O14 | Shop badge stays **"MOST POPULAR"**. | Old F8 removed. |
| O15 | Tilt, moving and switch are **on from the start** (by hoop index). Only two lifetime unlocks remain: **saw from game 4**, **squeeze from game 6**. Big height jumps are in-run only. | WP-C rewritten; the 7-step ladder is gone. The NEW! card + sticker of round 1 were removed in round 2 (O16). |
| Showcase | Keep the highlight, starter shield and free revive, but on the **normal mix**. Showcase runs are normal runs for versus, leaderboard and levels. (Round 1 also kept the practice loop; round 2 removed it, O16.) | WP-B, R6. |
| Versus | **Available from the start and the default mode.** No lock or unlock moment. | E3. |
| Ranked | The "ranked run" concept, `rankedBest`, versus-unlock-at-ladder-end and a ranked-run staircase are removed. The `fl` bump is left to the editor (R1: no bump in 2.6). Matching moves to best-score brackets. | WP-E, R1, R3. |
| Levels | 31 levels + endless (round 3: ETERNAL WING 32+, replaces ★), progress = points of every non-debug run, one level per run, surplus dropped, fresh start, coins + one random unowned item, 31 unique emblems (+ the ETERNAL WING emblem, round 3), names ≤ 13 chars. | WP-J. |
| Beat your best | Free Fly chip + gold line + mid-run NEW BEST! (GoldSticker). | WP-K, R7. |

**Round 2 (2026-10-21)** — the owner: "We don't want a NEW unlock moment on Home, no animation for that. Also no showcase moment. We want the first run to feel like the normal run for the user, so don't show anything."

| # | Decision | Effect in this PRD |
|---|---|---|
| O16a | Showcase runs 1–3 are **invisible**: no step framing, no graduation popup or "YOU'RE READY!" band, no FREE ribbon on the home slot, no special UI. | WP-B rewritten; §2 has no graduation row; old B6/B7 removed. |
| O16b | **No practice loop.** A death before hoop 0 is a normal death. | Old B5, its analytics (`hoop0_pass`, `practice_retries`), the hoop-0 KPI and its tests removed. |
| O16c | Keep the **invisible early highlight placement** (run 1 portal roller-coaster ≈ hoop 7, run 2 comet + power-ups, run 3 FEVER + another portal theme) so it looks like a lucky normal run. The advance-by-highlight logic (max 6 games) stays because it is internal only. | B1, B3. |
| O16d | Runs 1–3: **Big Hoops + shield armed at START** (they look like normal armed power-ups, no labels) and **one FREE revive** per run (the FREE label on the revive screen is accepted). | B2, B3. |
| O16e | Saw (game 4) and squeeze (game 6) stay gated but are **silent**: no NEW! card on Home, no in-run NEW! sticker, no unlock animation or popup. | WP-C rewritten; `unlock_card`, `next_unlock_tap`, `newCardsSeen`, the NEXT UNLOCK chip and the card tests removed; generic `first_meet` kept. |

**Round 3 (2026-10-21)** — endless numbered levels replace the ★ concept.

| # | Decision | Effect in this PRD |
|---|---|---|
| O17a | After level 31 THUNDERBIRD (74,725 cumulative) come levels **32, 33, 34, … all named ETERNAL WING**. Each needs 10,000 points and pays **2,500 coins + 1 random unowned item** (uniform over all unowned items; none left → only the coins). Same one-level-per-run / surplus-dropped rule, no cap. | J1, J2, J3; `level_star_*` → `level_eternal_points` 10000 / `level_eternal_coins` 2500. |
| O17b | **No stars anywhere**: no ★ badge, no "★n", no `lvlStars` key. `lvlIndex` keeps counting. | J5, J10, Appendix storage table. |
| O17c | Display: "ETERNAL WING" + the level badge after the name ("ETERNAL WING 34"). One own emblem for every level ≥ 32 (#32 "ETERNAL WING (32+)" in `design/levels_v26/emblems.html`). | J6, J7. |
| O17d | Versus: `players.level` and `plv` range 0–9999. | R4, E4, J8. |

**Round 4 (owner review of the full PRD, 2026-10-21; 24 questions, all other answers confirmed the PRD as written):**

| # | Decision | Effect |
|---|---|---|
| O18 | **Squeeze timing stays as in 2.5:** first at hoop 25–40, then every 25–45 hoops, hold 5–10. | D5 keys unchanged; `squeeze_hold_first/then` and `squeeze_gaps` are not added. The squeeze still counts in the hazard budget, calm stretches and the game-6 gate. |
| O19 | **2.6 ships to Android (Play internal) only.** iOS / TestFlight later. | §4 rollout step 2. The Swift / iOS parts of the code still land and must compile in CI. |

**Round 5 (2026-10-21):**

| # | Decision | Effect |
|---|---|---|
| O20 | **Everything planned for 2.7 and 2.8 ships in 2.6 — one release, one build.** Missions, day streak, state-aware notifications, worlds map, weekly course + weekly leaderboard (the board was dropped later, O30), G6 extras, E5 duel staircase, E6 pass-based `jump` flag, F9 / F10 cosmetics, formations 3 / 5 / 6, WP-H baked A/B arms, `bestHoops`, popup budget with streak / missions. | Every WP header says 2.6; §0.1, §2, §4 (waves), §5, §6 and the Appendix have no version split; R1 needs no extra bump; §7 lists the approvals still needed. |

**Round 6 (2026-10-21):**

| # | Decision | Effect |
|---|---|---|
| O21 | Level-up random items come **only from shop items** (bird / hat / gear / hoop / trail). Versus-card cosmetics are never level rewards. | J4, F9; §7 P1 closed. |
| O22 | **No "NEW WORLD" sticker** in runs; worlds appear only on the worlds map. | G4; §7 P2 closed. |
| O23 | **All four G6 extras ship in 2.6** (built last): first-versus-win-of-the-day +20, puzzle album, flight guide, Star Road free season. Priority **should**; each needs a design. | G6, §4 wave 4, §7 D11a–d / T12. |
| O24 | **No No-Ads revive change:** the revive stays exactly as in 2.5 (old F3 "watch ad / or 250 coins" removed). | WP-F, tests, §7 (D12, T11 removed). |
| O25 | ~~The worlds map is its own screen with its own small button (icon tile) on Home.~~ **Replaced by O29 (2026-10-22):** the worlds map is the WORLDS tab of the Levels screen; no Home tile. The approved levels content stays untouched under the tab bar. | G4, §7 D7. |
| O26 | Weekly course entry **without a new button**: (1) a card at the top of the daily-missions panel ("WEEKLY COURSE · 3 DAYS LEFT · BEST HOOP 34 · ▶ PLAY"; the button was ▶ FLY until round 21, O32); (2) at most once a day a small "Try this week's course → beat hoop 34" line on the results page after a normal run. No third mode, no Home tile. | G5, §7 D8 / T9. |
| O27 | The §7 store / console actions are **approved** (incl. the bigger functions + rules deploy, the weekly leaderboard — later dropped, O30 — and the mission-reroll rewarded placement), on the condition that everything works on **both Android and iOS** and is store-compliant on both. 2.6 ships Android-only (O19), but the iOS side is built, compiles in CI and is review-ready. | §7.3 statuses, new §7.5 requirements, G5. |
| O28 | **Daily missions count every game you play:** VERSUS (with or without opponent), FREE FLY and WEEKLY COURSE runs; revived runs count fully; only debug runs don't. Missions unlock from game 4. At most one mode-only mission (e.g. win versus races) per day. | G1. |

**Round 7 (2026-10-22, review of the 2.6 approval pages; round 21)** — notes in `.worktrees/briefs21/notes_*.md`, designer reports `CHANGES_*.md`, answers on `design/approvals_v26/texts.html` ("DECIDED 2026-10-22"). Precedence: the owner's notes over every older line of this PRD.

| # | Decision | Effect |
|---|---|---|
| O29 | **Worlds map, flight guide and puzzle album are tabs of the Levels screen:** LEVELS · WORLDS · GUIDE · ALBUM, always opening on LEVELS. ~~The tab bar sits in the empty top row right of the back button~~ (placement **replaced by O69**, round 23: under the screen title, text only); the approved levels content is unchanged under it. **No WORLDS tile on Home.** Replaces O25. | G4, G6, §7 D7 / D11b / D11c / D14. |
| O30 | **The weekly leaderboard is dropped on both platforms** (Play Games and Game Center; "not possible" as designed). Weekly runs count for the normal `bestScore` board like any run. The in-game week starts **Monday 00:00 UTC** for the course seed, every countdown ("3 DAYS LEFT", "LAST DAY", W-20, N6) and the `weeklyBest` / `weeklyRewards` reset (replaces the "device's local ISO week" note). | G5; old D13, C2, S1 removed; T9, T14 trimmed; §4 waves 0 and 4. |
| O31 | **Texts:** the reveal uses fixed category words **HATS / TRAILS / GEAR / HOOPS / BIRDS** ("ADDED TO YOUR GEAR"); the WP-K chip is **"BEST 42"** (no colon; PRD T2 corrected); the achievement group label **T3 is dropped** (Play Games and Game Center cannot group achievements, so no "RANKS" → "SCORE" rename); T4 = **"No rival yet – your run can become a rival for others"**. | J7, J9, WP-K, E3, §7 T2–T4. |
| O32 | **Daily missions:** M15 "reach a world" targets SKY & HILLS 20 / CITY SKYLINE 40 / GIANT'S DESK 80 (same scale as M11); power-ups (M05) = capsules, shields, comet stars, gift-pair gifts; the versus-win mission M10 is offered only when the player is online and their last versus run found a rival. The panel has **no explanation lines**; the swap works on **any unfinished mission, once a day**; the chest pays 40 coins in its coin case, opens on the **next Home visit** (C2) as the gold mystery box; the weekly card button reads **▶ PLAY**. | G1, G5, C2. |
| O33 | **Day streak:** ~~at most **2 freezes** held (`streakFreeze` 0–2)~~ (freeze parts **superseded by O46**, round 22); a **drawn, gently animated flame** in the game UI (no 🔥 emoji there; notifications keep it); ~~while a freeze is held the chip shows the ice icon on a blue ice-cube chip~~ (O46); rewards are paid on **COLLECT**; day 7 = feather + 60; free Big Hoops / Shield are kept until the next run; ~~a broken streak gets one quiet line~~ (replaced by the STREAK LOST popup, O47); tiles are labelled 1–7; the free Big Hoops / Shield fly into their buttons with small confetti and a sound. | G2, C2. |
| O34 | **Worlds:** no stars on any card (player or versus); the only world reward is the **SPACE FLYER** title. Locked worlds show a grey picture, their number and a lock only: names stay hidden until the world is next, no "HOOP n" text, no reward tags. Each world has its own menu colours. The map ends at SPACE; looping past hoop 200 earns nothing. | G4, §7 D7 / T8. |
| O35 | **Flight guide:** all **32** elements are listed; unmet ones as a silhouette with "? ? ?" / "Not met yet." One entry per portal ride theme (6) + COMET. A gold dot on the GUIDE tab until it is opened. One achievement for meeting all 32 (BIRDWATCHER, proposed). | G6, J9, §7 D11c. |
| O36 | **Puzzle album:** starts **empty for everyone** at 2.6 (only test accounts exist). The **first** full album (all 8 pictures) pays **one random unowned EPIC item of any category** (versus-card cosmetics excluded); later laps only add a ×n badge. No coin amounts on the pictures. | G6, §7 D11b. |
| O37 | **Star Road:** stars come from missions (easy 1, medium 2, hard 3), **+2 for the first finished run of the day** ("follow mockup") and +3 when all three missions are done (max 11 a day); 8 stars a tier, 25 tiers; the word stays "stars"; coin tiers unchanged; seasons run back to back; tiers reached but not claimed are added automatically at season end; nothing left to give → 250 / 500 / 1 000 coins; the card folds to one line on 568 pt screens; a **Home popup with GO TO STAR ROAD** when a tier becomes claimable. | G6, C2, §7 D11d / T12. |
| O38 | **Versus-card cosmetics: 51 items**, 17 per kind (frames, name styles, victory stickers), each kind split like a shop layer: 6 COMMON 250 · 5 RARE 750 · 4 EPIC 2,000 · 2 LEGENDARY 5,000 (nothing above 5,000; the 24 approved items repriced). One `look.card` field. The equipped sticker shows small on both VS intro cards; animated name styles also animate in the in-run versus bar; CARDS is the 6th shop tab. | F9, §7 D9 / T10. |
| O39 | **Skill-only cosmetics: 18 items, 3 per kind** (hoops, trails, hats, birds, gear, versus-card frames), all animated, shown in **LEGENDARY gold** with a trophy mark; secret achievements show "? ? ?" until earned; ~~items for achievements earned before 2.6 are granted quietly on first launch~~ (**replaced by O81**, round 23: no 2.5 path; an item is owned when its achievement is earned); skill items count in the collection bar and tab counters; a level reveal and a skill reveal in one run play level first. Option A: new achievements **BULLSEYE** and **SKY HIGH**. | F10, J9, §7 D10 / T10 / C6. |
| O40 | **First versus win of the day:** style A (one gold line "+20 FIRST WIN TODAY"); only "YOU WIN!" counts (no draws); solo / no-opponent runs never pay it. | G6, §7 D11a. |
| O41 | **Reward moments:** ~~reveal rays are always a bit longer, fade to transparent with a radial gradient, rotate slowly and sit **behind** the item~~ **rays: replaced by O98** (reuse an existing in-game ray as it is). Chest opening, the Big Hoops / shield fly-in and other reward moments get small confetti and a short pleasant sound (existing cues, see each section). | G1, G2, G6, F10. |
| O42 | **Notifications and extras:** fix the false reminders **#2, #13, #16, #17** in 2.6; keep **N7** (level almost reached); drop **N8** (Star Road ending); drop the **"WEEKLY 120"** sticker and the flight-guide footer **FG-3**. | G3, C3, G5, G6. |
| O43 | **BigQuery export: EU multi-region, kept 14 months** (table expiry ≈ 425 days), matching GA4. | A4, §5, §7 C3 / T14. |
| O44 | **Store description and website** ("Climb 10 ranks …"): only a draft note now; a marketing agent updates the store full description and the website later. | §7 T15. |
| O45 | **Chest name: BONUS CHEST** (what the approved mockups and the release-notes draft show; the texts page had "DAILY CHEST"). EDITOR pick — ~~to confirm~~ **confirmed** (Q4 → O83). | G1, §7 T5. |

**Round 8 (2026-10-22, streak restore + our own leaderboard; round 22)** — `.worktrees/briefs21/ROUND22.md`; server analysis `SPEC_L22.md`; designer reports `CHANGES_streak22.md`, `CHANGES_board22.md`. The section "Owner answers after the server analysis" is binding and wins over the analysis and the designer reports.

| # | Decision | Effect |
|---|---|---|
| O46 | **Streak freezes are removed entirely**: no `streakFreeze`, no FREEZE k/2, no ice chip, no "freeze earned". Supersedes the freeze parts of O33; old Q6 / Q7 are dropped. | G2, §7 D6 / T6, Appendix. |
| O47 | **STREAK LOST popup:** on the first Home visit after a break (any number of missed days), **top of the C2 order**, never in runs 1–3: old streak → 0 (drawn flame → grey flame), "{n} days of day streak interrupted!", **RESTORE ▶** (rewarded video) and **GIVE UP**. One restore brings back the ~~full streak~~ **last streak** (O73), however many days were missed; no limit on how often. Shown for every lost streak, 1 day included (O72). | G2, C2, §7 D16. |
| O48 | **No-Ads owners** never see the video: they restore for **500 coins** (button grey with fewer coins). Everyone else only has the video (existing AdMob rewarded units on Android and iOS, after UMP + ATT as today). | G2, C4, S2, S9. |
| O49 | The restore offer stays **pending across days until RESTORE or GIVE UP**; the popup returns on the **first Home visit of each day** (× = again on the next Home visit). A streak is never lost because an ad did not load (LOADING VIDEO → TRY AGAIN). Runs flown in between still count, and a restored streak includes them. | G2. |
| O50 | **Our own leaderboard ships in 2.6** (WP-LB): a daily group of **50** per best-score bracket (R3), lasting **24 h** from the group's first run; real players join an open group **until it is full**, no time limit. | WP-LB, §4. |
| O51 | **Ghosts:** empty spots are filled with real players' earlier days, **replayed live** at their real clock time; one unique user per board; PLAYING NOW only for real players (run < 5 min ago). Too few ghosts → **neighbouring brackets first, then fewer rows**; players are never invented. | WP-LB. |
| O52 | **TODAY** ranks by total points today (every non-debug run); **BEST RUN** = all players, all time, global top 50 + your own row with your **exact** global rank (approximate automatically above ≈ 20 k players). Seeded in wave 0 by importing **verified** best runs only (F5); the imported test players are removed by a **release-blocking cleanup** before production (F4: only the new leaderboard collections, keep-list of the owner's uids). | WP-LB, §4, §7.3 C8 / C9. |
| O53 | **Where:** the results page shows the board with a climb animation after every run from run 4 that moves you up ≥ 1 place (no climb = no board; 4 s answer timeout, F11); the existing Home trophy box opens our board; Play Games / Game Center boards ~~stay reachable from a small link and~~ still get every score (**no visible link any more, O64**). | WP-LB. |
| O54 | **Gift boxes:** ~~the top 3 **real** players who are also **rank ≤ 10 on the full board** (ghosts included) get a closed gold / silver / bronze box~~ (prize rule **replaced by O65**, round 23: only board places 1–3). Bronze 25–100 coins, silver 50–200, gold one roll: 50 % 100–300 coins · 20 % golden feather · 20 % puzzle piece · 10 % random unowned item ≤ 750 (common / rare; all owned → coins). Boxes are prize markers **on podium spots 1–3 only, never on rows**. Collected through **GO TO COLLECT** on the next Home visit (C2, after the streak popups). | WP-LB, C2, WP-F, §7 D18. |
| O55 | **Upload:** a small call after **every** run (score, hoops, time; Firebase auth + App Check; 2.5 protection reused: `kLeaderboardMaxScore`, `anomaly.ts`); the versus timeline is attached **only for notable runs** (F1). Offline runs are sent later within the same group-day. Versus uploads unchanged. | WP-LB. |
| O56 | **No name reporting** (names come from the fixed word spinner; the word filter stays). Store-review risk noted in §6. | WP-LB, §6, §7.5. |
| O57 | **Privacy:** leaderboard data is removed after **400 days** without play; privacy policy + Play Data safety + App Store privacy say that names, avatars and scores are shown on public leaderboards; **Delete My Data** removes all board data on the server and the leaderboard keys on the phone, but **keeps the streak** (local progress; F12). | WP-LB, §7.2 T14, §7.3 C5. |
| O58 | **Wording:** "no loot boxes / never mystery boxes" becomes **"random boxes are never sold"** (F8; the "odds shown" half is withdrawn by O61). Code tag **`P26-LB`** (2.5 code already uses "WP-L", F10). | §1.2, WP-F, §7.5 S5 / S10. |

**Round 8b (2026-10-23, the board's info overlay; round 22b)** — owner review of `leaderboard.html` §4.

| # | Decision | Effect |
|---|---|---|
| O59 | The board's **i** box opens a simple **picture guide** instead of the text sheet: the board stays visible but dimmed, big title LEADERBOARD, **4 steps** as big drawn pictures with short captions joined by curved arrows in a zig-zag — **FLY AND SCORE** (bird through a hoop, points pop) → ~~**CLIMB YOUR GROUP**~~ **TOP THE BOARD** (O67; mini top 3, your row moves up) → **WIN GIFT BOXES** (gold box on rays with a peek of coins / golden feather / puzzle piece / mystery item; never a specific prize promised) → **BEAT THE RECORDS** (BEST RUN tab: trophy + crown + record row) — and **TAP TO CONTINUE** (a tap anywhere closes it). No detail text (no player counts, no ghost / 24 h rules, no odds). LB-22–LB-35 and LG-16 are dropped; new LB-36–LB-39. | WP-LB LB1, §7 D17 / T16. |
| O60 | The guide shows **by itself the first time** the player opens the board from the Home trophy box (not over a results climb — **confirmed, O67**), then only from the i box. New storage key **`lbInfoSeen`** (bool; cleared by Delete my data with the other leaderboard keys). | WP-LB LB1, Appendix keys. |
| O61 | Gift-box **odds are not shown to players** anywhere (boxes are free, earned by rank and **never sold**; stores require odds only for paid boxes). The odds table stays a server / design rule (LB2, `leaderboard_gifts.html` §3). Replaces "their odds are shown" in O58, §1.2, WP-F, S5, S10. | §1.2, WP-F, WP-LB, §7.5 S5 / S10. |

**Round 9 (2026-10-23, second review of the approval pages; round 23)** — `.worktrees/briefs23/ROUND23.md` ("Owner answers given in chat this round" binding), notes `notes_*.md`, designer reports `CHANGES_board23.md`, `CHANGES_hub23.md`, `CHANGES_daily23.md`, `CHANGES_cards23.md`. Precedence: the owner's notes and chat answers over every older line of this PRD.

| # | Decision | Effect |
|---|---|---|
| O62 | **TODAY tab: no "BEST n" line anywhere** — podium, rows #4–#50, the pinned own row, the results-climb rows and the GO TO COLLECT rows show only the player's **total points today**. The BEST RUN tab still shows best runs. | WP-LB LB1, §7 D17 / D18 / T16. |
| O63 | **Achievements move into the board:** the medal (achievements) button is **removed from Home** (top row = gear, trophy, coin pill); our board gets a third tab **TODAY · BEST RUN · ACHIEVEMENTS** (~~↗~~, plain word, O89) that opens the **native** Play Games / Game Center achievements screen (the call the medal box made). No own in-game achievements list; back returns to the board on the tab it was on. | WP-LB LB1 / LB4, §2, §7 D17 / T16. |
| O64 | **No visible entry to the native leaderboards:** the "PLAY GAMES / GAME CENTER LEADERBOARDS" link at the bottom of the board is removed on both platforms. Scores and achievement unlocks are **still submitted** in the background on every run. Replaces the link part of O53 and S12. | WP-LB LB1 / LB4, E1, §7.5 S12. |
| O65 | **Prize = board places 1, 2 and 3 only** (gold, silver, bronze). A ghost on one of those places keeps it: that box goes to **nobody** and nobody moves up; a real player on place 4 or lower **never** gets a box (e.g. ghost 2nd → you 3rd still get bronze; you 4th get nothing, no popup). Replaces O54's "top 3 real **and** rank ≤ 10". Each group gives **0–3** boxes (fewer when ghosts hold podium places). | WP-LB LB2, F12, §5, §6, §7 D18. |
| O66 | **Join window:** the server never places a **new** joiner in a group with **< 3 h** left (`LB_MIN_LEFT_MS` 3 h); it opens a fresh group instead (Q24 approved with 3 h instead of 2 h). | WP-LB LB1 / LB3. |
| O67 | **Board details approved:** before the first run of a group-day the board shows "YOUR GROUP STARTS WITH YOUR NEXT RUN" + PLAY (Q22); **no rank badge** on the Home trophy box (Q23); the picture guide **never** opens over a results climb, `lbInfoSeen` is set only on the trophy open (O60 confirmed). Guide caption LB-37 **CLIMB YOUR GROUP → TOP THE BOARD**; BEAT THE RECORDS uses a **Flappy Spikes trophy** (gold cup with pink spike teeth, hoop-ring handles, pink bird badge, pink plinth); captions on pink bands; arrows with a dark edge. The gold glow on the Home trophy hugs the 38 × 38 box (2 → 4 pt pulse). | WP-LB LB1, §7 D17 / T16. |
| O68 | **Gift edge cases approved:** a feather the player cannot take becomes a puzzle piece, a piece becomes the 100–300 coins pre-rolled with the box (Q20); one GO TO COLLECT per box, oldest first, one per Home visit; an unopened box waits up to 400 days (Q21). | WP-LB LB2, C2. |
| O69 | **Levels tabs move under the screen title, text only, no icons:** LEVELS · WORLDS · GUIDE · ALBUM as 4 flat 70 × 28 pt tabs (4 pt gap) at x 14–306, y 134–162, in the board's TODAY / BEST RUN tab style (open tab pink #EC008C with white Opificio 11 pt, the others soft pink #FCD9EE with pink text, gold tab dot on the top-right corner). The top row holds only the back button. The approved levels header and list move down 32 pt (header y 172, list from y 264). Replaces O29's placement. | G4, G6, §7 D14. |
| O70 | **Home NEW tag** (replaces the Q5 recommendation "no hint on Home"): while a Levels tab dot is pending, the Home level emblem (tap → Levels) shows the existing gold `MenuTag("NEW")` on its top-right corner with the Skins-tile wobble. An explicit owner exception: "no NEW! stickers" still holds for unlock cards and in-run stickers. Exact rules: Q26 (approved as recommended, O83). | G4, G6, §7 D14. |
| O71 | **Mission rows:** no EASY / MEDIUM / HARD labels on mission rows (missions panel, Star Road mock, weekly course mock); the difficulty stays internal and still sets coins and stars. The panel's chest row reads only **"ALL 3 DONE"** ("→ BONUS CHEST" removed; the gold chest icon stays). | G1, G5, G6, §7 D5 / T5. |
| O72 | **STREAK LOST for every lost streak, 1 day included** (Q17 answered against the recommendation): the same popup, no extra text, with singular wording for 1 day. | G2, §7 D16 / T6. |
| O73 | **RESTORE brings back only the last streak** (Q18 answered against the recommendation): the offer holds the streak as it stood when it broke (restored days included). Each new break makes a new offer that **replaces** any open offer; a given-up or unrestored older streak never comes back. Examples: 13 lost and not restored → flew 2 days → missed → the offer is **2**; 13 restored → flew 2 days → missed → the offer is **15**. | G2, §7 D16. |
| O74 | **Chip after GIVE UP:** a grey flame with 0 until the next finished run makes it 1, no extra text (Q19 approved). | G2. |
| O75 | **Star Road:** no rarity word (RARE / EPIC / LEGENDARY) on the road or in the Home popup — item tiers show "MYSTERY" and only the box colour shows the rarity; no difficulty labels on the mission rows (O71); the popup comes **at most once a day**, on the first Home visit after a tier became claimable (Q10 decided). **Season names:** a themed name per season instead of plain "SEASON 4" (owner: "more creative, outside the box") — the designer's list of 13 names needs the owner's OK (Q27; approved in round 24, O83). | G6, §7 D11d / T12. |
| O76 | **Weekly course:** no difficulty labels on its mission rows (O71); the weekly results have **no level line** (level points still count silently; a level reveal still plays after the page); no weekly board on Game Center either (confirmed). | G5, §7 D8 / T9. |
| O77 | **BIRDWATCHER = 25 points**, icon in the spike-ring style with a bird holding binoculars, name unchanged (Q11 approved). | J9, §7 D15. |
| O78 | **Puzzle album:** pieces held at the 2.6 update are kept and the picture in progress counts when it is finished; only pictures finished before 2.6 are left out (Q8 approved). | G6. |
| O79 | **The shop header never scrolls** (every tab): back, coins, collection bar, stage, the category tab row and (CARDS) the FRAMES / NAMES / STICKERS row stay fixed; only the tile grid scrolls under them, with a light shadow under the fixed rows while scrolled and a thin scroll bar. | F9, §7 D9. |
| O80 | **6 new skill-only card items** (owner: "very unique and special … only earned through skills"): name styles **Skywriter**, **Thunderstruck**, **Headliner**; victory stickers **Unstoppable**, **Flawless**, **Top of the Flock**; each unlocked by one new versus achievement (proposed, Q30; approved in round 24, O83; in the shop shown as "? ? ?", O85). Skill-only items 18 → **24**; per card kind x/20 (17 sold + 3 skill); a locked skill tile opens a **HOW TO EARN** sheet. | F9, F10, J9, §7 D9 / D10 / D15 / T10 / C6. |
| O81 | **No 2.5 grandfathering** (owner: "there are no players in 2.5"): no quiet first-launch grant and no "returning player" path — a skill item is owned when its achievement is earned (derived from the achievement state). **PROUD PEACOCK** counts every **sold** item, the 51 versus-card items included (Q13 answered against the recommendation); skill items stay excluded. Changes O39. | F10, §7 D10. |
| O82 | **Approved as recommended:** BIRD OF PREY (5 versus wins in a row, 25 points, hidden; Q14); frames may reach up to 7 pt past the avatar box, drawn under the score box (Q15); BULLSEYE 40 and SKY HIGH 50 points (Q12). | F9, F10, J9, §7 C6. |

**Round 10 (2026-10-23, third look at the approval pages; round 24)** — red-box notes (label app26) on `leaderboard`, `leaderboard_gifts`, `levels_tabs`, `star_road`, `texts` and `versus_cards`; designer report `.worktrees/briefs21/CHANGES_round24.md`. Precedence: the owner's notes over every older line of this PRD.

| # | Decision | Effect |
|---|---|---|
| O83 | **Every open question approved as recommended** (owner: "Approved with recommended" / "All recommended approved"): **Q4** chest name **BONUS CHEST** everywhere; **Q16** the flight guide is built from the `texts.html` FG-E rows (mockup lines are placeholders); **Q25** the WP-LB deploy + import (C8) is covered by O27 (import only after the owner's OK on the day, cleanup C9 before production); **Q26** Home NEW tag rules as proposed (shows while a Levels tab dot is pending, clears when Levels is opened, never in runs 1–3, waits behind a LEVEL UP claim; one bool `homeLevelsTag`); **Q27** the 13 season names as listed; **Q28** the rarity chip stays in the item reveal after CLAIM; **Q29** ACHIEVEMENTS tab while signed out = the medal-box sign-in, the native screen after it succeeds, a cancelled sign-in leaves the board, no disabled look; **Q30** the six skill-item achievements as listed (58 achievements, 965 of 1,000 points). | G1, G4, G6, F10, J9, WP-LB, §7 |
| O84 | **GO TO COLLECT has no ghost line:** LG-6 "Runs from earlier days win no prize." is dropped (Q31; owner: "users can't see it's a ghost and don't need to know it's a ghost"). Confirmed: a ghost on a prize place keeps it and **nobody else** gets that prize (O65). | WP-LB, §7 D18 / T16 |
| O85 | **Skill card items are secret in the shop** (owner: "all earned by skills have a ??? instead of telling how to get it"): all 9 EARNED BY SKILL card items (3 frames, 3 name styles, 3 stickers) show the **"? ? ?"** pill, the stage strip **"SKILL ONLY · SECRET"**, and the HOW TO EARN sheet shows only the item, LEGENDARY · SKILL ONLY · NEVER SOLD, "? A SECRET ACHIEVEMENT ? / Keep racing to find out.", "ACHIEVEMENT: ? ? ?" and GOT IT (no condition, no best-so-far, no points), until earned. The achievements themselves keep their console visibility (the six round-23 ones stay visible, Q30). Replaces "their goals are visible" (O80). ~~Whether the 18 skill items of the other shop tabs follow: **Q32**.~~ Round 25: they do — all 24 skill items (Q32 → O88). | F9, F10, §7 D9 / D10 / T10 |
| O86 | **Thunderstruck restyled** (owner: Skywriter and Thunderstruck "are the same color, change one … more unique and special"): a small dark storm cloud drifts over the name, electric-yellow letters (white → #FFF176 → #FFB300) with a deep violet edge (#2A0845) and a violet crackle aura (#B388FF); every 2.3 s a bolt drops from the cloud onto a letter, the cloud lights up and the name flashes white. Skywriter keeps the sky blue. | F9, §7 D9 |
| O87 | **WORLDS tab order: world 1 at the top**, counting down 1, 2, 3 … 10 (START · HOOP 0 above NEST CANOPY, SPACE last); it was SPACE on top. The tab still opens scrolled to the player's furthest world. | G4, §7 D7 |

**Round 11 (2026-10-23, round 25)** — red-box notes (label app26) on `leaderboard`, `star_road_popup` and `texts`; designer report `.worktrees/briefs21/CHANGES_round25.md`. Precedence: the owner's notes over every older line of this PRD.

| # | Decision | Effect |
|---|---|---|
| O88 | **Every skill item is secret in the shop** (Q32 approved as recommended; owner: "Approved on recommendation"): all **24** EARNED BY SKILL items — the 15 of BIRDS / GEAR / HATS / HOOPS / TRAILS and the 9 card items — show the **"? ? ?"** pill on a locked tile, the stage line **"UNLOCK: ? A SECRET ACHIEVEMENT ?"** / strip **"SKILL ONLY · SECRET"**, and the HOW TO EARN sheet in its secret form ("? A SECRET ACHIEVEMENT ? / Keep racing to find out.", "ACHIEVEMENT: ? ? ?", no condition, no progress, no points) until earned. One shop rule. The achievements keep their console visibility (visible ones stay visible in Play Games / Game Center). Extends O85 from the card items to all skill items; the goal pills ("HOOP 150" …), the goal form of the strip and the progress line are dropped. | F10, §7 D10 / T10 |
| O89 | **ACHIEVEMENTS tab without an icon** (owner: "Remove the icon from ACHIEVEMENT"): the third board tab is the plain word **ACHIEVEMENTS**, drawn exactly like TODAY and BEST RUN; no "opens outside" mark / ↗. The tap still hands off to the native screen (O63). | WP-LB LB1, §7 D17 / T16 (LB-40) |
| O90 | **Spike strips as in the game, everywhere they are drawn** (owner, on the picture guide's FLY AND SCORE picture: "there is a white space between the ceiling and the spikes" / "same here … bottom and spikes"): any picture of the run, also small ones in guides and popups, uses the one strip master (solid band + teeth, the stage foreground colour), **pinned to the very top and bottom edge, full bleed**, with no frame or gap between the edge and the band. | WP-LB LB1 (picture guide), §7 D17; art rule for every guide picture |
| O91 | **Star Road Home popup polish** (owner: "Make more fun, add confetti animation, more polished animation … uniform with the other popups … keep the overall design"): same layout; the card pops in (`Sfx.skDialog`), the reveal rays (O41) turn behind the tier badge, the badge drops in and squashes on landing while its number ticks up to the new tier, with a sparkle ring, a confetti burst and two small confetti poppers from the card's top corners (`Sfx.lvUp`); the title pops, the reward tiles pop in one by one with a sparkle and a shine (`Sfx.vsPop`, rising pitch); the button slides up. Idle: rays turn, badge bobs, twinkles, the mystery box wiggles every 2.4 s, the button breathes. GO TO STAR ROAD presses with a star puff (`Sfx.skTap`), × `Sfx.skClose`. Reduced motion: no confetti, rays static (as O41). Existing cues only. | G6, §7 D11d |

**Round 12 (2026-10-23, design approval)** — owner: "All designs are now approved".

| # | Decision | Effect |
|---|---|---|
| O92 | **All 2.6 design pages approved** as they stand after round 25: levels tabs (Worlds / Guide / Album), missions, day streak + STREAK LOST, weekly course, Star Road + Home popup, first win of the day, versus cards, skill cosmetics, our leaderboard and the gift boxes. The pages in `design/approvals_v26/` are the build reference; a builder follows the page wherever the PRD is silent and the PRD wherever both speak. | §7.1 D5–D18 Approved; builds no longer wait on designs. Still to come: D2 emblem export check, D15 achievement icons, item art for new card / skill items (made from the approved page drawings). |
| O93 | **All texts approved** (owner: "Approve all"): every current row of `design/approvals_v26/texts.html` (T5–T12, T16, item names, achievement names) is approved as it stands. **Except T13 release notes:** a marketing agent writes the 2.6 "What's new" and the reviewer notes later, together with the store / website copy (O44); they must name the daily leaderboard with free gift boxes and the optional streak-restore video (S7). | §7.2 statuses. |
| O94 | **Icons for the 10 new achievements (D15):** an Opus 5.5 designer first makes an approval page in the `design/achievements/` style; the owner approves it with red-box notes; Sol (codex) exports the PNGs during the build. | §7.1 D15. |
| O95 | **Privacy policy (T14):** the proposed lines incl. PV-10 (leaderboard paragraph) are approved; the website change is deployed **on the day 2.6 goes to Play internal**, with the owner's OK on the day, before real players see the board. | §7.2 T14, C5. |
| O96 | **The 10 new achievement icons are approved** (owner: "All designs approved"): `design/approvals_v26/achievement_icons.html`, the recommended **A** variant for BULLSEYE (hoop target), IRON BEAK (steel beak snaps a spike) and TOP BIRD (our leaderboard trophy); the other seven as drawn. Art source `design/achievements/ach_art_v26.js` (adds to the 48, same ring / bird code); Sol exports the PNGs in wave 5 via the page's `#export=<size>` route (the `rec` variant), named by the final achievement ids. | §7.1 D15, §7.3 C6, §4 wave 5. |

**Round 13 (2026-10-24, build setup)** — owner: "reuse the same elements that are already in the game instead of remaking them … so that the game feels coherent in design and not messy because the same element looks different in different screens."

| # | Decision | Effect |
|---|---|---|
| O97 | **Reuse existing game elements; the game wins.** When an approved 2.6 design draws an element the game already has (rays, boxes, confetti, coin fly / counter, popup frame, buttons, tags, banners, stickers, sparkles, emblems, avatars, card painters …) and the two look different, the builder reuses the **existing in-game element and its code**. The design pages count for layout, size, colour and timing only. A new look is allowed only as a parameter (colour, size, label) of the same master, never as a second drawing. Exception: the box (O99). | Every WP with UI; extends PRD-2 §3.0.9 (one master per shared part). |
| O98 | **Rays: the 4 existing ray versions stay** (results page gold / light, LEVEL UP pink, No-Ads celebration gold, shop preview rarity rays); old screens are not restyled. Every new 2.6 reward moment reuses the existing ray that fits best, **as it is**. The O41 ray look ("a bit longer, fading to transparent with a radial gradient") is **dropped**; rays still sit behind the item and turn slowly, as the existing ones do. O41's confetti and sound parts stay. | O41 (rays part replaced), O91, G1 chest, J7a reveal, F10 reveal, WP-LB gift opening, G6 Star Road. |
| O99 | **One box master = the approved mystery box** (`docs/p26/design/levels_v26/item_reveal.html`): the level mystery box, the BONUS CHEST (gold), the leaderboard gift boxes (gold / silver / bronze), the Star Road mystery tiles and the **in-run gift box of the paired hoops** (`lib/run/hoops/kinds/pair/gift_box.dart`, restyled to match) all draw from it; colour, size, label ("?") and the lid animation are parameters. | J7a, G1, WP-LB, G6, the pair hoops (visual only; hitboxes and rules unchanged). |
| O100 | **Enforcement:** the first M0 issue writes `docs/p26/SHARED_ELEMENTS.md` (every shared element, its master file / class, its allowed parameters, and which 2.6 design elements map to it) and extracts the box master (O99) into one place with tests. Every later builder must use the list; the tester fails any second drawing of a listed element. | §4 wave 0, df4 builder / tester notes. |

**Still open for the owner:** ~~the designs, texts, the D15 achievement icons~~ the T13 release notes (marketing agent) and the console actions in **§7** (designs, texts and achievement icons approved 2026-10-23, O92 / O93 / O96). **No open product questions** (round 25: Q32 → O88). ~~and one new question **Q32** (§7.4, with a recommended answer)~~. ~~The questions in §7.4 still open from rounds 21–22 (Q4, Q16, Q25) and the round-23 questions Q26–Q31~~ (all decided in round 24, O83 / O84). Earlier questions:
- **Q1 (decided 2026-10-21):** accept R5 — the 10 rank achievements stay single-run score achievements; consoles unchanged.
- **Q2 (decided 2026-10-21):** drawn art (PNG) for the 31 emblems (J6 route b); concepts generated for owner approval first, like the icon / achievement icons.
- **Q3 (decided 2026-10-21):** approved — deploy functions + rules for R3/R4 as rollout step 1, before the 2.6 app goes to Play internal.

---

## §1 Goals, non-goals, pillars, invariants

### 1.1 Goals (measurable in §5)
- **G1 Hook:** in run 1 a new player sees a ride and reaches a median of 15–25 hoops. At least 85 % start run 2.
- **G2 Mastery:** inside a run, difficulty grows with depth to a ceiling at hoop 150. Over lifetime, saw (game 4) and squeeze (game 6) silently start appearing.
- **G3 Far for the best:** the top 5 % reach hoop 150 by day 30, and the 99th-percentile best is ≥ 200 hoops. Past 150 the runs stay varied.
- **G4 Fair competition:** every versus ghost and leaderboard score comes from the same in-run curve (R2). Money keeps buying only what it buys in 2.5 (cosmetics, No-Ads, coin revives).
- **G5 Long-term progress:** levels give a visible goal every few runs (level 5 in session 1) reach THUNDERBIRD at 74,725 cumulative points and then continue endlessly as ETERNAL WING 32, 33, … (WP-J). Beat-your-best gives a goal inside every Free Fly run (WP-K).
- **G6 Retention:** D1 ≥ 35 %, D7 ≥ 12 %, D30 ≥ 4 % (hyper-casual targets, not measured yet).

### 1.2 Non-goals
- No per-player in-run difficulty (no dynamic difficulty adjustment). Level, best score and payments never change the curve.
- No same-course versus replay (systems A.5: the course depends on player state; needs its own PRD).
- No remote behaviour config, no paid or purchasable random boxes (free gift boxes and level / chest reveals are never sold, O58 / O61), no paid in-run boosts, no end-of-run ×2-coins ad. Level items are a fixed reward per level, not a purchase.
- No change to ad timing, system-dialog timing, revive rules or point sources (O2–O5, O13).
- No carry-over or migration design beyond the level fresh start (J4). Every player is new; 2014 players may simply be better at flapping.

### 1.3 Design pillars
1. **Spectacle before skill, invisibly:** the first runs happen to show a ride, power-ups and coin moments early, without ever telling the player they are special.
2. **One new thing at a time:** in-run (introductions ≥ 5 hoops apart, one headline per 8 hoops) and over lifetime (saw at game 4, squeeze at game 6, appearing without ceremony).
3. **Readable difficulty:** what kills you could be seen and passed (aligned tilts, Δy cap in points, hazard budget).
4. **Same curve, same race:** one in-run curve for everyone (R2).
5. **Always a next goal:** the next level (WP-J) and your best (WP-K).

### 1.4 Invariants (must stay true; tests guard them)
- **CLAUDE.md:**
  - `maxTranslation = 10000`.
  - One master per shared part: the NEW BEST! sticker reuses `GoldSticker`, the level-up popup reuses the P1 popup frame, and no new banner variant is added.
  - Never `GameAuth.signIn()` at launch; never `GameAuth.isSignedIn`.
  - SFX only through the low-latency `AudioPool`.
  - Results-page labels use `Config.uiAccent`.
  - New run elements (the WP-K gold line included) go through `world.addRun(...)`.
  - `flutter analyze` is clean and `flutter test` is green; `autopilot_test.dart` passes ≥ 12 hoops at 568 and 711 pt.
- **PRD-2.5:**
  - No downloaded behaviour config.
  - Storage key **names** never change (`playerLevel`, `claimedLevels`, `unclaimedLevelReward`, `levelRewardPayout` stay). New keys are appended at the END of `kObfStrings` (`tool/gen_obf_strings.dart`), then regenerate `obf_strings.g.dart` and add them to `tool/anchor_strings.txt`.
  - New tuning keys get a `// §` comment, never a description string.
  - Same behaviour for reviewers: arms are random, with no reviewer detection.
  - `kLeaderboardMaxScore` stays 32,500,000 and `test/protection/leaderboard_max_test.dart` passes **unedited**, so top speed stays 187.5 and spacing 310 everywhere (formations included).
  - Server constants `PASS_MAX_SPEED` 187.5, `PASS_SPACING` 310 and `PACE_MIN_MEDIAN_CS` 135 (`functions/src/schema.ts:265-271`) stay valid.
  - New point sources must go through the existing `BONUS_CAP` (80) / flags. (2.6 adds none.)
- **Versus fairness rule (R2):** everything that changes death risk or points per hoop is a function of the in-run hoop index and in-run state. That covers opening, band, speed, Δy, tilt, motion, specials, hazards, calm stretches, squeeze, rides, Big Hoops, hearts and shield rates. The only lifetime inputs are the saw / squeeze gates, the showcase safety net and the 2.5 first-meet pulls. Nothing depends on best score, level, profile, arm, payment or device height (Δy in points). A test enforces it (§3.D tests).
- **Determinism:** the same seed + the same context gives the same plans. All new filters (hazard downgrade, calm, the squeeze gate) act on draws that are still made, so random streams never shift.

---

## §2 Player journey

Times assume about 2.07 s per hoop early (150 pt/s, 310 pt spacing) and about 1.8 s at hoop 50.

| Moment | What the player sees / does | Unlocks / earns |
|---|---|---|
| **Minute 0, first launch** | As today: Home, with the system sheets at launch (O3, O8). VERSUS is the default mode. The Home top row has the gear and the trophy box only: the medal (achievements) button is gone; achievements open from the board's ACHIEVEMENTS tab (O63). | — |
| **Run 1, about 0:00–1:00** | A normal-looking VERSUS run (VS intro and an opponent when the pool has one), on the normal curve. A death before hoop 0 is a normal death. Big Hoops (60 s) + shield armed at start, like any armed power-up. Star trails at gaps 2 and 5, golden feather at gap 4. **Portal at hoop 7 (about 16 s) → the Cannon roller-coaster ride** (any crossing of the portal plane starts it). Hearts at gaps 10/13/16. The first death after hoop 0 → **FREE revive**. | Typically 18–25 hoops; the score usually clears 25 points → **level 1 HATCHLING** (25 points): 50 coins + a common hat. |
| **Results page after run 1** | Level bar fills, LEVEL UP! with the HATCHLING emblem, coins fly in, the mystery box opens on a common hat → EQUIP / LATER (J7a). Skins/Shop open (R8). | — |
| **Run 2** | Big Hoops + shield armed at start; Coin Frenzy capsule at gap 3; **comet star at hoop 9 with a magnet** → comet ride; bullseye at hoop 14. | Level 2 FLUFFBALL (50) likely: 50 coins + a common trail. |
| **Run 3** | Big Hoops + shield armed at start; **FEVER ring at hoop 5** (any pass lights it, streak ×5); puzzle piece 1/4; **Space portal ride at hoop 15**. | Level 3 (100) likely. |
| **Run 4 (game 4)** | Home is just Home. Saw can now appear on the curve from hoop 30, without any card or sticker. In Free Fly: "BEST 42" chip + gold line (WP-K). From now on a run that moves you up in your leaderboard group shows the board climb on the results page (WP-LB). | Level 4–5 around runs 4–8. |
| **Run 6 (game 6)** | The first squeeze can come at hoop 25–40 when reached (2.5 timing); no card or sticker. | — |
| **End of session 1** | About 10–14 runs, about 20–25 minutes, 300–600 coins from play plus about 375 from levels, level 5–8, 5–8 items. | — |
| **Day 1** | The 2 reminders a day leave out elements the player has not met. "New daily missions are in! 🎯", missions strip under START, the drawn flame chip with "2" (O33). The Home trophy box opens our leaderboard: yesterday's group ended → GO TO COLLECT if the player finished on board place 1, 2 or 3 (O65). | Missions about 150 coins/day; streak day 2 = 30; a gift box for board place 1–3 (O65). |
| **A missed day** | The next Home visit shows STREAK LOST (old streak → 0, also for a 1-day streak, O72): RESTORE by video (No-Ads owners: 500 coins) or GIVE UP; the offer waits across days (O47–O49). | The last streak back (O73). |
| **Day 7** | Streak day 7 = feather + 60 (no freezes, O46). Weekly course open for players with best ≥ 40 hoops. Typical best 40–80 hoops, level 10–14 (HUMMINGBIRD: the first rare bird). | — |
| **Day 30** | Top players at the hoop-150 ceiling, with formations and mix chapters past it. SPACE (hoop 180) for about the top 5 %. Levels 20+ (epic items). Worlds tab (SPACE FLYER title at SPACE), weekly course, Star Road season end, versus-card cosmetics. | Weekly: max 570 coins/week. |

---

## §3 Work packages

Each WP lists: priority (must / should / could) · effort (S/M/L) · release.

### WP-A Analytics baseline — must · M · 2.6

**Goal:** answer "where and why do players die, did they see the wow, and what unlocks when" from day one.

**A1 Fix first**
- `perfect_pass` fires once per perfect pass (`lib/run/items/streak.dart:157`) and would hit the 1 M/day export limit at about 1–1.5 k daily players.
- Remove it. Its counts move to `run_extra` (per run).

**A2 New / extended events** (names ≤ 40 characters, ≤ 25 parameters; buckets because GA4 has no medians)
- **Hoop buckets (`hb`):** 00-04, 05-09, 10-14, 15-19, 20-29, 30-39, 40-59, 60-79, 80-99, 100-149, 150-199, 200+.
- **Games buckets (`gb`):** 1, 2, 3, 4-5, 6-9, 10-19, 20-49, 50+.

| Event | When | Parameters |
|---|---|---|
| `run_fail` (merges curves' `mistake` and systems' `run_fail`) | Every mistake that would end the run, whatever the outcome | hoop, hb, cause, elem, tilt_deg, motion, opening, dy_pt, squeeze_idx (−1 = none), calm, hazard_x10, since_calm, formation, ride_exit, new_elem, outcome (end / revive_ad / revive_coins / revive_free / shield / life), run_no, gb, level, mode, showcase, speed — 22 |
| `run_end` (extend) | Existing (`analytics_router.dart:78-100`) | Add mode, showcase (0–3), hb, highlights, calm_count, max_hazard_x10, revives_ad, revives_coin, level, lvl_pts_before, beat_best_hoop (WP-J/K). Drop `clean_passes` and `opening_end` if the count goes over 25. |
| `run_extra` | Run end | perfect counts by tier, ride_hoops, squeezes, max_speed, coins_bonus, formations, downgraded |
| `ftue_step` | Once per step per install | name ∈ {first_tap, run1_highlight, run1_end, run2_end, run3_end, showcase_done, run4_start, first_saw, first_squeeze, level_1, level_5, level_10, versus_first_end, run20_end}, s_since_install |
| `showcase_start` / `showcase_end` | Showcase runs | step, attempt / + hoops, score, highlight (0/1), cause, shield_used, revive_used |
| `showcase_done` | Once | runs, s_since_install, via (all / cap / fast) |
| `highlight_seen` | A ride, comet or FEVER starts | id, scripted, run_no, hoop |
| `first_meet` | An element is met for the first time | element, hoop, games, forced, survived |
| `level_up` / `level_reward_claimed` (extend) | WP-J | see J10 |
| `best_beaten` | WP-K | mode, hoop, best_before, games |

(No `unlock_step`, `unlock_card`, `next_unlock_tap`, `versus_unlocked`, `launch_ask` or new `interstitial_skip` reasons: the ladder, the unlock cards, the versus lock, the dialog deferral and the cadence change are gone, O2/O3/O15/O16. All showcase events are silent analytics only.)

**A3 User properties** (≤ 24-character names; none are set today, there is no `setUserProperty` in `lib/`):
- `fs_level` (plain level number, 0 … no cap), `fs_gb`, `fs_best_hb`, `fs_showcase` (0/1), `fs_arm`.
- Add a try/caught `setUserProperty` to `GameServices`; the no-op default stays.

**A4 GA4 registration (owner):**
- About 16 event dimensions: hb, cause, elem, motion, outcome, gb, mode, showcase, name, id, element, new_elem, formation, item_layer, rarity, fallback.
- About 9 metrics: hoop, hoops, score, run_s, coins, highlights, hazard_x10, level.
- Plus O10 (approved): BigQuery daily export, retention 14 months, Google signals off, $5 budget alert; the orchestrator sets them up in the console when the owner is signed in.

**Files:**
- `lib/run/items/analytics_router.dart`
- `lib/run/mistakes.dart` (emit `run_fail` from the existing save / death events)
- `lib/run/items/streak.dart`
- New `lib/services/ftue_tracker.dart`
- `lib/services/game_services.dart`

**Storage:** `ftueSteps` (bitmask int).

**Tests:**
- `analytics_names_test` (every name ≤ 40 characters and snake_case, ≤ 25 parameters)
- `run_fail_test` (one event per mistake, with the right outcome for shield / life / revive / end)
- `perfect_pass` no longer sent per pass
- `ftue_tracker_test` (each step once, survives a restart)

### WP-B Showcase (invisible early highlights) — must · M · 2.6

**Goal:** runs 1–3 feel like normal runs that happen to be lucky. Each has a guaranteed highlight, placed early and invisibly, on the normal curve (O15, R6, O16).

**Invisible to the player (O16):** no step names or framing, no graduation popup or "YOU'RE READY!" band, no FREE ribbon on the home slot, no practice loop, no special UI of any kind. A death before hoop 0 is a normal death. The only visible trace is the revive screen's FREE label on the first revive (accepted by the owner).

**B1 State** (new pure model `lib/run/showcase/showcase_plan.dart` and constants in a new `lib/run/config/showcase_config.dart`; internal only, nothing is shown)
- **Step S** = the first step whose highlight bit is unset. Bits: 0 portal ride, 1 comet ride, 2 FEVER lit.
- **Done** when all bits are set, OR `gamesPlayed ≥ showcase_max_games` (6), OR a showcase run passes `showcase_fast_hoops` (40).
- **Attempt A** is incremented and saved at START. The plan is frozen into `RunSetup.showcase` at START.
- **Never build the showcase on `setup.forced`.** `_cleanStart` requires `forced.isEmpty` (`run_controller.dart:118`), so a forced showcase run would never count for achievements. Use a separate planner step 0 in `RunDirector`, before debug-force, first-meet and the portal schedule.
- **Highlight bits are written the moment the highlight starts**, so a kill or crash never replays it.

**B2 What all showcase runs share**
- **Mode, ads, dialogs: as today.** The run is played in the Home mode (VERSUS by default, with VS intro, opponent and upload by the 2.5 rules) or Free Fly. Banner, interstitial grace and system sheets are unchanged (O2, O3). The only ad difference is that the first revive offer is FREE (below).
- **Counts for everything:** versus upload, leaderboard (`bestScore`), levels (WP-J), coins, achievements (`countsForAchievements` stays true).
- **Element set: the normal mix by hoop index** (tilt from 10, switch 15, moving 25 …, D1), plus the lifetime gates: no saw before game 4, no squeeze before game 6 (C1). Repeated showcase runs at games 4–6 therefore can meet saw, which is consistent with R2.
- **Layout and opening:** the normal curve (R6).
- **First-meet** pulls are off in showcase runs, so they don't compete with the script. The headline window (D6) keeps the rest calm around the highlight.
- **Starters:** Big Hoops + shield are armed at START in every showcase run. They look exactly like a normal armed power-up: no label and no FREE offer on the home slot. If the player already armed one from the home slot, the other is added. Big Hoops lasts D = 60 s in step 1 (today a 30–40 s roll) and the normal roll in steps 2–3.
- **Revive:** one FREE revive per run, from the first death after hoop 0 is passed. It ignores `revive_min_hoops` (6, `tuning_defaults.dart:77`). It adds `ReviveOfferKind.free` back for showcase only (`revive_ladder.dart:7`); the revive screen labels it FREE. After it, the normal 2.5 revive ladder applies (ad, then coins; in versus too, O5).

**B3 Scripts** (hoop = slot index, gap = gap index; step names are code-internal only)

**Step 1** (highlight: portal ride start; theme = Cannon, the owner's "roller-coaster", placed early)

| Item | A = 1 | A = 2 | A ≥ 3 |
|---|---|---|---|
| Starters | Big Hoops 60 s + shield | same | same |
| Portal (Cannon) | hoop 7 | 5 | 3 |
| Star Trail | gaps 2, 5 | 2 | 2 |
| Golden feather | gap 4 | 3 | 2 |
| Hearts | gaps 10, 13, 16 | same | same |

**Step 2** (highlight: comet ride start; power-ups)

| Item | A = 1 | A = 2 | A ≥ 3 |
|---|---|---|---|
| Starters | Big Hoops (normal roll) + shield | same | same |
| Coin Frenzy | gap 3 | 3 | 2 |
| Comet star | hoop 9 | 6 | 4 |
| Star Trail | gap 6 | 5 | — |
| Bullseye | hoop 14 | 14 | 14 |
| Hearts | gaps 12, 15, 18 | same | same |

**Step 3** (highlight: FEVER lit; plus a portal ride in another theme, O12)

| Item | A = 1 | A = 2 | A ≥ 3 |
|---|---|---|---|
| Starters | Big Hoops (normal roll) + shield | same | same |
| FEVER ring | hoop 5 | 4 | 3 |
| Puzzle piece | gap 8 | 6 | 5 |
| Portal (Space; not Cannon) | hoop 15 | 13 | 11 |
| Hourglass | gap 11 | 11 | 9 |

After the script's last item the run continues on the normal schedule. The portal schedule is re-seeded after a scripted portal (`last scripted portal + 25..40`).

**B4 Highlight grabs** (showcase only; invisible, they only make the lucky moment hard to miss)
- **Portal:** any live crossing of the portal plane starts the ride. The existing 0.5 s join smooths it.
- **Comet:** pickup radius 18 → 60 pt, and the star drifts toward the bird at up to 90 pt/s (`lib/run/pickups/comet_star.dart`). It is placed via the existing `cometMode = 2` path.
- **FEVER:** in `RunController._pass`, the FEVER branch's `!h.touched` is treated as true.

**B5 Home:** unchanged during and after the showcase. There is no showcase or graduation moment; the next Home after run 1 is just Home (plus the WP-J level-up flow, which is not a showcase element).

**Edge cases**
- **Dies at hoop 2 in step 1:** normal results (it counts for levels and versus like any run); the next START is step 1 with A = 2.
- **Dies before hoop 0:** a normal death and a normal results page (no practice loop, O16). The free revive is not offered there, because it starts after hoop 0.
- **Kill after the highlight:** the bit is already set, so the next run is the next step.
- **"Delete my data":** resets every showcase key.
- **Testers / existing installs** with `gamesPlayed ≥ 3` and no showcase key: treated as done.
- **No-Ads owners:** the same script.
- **Tablets:** scripted items go through the director, so `world.addRun` holds.

**Files:**

| File | Change |
|---|---|
| `lib/run/run_setup.dart` | `showcase`, `extraStarters` |
| `lib/run/run_controller.dart` | Scripted items; FEVER / portal grab rules; never touches `_cleanStart` |
| `lib/run/director/run_director.dart` | Planner step 0; first-meet off in showcase; portal re-seeded after a scripted portal |
| `lib/run/items/big_hoops.dart` | D override, still drawing once so the seeds stay stable |
| `lib/run/items/shield.dart` | Arm from the extra starter |
| `lib/run/items/comet.dart`, `lib/run/pickups/comet_star.dart` | Magnet |
| `lib/run/screens/revive_rules.dart`, `revive_ladder.dart`, `revive_screen.dart` | The `free` kind for showcase only |
| `lib/game/flappy_game.dart` | Build the plan; arm the starters; `endRun` counters |
| `lib/run/debug/force_menu.dart` | Showcase row: step / attempt / done |

**Storage (new):** `showcaseSeen` (bitmask, bit 7 = done), `showcaseAttempt`, `showcaseRuns`, `showcaseDoneAt` (gamesPlayed at done).

**Tests:**
- Plan per step × attempt at 568 / 711 / 730 pt.
- Normal mix over 200 seeds: showcase plans equal the normal director's plans for the same seed except for scripted slots/gaps; no saw at `gamesPlayed` < 3, no squeeze at < 5.
- Bits persist across a kill; A increments at START.
- Invisible: no showcase widget, ribbon, banner or popup is mounted in showcase runs or on the Home after them (component scan); a death before hoop 0 ends the run normally.
- Big Hoops + shield are armed at START in steps 1–3 with the normal HUD; no FREE offer on the home slot.
- Portal grab in the showcase vs the old miss rule outside it.
- FREE revive once, with no `revive_ad` logged; then the 2.5 ladder (coins allowed in versus).
- `countsForAchievements` is true for showcase runs; a showcase run in VERSUS uploads like any run.
- Testers are treated as done.
- **Human-noise bot** (§0.3.4): sees the step-1 highlight in ≥ 85 % of 100 seeds at A = 1 and in 100 % at A = 3; the perfect autopilot sees each highlight in 100 % of 50 seeds.
- Golden: FREE revive heart.

**Analytics** (silent, nothing shown): `showcase_*`, `ftue_step`, `highlight_seen`.

### WP-C Lifetime gates (saw, squeeze), popup budget — must · S · 2.6

**Goal:** everything is on from run 1 except two silent lifetime gates: saw from game 4 and squeeze from game 6 (O15). They simply start appearing: no NEW! card on Home, no in-run sticker, no unlock animation or popup (O16). There is no ladder and no versus lock.

**C1 Gates** (`gamesPlayed` = every finished run in every mode, `gates_config.dart`; "game N" = `gamesPlayed ≥ N−1` at START)

| Key (`tuning_defaults.dart`) | Current | Proposed |
|---|---|---|
| `gate_egg`, `gate_pair` (:185, :187) | 4 | 0 |
| `gate_feather`, `gate_puzzle`, `gate_piggy`, `gate_jar` (:189–195) | 6 | 0 |
| `gate_fever`, `gate_lucky_spin` (:197, :199) | 8 | 0 |
| `gate_spring` (:183) | 4 | 0 |
| `gate_switch` (:171) | 0 | 0 (in-run from hoop 15, D2) |
| `gate_saw` (:201) | 12 | **3** (game 4) |
| `gate_squeeze` (new; `ElementId.squeeze` added to `GatesConfig.keys`) | — (not gated) | **5** (game 6) |

- Tilt, moving and big height jumps stay ungated (`gates_config.dart:8-10` already says so). They appear by in-run hoop index only (D1/D2).
- The squeeze gate is a pure filter: the squeeze schedule draws are still made and only the trigger is skipped while closed, so the random streams stay put (§1.4).
- No forced first meet for saw or squeeze: they come on the curve (saw from hoop 30, first squeeze at hoop 25–40 as in 2.5). The 2.5 first-meet pull for other elements is unchanged outside the showcase (R2).
- Debug: the "Runs: N" row (`force_menu.dart:42-48`) and `ignoreGates` keep working.

**C2 Popup budget** (for the existing game popups): at most ONE big game popup per Home visit.
- Priority: **STREAK LOST** (G2, O47) → LEVEL UP catch-up (WP-J) → streak reward (G2) → **leaderboard GO TO COLLECT** (WP-LB, O54) → missions chest (G1) → **Star Road reward popup** (G6, O37) → No-Ads popup → rating sheet.
- Everything else stays pending for later visits. The missions chest and the Star Road popup never show in the same visit; the Star Road popup shows at most once a day and never in runs 1–3. A STREAK LOST offer that is still pending takes the first visit of each day (O49); several waiting gift boxes show one per visit, oldest first (O68). The Star Road popup comes on the first Home visit after a tier became claimable (O75). The results-page board climb (WP-LB) is part of the results page, not of this budget.
- The achievement toast and mission ticks on results are exempt. System sheets (UMP / ATT / notifications / Game Center) stay at launch and are outside this budget (O3).

**C3 Small fixes**
- `ElementId.portal.firstPossible` 40 → 12 (`elements.dart:51`, the stale comment).
- Reminder texts #11, #13, #16 and #19 (squeeze, lucky spin, egg, FEVER; PRD-2 §3.34) are skipped while that element is not in `metElements` (`lib/services/reminders.dart`).
- **Reminder bodies that are false today are fixed (O42):** #2 "Your best is {best} points. How close can you get today?" (the value is the best *score*); #13 "Fly through a Lucky Spin ring and see where the wheel stops!"; #16 "Carry an egg through 5 hoops to hatch a chick for bonus points!"; #17 "Grab the piggy bank and catch the coins that follow!" (titles unchanged; exact rows in `texts.html` §3).
- Rating: `rate_min_runs` becomes max(5, showcaseDoneAt + 2).

**Storage (new):** none.

**Tests (`unlocks_test`):**
- 200 seeds × 60 hoops: no saw at `gamesPlayed` 0–2, no squeeze at 0–4; both present on the curve at ≥ 3 / ≥ 5.
- At `gamesPlayed` 0, tilt, moving and switch appear from their D1 hoops.
- The squeeze gate does not shift the random streams: plans at `gamesPlayed` 4 and 5 are equal except for the squeeze slots.
- No popup, card or sticker is mounted when a gate opens or at the first meet.
- `home_moments_test`: one popup per visit, in priority order (STREAK LOST first, GO TO COLLECT right after the streak reward); the missions chest and the Star Road popup never in one visit; the Star Road popup at most once a day.
- Autopilot ≥ 12 hoops at `gamesPlayed` 0 and 10, at 568 and 711.

**Analytics:** `first_meet` {element, hoop, games, survived} (silent; it measures deaths at the first saw / squeeze).

### WP-D In-run curve (one curve for every run) — must · L · 2.6

**Goal:** a fair, staggered climb to a hard but doable ceiling at hoop 150 (O1), then variety. The curve is the same in every run, showcase runs included (R2, R6).

**D1 Introduction schedule (in-run)** — one dimension at a time, at least 5 hoops apart. Saw (hoop 30) needs `gamesPlayed ≥ 3` and squeeze needs `gamesPlayed ≥ 5` (C1); every other row holds from run 1:

| Hoop | Introduced |
|---|---|
| 3 | Height variation |
| 10 | Tilt ≤ 15° |
| 15 | Switch |
| 20 | Δy step |
| 25 | Moving (slow rails) |
| 30 | Saw |
| 25–40 | Squeeze #1 (2.5 timing, O18). It can overlap the moving (25) / saw (30) introductions; the existing one-headline-per-8-hoops rule (D6) lets the squeeze warning wait up to 5 hoops, so introductions still never land together. |
| 40 | Δy step |
| 50 | 20–30° tilts (aligned) |
| 60 | 45° tilts |
| 65 | Δy step |
| 70 | Horizontal and diagonal slides |
| 80 | Slide speed step |
| 90 | Orbit and rock |
| 100 | Δy row + bigger 45° share; saw allowed in a squeeze |
| 150 | Ceiling; moving + 30° tilt; formations |

**D2 Keyframes** (all baked in `kTuningDefaults` / `LayoutConfig`; current → proposed)

| Key | Current | Proposed |
|---|---|---|
| `curve_speed` (:87) | [[0,150],[50,172.5],[150,187.5]] | **unchanged** (pinned, §1.4) |
| `curve_opening` (:89) | …[50,81],[60,76.5],[75,72],[100,66] | [[1,118],[2,118],[6,114],[10,110],[16,105.5],[20,102],[25,98],[30,95],[40,88.5],[50,83],[60,79],[75,75.5],[100,72.5],[125,71],[150,70]] |
| `point_perfect_band` (:59) | …[40,12.7],[50,11.6],[60,10.7],[75,10],[100,8] | Hoops 0–40 **unchanged** (2.5.0+46: [[1,40],[2,40],[6,36],[10,30],[16,24],[20,18],[25,14.5],[30,13.9],[35,13.2],[40,12.7]]; the 20→25 drop is kept by the owner), then [50,11.8],[60,11.2],[75,10.6],[100,10.2],[150,10]. Big Hoops growth ×1.5 unchanged. |
| `curve_tilt` (:99) | [[9,0],[10,.3],[19,.3],[20,.5],[34,.5],[35,.6],[44,.6],[45,.78]] | [[9,0],[10,.30],[49,.35],[50,.50],[100,.60],[150,.65]] |
| `tilt_rows` (new; replaces the signed `tiltWeights` in `layout_config.dart:19-67`) | Signed weights per band | Magnitudes: from 10 {10:6, 15:4}; from 50 {10:30, 15:30, 20:20, 30:20}; from 60 {10:20, 15:20, 20:15, 30:30, 45:15}; from 100 {10:15, 15:15, 20:15, 30:30, 45:25} |
| Tilt sign (`layout_sampler.dart:121-131`) | Fixed sign per weight entry, independent of the path | ≤ 15°: random sign (its own draw). ≥ `tilt_align_min_deg` (20°): the sign follows the approach (next hoop higher → negative, top leans left; lower → positive). If \|Δy\| < `tilt_align_min_dy` (40 pt): clamp to 15° |
| `tilt45_extra_opening` (new) | — | +6 pt on 45° rings |
| `curve_moving` (:91) | [[19,0],[20,.15],[35,.4],[60,.6],[80,.75]] | [[24,0],[25,.15],[34,.15],[35,.25],[60,.42],[100,.52],[150,.58]] |
| Moving + tilt (new) | Independent | A moving ring tilts ≤ 15° before hoop 150, and ≤ 30° (aligned) from 150 |
| Δy rows (`layout_config.dart:19-67`), as fractions of **dyRef = min(band, `dy_ref_band` 540 pt)**, centre as a fraction of the band | Rows 0/3/10/20/35/45; max .52 × band (324 pt on 711) | See "Δy rows" below. Max climb 270 pt (711) / 240 pt (568) |
| `dy_hard_factor` (new) | — | 0.85 × Δy max on the slot after a moving ring or a ≥ 30° tilt |
| Early pool (`director_tables.dart:416-425`) | starTrail / bullseye / **angled** / nothing, 1:1:1:1 | starTrail / bullseye / nothing, 1:1:1 |
| `spawn_switch` (:135) `from` / `ElementId.switchRing.firstPossible` | 7 / 12 | 15 / 15 |
| `spawn_saw` (:143) from / firstPossible / weight | 20 / 20 / 18, 26 from 45 | 30 / 30 / new `spawn_saw_weight` [[30,14],[60,20],[100,26]] (retire `weight_from_45`) |
| `ElementId.movingRing.firstPossible` | 20 | 25 |
| Saw during a squeeze | Allowed | From hoop 100 only |
| `spawn_special_chance` (:125) | [[0,0],[3,0],[4,.4],[15,.5],[30,.6],[50,.7]] | Unchanged (the hazard budget limits the hard share) |

**Δy rows:**

| From hoop | Δy (median, p90, max) × dyRef | Centre range (× band) |
|---|---|---|
| 0 | (.03, .06, .07) | (.45, .55) |
| 3 | (.11, .27, .35) | (.33, .67) |
| 20 | (.12, .31, .38) | (.27, .70) |
| 40 | (.14, .33, .42) | (.24, .73) |
| 65 | (.15, .35, .46) | (.20, .76) |
| 100 | (.15, .37, .50) | (.16, .78) |

**Motion rows** (replace `movingTypes20` / `movingTypes45` / `allMotionTypesFrom` in `layout_config.dart:84-104`):

| Hoops | Types (weights) | Speed |
|---|---|---|
| 25–34 | rail 100 | 22–28 pt/s, ±30–45 pt |
| 35–69 | rail 75, swing 25 | 26–34 pt/s |
| 70–89 | rail 55, swing 15, horizontal 15, diagonal 15 | 30–39 pt/s |
| 90+ | rail 45, swing 15, horizontal 10, diagonal 10, orbit 10, rock 10 | 30–39 pt/s; 34–42 from 120 (cap) |

**At the ceiling (hoop 150+):**
- 187.5 pt/s (1.65 s per gap);
- opening 70 (clean window 40.5 pt);
- band ±10;
- tilt 65 % (45° = 25 % of tilts, aligned, +6 pt);
- moving 58 % (≤ 42 pt/s);
- Δy ≤ 270 pt (sustained climb about 225 pt/s ≈ 4.5 taps/s);
- a squeeze every 25–45 hoops (2.5 timing, O18);
- a calm stretch at least every 55 hoops;
- hazard budget 5.5 per 4 slots.

Physics: curves §3.4. Every element passes at ≤ 4.5 taps/s with a clean window ≥ 20 pt on the natural path.

**D3 Hazard budget** (should→**must in 2.6**, M)
- **Cost per slot:**

  | Element | Cost |
  |---|---|
  | Saw | 2 |
  | Switch | 1.5 |
  | Spring, pair, train | 0.5 |
  | Tilt 10–20° | 0.25 |
  | Tilt 30° | 1 |
  | Tilt 45° | 1.5 |
  | Rail / swing | 1 |
  | Horizontal / diagonal / orbit / rock | 1.25 |
  | Δy above the row's p90 | +1 |
  | Slot inside a squeeze | +1 |
  | Bullseye, FEVER, spin, comet, portal, ride slots | 0 |

- **Budget:** the sum over the last 4 slots (current included) may not exceed `hazard_budget` [[0,0],[3,0.5],[10,2],[25,3],[50,4],[100,5],[150,5.5]].
- **Downgrade order:** drop motion → tilt to ≤ 15° → Δy to p90 → special to a normal hoop.
- Forced slots (first-meet, debug, scripted) are exempt but count in the window.
- `SlotPlan.hazardCost` is new.

**D4 Calm stretches** (must, M)
- **A calm slot** is a normal hoop: no motion, tilt ≤ 10°, Δy ≤ the row median, opening on the curve (the band is unchanged).
- Gap items and fun pickups are preferred in calm gaps.
- **Triggers:**
  - after a revive: 3 slots (replaces today's single plain slot, `run_director.dart:555`);
  - after a squeeze ends: 2;
  - after a ride ends: 2;
  - periodic: 3, first at hoop 30–34, interval × 1.2 each time, capped at 55 (≈ hoops 32, 68, 111, 163, 218 …).
- **Spacing:**
  - Calm stretches are at least 12 hoops apart; a revive calm always happens.
  - Any calm stretch or ride resets the periodic timer.
  - A squeeze warning never starts inside a calm stretch.

**D5 Squeeze schedule** (owner O18, 2026-10-21: **timing unchanged from 2.5**)

| Key | Current | 2.6 |
|---|---|---|
| `squeeze_first` (:101) | [25, 40] | **unchanged** [25, 40] |
| `squeeze_hold` (:103) | [5, 10] | **unchanged** [5, 10] |
| `squeeze_gap` (:105) | [25, 45], constant | **unchanged** [25, 45] |
| Tilt during a squeeze | Any | ≤ 15° before hoop 150 |

- Depth is unchanged (50 / 45 / 40 / 35 %, ≥ 230 pt open), with no motion inside.
- A revive keeps the squeeze index.
- The squeeze index is passed in `squeeze.dart:111, 213, 331` and in `revive_rules.dart:69`.

**D6 Headline window** (should, S): within any 8 hoops, at most one of:
- a ride start;
- a squeeze warning;
- a big bonus;
- a first meet;
- an in-run introduction step (D1).

A due item waits up to 5 hoops.

**D7 After the ceiling** (should, M–L for all 6 formations, all in 2.6 per O20)
- **Formations:** one every 12–20 hoops from hoop 150, never one of the last 2, all within the budget, and ≥ 310 pt between hoop planes.
- All six ship in 2.6:
  1. **Stairs:** 4 hoops, +70–90 pt each in one direction, aligned 15° tilts.
  2. **Slalom:** 4 upright hoops alternating ±110–130 pt.
  3. **Tilt wave:** −30 / −15 / 0 / +15 / +30°, aligned by construction.
  4. **Sync rails:** 3–4 moving rings on rails in phase, so one line passes all.
  5. **Saw gate:** a saw ring between two upright hoops, the clean line through the middle.
  6. **Switch chain:** 3 switch rings in a row, alternating sides.
  (EDITOR: shapes 4–6 are first drafts of the run-20 names; they are tuned with the human-noise bot within the hazard budget.)
- **Mix chapters:** every 50 hoops past 150, the hard-special weights rotate (saw-heavy → switch-heavy → moving-heavy) at equal budget.

**Files:**

| File | Change |
|---|---|
| `lib/run/config/tuning_defaults.dart` | Edit and add per the Appendix |
| `lib/run/config/layout_config.dart` | Δy rows, `tilt_rows`, motion rows, `dyRefBand`, `hardHoopDyFactor` |
| `lib/run/config/director_tables.dart` | Weight curve in `SpecialRule`, early pool, saw-in-squeeze ≥ 100 |
| `test/fixtures/spawn_tables.json` | Updated with the tables |
| `lib/run/director/layout_sampler.dart` | Δy × min(band, dyRef); clamp after a hard hoop; tilt magnitude then sign rule; motion rows and the tilt clamp |
| `lib/run/director/run_director.dart` | Hazard ledger and `_downgrade`; calm state; `onSqueezeEnded` / `onRevive`; 45° allowance; headline window; squeeze index; the squeeze gate (WP-C) |
| New `lib/run/director/formations.dart` | Formations |
| `lib/run/director/plans.dart` | `SlotPlan.calm`, `.hazardCost`, `.formation` |
| `lib/run/items/squeeze.dart`, `lib/run/screens/revive_rules.dart` | Squeeze index |
| `lib/run/elements.dart` | `firstPossible` changes |
| `docs/gameplay-v2/ARCH.md`, `SPEC.md` | DEVIATION notes |

**Tests:**
- **New `test/run/director/curve_ceiling_test.dart`** (200 seeds × 568 / 711 / 730 × 400 slots, with and without squeeze):
  - Δy ≤ 270 pt;
  - every tilt ≥ 20° is aligned, with \|Δy\| ≥ 40;
  - the 45° allowance is applied;
  - no moving ring tilts more than 15° before 150;
  - the rolling hazard cost stays within the budget (forced slots excepted);
  - calm stretches on schedule (±4 hoops) and ≥ 12 apart;
  - no element before its introduction hoop;
  - the straight-path clean window is ≥ 15 pt level and ≥ 35 pt at aligned slope ±0.5;
  - determinism holds with downgrades.
- **Fairness test** (`same_rules_test`, R2): with a non-showcase, non-debug setup, plans are identical for the same seed across `gamesPlayed` ∈ {6, 500}, bestScore, level (0 / 31 / 36), Free Fly vs VERSUS, No-Ads and arm (with the same `metElements`), and Δy in points is identical at 711 and 730 when the band is ≥ 540.
- **`autopilot_test.dart`:** add a ceiling gate. `startHoopIndex` 150 and 250, ≥ 40 hoops at 568 and 711, 3 seeds. The human-noise bot reaches a median ≥ 40 hoops from hoop 0 at `gamesPlayed` 10 (the "after 10 games ≈ 40" proxy).
- **Update:**
  - `test/p24/s1_hoop_curve_test.dart`
  - `test/p23/s14_perfect_band_test.dart`
  - `s3_0_2_layout_ramp_test.dart`
  - `tables_mirror_test.dart`
  - `s3_17_squeeze_test.dart`
  - `audit17/baked_tuning_test.dart`
  - `p231/s0_live_tuning_defaults_test.dart`
- **`leaderboard_max_test.dart`** passes **unedited**.

**Analytics:** the `run_fail` fields (tilt, motion, Δy, hazard, calm, formation); `run_extra.downgraded`.

### WP-E Versus, leaderboard and matching — must · M · 2.6 (staircase + jump flag: should · M · 2.6)

**E1 What counts (unchanged from 2.5; O4–O6).**
- Every finished run that is not a debug run (`_debugTouched`, a debug force, FS_TESTER god mode / bot) is a normal run: showcase runs, Free Fly, versus, runs with ad or coin revives.
- **Versus uploads:** the 2.5 rules in `upload_queue.dart:79-87` (the first 3 a day + new bests, score ≥ 3), from both modes as today (`flappy_game.dart:4107-4108`).
- **Leaderboard:** `services.submitBestScore(storage.bestScore)` as today (`flappy_game.dart:4106`). No `rankedBest`, no board reset. **Plus** every such run goes to our own board (WP-LB, O55); the platform submit stays unchanged (it runs in the background; there is no visible entry to the native boards any more, O64; achievement unlocks are reported as today).
- **Revives in versus:** the 2.5 ladder (ad, then coins) stays (O5). No-Ads owners keep the free home slot, as today.

**E2 Rule-set marker:** the `fl` version byte **stays 2** in 2.6 (R1).
- Client `lib/versus/timeline.dart:56` and server `functions/src/timeline.ts:61` are unchanged.
- From the public launch on, every change to the curve, gates or points per hoop bumps the byte (then the server accepts {old, new} while old builds are in use). Batch such changes per release.

**E3 Versus from the start:** VERSUS is available on the first launch and stays the default `homeMode` (`storage.dart:157`, unchanged). With an empty pool: solo, with the honest line "No rival yet – your run can become a rival for others" (owner wording, O31; not every run is uploaded, and the game does not say "ghost"). No fake or bot ghosts presented as players.

**E4 Matching on best-score brackets (R3)**
- **Today:** the server files each accepted run into pool `{levelFor(best)}_{shard}` (`functions/src/pools.ts:136-138`; `levelFor` and `LEVEL_THRESHOLDS` in `functions/src/levels.ts`). The client searches its own bracket first (`versus_service.dart:947` → `poolSearchOrder`, `matcher.dart:132`) and picks "same level and score < my best" (`matcher.dart:71-75`, `functions/src/matching.ts:56`). The thresholds live in the *level* table `kLevels` (`lib/levels/levels.dart`), and `functions/test/levels.test.ts` parses that table. The stored player level (`playerLevel`) is already *not* used for matching (`versus_service.dart:908`).
- **2.6 change: decouple only; the numbers stay.**

  | Place | Change |
  |---|---|
  | New `lib/versus/brackets.dart` | `const kBestBrackets = [25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000]`, `int bracketFor(int best)` (0–10). It replaces `levelFor` for every versus use. |
  | `lib/levels/levels.dart` | `levelFor` is removed (levels are WP-J's 31 time-played levels). |
  | `lib/services/versus_service.dart:916, :947` | `myLevel: levelFor(best)` → `myBracket: bracketFor(best)`; `poolSearchOrder(bracketFor(storage.bestScore))`. |
  | `lib/versus/matcher.dart` | `MatchTier.level` → `MatchTier.bracket`; `myLevel` → `myBracket`; `e.level` reads the pool entry's `level` field, which **keeps its stored name** and now means bracket. |
  | `lib/run/config/versus_config.dart:53, :106` | `maxLevel` → `maxBracket` (10); `maxSearchReads` stays 44. |
  | `lib/versus/run_entry.dart:236` | Opponent emblem: `level: entry.plv ?? 0` instead of `levelFor(run.best)` (R4). |
  | `functions/src/levels.ts` → `functions/src/brackets.ts` | `BEST_BRACKETS`, `bracketFor`, same numbers. |
  | `functions/src/pools.ts:136-138, :216, :243` | `bracketFor(playerBest)`; each new pool entry also gets `plv` = clamp(player doc `level`, 0, 9999) (R4). Pool doc ids and the `level` field names are unchanged, so every existing entry stays in the right pool. |
  | `functions/src/schema.ts:7-8` | `MAX_LEVEL` → `MAX_BRACKET` (10); `PoolEntry.plv?: number`. |
  | `functions/src/matching.ts` | `level` → `bracket` in the reference matcher (same logic). |
  | `functions/test/levels.test.ts` → `brackets.test.ts` | Parses `kBestBrackets` in `lib/versus/brackets.dart` (not `kLevels`); the same boundary cases. |
  | `firestore.rules:117` | `isInt(d.level, 0, 10)` → `isInt(d.level, 0, 9999)`. The player doc's `level` is the WP-J level; 2.5 clients write 0–10 and stay valid. |
  | `test/fixtures/versus_matching.json` | Field renamed in the fixture only; the same cases plus a "level 25 player with best 80 → bracket 2" case. |

- The level never feeds matching.
- This needs a **functions + rules deploy** (approved, Q3). It is backward compatible: 2.5 clients compute the same bracket numbers.

**E5 Duel staircase** (should, M, 2.6)
- `duelStep` starts at −2 and is clamped to [−4, +8]: +1 on a win, −2 on a loss, unchanged on a draw. It settles at about 67 % wins.
- Target T = clamp(0.8 + 0.1·duelStep, 0.4, 1.6) × median(`recentScores`), where `recentScores` (new, must because E5 needs it) holds the last 10 non-debug scores.
- Pick within the found pool doc (the own best-score bracket first, E4): fresh run in [0.75T, 1.25T] → else the closest fresh run → else a rematch → else solo.
- Mirror it in `matching.ts` with shared fixtures.
- Analytics: `versus_result` + tier, duel_step, ratio_x100, first.

**E6 Server checks**
- New `functions/test/curves.test.ts`. It parses `tuning_defaults.dart` and asserts:
  - `PASS_MAX_SPEED` == the top of `curve_speed`;
  - `PASS_SPACING` == `RunConfig.spacing`;
  - `PACE_MIN_MEDIAN_CS` ≤ 0.8 × 310 / 187.5 × 100.
- **(should, 2.6; functions deploy wave 0)** Soft `jump` flag based on passes, not points: flag when passes ≥ 150 and passes > 4 × the median of at least 5 earlier pass counts. Needs an optional server-only `versusRate.passHist`. The uncapped streak makes points jump on honest progress.

**Storage (new):** `duelStep`, `recentScores`.

**Tests:**
- `upload_rules_test`: showcase, Free Fly and revive runs upload under the 2.5 rules; debug runs never.
- `matcher_bracket_test` (shared fixture): matching ignores the level; bracket = `bracketFor(best)`.
- Opponent emblem from `plv`; missing `plv` → UNRANKED.
- Timeline: `fl` 2 unchanged (the existing encode/decode tests stay green).
- `functions`: `brackets.test.ts`, `pools.test.ts` (entry gets `plv`; pool id from the bracket), rules test (`level` 9999 accepted, 10000 rejected), `curves.test.ts`.
- `matcher_duel_test`, `anomaly.test.ts` (honest 20 → 60 → 140 hoops is not flagged).

### WP-F Economy — should · M · 2.6

Unchanged by owner decision: point sources (O13), revive ladder incl. versus coin revives (O5), ad timing `ads_grace_runs` 5 / `ads_grace_seconds` 300 (either ends the grace) / `ads_interstitial_min_gap_s` 60 (O2), banner placement, the "MOST POPULAR" badge (O14). F1, F2, F4 and F8 of the run-20 draft are removed, and so is F3 (No-Ads revive): the revive stays exactly as in 2.5 (O24).

**F5 Budget test** (must, S)
- New `test/economy_budget_test.dart`: 3 bot profiles × 20 seeds × 568 / 711.
- It asserts 1.4–2.1 coins per hoop, ≤ 80 coins per run-minute, ≤ 0.35 non-hoop coins per hoop, and showcase runs 1–3 paying 90–200 play coins in total.
- **Level rewards** (WP-J) are counted separately: it reports level coins / play coins over the medium bot's first 50 runs and asserts level coins ≤ play coins in that window. That is an EDITOR guard; levels pay most in the early runs by design.

**F6 Shop / Skins unlock** (should, S; R8)
- `ui_unlock_best` 25 stays; add `ui_unlock_games` = 3.
- `Config.menuUnlockBest` becomes `menuUnlocked(best, games, level)` = best ≥ 25 ∨ games ≥ 3 ∨ level ≥ 1 (`menu_state.dart:43`).
- It opens as in 2.5, with no extra unlock animation (O16).

**F7 Lifetime counters** (must, S)
- `lifetimeCoinsEarned`, `lifetimeCoinsSpent`, `lifetimeCoinsBought` in `lib/menu/wallet.dart`.
- Events: `item_bought`, `first_item_bought` {key, rarity, price, balance_before, games, minutes}, and the daily `economy_daily`.

**F11 Coin budget** (statement, replaces the old rank-reward budget)
- The 10 rank rewards (`level_rewards` 25 … 5000 = **10,175 coins**) are retired.
- Levels pay **18,800 coins + 31 items** (shop value ≈ 32,750: 13 common, 10 rare, 6 epic, 2 legendary) over 74,725 cumulative points, plus 2,500 coins + 1 item per ETERNAL WING level (32+, 10,000 points each).
- Level 1–5 pay 250 coins + 5 commons, so the first equip happens in run 1–2 without a purchase.
- Meta per day (D8) stays about 180 coins and does not include levels.

**F9 Versus-card cosmetics** (should, M, 2.6; design, art and names: `design/approvals_v26/versus_cards.html`, §7 D9 / T10; O38)
- Frame, name style and victory sticker: **51 items, 17 per kind**, each kind split like a shop layer: **6 × 250 (COMMON), 5 × 750 (RARE), 4 × 2,000 (EPIC), 2 × 5,000 (LEGENDARY)** — the standard `Rarity` prices, nothing above 5,000 (the 24 items approved earlier are repriced 500→250, 1,500→750, 4,000→2,000, 10,000→5,000). Fixed coin price, no boxes, no IAP. Plus ~~3 skill-only frames~~ **9 skill-only items (F10): 3 frames, 3 name styles, 3 victory stickers** (O80).
- New `SkinLayer.card`; **one** optional field `look.card` in `schema.ts` `Look` / `validLook`: a string `"<frame>|<name>|<sticker>"` (each slot an item id or empty, e.g. `"f_orbit|n_fire|s_fireworks"`, `"|n_ocean|"`), max 48 chars. `validLook` / `firestore.rules`: exactly 2 `|`, each non-empty slot in the allow-list for its kind (the frame slot also accepts the skill frames `pecking`, `roost`, `prey`; the name slot also `n_sky`, `n_thunder`, `n_marquee`; the sticker slot also `s_unstop`, `s_flawless`, `s_topflock`, O80). Ownership is client-side, as for all looks. Versus-card cosmetics are never level, Star Road or album rewards (O21, O36).
- Display: VS intro card = frame + name style + the equipped sticker drawn small (≈ 42 %, tilted) on the bottom edge of **both** cards. Versus bar (run HUD): frame round the 38 pt avatar + name style on the name plate; **animated name styles animate there too**; no sticker in the run. Results: the winner's sticker slaps on (unchanged). Frames that reach up to 7 pt past the avatar box are drawn under the score box (approved, O82).
- Shop: CARDS is the 6th tab with a FRAMES / NAMES / STICKERS row (~~"x/17" each, tab counter x/54 incl. the 3 skill frames~~ **"x/20" each = 17 sold + 3 skill, tab counter x/60**, O80). Each kind ends with "EARNED BY SKILL · NOT SOLD" and its 3 gold skill tiles. Tile sub-label "NAME STYLE".
- **Fixed shop header (O79, every tab):** back, coins, collection bar, stage, the category tab row and (CARDS) the FRAMES / NAMES / STICKERS row never scroll; only the tile grid scrolls, in its own clipped scroll view (`lib/components/skins/…`), with a ≈ 5 pt shadow under the fixed rows while scrolled and a thin scroll indicator. Sounds: buy `sk_buy_<rarity>`, equip `sk_equip` (existing).
- Build: everything is vector — frames / stickers `CustomPainter`, name styles `TextPainter` (+ `ShaderMask` for the gradient styles, per-glyph offset for Flappy); animations run off the game clock so they freeze with the run.

**F10 Skill-only cosmetics** (should, M, 2.6; design and art: `design/approvals_v26/skill_cosmetics.html`, frames in `versus_cards.html`; §7 D10 / T10; O39)
- ~~**18 items, 3 per kind**~~ **24 items** (O80: 3 per shop kind + 9 versus-card items), each unlocked by one achievement (`SkinItem.unlock: AchievementId?`), never sold, never a level, Star Road or album reward (excluded from those draws):
  - hoops: `spikes` · SPIKE ACE; `phoenixring` · PHOENIX; `legend` · LEGEND
  - trails: `thread` (Golden Thread) · **BULLSEYE** (new); `constellation` · SEEING STARS; `fireflies` (Firefly Swarm) · NIGHT OWL
  - hats: `skycrown` (Sky Crown) · **SKY HIGH** (new); `nest` (Nest Hat) · MOTHER HEN; `jackpot` · GOLDEN EGG
  - birds: `magpie` · MAGPIE; `prism` · FLYING COLORS; `daynight` (Day & Night) · HOMING PIGEON
  - gear: `goggles` (Flight Goggles) · FREQUENT FLYER; `hoopchain` (Hoop Necklace) · RING-NECKED; `peacock` (Peacock Fan) · PROUD PEACOCK
  - versus-card frames: `pecking` (Pecking Order) · PECKING ORDER; `roost` (Roost Ruler) · RULES THE ROOST; `prey` (Bird of Prey) · **BIRD OF PREY** (new, approved O82)
  - versus-card name styles (round 23, O80): `n_sky` (Skywriter) · **SECOND WIND**; `n_thunder` (Thunderstruck) · **ALBATROSS**; `n_marquee` (Headliner) · **THREE LITTLE BIRDS**
  - versus-card victory stickers (round 23, O80): `s_unstop` (Unstoppable) · **IRON BEAK**; `s_flawless` (Flawless) · **FLAWLESS**; `s_topflock` (Top of the Flock) · **TOP BIRD**
  - The six round-23 achievements are **approved** (J9, Q30 → O83); all six are visible in the consoles, but in the shop their items are secret (O85).
- Shown in **LEGENDARY gold** (rarity colour, chip "LEGENDARY", gold pill with plum text) with a trophy mark ("earned, not bought"). The reveal is the approved style A box in gold with a plum ribbon and the legendary extra ring; sound `lv_up_big`.
- ~~Locked tile shows the goal where the price would be; for console-hidden achievements it shows **"? ? ?"** and "UNLOCK: ? A SECRET ACHIEVEMENT ?" until earned (no progress bar).~~ **Round 25 (O88): every locked skill tile, in every tab, shows "? ? ?"** and "UNLOCK: ? A SECRET ACHIEVEMENT ?" until earned (no goal, no progress bar). Console visibility is unchanged: Hidden: the masteries, MAGPIE, rides, vs_10, vs_50, skin_all, daily_30 and BIRD OF PREY. **All 9 skill card items** (frames, name styles, stickers) are shown secret in the shop whatever their console visibility (O85); ~~the other 18 follow the console visibility unless Q32 says otherwise~~ the other 15 too (Q32 → O88).
- ~~On the first launch of 2.6, items for achievements already earned are granted **silently** (no reveal, no popup, O16).~~ **A skill item is owned when its achievement is earned** (derived from the achievement state): no grant step, no 2.5 returning-player path, no "Returning player" shop state (O81; there are no 2.5 players).
- **Locked skill tile tap (O80):** tries the item on and slides up the **HOW TO EARN** sheet: the item on gold rays, "LEGENDARY · SKILL ONLY · NEVER SOLD", ~~the condition (2 lines), best so far, achievement + points,~~ GOT IT (any tap closes); the stage strip ~~"SKILL ONLY · <goal> · HOW TO EARN ›"~~ "SKILL ONLY · SECRET · HOW TO EARN ›" reopens it (round 25, O88: every skill item uses the secret form below). Secret achievements show "? ? ?" there too. The 3 skill frames use the same sheet. **Skill card items (O85) and, since round 25, every skill item (O88):** always the secret form — "SKILL ONLY · SECRET", "? A SECRET ACHIEVEMENT ? / Keep racing to find out.", "ACHIEVEMENT: ? ? ?", no condition, best so far or points.
- Skill items count in the shop's "x / total" collection bar and in every tab counter (+3 per shop tab, +9 on CARDS).
- If one run gives a level item and a skill item, the level reveal plays first, then the skill reveal.
- PROUD PEACOCK (own every shop item) ignores skill items (they cannot be bought) but **counts every sold item, the 51 versus-card items included** (O81; about +75,000 coins on that goal). Its console description stays "Own every item in the shop."
- Build: all vector and animated off the game clock (`CustomPainter`); Day & Night and Prism need a per-frame body colour; Jackpot clips its reels.

**Never:** a random box that is sold (for money, coins or an ad), paid in-run boosts, an end-of-run ×2 ad. Free random boxes (level reveal, BONUS CHEST, leaderboard gift boxes) are allowed; they are never sold (O58). Their odds are not shown to players (O61).

**F12 Leaderboard gift boxes** (WP-LB, O54, O65): bronze 25–100, silver 50–200, gold 50 % 100–300 coins / 20 % feather / 20 % piece / 10 % unowned common-or-rare item ≤ 750. `CoinSource.leaderboardGift`. They count as **meta** in the economy budget test. **Round 23 (O65): only board places 1–3 win**, so a group gives **0–3 boxes** (a ghost on a podium place takes that box away from everyone); the gift budget per group is lower than in round 22 and the box contents are unchanged. ~~At small scale nearly every active player can win a box most days~~ — at small scale a real player wins only by beating the ghosts to the podium (§6). The test keeps the "meta incl. gift boxes ≤ 25 %" case as the upper bound (worst case: a real player on place 1 every day), and the gift ranges stay baked server constants that a functions deploy can change. The streak restore for No-Ads owners is a coin **spend** (`CoinSource.streakRestore`, 500).

**Tests:**
- `economy_budget_test`
- `shop_unlock_test` (best, games, level paths)
- `wallet_counters_test`
- `audit17/baked_tuning_test.dart`: the ad keys are unchanged.

### WP-G Retention and long-term goals — should · L · 2.6 (O20; designs and texts: §7)

**G1 Daily missions** (M)
- **Unlock:** from game 4 (after the showcase runs 1–3, so the first runs stay clean; O28).
- **Missions:** 3 a day (easy / medium / hard), reset at local midnight, refreshed only when `today > missionDay` (rolling the clock back does nothing).
- **Rewards:** **20 / 35 / 55** coins; all done → the **BONUS CHEST** (name confirmed, O83): a feather if ≤ 1 held, else a piece if ≤ 2 held, else **40** coins (confirmed). Mission coins are claimed automatically at run end; the chest opens on the **next Home visit** as that visit's one big popup (C2), never on the results page. Art: the approved mystery-box master in gold. Opening: the lid flies open and the rays master (12 rays, a bit longer, ending in a transparent radial gradient, turning ≈ 18°/s, behind the box) fades in with small confetti and a sparkle ring; sound `Sfx.pairBoxOpen` (lid) + `Sfx.bnPrizeM` (reveal) (O41). **(Round 13: the ray look here is replaced by O98 — reuse an existing in-game ray as it is; the box is the O99 master.)**
- **Template rules (O32):** M15 "reach a world" targets SKY & HILLS (hoop 20) for T1, CITY SKYLINE (40) for T2, GIANT'S DESK (80) for T3, not offered at T0 (same scale as M11). M05 power-ups = capsules (Hourglass, Mini Bird, Coin Frenzy), shield pickups, comet stars and gift-pair gifts; hearts, armed Big Hoops and streak-gift starts do not count. M10 (win versus races) is offered only when the player is online **and** their last versus run found a rival; otherwise another medium mission is rolled.
- **Tiers** by `bestHoops` (new, must because G1 and G5 need it: best hoops passed in any non-debug run): T0 < 15, T1 15–39, T2 40–99, T3 ≥ 100, fixed at the day's first roll.
- **Templates and targets (T0/T1/T2/T3):** use progression §3.3. Missions use only met elements; no template twice a day; not yesterday's hard mission. **At most one mode-only mission a day** (e.g. "Win 2 versus races"); every other mission can be completed in any mode (O28).
- **What counts (owner O28): every game you play adds to the missions** — VERSUS runs (with or without an opponent), FREE FLY runs and WEEKLY COURSE runs alike, once missions are unlocked. A run with a revive (ad or coins) counts **fully** (before and after the revive). Only debug runs count nothing.
- **UI** (approved design `design/approvals_v26/missions.html`): a MISSIONS strip under START (kept on 568-pt screens; the emblem shrinks by the tight-gap rule), pips on results, and a panel with "NEW IN 5 H 12 M". The panel has **no explanation lines** (no swap hint, no "swap used" line, no chest-contents line); the chest row reads only ~~"ALL 3 DONE → BONUS CHEST"~~ **"ALL 3 DONE"** with the gold chest icon, centred (O71). **Mission rows show no EASY / MEDIUM / HARD label** (O71): the difficulty stays internal and still sets the coins (and the Star Road stars); rows are 54 pt in the panel. The weekly-course card sits at the top (G5) and the Star Road card is part of the panel (G6).
- **Reroll** (should): one a day via a rewarded ad, for **any unfinished mission**; after use every SWAP button is hidden until tomorrow.

**G2 Visible day streak** (S; design `design/approvals_v26/day_streak.html`; O33 without its freeze parts, O46–O49)
- 1 finished run per local day keeps it. A missed day breaks it. **No freezes** (O46): no `streakFreeze`, no FREEZE k/2, no ice chip, no freeze pill.
- Rewards: 20, 30, free Big Hoops, 40, free Shield, 50, feather (or piece or 50) + 60. That is 200 coins and 2 free starts a week.
- **Chip:** a **drawn flame + n** (no emoji in the game UI; notifications keep 🔥), right-aligned under the coin pill. Lit flame: a subtle flicker (three layers on 1.2 / 0.9 / 0.6 s sway loops plus two tiny embers, ≤ 1 pt of movement). Not flown today: a grey, still flame on a paler chip. A gold dot when a reward waits. Reduced motion turns all motion off.
- **Card** (tap the chip): 7 tiles labelled **1–7**; the bottom line is only "ENDS AT MIDNIGHT" / "NEXT REWARD TOMORROW".
- The reward is the streak popup on Home (C2) and is paid on **COLLECT** (nothing paid unseen). Day 7 = feather (else a piece, else 50) + 60. Free Big Hoops / Shield are **kept until the next run**, whatever day that is.
- Free Big Hoops / Shield reward moment (O41): after COLLECT the icon arcs into its button under START (≈ 0.6 s, a whoosh); on landing the button pops (1.14×, 0.32 s) with a white flash, a small confetti puff (~22 pieces) and a sound (`Sfx.skHoop` for Big Hoops, `Sfx.puShieldGet` for Shield), and the FREE tag stamps in.
- **STREAK LOST popup** (O47–O49; design `day_streak.html` §4, P1 frame):
  - **Trigger:** `today > streakLastDay + 1` with an old streak ~~n ≥ 2 (Q17)~~ **n ≥ 1 — every lost streak, 1 day included (O72)** → `streakLostDays` = n. Shown on the first Home visit after the break, **top of the C2 order**, never in runs 1–3. Same popup and no extra text for a 1-day streak; S-28 / S-29 / S-30 have singular forms ("1 day of day streak interrupted!", "… restore it").
  - **Content:** n with a lit flame → 0 with a grey flame (pulsing arrows), S-28 "{n} days of day streak interrupted!", line 2 (S-29 video / S-30 coins), **RESTORE** and **GIVE UP**, ×.
  - **Payment:** players without No-Ads: a rewarded video, `AdPlacement.streakRestore` (`'streak_restore'`, `ads_service.dart:15-31`), the existing AdMob rewarded unit on Android and iOS, only after UMP `canRequestAds` (+ ATT on iOS) as today. **No-Ads owners never see the video:** RESTORE · 500 (`streak_restore_coins`, a spend, `CoinSource.streakRestore`); under 500 coins the button is grey and inactive with S-37 "You have {c} coins."
  - **No video** (offline / no fill / not completed): LOADING VIDEO with a spinner for ≈ 8 s, then TRY AGAIN ▶ and S-36. The streak is never lost because an ad did not load.
  - **Pending across days (O49):** the offer stays until RESTORE or GIVE UP. The popup returns on the first Home visit of each day (`streakLostSeenDay`); × = again on the next Home visit. Runs flown meanwhile count normally: they build a new streak k from 1 and pay their track rewards as usual.
  - **RESTORE:** `streakDays` = n + k (the in-between days included), `streakLastDay` = max(`streakLastDay`, yesterday), so today's run (if not flown yet) continues it with that day's normal reward. No limit on how often. ~~A second break while an offer is pending: one offer for the bigger total (Q18).~~
  - **Only the last streak (O73):** the offer holds the streak as it stood when it broke (the chip's count on the last day with a finished run, restored days included). Each new break makes a new offer that **replaces** any open one (`streakLostDays` is overwritten); a given-up or unrestored older streak never comes back. Examples (`day_streak.html` §4b): A — 13 given up, then a 2-day streak breaks → offer **2**; B — the 13 offer left open (×), 2 days flown, then a miss → the 2 offer replaces it → offer **2**; C — 13 restored, 2 more days flown, then a miss → offer **15**.
  - **GIVE UP:** the offer is cleared; the streak stays k (0 when nothing was flown since; chip grey 0 until the next run, O74).
  - **Moments:** RESTORE — the grey flame relights from the bottom on slowly turning gold rays behind it (O41 rays master), the count runs 0 → n, a pop (1.28×), a small confetti puff (~24 pieces), `Sfx.rvIgnite`, title S-38 STREAK RESTORED!, card closes after ≈ 1.15 s and the chip pops. No-Ads: the coins fly from the pill into the button first. GIVE UP — the lit flame drains to grey with `Sfx.skClose` (or no sound).
- `achDayStreak` stays as it is for `daily_7` / `daily_30`.

**G3 Notifications** (S)
- Texts that react to the player's state, chosen at scheduling time and used only when true. Priority:
  1. streak at risk (evening)
  2. missions left
  3. new missions
  4. 2 feathers held
  5. 3 pieces held
  6. weekly course ending (< 24 h before **Monday 00:00 UTC**, O30)
  7. level almost reached (N7, kept by the owner, O42: points still needed ≤ the player's average run score)
- No Star Road notification (N8 dropped, O42). Exact texts: `design/approvals_v26/texts.html` §3.
- Decay: 2 a day on days 1–3 after the last run, 1 a day on days 4–7, none after.

**G4 Worlds map** (M; approved design `design/approvals_v26/worlds_map.html` inside `levels_tabs.html`)
- The 10 background scenes become worlds (one per 20 hoops; SPACE at 180).
- **The WORLDS tab of the Levels screen** (O29; `lib/components/levels/tabs/worlds_tab.dart`, no `worlds_screen.dart`). **No WORLDS tile on Home.** The Levels screen gets 4 tabs **LEVELS · WORLDS · GUIDE · ALBUM** ~~in the empty top row right of the back button (x 60–306, y 54–92, 4 × 58.5 pt, 15 pt icon over an 8.6 pt Opificio label; active tab pink with a darker bottom edge)~~ **under the screen title, text only, no icons (O69):** 4 flat blocks of 70 × 28 pt with a 4 pt gap at x 14–306, y 134–162, in the board's TODAY / BEST RUN tab style — the open tab solid pink #EC008C with white Opificio 11 pt text, the others soft pink #FCD9EE with pink text; the gold tab dot sits on the tab's top-right corner. The top row holds only the back button. It always opens on LEVELS, which is the approved levels screen unchanged; the title above the bar names the tab (LEVELS / WORLDS / FLIGHT GUIDE / PUZZLE ALBUM); every tab uses the same header box, moved down 32 pt (14,172 · 292×84), and list area (from y 264; on a 320 × 568 phone the list is 304 pt, about 3½ rows). Back always returns to Home; the open tab is not remembered. Tab tap sound `Sfx.skTab`.
- **No in-run sticker** or moment when a world is reached (O22). A newly reached world sets a **gold dot on the WORLDS tab** until it is opened; it then colours in with a small burst + `Sfx.lvUp`. No NEW stickers in runs, no popups.
- **Home NEW tag (O70; rules approved, Q26 → O83):** while any Levels tab dot is pending (`worldsReached > worldsSeen` or the met count > `guideSeenCount`), the Home level emblem (tap → Levels) shows the existing gold `MenuTag("NEW")` (flat gold, white Opificio 11 pt, `LiveCurves.newTagWobble`, as on the Skins tile) on its top-right corner. It clears when the Levels screen is opened; the tab dots inside stay until each tab is opened. Never after runs 1–3; while the emblem has a LEVEL UP to claim, the claim wins and the tag waits. Storage: one bool `homeLevelsTag`, set at run end when a new dot appears and cleared on opening Levels (Q26). This is an explicit owner exception to "no NEW! stickers", which still holds for unlock cards and in-run stickers.
- **Order (O87):** world 1 NEST CANOPY at the top, counting down to 10 SPACE at the bottom ("START · HOOP 0" above world 1); the tab opens scrolled to the player's furthest world. ~~SPACE at the top, the way the run climbs~~ (replaced, round 24).
- Cards (O34): reached = picture + name + ✓; next = name + a small bar ("57 / 60"); locked = **grey picture + grey number + lock only** (no name, no "HOOP n" text, no reward tag) until the world is next. Each world has its **own menu palette** (not the run colour stage). Header: "WORLD 4 / 10 · BEST 63 HOOPS" and "17 HOOPS TO GIANT'S DESK" (at SPACE: "ALL 10 WORLDS · SPACE FLYER").
- **Reward: only the SPACE FLYER title** under the name on the versus card (VS intro + results race card) after reaching SPACE. **No stars anywhere** (O17b, O34). The map ends at SPACE; the looping backgrounds after hoop 200 earn nothing. Pool entries carry a `space` flag copied by the server like `plv` (R4); old entries show no title.
- Storage `worldsReached`, `worldsSeen`.

**G5 Weekly course** (M–L)
- **Seed:** hash(**UTC** ISO year, **UTC** ISO week, salt): the week starts **Monday 00:00 UTC** (O30). The same moment drives "{d} DAYS LEFT", "LAST DAY" (N6, G3 item 6), "NEW COURSE IN …" (W-20) and the `weeklyBest` / `weeklyRewards` reset. The salt is **compiled in**, not remote (PRD-2.5).
- **Rules:** the normal curve with every gate open, no home slot, no revive, unlimited tries.
- **Rewards** at best hoop 15 / 30 / 60 / 120: 40 / 80 / 150 / 300 coins (max 570 a week).
- **No weekly leaderboard** (O30, dropped on both platforms). Weekly runs submit only to the existing `bestScore` board, as any run does. No weekly sticker on the player / versus card ("WEEKLY 120" dropped, O42); `look` gets no weekly field.
- **Entry, no new button (O26):** (1) a card at the top of the daily-missions panel: "WEEKLY COURSE · 3 DAYS LEFT · BEST HOOP 34 · ▶ PLAY" (▶ PLAY starts a weekly-course run; the card shows no rank); (2) at most once a day, a small line on the results page after a normal run: "Try this week's course → beat hoop 34" (tap = start; at 568 pt it waits for a run where no mission moved). No third mode, no Home tile. Storage `weeklyHintDay`.
- **Weekly results** (approved design `design/approvals_v26/weekly_course.html`): the WEEKLY COURSE banner and the reward tiers in the middle ~~and one level line~~ (**no level line**, O76: level points are added silently and a level reveal still plays after the page; no emblem, no rank line); the trophy box opens our board (WP-LB); HOME + ▶ FLY AGAIN. The mission rows of the missions panel carry no difficulty label (O71). The in-run best marker is the beat-your-best line with a "WEEK n" flag; passing it shows **NEW WEEK BEST!** (GoldSticker master).
- **Unlock:** `gamesPlayed` ≥ 6 (squeeze open) + `bestHoops` ≥ 40.

**G6 Extras** (should, M in total, 2.6, built last; O23; designs and texts: §7 D11a–d / T12). None needs a purchase or an ad (O27):
- **First versus win of the day** (approved design `first_win_of_day.html`, style A, O40): +20 coins (`CoinSource.firstWinDay`, storage `firstWinDay`), one gold line "+20 FIRST WIN TODAY" centred under the reward row (NEXT moves 10 pt when the missions strip also shows). Only a "YOU WIN!" counts (draws don't); solo / no-opponent versus runs never pay it.
- **Puzzle album** (O36; the **ALBUM tab** of the Levels screen, approved design `puzzle_album.html`): 8 pictures in a fixed round order. Storage `albumCounts` (8 ints, all 0 at the 2.6 update; +1 for a colour when its picture completes), `albumRewardClaimed`, `albumRewardItem`. The album **starts empty for everyone**; pieces already held for the picture in progress at the update **are kept and count** when that picture is finished; only pictures finished before 2.6 are left out (O78). The **first** time all 8 counts are ≥ 1: one random **unowned EPIC item of any category** (no versus-card cosmetics, no skill items; R9 fallback: next rarity up, then coins), shown on that run's results page with the approved reveal + confetti + `Sfx.lvClaim`. Later laps: no reward, only a ×n badge. No coin amounts on the pictures.
- **Flight guide** (O35; the **GUIDE tab** of the Levels screen, approved design `flight_guide.html`): lists **all 32** elements (hoops 10, pick-ups 7, power-ups 5, rides 7 = COMET + 6 portal ride themes, hazards 3); unmet ones as a silhouette with "? ? ?" and "Not met yet." (replaces the old "unmet ones are not shown"). A gold dot on the GUIDE tab while the met count > `guideSeenCount`. Storage: per-theme portal ride ids in `metElements` (today only `portal`), SPIKES met from run 1, `guideSeenCount`. Achievement **BIRDWATCHER** when all 32 are met (J9; **25 points**, bird-with-binoculars spike-ring icon, O77). Rule lines: `texts.html` FG-E rows (they win over the mockup's draft lines, Q16).
- **Star Road free season** (O37; approved design `star_road.html` + `star_road_popup.html`):
  - **Stars:** easy mission 1, medium 2, hard 3, **+2 for the first finished run of the day**, +3 when all 3 missions are done: **max 11 a day**. 8 stars a tier, **25 tiers** (200 stars), **28-day seasons back to back**. The word stays "stars". Players who join mid-season start at tier 0 with the days left.
  - **Rewards:** existing shop items and coins only; free, no paid track. Coins as in the tier table, unchanged (≈ 960 a season; meta in the F5 "≤ 25 %" case). Tier 5 feather, tier 15 puzzle piece (50 coins if 3 are already held). Item tiers 10 / 20 / 25 = random unowned RARE / EPIC / LEGENDARY shop item (R9); none left → **250 / 500 / 1 000 coins**. **No rarity word on the road or in the Home popup (O75):** the item tier box keeps its rarity colour with a centred "MYSTERY" (popup tile label "MYSTERY", reward line "MYSTERY ITEM"); the rarity shows only in the item reveal after CLAIM (chip kept there, Q28 → O83). The Star Road mission rows show no difficulty label (O71); the difficulty still sets the stars 1 / 2 / 3.
  - **Season names (O75; list approved, Q27 → O83):** `SEASON_NAMES[13]`, compiled in; season n uses name `(n − 1) mod 13` (13 × 28 = 364 days, so the list repeats about once a year). The road header shows a small line "SEASON n" with the days chip and the name big below it (e.g. "SUGAR SPIKES"). Approved list: SPIKE SPRING, HILLTOP HOP, SUGAR SPIKES, ROOFTOP RUSH, TICK TOCK, PAPER PLANES, BUBBLE BAY, HOOP DREAMS, PENCIL PASS, SLEEPY SKIES, FEATHER STORM, ZERO GRAVITY, SPIKE NIGHT (≤ 13 characters, none repeats a level, world or item name); spares WING IT, TAIL WIND, BEAK PEAK, NEST EGG, RING RUSH, SHARP TURN, FLAP HAPPY. Tiers reached but not claimed are **added automatically at season end** and listed once on the summary.
  - **Entry:** the Star Road card in the missions panel: bottom line "4 / 8 STARS TO TIER 11" (no "TIER X OF 25"). On short screens (panel content taller than the panel, e.g. 568 pt) the card folds into one 44 pt line "★ STAR ROAD · TIER 10 · 2 TO CLAIM ›". **No 5th Levels tab.**
  - **Home popup (new):** when at least one tier is claimable, the next Home visit shows the Star Road popup (P1 frame): tier badge on slowly turning rays, the waiting rewards as road tiles (max 3, then "+N"), "They wait for you on the Star Road.", the button **GO TO STAR ROAD** (opens the road scrolled to the first CLAIM) and ×. At most **once a day**, on the first Home visit after a tier became claimable (decided, O75), never in runs 1–3, inside the C2 budget, never together with the missions chest. The season-end summary stays in the missions panel. No NEW! sticker, no badge on tiles. ~~Sound `sk_dialog` on pop.~~ **Motion and sound (O91, round 25):** card pop `sk_dialog`; rays behind the badge (O41); badge drops in, squashes, number ticks up to the new tier, sparkle ring + confetti burst + two corner confetti poppers with `lv_up`; title pops; tiles pop one by one with a sparkle and a shine, `vs_pop` each (rising pitch); button slides up; idle: rays turn, badge bobs, twinkles, mystery box wiggles every 2.4 s, button breathes; GO `sk_tap` with a star puff, × `sk_close`. Reduced motion: no confetti, static rays.
  - **Claim:** coin tier `bn_coin`, item tier `lv_claim`, LEGENDARY item tier `lv_up_big` (existing cues). Reveal rays per O41; coin claims get a small confetti puff.
  - Storage `starRoadSeason`, `starRoadXp`, `starRoadClaimed`, `starRoadPopupDay` (local day of the last popup).
- **Reveal rays (shared master, O41):** every reward reveal (level item, album, Star Road, chest, skill item, leaderboard gift box, streak restore) uses one rays master: rays reach ≈ 2× the item stage (r ≈ 250–300 pt), fade to transparent with a radial gradient, rotate slowly (≈ 9–18°/s; static with reduced motion) and are drawn behind every other element of the moment. **(Round 13: the ray look here is replaced by O98 — reuse an existing in-game ray as it is; the box is the O99 master.)**

**Coin budget check:** missions 150 + streak 29 ≈ 180 coins a day ≈ 19 % of a 15-minute day (§0.2 D8). The economy budget test gets a "meta ≤ 25 %" case. Leaderboard gift boxes (WP-LB, F12) also count as meta in that case. Level rewards (WP-J, F11) are not meta and are checked separately (F5). The first-versus-win bonus (G6, ≤ 20 a day) and Star Road rewards count as meta; the budget test's meta case includes them and the 25 % cap stays.

**Storage (new):** `bestHoops`, `missionDay`, `missions` (JSON), `missionTier`, `missionRerollDay`, `streakDays`, `streakLastDay`, `streakPaidDay`, `streakLostDays` (the old n waiting for restore, 0 = none), `streakLostSeenDay` (local day of the last STREAK LOST popup), `worldsReached`, `worldsSeen`, `weeklyBest`, `weeklyRewards`, `weeklyHintDay`, `firstWinDay`, `albumCounts`, `albumRewardClaimed`, `albumRewardItem`, `guideSeenCount`, `starRoadSeason`, `starRoadXp`, `starRoadClaimed`, `starRoadPopupDay`, `vsWinStreak`, `vsWinStreakBest` (BIRD OF PREY, approved O82), + round 23: `homeLevelsTag` (Home NEW tag, O70 / Q26), `vsBigWinsDay` (THREE LITTLE BIRDS, approved O83; was: only if Q30 is approved).

**Files:**
- New `lib/progression/missions.dart`, `day_streak.dart`
- `lib/components/progression/missions_panel.dart`, `streak_strip.dart`, `streak_lost_popup.dart`, `star_road_screen.dart`, `star_road_popup.dart`
- `lib/components/levels/tabs/` (`levels_tabs.dart`, `worlds_tab.dart`, `guide_tab.dart`, `album_tab.dart`; O29)
- `CoinSource.mission`, `.missionChest`, `.streak`, `.streakRestore` (spend)
- `lib/services/reminders.dart` (`ReminderState`)

**Tests:**
- `missions_test`: stable daily roll, locked elements left out, tiers, clock rollback, paid exactly once after a kill, chest fallback, debug runs count nothing, M10 only online + last versus run found a rival, swap any unfinished mission once a day
- `day_streak_test` (no freezes anywhere; a missed day breaks it; paid on COLLECT) and `streak_restore_test` (popup for every n ≥ 1 incl. the singular text (O72); a second break replaces the open offer with the last streak (O73: cases A / B / C); video completed → n + k back; ad failed / no fill → still pending on the next visit and the next day; No-Ads → 500 coins, grey under 500, never a video; × → again on the next visit; GIVE UP → k; runs while pending count; never in runs 1–3)
- `weekly_week_test`: the week flips at Monday 00:00 UTC in every time zone (seed, countdowns, reset)
- `star_road_test` (stars incl. the +2 first-run bonus, max 11 a day, season roll-over, auto-claim at season end, popup once a day) and `album_test` (starts empty, first full album pays one EPIC item once)
- reminder truth / decay tests

**Analytics:** `mission_assigned`, `mission_complete`, `missions_all_done`, `mission_reroll`, `day_streak`, `streak_lost_shown` {days, visit} (was `day_streak_lost`; not `streak_broken`, which is the perfect streak), `streak_restore` {days, method: ad / coins, ad_tries}, `streak_restore_ad_fail` {reason}, `streak_give_up` {days}, `world_reached`, `weekly_run`, `weekly_reward`; `notif_opened {type}`.

### WP-H Profiles and A/B — should · S–M · 2.6 (O20)

- **Baked arms:** `abArm_v1` is drawn with `Random.secure` at first launch and reported as `fs_arm`.
- **What arms may differ on:** only lifetime keys:
  - `showcase_*`;
  - `gate_saw`, `gate_squeeze` (lifetime gates; R2 already accepts them as lifetime inputs);
  - `ads_grace_*`;
  - `ads_interstitial_*`;
  - `rate_min_runs`;
  - `ui_unlock_*`;
  - mission targets.
- **Never:** `curve_*`, `point_*`, `spawn_*`, `squeeze_*`, `ride_*`, `coin_*`, `revive_*`, `hazard_*`, `calm_*`, `level_*` (levels are an economy track shared by everyone).
- **Enforcement:** `profiles_test` checks both lists.
- **Ending an experiment:** a release sets all arms to the winner; the next test uses a new key.
- **No remote switch (O11).**
- **When:** the plumbing ships in 2.6 with a single arm (every install gets arm 0, all keys at their defaults). Start the first experiment only at ≥ 1,500 new installs per arm per test window (a later 2.6.x release adds the second arm). Until then, compare releases by in-run metrics.

### WP-I Docs — must · S · with each release

- `SPEC.md` and `docs/gameplay-v2/ARCH.md` get DEVIATION notes:
  - curve, tilt sign, Δy in points, hazard budget, calm, squeeze;
  - showcase, the saw / squeeze gates, all other gates at 0;
  - levels (31 + endless ETERNAL WING, points-based, item rewards), pool brackets decoupled from levels, `plv`;
  - beat-your-best HUD.
- `lib/progression/` and `lib/levels/` (new models) in the ARCH module map.
- PRD-2.3 §14.6 (gates), §26 and PRD-home-v3 §4 (ranks) are marked superseded.
- AGENTS.md: the GA4 / BigQuery settings (O10), the functions + rules deploy for R3/R4, and "test runs stay in the pools" (O7).

### WP-J Levels (31 ranks), level rewards and the "beat your best" goal — must · L · 2.6

**Goal:** a long, always-visible progress track that measures time played (points summed over runs), pays a cosmetic every level, and replaces the 10 ranks (EGG … LEGEND). The in-run "beat your best" goal is WP-K.

**J1 The table** (baked: `lib/levels/levels.dart` `kLevels` + tuning keys `level_points`, `level_coins`, `level_items`)

| # | Name | Points for level | Cumulative | Coins | Item (category · rarity) |
|---|---|---|---|---|---|
| 1 | HATCHLING | 25 | 25 | 50 | Hat · Common |
| 2 | FLUFFBALL | 50 | 75 | 50 | Trail · Common |
| 3 | NEST HOPPER | 100 | 175 | 50 | Gear · Common |
| 4 | FIRST FLAP | 150 | 325 | 50 | Hoop · Common |
| 5 | FLEDGLING | 200 | 525 | 50 | Bird · Common |
| 6 | WING WOBBLER | 300 | 825 | 75 | Hat · Common |
| 7 | HOOP ROOKIE | 400 | 1,225 | 100 | Trail · Common |
| 8 | FEATHERWEIGHT | 500 | 1,725 | 125 | Gear · Common |
| 9 | SWALLOW | 600 | 2,325 | 150 | Hoop · Common |
| 10 | HUMMINGBIRD | 700 | 3,025 | 175 | Bird · Rare |
| 11 | KINGFISHER | 800 | 3,825 | 200 | Hat · Common |
| 12 | RIM SKIMMER | 900 | 4,725 | 225 | Trail · Common |
| 13 | STARLING | 1,000 | 5,725 | 250 | Gear · Common |
| 14 | SHRIKE | 1,200 | 6,925 | 300 | Hoop · Common |
| 15 | SWIFT | 1,400 | 8,325 | 350 | Bird · Rare |
| 16 | TAILWIND | 1,600 | 9,925 | 400 | Hat · Rare |
| 17 | HAWKEYE | 1,800 | 11,725 | 450 | Trail · Rare |
| 18 | CANNONBALL | 2,000 | 13,725 | 500 | Gear · Rare |
| 19 | STORM PETREL | 2,200 | 15,925 | 550 | Hoop · Rare |
| 20 | FEVER FINCH | 2,400 | 18,325 | 600 | Bird · Epic |
| 21 | SKYLARK | 2,600 | 20,925 | 650 | Hat · Rare |
| 22 | PEREGRINE | 2,800 | 23,725 | 700 | Trail · Rare |
| 23 | PORTAL PIGEON | 3,000 | 26,725 | 750 | Gear · Rare |
| 24 | COMET CONDOR | 3,500 | 30,225 | 875 | Hoop · Rare |
| 25 | GOLDEN EAGLE | 4,000 | 34,225 | 1,000 | Bird · Epic |
| 26 | NIGHT OWL | 4,500 | 38,725 | 1,125 | Hat · Epic |
| 27 | MOONBIRD | 5,000 | 43,725 | 1,250 | Trail · Epic |
| 28 | ALBATROSS | 6,000 | 49,725 | 1,500 | Gear · Epic |
| 29 | PHOENIX | 7,000 | 56,725 | 1,750 | Hoop · Epic |
| 30 | SPIKE LEGEND | 8,000 | 64,725 | 2,000 | Bird · Legendary |
| 31 | THUNDERBIRD | 10,000 | 74,725 | 2,500 | Legendary · random category |
| 32+ | ETERNAL WING | 10,000 each | +10,000 | 2,500 | 1 random unowned item |

Totals levels 1–31: **18,800 coins** + 31 items (≈ 32,750 shop value). Shop: 148 items (`lib/skins/catalog.dart`; per layer 10 common, 10 rare, 5–6 epic, 4 legendary).

**J2 Endless levels (ETERNAL WING, round 3):** after level 31 THUNDERBIRD come levels 32, 33, 34, … all named **ETERNAL WING**. Each needs 10,000 points (`level_eternal_points`), with the same one-level-per-run / surplus-dropped rule, and pays 2,500 coins (`level_eternal_coins`) + 1 random unowned item while any are left (R9: uniform over all unowned items; none left → only the coins). No cap and no stars anywhere: `lvlIndex` just keeps counting. It is shown as "ETERNAL WING 34" (name + level badge).

**J3 Progress rules** (pure `lib/levels/level_track.dart`; `LevelProgress` in `level_progress.dart` is rewritten on it)
- **Input:** the run's final score at `endRun` (`flappy_game.dart:4052`, where `menu.levels.recordRun(score)` is today).
- **Counts:** every finished run in every mode: showcase, versus, Free Fly, runs with ad / coin / free revives. **Debug runs count nothing:** `_debugTouched`, a debug force, `ignoreGates`, FS_TESTER god mode / bot. Killed runs (no `endRun`) count nothing either.
- **Step:** `p = lvlPoints + score`; `need = level_points[lvlIndex]` (or `level_eternal_points` at 31 and above).
  - If `p ≥ need`: the level goes up by exactly one, and **`lvlPoints = 0`. The surplus is dropped.**
  - Else `lvlPoints = p`.
- **One level per run at most**, however high the score.
- The level never changes anything in a run (§1.4).

**J4 Rewards: coins + one random unowned item** (no choice of 3, anywhere)
- **Coins:** `level_coins[l]` via `wallet.add(coins, CoinSource.levelReward)` (existing source).
- **Item:** category C and rarity R from the table (`SkinLayer` bird / gear / hat / hoop / trail; `Rarity` in `lib/skins/look.dart:29-33`). Candidates exclude owned items, items already chosen for another pending reward, and non-shop items: only the shop layers bird / hat / gear / hoop / trail are ever drawn (O21); never F9 card cosmetics or F10 achievement items.
  1. A random unowned item of C at R.
  2. Else C one rarity up, then the next one up (random within the first rarity that has one).
  3. Else ("C is owned" = nothing of C at ≥ R; R9) a random unowned item of the other categories at R, then R+1, ….
  4. Else coins at the shop price of R: common 250, rare 750, epic 2000, legendary 5000 (`Rarity.price`), on top of the level coins.
  - Level 31: R = legendary, C = random over all layers (step 1 is "any layer", then step 4).
- **The roll happens at run end** with `Random()`. The chosen item key (or fallback coins) is saved in `lvlPending` (JSON list of {lvl, star, coins, item, extraCoins}) **before** anything is shown, so a kill never re-rolls.
- **Payout** when the results-page reveal is closed with EQUIP or LATER (J7), or by the Home catch-up popup after a kill. It uses the existing crash-safe pattern (`level_progress.dart:118-152`): record the target balance in `lvlPayout`, add the item to `ownedItems` (new `ItemStore.grant(key)`, sealed write like purchases) and credit the coins, then clear the pending entry. It is paid exactly once after a kill at any point.
- The item is **not auto-equipped**. The reveal has **EQUIP** (equips it, the bird shows it, closes) and **LATER** (keeps it in the inventory with a NEW sticker). Owner-approved design 2026-10-21 (J7a); replaces "EQUIP / CLAIM".

**J5 Fresh start for existing installs** (the owner's decision)
- New keys, appended at the END of `kObfStrings` in `tool/gen_obf_strings.dart`, then regenerate `obf_strings.g.dart` and add them to `tool/anchor_strings.txt`: `lvlIndex`, `lvlPoints`, `lvlPending`, `lvlPayout`. `lvlIndex` and `lvlPending` are written with `_sealedWrite` (`storage.dart:605`), like coins and owned items.
- Absent keys = level 0 (UNRANKED), 0 points: every existing install starts fresh. Coins, owned items and earned achievements are kept.
- The old keys `playerLevel`, `claimedLevels`, `unclaimedLevelReward` and `levelRewardPayout` keep their names and stay in `kObfStrings`. They are no longer read, with one exception: on the first 2.6 load, an interrupted 2.5 claim (`levelRewardPayout` > balance) is paid out once and the record cleared (EDITOR rule, so no coins are lost across the update). "Delete my data" clears old and new keys.
- The tuning key `level_rewards` (`tuning_defaults.dart:79`) is retired together with its baked-tuning test rows. `LevelDef.threshold` / `reward` are replaced by `points` / `coins` / `item`.

**J6 31 unique emblems + the ETERNAL WING emblem** (art WP, must for 2.6; effort L for art, S for code)
- One drawn emblem per level 1–31, plus **one own emblem for ETERNAL WING**, used for every level ≥ 32 (#32 "ETERNAL WING (32+)" in `design/levels_v26/emblems.html`, added by the designer). 32 PNG emblems in total.
- Today 10 emblems are painted in code (`lib/levels/emblem_painter.dart`, from `design/menu_v2/emblem_art.js`; `EmblemView` in `lib/components/levels/emblem_view.dart`). Route per Q2 = **(b), owner 2026-10-21**: drawn art as PNG @1x/2x/3x in `assets/emblems/` with `EmblemView` switching to an image. The UNRANKED emblem stays painted either way.
- Sizes: Home emblem, results level bar, LEVEL UP popup, Levels screen, settings player card, versus opponent card (R4), share card (`lib/share/share_card.dart`).
- **Approved design (owner, 2026-10-21): `design/levels_v26/emblems.html`** — the reference for the PNG art. Same flat plate style as today's emblems; the player's own bird stays drawn on the plate centre at every size (as today), so each name's motif sits on the ring, rim, crest, wings and ornaments around it, never in the middle.
- **Escalation per group (each group adds one layer):**
  | Group | Levels | Adds |
  |---|---|---|
  | The nest | 1–5 | plain coloured rim, ribbon number, small motifs (cracked egg cap, fluffy rim + tuft, twig nest + hop arc, stubby first wings, sprig wreath) |
  | Learning to fly | 6–10 | silver band, shield plate, 3–4-feather wings (wobble wings, hoop ring, big quill, swallow fork tail, blurred hummingbird wings + flower) |
  | Among the spikes | 11–15 | gold band, steel spikes (kingfisher splash, rim-skimming hoop + sparks, starling spots + gold star, thorn ring + branch for SHRIKE, sickle wings for SWIFT) |
  | Speed and rides | 16–20 | gold laurel, shiny 5-feather wings (wind swirls, hawk eye + crosshair, iron-cannonball plate with lit fuse, storm cloud over a wave, FEVER fire ring) |
  | High sky | 21–25 | gems on the band, slowly turning sun rays (clouds + notes, diving falcon, swirling portal ring, comet tail + condor wings, all-gold GOLDEN EAGLE with crown) |
  | Into space | 26–30 | night plates, soft glow pulse, twinkling stars (owl tufts + crescent, full moon + orbit trail, albatross wings around a ringed planet, flickering fire wings + embers, crown of game spikes + turning spike ring) |
  | Ultimate | 31 | double band, lightning-bolt wings, storm halo, thunder crown, flashing side bolts |
- **Idle animation** (code, on top of the PNG): the existing light sweep every 6.4 s on all levels; ray turn from 21, twinkle + glow from 26, flicker on PHOENIX and THUNDERBIRD. Off when the OS asks for reduced motion.
- **Production:** export each emblem from the approved mockup (SVG → PNG @1x/2x/3x, transparent, centred on the plate so `EmblemView` keeps the bird placement); animated layers (rays, glow, twinkles, flicker) are separate small layers or painted in code. Check legibility at the smallest in-game sizes shown in the mockup (levels list ≈ 0.29×, versus name box ≈ 0.32×).

**J7 UI**
- **J7a Approved design (owner, 2026-10-21): `design/levels_v26/item_reveal.html`, reveal style A (mystery box).** Everything happens **on the results page** after the run (owner choice; no separate Home step). Sequence (≈ 5.5 s, a tap skips to the reveal):
  | t (s) | Step |
  |---|---|
  | 0–0.3 | page fades in |
  | 0.45–1.15 | score and run coins count up |
  | 1.25–1.95 | level bar fills with this run's points ("+180" at the bar end) |
  | 1.95–3.05 | bar full + flash; **the surplus piece falls off with "+N OVER · DROPPED"** (shown on purpose: it explains the one-level-per-run rule; DEVIATION from the earlier "surplus not shown") |
  | 1.93–2.6 | old emblem flashes white → new emblem pops in with rays, confetti, the LEVEL UP! drop and the new name |
  | 2.4–3.0 | bar restarts empty, label for the next level |
  | 2.6–3.65 | level coins fly into the YOUR REWARD box (gold "+175") |
  | 3.55 | reveal sheet opens below the score card |
  | 3.75–5.5 | **mystery box** in the rarity colour drops in, shakes harder, bursts at 4.8 with sparkles (more for higher rarity; legendary gets a second gold burst), the item pops out |
  | ≈ 5.5 | item name, rarity chip, category, "NEW ITEM · ADDED TO YOUR …" with a **fixed word per category: HATS / TRAILS / GEAR / HOOPS / BIRDS** (no code-added S, so never "GEARS"; O31), **EQUIP / LATER** |
  | EQUIP | the pink bird puts the item on (hat drops on / skin swaps with a poof / flies through the hoop / trail turns on), "EQUIPPED ✓" at +0.6, sheet closes at +1.45–1.75; the emblem's bird wears it, an item tile with ✓ appears beside the emblem |
  | LATER | sheet closes at once; item tile with a NEW sticker beside the emblem |
  A run without a level-up only fills the bar (settles ≈ 2.15 s). The reel (B) and card flip (C) variants in the mockup are not built.
- **Results page** (`lib/run/screens/results_screen.dart`, `LevelBar`): the bar shows `lvlPoints / need` and fills by this run's score, as in J7a. The reveal sheet, the box and the EQUIP preview reuse the existing masters (P1 frame, GoldSticker, CoinReward, the shop item renderers) — no second variant of a shared part (CLAUDE.md). Rank line "HUMMINGBIRD · LV 10" / "ETERNAL WING · LV 34" / "UNRANKED". Under it, only after the reveal, the reward chip: "+175 · RARE BIRD" (before a level is reached its item is never named, J7 levels screen). `Config.uiAccent` labels.
- **Home LEVEL UP popup** (`lib/components/levels/level_up_popup.dart`, P1 frame): **catch-up only** — when a reward is still pending after an app kill before the results-page reveal finished. Same mystery-box reveal and EQUIP / LATER; several pending levels are listed and paid together.
- **Levels screen — approved design (owner, 2026-10-21, FINAL after 8 review rounds; the mockup is the reference, including the ETERNAL WING #32 emblem in `emblems.html`): `design/levels_v26/levels_screen.html`** (`lib/components/levels/levels_screen.dart`). **The item of a level is a surprise until it is earned.**
  - Header card in today's `LevelsHeader` layout (84 pt): current emblem with the player's bird (no badge on the emblem), level name (20 pt; shrinks only if name + badge overflow 202 pt, e.g. COMET CONDOR → 19 pt) with the **level badge at the end of the name** on the same line (pink plate, white Fredoka 12 px number "10", 6 pt gap; endless: "ETERNAL WING" + badge "34"; no badge when UNRANKED), "BEST 640 · GAMES 34" line in today's style, and the bar `lvlPoints / need` (186×16, soft-pink track, pink fill) with **"380 TO KINGFISHER" inside the bar** (10 pt Opificio, plum, centred; "25 TO HATCHLING" when new, "10 000 TO ETERNAL WING" at THUNDERBIRD; from level 32 on, where every next name is the same, the text names the number: "3 760 TO LEVEL 35"). No "LV" tag, no total points, no next-reward preview.
  - One continuous list, **no dividers** (no group titles, no "ENDLESS" divider); the ETERNAL WING row follows THUNDERBIRD.
  - Reached rows (item earned): full-colour emblem with the bird, name, points needed, "✓ +175", the earned item's name in its rarity colour and a small item drawing in a rarity-bordered tile with the rarity caption; a gold NEW sticker while the item is not yet equipped.
  - Current row: pink outline, YOU tag, soft pulse; the list scrolls smoothly to it on open. Only this row's emblem and the header emblem run their idle animation; all other row emblems are static.
  - Next row: NEXT tag, small progress bar (420 / 800), the coin chip and a plain grey box.
  - Locked rows: greyed emblem without the bird, lock icon, the "+800" coin chip and a **plain grey mystery box with "?"** — no category, no rarity colour, no rarity caption.
  - ETERNAL WING row (one row for all levels ≥ 32): ETERNAL WING emblem (drawn smaller: 60 pt in the list, 70 pt in the header — it is the widest), title "ETERNAL WING" (no number or "32+" badge in the row), "10 000 PTS EACH", "+2 500" and the grey box. No explanatory text below it. In the top state (level ≥ 32) it is the current row with the bar to the next level and an EARNED strip of the items from levels 32+: an "EARNED · N" label (no dots, no chip) above a **horizontal swipe carousel**: big item tiles (40 pt item tile, 10.5 pt name in the rarity colour, pink "LV 35" tag, "✓ +2 500" with the coin icon), **newest first** (the just-earned item at the left), about 3 tiles visible with ~20 pt of the next one peeking at the right edge, snap per tile, fixed 84 pt height however many items. Only horizontal gestures move it; vertical swipes still scroll the list. Mockup top state: level 40, header "ETERNAL WING" + badge "40", "3 760 TO LEVEL 41", 9 earned items (LV 32–40).
  - Numbers use the game's space thousands separator ("10 000").
  - ALBATROSS is drawn smaller at list size (64 instead of 74) so its wings don't overlap the row name.
- **Name fit (13 characters, e.g. PORTAL PIGEON, COMET CONDOR):** check results rank line, settings player card (`lib/components/settings_player_card.dart`), versus name box / HUD (`lib/run/hud/fit_name.dart`, `run_hud.dart`), share card. Goldens at 320 pt for the 3 longest names + "ETERNAL WING" with badge "999".

**J8 Versus** (details in E4)
- Matching keys on `bracketFor(bestScore)`, never on the level (the level now measures time played).
- The player doc's `level` = `lvlIndex` (0–9999; rules 0–9999); levels ≥ 32 show the ETERNAL WING emblem on the opponent card; the opponent emblem comes from the pool entry's `plv`.

**J9 Achievements** (`lib/achievements/achievements.dart:290-297`, catalog `achievement_catalog.dart:15-104`)
- Today `onLevel(level)` earns rank_egg … rank_legend from the stored level.
- 2.6 (R5): `onLevel` is replaced by `onRunScore(score)` in the counting-run batch (`finishRun`). rank_N is earned when one counting run scores ≥ its old threshold [25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000]. This is what the live console descriptions say. Thresholds move into `achievement_catalog.dart`; they no longer come from `kLevels`. Earned achievements stay earned.
- **No group label change (O31):** Play Games and Game Center cannot group achievements, so the old "RANKS" → "SCORE" rename (T3) is dropped; the "RANKS" code comment goes too. Achievement names (EGG … LEGEND) are unchanged in the consoles (Q1).
- No new level achievements in 2.6 (the 48 approved stay unchanged). **New achievements for the 2.6 extras** (each needs a Play Console + Game Center entry and a 17C-style spike-ring icon; re-reported on sign-in like the others; §7 C6):

  | Achievement | Description | Points | Visible | Unlocks | Status |
  |---|---|---|---|---|---|
  | BULLSEYE | Score a ×25 perfect streak. | 40 | yes | Golden Thread trail (F10) | **approved** (option A, O39; 40 points, O82) |
  | SKY HIGH | Pass 150 hoops in one run. | 50 | yes | Sky Crown hat (F10) | **approved** (option A, O39; 50 points, O82) |
  | BIRD OF PREY | Win 5 versus races in a row. | 25 | hidden | Bird of Prey frame (F10) | **approved** (O82). Only races where a rival was found count; a race without a rival neither adds nor breaks the streak (`vsWinStreak`, `vsWinStreakBest`). |
  | BIRDWATCHER | Meet all 32 things in the Flight Guide. | 25 | yes | — | **approved** (O35; 25 points + bird-with-binoculars icon, O77) |
  | SECOND WIND | Win a versus race after trailing your rival by 100 points. | 10 | yes | Skywriter name style (F10) | **approved** (round 23, O80; Q30 → O83). Track the largest live deficit vs the ghost replay during the run. |
  | ALBATROSS | Win a versus race with double your rival's score (rival 100+). | 15 | yes | Thunderstruck name style | **approved** (O83) |
  | THREE LITTLE BIRDS | Win 3 versus races in one day, each with 500+ points. | 10 | yes | Headliner name style | **approved** (O83). Local day, counter `vsBigWinsDay`. |
  | IRON BEAK | Win a versus race with 1,000 points or more. | 10 | yes | Unstoppable sticker | **approved** (O83) |
  | FLAWLESS | Win a versus race with a ×20 perfect streak and no revive. | 10 | yes | Flawless sticker | **approved** (O83) |
  | TOP BIRD | Finish a day #1 in your leaderboard group. | 15 | yes | Top of the Flock sticker | **approved** (O83). #1 of the whole group, ghosts included: if a ghost is #1, nobody earns it that day (same rule as the gold box, O65). Earned on settle (`lbSettleGroups`) → the client on its next board read. |

  For the five round-23 versus achievements only races where a rival was found count (as BIRD OF PREY); TOP BIRD comes from the leaderboard settle.

  Totals: 48 → **52 achievements**, points 755 → **895** with the four approved ones; with the six round-23 achievements (approved, O83) → **58 achievements**, **965** of the 1,000 cap on both platforms ~~(fallback: all six at 10 points → 955)~~. The PRD-2.3.1 §12.1 catalogue tests and group point sums are updated; internal catalogue groups: BULLSEYE → mastery, SKY HIGH → hoops; BIRD OF PREY, BIRDWATCHER and the six round-23 achievements go into the closest existing group (versus / collection), builder's choice.

**J10 Analytics**
- `level_up` (existing name, `game_services.dart:615`): {level, games, run_score, s_since_install}. Drop `best`.
- `level_reward_claimed` (existing): {level, coins, item_layer, rarity, fallback (none / up / other_cat / coins)}.
- User property `fs_level` (the plain level number; no stars).
- `run_end` + `level`, `lvl_pts_before`.

**J11 Files**

| File | Change |
|---|---|
| `lib/levels/levels.dart` | 31 `LevelDef`s (name, points, coins, item C·R, emblem ref) + one `kEternalWing` def for every level ≥ 32 (`levelDef(n)` returns it with number n); `levelFor` removed; no max level |
| New `lib/levels/level_track.dart` | Pure step rule + star rule |
| New `lib/levels/level_reward_roll.dart` | J4 roll + fallbacks (pure, takes owned set + `Random`) |
| `lib/levels/level_progress.dart` | Rewritten on the new keys; pending list; crash-safe payout; 2.5 payout finish |
| `lib/levels/emblem_painter.dart`, `lib/components/levels/emblem_view.dart` | 31 emblems (J6) |
| `lib/components/levels/level_up_popup.dart`, `levels_screen.dart` | J7 |
| `lib/run/screens/results_screen.dart`, `lib/run/config/results_config.dart` | Bar, rank line, reward chip |
| `lib/skins/item_store.dart` | `grant(String key)` (sealed `ownedItems` write) |
| `lib/game/storage.dart`, `tool/gen_obf_strings.dart`, `obf_strings.g.dart`, `tool/anchor_strings.txt` | New keys (J5) |
| `lib/game/flappy_game.dart` | `endRun` → `levels.recordRun(score, debug:)`; popup queue |
| `lib/achievements/achievements.dart`, `achievement_catalog.dart` | J9 |
| `lib/services/versus_service.dart`, `lib/versus/*`, `functions/src/*`, `firestore.rules` | E4 |
| `lib/services/game_services.dart` | J10 events |
| `lib/run/config/tuning_defaults.dart` | `level_points`, `level_coins`, `level_items`, `level_eternal_points`, `level_eternal_coins`; `level_rewards` retired |
| `lib/components/debug_panel.dart` | "LEVEL UP" forces the next level's points; a "+1 level" button that also works past 31 |

**J12 Tests**
- `level_track_test`: the 31 cumulative values (25 … 74,725); one level per run; the surplus dropped (24 + 30 → L1 with 0 points); exact hit; levels 32+ every 10,000 (31 → 32 → 33, no cap); debug / killed runs count nothing; revive and versus runs count.
- `level_reward_roll_test`: each fallback step (C·R → C·R+1 → other C·R → coins at `Rarity.price`); never a lower rarity; never an owned or already-pending item; level 31 any layer; levels 32+ uniform; deterministic with a seeded `Random`.
- `level_payout_test`: kill before / between / after credit pays exactly once; the item is owned after; the 2.5 `levelRewardPayout` record is finished once.
- `level_fresh_start_test`: a 2.5 store with `playerLevel` 7 + claims → level 0, coins and items kept, old keys untouched.
- `obf_strings` / anchor test with the new keys.
- `achievements_rank_score_test` (R5).
- Goldens: results bar at L0 / L10 / L34 (ETERNAL WING + badge), popup with an item, Levels screen, 13-character names.
- `functions`: see E4.

**J13 Priority / effort / release:** must · L (code M, art L) · 2.6. The code can ship with the 10 existing painted emblems mapped onto levels 1–31 only in internal builds; 2.6 production needs all 31 emblems.

### WP-K Beat-your-best in-run goal — must · S · 2.6

**Goal:** every Free Fly run has a visible target (the owner's 2026-10-21 decision).

- **When:** Free Fly runs with `bestScore > 0`, and VERSUS runs without an opponent (solo / offline / empty pool — the same as Free Fly), per R7 and the owner. Not in debug runs.
- **Approved design (owner, 2026-10-21): `design/levels_v26/beat_your_best.html`, marker variant A "line + flag"** (B and C in the mockup are not built). Shown only in Free Fly and in a VERSUS run with no opponent (that run is the same as Free Fly, owner); never in a versus run with an opponent, never in a first run (best 0).
- **HUD chip "BEST 42"** (no colon; owner, O31) in the free middle of the top row, between the heart and the pause button (that slot is empty in Free Fly; nothing covers the playfield). White plate, label + number in `Config.uiAccent` (two fonts, so no colon). After NEW BEST! it flips to gold with plum text and shows the live score, popping on each new point. Files: `lib/run/hud/run_hud.dart`, position in `hud_config.dart`.
- **Line + flag:** a thin 2 pt gold line (#FFB529, the GoldSticker gold) from the top spike strip to the bottom spike strip at the plane of hoop index `bestRunHoops` (hoops passed in the best-scoring run), with a small gold "BEST 42" flag just under the HUD row. It scrolls in with the run (`world.addRun(...)`, tablet shift) and becomes visible about 1.25 s before that hoop. Hidden when `bestRunHoops` is unknown (existing installs until their next new best).
- **NEW BEST! moment (owner: fires on the SCORE):** the first time in the run the live score passes `bestScore`, a small gold burst plays and `GoldSticker.newBest(text: 'NEW BEST!')` (`lib/run/effects/gold_sticker.dart:40`; plum on gold, tilted −4°, no new banner variant) pops at y≈114 under the HUD — never over the next hoop — for 1.2 s (0.38 s pop-in, hold, fade) with the existing SFX; the chip flips gold 0.18 s later. Once per run. If the score passes the best before the line is reached (high streaks), the line pulls into the bird / the flag shrinks away together with the moment; if the line is reached first without beating the score, nothing happens at the line.
- **Storage (new):** `bestRunHoops`, saved when a run sets a new `bestScore`.
- **Files:** `run_hud.dart`, `hud_config.dart`, new `lib/run/effects/best_line.dart`, `run_controller.dart` (score watch), `flappy_game.dart` (save `bestRunHoops`).
- **Tests:** chip and line only in Free Fly / solo versus; sticker exactly once; nothing at best 0; line position at 568 / 711 and on a tablet width; `bestRunHoops` saved only on a new best.
- **Analytics:** `best_beaten` {mode, hoop, best_before, games}; `run_end` + `beat_best_hoop` (−1 = not beaten).

### WP-LB Our own leaderboard and gift boxes — must · L · 2.6 (O50–O68; code tag `P26-LB`)

**Goal:** a small daily race against players of your own level, with a reason for one more run and a free reward. Designs `design/approvals_v26/leaderboard.html` and `leaderboard_gifts.html` (§7 D17 / D18), texts T16. Server analysis: `.worktrees/briefs21/SPEC_L22.md` (its `file:line` anchors refer to `.worktrees/p25-merge`); **this section wins where they differ** (owner answers O50–O58 and round 23 O62–O68: join until full but not with < 3 h left, ~~prize rank ≤ 10~~ prize = board places 1–3 only, boxes only on the podium, no BEST n on TODAY, ACHIEVEMENTS tab, no native-board link, no name reporting, 400-day retention, exact rank). Region comments use `P26-LB` (2.5 code already uses "WP-L").

**LB1 What the player sees**
- **TODAY tab (default every time):** a group of up to **50** in the player's best-score bracket (R3, `bracketFor` of the server-verified best, frozen for the group). The group starts with its first run and lasts **24 h**; a timer shows the time left. Real players of that bracket join an open group **until it is full** (O50), except that a **new** joiner is never placed in a group with **< 3 h** left — the server opens a fresh group instead (O66, `LB_MIN_LEFT_MS`). Rank = **total points today** (every non-debug run: Free Fly, versus, weekly), ties → best run today → who got there first (the tie-break is internal only). ~~Each row also shows the best run today.~~ **No "BEST n" line on this tab (O62):** podium spots, rows #4–#50 and the pinned own row show only the total points today.
- **Tabs (O63):** **TODAY · BEST RUN · ACHIEVEMENTS** (three tabs, labels at 11.5 pt; ~~ACHIEVEMENTS carries a small "opens outside" mark~~ all three are plain words, no icon, O89). TODAY and BEST RUN are our pages. Tapping **ACHIEVEMENTS** flashes the tab and opens the **native** Play Games / Game Center achievements screen (`game.showAchievements()`, `flappy_game.dart:4610` → games_services `Achievements.showAchievements`, the call the old Home medal box made); it is not a page of ours. Back / Done returns to the board on the tab that was open. Signed out: the same sign-in flow the medal box used, started by the tap (never at launch; Q29 → O83: the native screen opens after the sign-in succeeds, a cancelled sign-in leaves the board, no disabled look on the tab). Unlock reporting is unchanged.
- **Ghosts (O51):** empty spots are filled with real players' earlier days (≤ 14 days old), **replayed live**: each ghost run appears at the first moment ≥ the group start with the same UTC time of day, so ghosts climb during the day. Supply: own bracket → ±1 → ±2 → **fewer rows**. Never invented, never generated test data, never hidden / tester players. **One unique user per board** (no ghost of a member or of the viewer; a joining real player replaces the last shown ghost). PLAYING NOW only for real players with a run < 5 min ago; everyone else, ghosts included, shows a time tag. Ghosts carry no mark.
- **BEST RUN tab:** all players, all time — the global top 50 verified best runs + your own row pinned with your **exact** global rank; above ≈ 20 000 players it switches by itself to an approximate rank from a histogram doc ("#~1 2xx", O52). No boxes on this tab.
- **Rows:** rank, bird avatar in the player's versus-card frame, username in their (animated) name style (F9 painters), tag, one pink pill (TODAY: total points today; BEST RUN: the best run), centred in the row. Top 3 on a podium; your own row pink, **pinned at the bottom** when off screen. No hearts / likes, no platform icon, **no report option** (O56).
- **Gift boxes on the board:** closed gold / silver / bronze boxes are drawn **only on podium spots 1–3** (TODAY), as prize markers — never on rows, so the rows never give a ghost away (O54). They are exactly the prize places (O65): the podium always shows three markers, also when a ghost holds one of them.
- **Info overlay (picture guide, O59 / O60):** a full-screen overlay over the dimmed board (not a P1 popup): title LEADERBOARD (LB-01), 4 drawn steps with captions LB-36–LB-39 (LB-37 now **TOP THE BOARD**, O67) on pink bands with white text, in a zig-zag joined by curved gold arrows with a dark plum edge; BEAT THE RECORDS draws the **Flappy Spikes trophy** (gold cup crowned with 5 pink spike teeth, two hoop-ring handles, the pink bird on a white diamond badge, pink plinth; `fsTrophy()` in `leaderboard.html`), TAP TO CONTINUE (LB-17) — a tap anywhere closes it. Motion: dim fades in, title pops, pictures pop in one by one (0.6 s apart, `Sfx.vsPop` rising; open `Sfx.skDialog`), each arrow draws to the next picture, captions slide up, TAP TO CONTINUE pulses (`Sfx.skClose` on tap); the pictures keep moving gently (bird through the hoop, rays turning, prizes bobbing). No detail text, no numbers, **no odds**. Opens **by itself on the first board open from the trophy box** (never over the results climb, O67), sets `lbInfoSeen` only then; afterwards only from the i box.
- **Home entry:** the existing trophy box (`homeTrophyRectFor`, `home_screen.dart:154-160`) opens our board (`game.openBoard()`). ~~The old `showLeaderboard` (`flappy_game.dart:4591-4605`) becomes `showPlatformLeaderboards`, reached by the link LB-13 / LB-14 at the bottom.~~ **No visible entry to the native leaderboards (O64):** the link LB-13 / LB-14 is removed on both platforms and `showLeaderboard` loses its UI caller; `submitBestScore` still runs after every counting run and achievement unlocks are still reported. **The Home medal (achievements) box is removed (O63):** `Config.homeAchievementsRectFor`, the `homeMedal*` constants, the medal `MenuIcon` / button and `medalWiggle` in `home_screen.dart:163-178, :322-325` go; the Home top row is gear, trophy box and the coin pill on the right. The trophy's gold glow ring sits on the 38 × 38 box and pulses 2 → 4 pt (O67). No badge on the trophy (O67). Before the first run of a group-day the board shows the "YOUR GROUP STARTS WITH YOUR NEXT RUN" state with PLAY (O67).
- **Results climb (O53):** from run 4 (`gamesPlayed ≥ 4`, `lb_results_min_games` 3), only when the run's submit answered within **4 s** (`lb_results_wait_ms`, F11) with a better rank. Its rows show only the total points today (O62). The board card slides up over the results page (`Sfx.vsWhoosh`), your row climbs (`Sfx.vsTick` per place; 0.55 s for 1 place, 1.1 s for 2–3, 2.3 s for more), then the GoldSticker "YOU CLIMBED N SPOTS!" (`Sfx.vsChime`) and TAP TO CONTINUE. No climb, run ≤ 3 or a late answer → no board; the results page is never held.
- **GO TO COLLECT (O54, O65):** on the next Home visit after the player's group ended with them on **board place 1, 2 or 3** (C2 slot after the streak reward; place 4 or lower: no box and no popup): the final podium (box markers), rows 4–5 ("8h ago" only, no best run, O62), a pink panel (LG-4 / LG-5; ~~+ LG-6 when a ghost finished above you~~ — **no ghost line**, O84), GO TO COLLECT; × = later. Several boxes: one per Home visit, oldest first (O68). Opening: the box master in its tier colour with the pink ribbon drops in, TAP TO OPEN, shakes (`Sfx.skTick`), the lid flies off (`Sfx.pairBoxOpen` + `Sfx.bnPrizeS` / `bnPrizeM` / `bnPrizeBig`), the O41 rays master in the box colour behind it, small confetti, the prize rises, COLLECT (`Sfx.col4Coins`, coins fly into the pill). An item prize plays the approved mystery-box reveal (`item_reveal.html` style A) with EQUIP / LATER.

**LB2 Prize rule and gift table (server, `functions/src/board.ts`; mirrored for tests by `test/fixtures/lb_gifts.json`; never shown to players, O61)**
- ~~At group end: rank the real, non-hidden members; realRank 1 / 2 / 3 → gold / silver / bronze **only if their rank on the full board (ghosts included) is ≤ 10**. Ghosts never take a prize.~~ **Round 23 (O65):** at group end, rank the **full board** (real members and ghosts). **Board place 1 / 2 / 3 → gold / silver / bronze**, only for a real, non-hidden member on that place. A ghost (or a hidden member) on a prize place keeps the place: that box goes to **nobody** and nobody moves up. A real player on place 4 or lower never gets a box. Each group therefore gives **0–3** boxes. Example (`leaderboard_gifts.html` state "A ghost on 2nd · you 3rd · bronze"): LenaFlaps 1st gold, ghost 2nd → silver to nobody, you 3rd bronze, SamSky 4th nothing.
- bronze: coins 25–100 · silver: coins 50–200 · gold, one roll: 50 % coins 100–300 · 20 % golden feather · 20 % puzzle piece · 10 % random unowned **shop** item with price ≤ 750 (common 70 % / rare 30 %; versus-card and skill items excluded). Coins are uniform in the range, step 5. Every gold roll also carries pre-rolled 100–300 coins as the fallback: all eligible items owned → coins; a feather the player cannot take → a puzzle piece; a piece at its limit → the pre-rolled coins (O68).
- The roll is made **on the server at the first claim** (`crypto.randomInt`) and stored; every later claim returns the same result (no re-roll by closing the app). Boxes are free: no purchase, no ad, never sold; the odds are not shown to players (S10, O58, O61).

**LB3 Server (wave 0; `functions/src/board.ts` pure, `board_store.ts` Firestore)**

| Collection (server-only) | Content · TTL |
|---|---|
| `lbPlayers/{uid}` | verified `best`, `bestAt`, `bestShadow`, server-derived `name`, `look`, `card`, `platform`, `bracket`, `groupId` / `groupStart` / `groupEnd`, `rate` (daily count + last 50 run ids), `hist` (last 10 scores), `lastRunAt`, `hidden`, `src` (`import` / `play`), `rankCache`, `expireAt` · **TTL 400 d after the last run** (O57) |
| `lbGroups/{gid}` | `bracket`, `start`, `end`, `memberUids[]` ≤ 50, `members {uid: {t, b, n, last, name, look, card, platform}}`, embedded `ghosts [{runs:[[todSec, score]] …}]`, `ghostUids[]`, `settled` · TTL end + 3 d. One doc per group: one read per board open. |
| `lbOpen/{bracket}_{k}` | the open group per bracket (1 shard at launch, up to 4 at scale) |
| `lbGhostPool/{bracket}_{shard}` (11 × 4) | ghost days of real members, ≤ 200 entries / 900 KB, ≤ 14 d |
| `lbBest/global` (+ `lbBest/hist` from ≈ 20 k players) | top 50 verified, not hidden / shadow; `floor` |
| `lbGifts/{uid}_{gid}` | `tier`, ~~`realRank`~~, `boardRank` (1–3, O65), `rolled`, `claimedAt` · TTL 400 d (O68) |
| `lbTomb/{uid}` | Delete My Data tombstone · 7 d |
| `lbFlags/{uid}_{runId}` | anomaly flags · 60 d |
| `lbMeta/import` | `ranAt`, `count`, `keepUids[]`, `cleanedAt` |

- **Rules:** no new `allow`; the catch-all deny covers every `lb*` collection (header comment extended, "Do not add a rule for them"); `rules.test.ts` proves clients are denied.
- **Indexes / TTL:** composite `lbGroups (settled, end)`, `lbPlayers (hidden, bestShadow, best desc)`; TTL on `expireAt` for `lbPlayers`, `lbGroups`, `lbGifts`, `lbTomb`, `lbFlags`; exemptions for `members`, `ghosts`, `entries`, `rows`.
- **Callables** (`onCall({enforceAppCheck: true})`, Firebase Auth anonymous or linked, `europe-west1`, `maxInstances 10`, refused for a tombstoned uid):
  - `lbSubmitRun {runs[1–10]: {id, score, hoops, cs, endTs, mode, tl?, fl?}, name, look, card, platform, t?}` → `{accepted, dropped [{id, reason}], group {id, end, bracket}, rank {before, after}, board?, gifts?}`. Per run: shape (`score ≤ LB_MAX_SCORE` = `kLeaderboardMaxScore` 32,500,000, mirror test), dedupe, time (no overlap, Σ`cs` ≤ elapsed + 60 s, a run that ended before the current `groupStart` → `old`; it may still raise BEST within 7 d with a timeline), bounds (`passBound`, the `anomaly.ts` score cap), **timeline required when notable** (new personal best, > max(500, 2 × verified best), ≥ the top-50 floor) → `checkRun` + `scoreRun` (F1). Without it the run counts for TODAY clamped to 2 × best (min 500) and never reaches BEST; a hard anomaly → flag + shadow best (owner sees it, others don't); daily cap 400 accepted runs per UTC day. `t: 1` (debug / profile / FS_TESTER / FS_E2E) → `hidden`: never shown, never a ghost, never a prize. Join or create the group in the same transaction (create: start = run start, ≥ now − 6 h; ghosts chosen then).
  - `lbGetBoard {tab}` → rows with an opaque `rid` (no uid, no ghost marker), `me`, `best`, gift stubs; settles the caller's ended group lazily; `lbBest/global` cached 60 s in memory.
  - `lbClaimGift {id}` → `{tier, kind, coins, seed}`; idempotent; another uid's gift is refused.
  - **No `lbReportName`** (O56).
- **Scheduled `lbSettleGroups`** (every 10 min, Etc/UTC): settle ended groups (LB2 prize rule: board places 1–3 only), write each real member's day into a ghost pool shard, record a real #1 for TOP BIRD (approved, O83; reported by the client on its next board read), mark settled; idempotent. This is the 4th Cloud Scheduler job (free tier is 3): ≈ $0.10 a month.
- **Names (L5):** server-derived only — the custom name (`versusNames`, word-filtered) else the generated nickname; never a platform name. `setCustomName`, `releaseGuestName` and the lost-name path also update the lb name.
- **Delete My Data:** `deleteMyData` gets `deleteBoardData` after `clearPurchaseUid`, before the players transaction: tombstone, remove the uid from groups (member and ghost) and the 44 pool docs, delete gifts / flags / player, rebuild `lbBest` if needed; idempotent. The account-switch guest clean-up removes the guest's board day too (accepted, F10).
- **Import** (`functions/scripts/lb_import.ts`, run on prod right after the wave-0 deploy, with the owner's OK): per `players/{uid}` the verified `bestRun` (`checkRun` passes) else the max verified `recent[]` score, else skip — the client-written `best` field is never trusted (F5); writes `lbPlayers` (`src: 'import'`, `expireAt` now + 400 d), rebuilds `lbBest`, writes `lbMeta/import` with `keepUids` (hiesem, hiesemie + testers the owner names). Urgent: `players` docs expire 60 d after their last write.
- **Cleanup — RELEASE-BLOCKING for production (C9, F4):** `functions/scripts/lb_cleanup_test.ts --keep <uids>` (dry run by default) deletes every imported `lbPlayers` not on the keep-list plus their gifts, ghost-pool entries and group rows — **only the new lb collections**; the versus pools keep their test runs (O7). It sets `lbMeta/import.cleanedAt` and prints the remaining top 50 for the owner. `SUBMISSION.md` gets the gate "lbMeta/import.cleanedAt set".
- **Costs:** small (100 DAU) ≈ $0.10 a month; 100 k DAU ≈ $250–300 a month; `minInstances: 1` on `lbSubmitRun` (≈ $3 a month) only if p50 > 2 s in internal testing. The $5 budget alert (O10) stays.

**LB4 Client (Flutter)**
- New `lib/leaderboard/`: `lb_models.dart`; `lb_queue.dart` (`lbQueue`, ≤ 30 runs, flushed oldest first ≤ 10 per call on Home, resume and after each run; dropped after their group-day, best candidates kept 7 d); `lb_service.dart` (`LeaderboardService` + `NoopLeaderboardService` for tests / Linux / soak + `FakeLeaderboardService` + `FirebaseLeaderboardService`, sharing the versus App Check / auth start-up and serialized with it; every call try/caught, 6 s time box); `gift_apply.dart` (resolves the gift locally; the gift id goes into sealed `lbGiftsClaimed` **before** the wallet write; `lbGiftPending` keeps an unshown result across a kill); `lb_config.dart`.
- New `lib/components/leaderboard/`: `board_screen.dart` (three tabs, O63), `board_row.dart`, `podium.dart`, `board_info_sheet.dart`, `results_climb.dart`, `gift_popup.dart`. `lib/components/home/home_screen.dart` + `lib/game/config.dart`: the medal box and its constants removed (O63).
- **Run end** (`flappy_game.dart:4103-4109`, right after `submitBestScore`): `leaderboard.submitRun(...)` only when `countsForAchievements` and `IntegrityGuard.trusted`; `tl` / `fl` from `RunEntry.fromSummary` only when notable and `fitsLimits`.
- Wiring: `lib/main.dart` — the Firebase service on mobile (not soak), Noop otherwise. Delete My Data (`flappy_game.dart:4378-4395`): after `versus.deleteMyData()` succeeds, `leaderboard.resetLocal()`; `resetVersusData` also clears `lbQueue`, `lbGroupId`, `lbGroupEnd`, `lbLastRank`, `lbGiftPending`, `lbGiftsClaimed`, `lbInfoSeen`; the streak keys stay (O57).
- `CoinSource.leaderboardGift`.

**Storage (new):** `lbQueue`, `lbGroupId`, `lbGroupEnd`, `lbLastRank`, `lbGiftsClaimed` (sealed), `lbGiftPending`, + round 22b: `lbInfoSeen` (O60).

**Tuning (baked, `tuning_defaults.dart`, `// §`; no Remote Config — PRD-2.5 forbids downloaded behaviour config):** `lb_results_min_games` 3, `lb_results_wait_ms` 4000, `lb_queue_cap` 30. **Server constants** (`schema.ts`, changed by a functions deploy): `LB_GROUP_SIZE` 50, `LB_GROUP_MS` 24 h, `LB_MIN_LEFT_MS` ~~2 h~~ **3 h** (O66), `LB_OPEN_SHARDS` 1, `LB_PLAYING_NOW_MS` 5 min, `LB_GHOST_MAX_AGE` 14 d, `LB_GHOST_RUNS` 48, `LB_MAX_RUNS_DAY` 400, `LB_OFFLINE_BACKDATE` 6 h, `LB_BEST_SIZE` 50, `LB_MAX_SCORE` 32,500,000, `LB_PLAYER_TTL` 400 d, `LB_GIFT_TTL` 400 d (O68), ~~`LB_PRIZE_MAX_RANK` 10~~ **`LB_PRIZE_PLACES` 3** (O65), `LB_HIST_FROM` ≈ 20,000 players, `LB_GIFTS` (LB2).

**Analytics:** `lb_submit` {accepted, dropped_reason, queued, ms}, `lb_join` {bracket, real, ghosts}, `lb_board_open` {source: home / results, tab, rank, real_count}, `lb_climb` {from, to, shown}, `lb_info_open`, ~~`lb_platform_link`~~ (no link, O64), `lb_achievements_tab` {signed_in} (O63), `lb_gift_shown` {tier}, `lb_gift_collect` {tier, kind, coins, rarity, fallback}. Server (Cloud Logging): `lbSettle` {groups, gifts, gifts_lost_to_ghosts, ghostDays} (gifts per group for the §5 KPI, O65), `lbFlag`.

**Tests:**
- Functions (`npm --prefix functions test`): `board.test.ts` (brackets; join until full / 50 cap; ghost drop on join, own ghost skipped, no uid twice; ±1 / ±2 fill and fewer rows when short; replay by time of day with monotonic totals; never "playing now" on a ghost; tie order; ~~prize by real rank with a ghost at #1 and only within board rank ≤ 10~~ **prize by board place 1–3 only: a ghost on 2nd → silver to nobody and the real player on 3rd still gets bronze; a real player on 4th gets nothing; a ghost on 1st → no gold (O65)**; run bounds and reasons; timeline required when notable; shadow best; gold roll distribution over 20 k seeded rolls ± 1.5 pp; bronze / silver ranges); `board_store.test.ts` (submit → join → settle writes gifts once; lazy settle = scheduled settle; claim idempotent and refused for another uid; Delete My Data removes every lb trace and the tombstone blocks a late submit; name hooks); `lb_import.test.ts` (verified `bestRun` used, forged `best` ignored, keep-list kept by the cleanup, dry run writes nothing); `rules.test.ts` (every `lb*` collection denied); `limits_mirror.test.ts` (`LB_MAX_SCORE` == `kLeaderboardMaxScore`; `lb_gifts.json` == `LB_GIFTS`).
- Dart (`flutter test`): `lb_queue_test`, `lb_submit_rules_test` (debug / god / bot / soak / e2e runs never sent; untrusted guard → not sent; tester builds send `t: 1`; timeline only when notable; PG / GC submit still every run), `results_climb_test` (climb ≥ 1 and game ≥ 4 → board; else or late → none), `board_screen_test` (TODAY default, own row pinned, podium, **boxes only on the podium**, **no BEST n text on any TODAY row / podium / pinned row (O62)**, three tabs with **ACHIEVEMENTS → `showAchievements`** and the board kept on its tab (O63), **no platform link (O64)**, no report action, picture guide auto on first open from the trophy only (`lbInfoSeen`), never over a results climb, + i box, no odds text), `home_screen_test` (no medal box; top row gear + trophy, O63), `gift_apply_test` (credited once across a kill; item → coins fallback; feather / piece limits), `home_moments_test` (GO TO COLLECT after the streak reward), `delete_my_data_test` (lb keys cleared, streak kept), obf-strings / anchor test (new keys).
- Pixel e2e: `release_e2e_test.dart` with `FS_LIVE_VERSUS` and `--no-uninstall` — submit → the board shows the row.

---

## §4 Release plan

**One release, one build (O20).** Everything that was planned for 2.7 and 2.8 ships in 2.6.0.

| Version | Contents | Why together |
|---|---|---|
| **2.6.0** | WP-A; WP-B; WP-C; WP-D (D1–D6 + **all 6 formations** + mix chapters); WP-E (E1–E6 incl. the duel staircase and the pass-based `jump` flag); WP-F (F5, F6, F7, F9 versus-card cosmetics, F10 skill-only cosmetics, F11); WP-G1–G6 (missions, day streak, state-aware notifications, the Levels-screen tabs with worlds map / flight guide / puzzle album, weekly course without a weekly board, Star Road + its Home popup, first-win bonus); WP-H (baked A/B arms, one arm until the install threshold); WP-I; **WP-J** (levels, rewards, 32 emblems); **WP-K** (beat your best); **WP-LB** (our own leaderboard, gift boxes) and the G2 streak restore (round 22) | The owner's decision (O20). Before launch it also means one rule set for every ghost (R1, R2), one fresh level start (J5) and one server deploy. |
| 2.6.x | Tuning only, from internal / closed-test data (§5 decision rules). After the public launch, every curve / gate / points-per-hoop change bumps `fl` (R1). | — |

**Build order in waves** (each wave ends with `flutter analyze` clean, `flutter test` green and `npm --prefix functions test` green; later waves never start on a red tree):

| Wave | Contents | Depends on |
|---|---|---|
| **0 — server + consoles** | Functions + rules in **one deploy, before any app build reaches a device**: brackets rename + `plv` + `players.level` 0–9999 (E4, R3/R4); `look.card` (one `"frame\|name\|sticker"` string) in `schema.ts` `Look` / `validLook` and `firestore.rules` (F9); the `space` flag (SPACE FLYER title) copied into pool entries like `plv` (G4); `versusRate.passHist` + the soft `jump` flag (E6); the reference duel staircase in `matching.ts` + shared fixtures (E5; tests only, not deployed logic); `functions/test/curves.test.ts`. **WP-LB server (O50–O57):** LB3 collections, callables `lbSubmitRun` / `lbGetBoard` / `lbClaimGift`, scheduled `lbSettleGroups`, `deleteMyData` + name hooks, rules comment + tests, the import script. **Deploy order:** (1) `firestore.indexes.json` (wait until the composite indexes are built); (2) rules (comment only); (3) functions (the E4 / F9 / G4 / E6 changes above together with the lb functions; `validCard` is needed for the card field); (4) TTL policies (`functions/scripts/set_ttl.sh`); (5) **`lb_import.ts` on prod** after the owner's OK (C8). Backward compatible: 2.5 clients never call the lb functions. Consoles: the new achievements (J9: BULLSEYE, SKY HIGH, BIRD OF PREY, BIRDWATCHER — approved, O82 / O77 — + the six round-23 versus / board achievements, approved O83) in Play Console and Game Center (drafts; the owner publishes), GA4 / BigQuery settings (EU, 14 months) and the A4 dimensions (O10, O43). No weekly leaderboard (O30). | §7 approvals C1–C3, C8. |
| **1 — run core** | WP-A events + bucket helpers; WP-D curve, tilt / Δy, hazard budget, calm, headline window, **all 6 formations**, mix chapters; WP-C gates; WP-B showcase as planner step 0. | — |
| **2 — progression model** | WP-J model, storage, reward roll, payout; `bestHoops`, `recentScores`; WP-E client (brackets, `plv`, E5 duel staircase); WP-K; WP-F F5 / F6 / F7 / F11; WP-H arm plumbing (`abArm_v1`, `fs_arm`; one arm); WP-LB client model (`lib/leaderboard/`: service, queue, submit at run end, `gift_apply`; no UI yet). | Wave 0 deploy (brackets, `plv`, lb functions). |
| **3 — daily meta** | WP-G1 missions, G2 day streak (no freezes) + the STREAK LOST restore popup (`AdPlacement.streakRestore`), G3 state-aware notifications; popup budget (C2) extended with STREAK LOST, streak reward, GO TO COLLECT + gift opening, missions chest and the Star Road popup slot. | `bestHoops` (wave 2); §7 texts T5–T7, designs D5–D6. |
| **4 — long-term layer** | WP-LB board screen (tabs, podium, rows with the F9 painters, picture guide) and the results climb; Levels-screen tabs (O29) with G4 worlds map, flight guide and puzzle album; G5 weekly course (no board); F9 versus-card cosmetics (51) + the fixed shop header (O79); F10 skill-only cosmetics (24, O80) + HOW TO EARN sheet + new achievements; Home without the medal box (O63); G6 extras incl. Star Road + popup (O23). | Wave 0 (`look.card`, `space` flag, achievement ids); §7 designs D7–D11d, D14, texts T8–T10, T12. |
| **5 — art, polish, docs** | Emblem PNGs (32), cosmetic art (51 card items + 24 skill items, all vector), achievement icons (4 + 6 new, O83), goldens, WP-I docs, full Pixel e2e. | All art approvals in §7. |

The G6 extras are built last in wave 4; all four ship in 2.6 (O23). Every wave builds and tests the iOS side too (CI compile), per O27.

**Rollout:**
1. Wave 0: the functions + rules deploy goes first. It is backward compatible with 2.5 clients. Approved in full (Q3, O27).
2. 2.6 to Play **internal only** (Android; owner O19 — no TestFlight / iOS build for 2.6, iOS later).
3. The owner plays a fresh install and an upgraded 2.5 install on the Pixel (`--no-uninstall` rule for e2e): fresh level start, coins and items kept, missions / streak / weekly course reachable.
4. Fix.
5. Closed testing (no pool purge, no board reset: O4, O7).
6. **Before production (release-blocking, round 22):** run the test-player cleanup `lb_cleanup_test.ts` and check `lbMeta/import.cleanedAt` (C9); publish the privacy-policy update (PV-10) and update Play Data safety / App Store privacy (C5, O57).
7. Production: the owner presses publish.

---

## §5 Measurement plan

Sources: GA4 + BigQuery daily export, GA4 retention 14 months, Google signals off, $5 budget alert (O10; the orchestrator sets these up in the console when the owner is signed in). Medians come from BigQuery, or from the bucket at which the cumulative share passes 50 % in GA4.

| KPI | Target | Decision rule (if missed → tune) |
|---|---|---|
| Highlight 1 seen in run 1 | ≥ 80 % (≥ 95 % by A = 3) | If below 80 %: portal at A = 1 → hoop 5 |
| Median hoops, run 1 / runs 1–3 | 15–25 (P25 ≥ 8) | Below 12: opening +4 pt on hoops 0–20 of `curve_opening` (applies to everyone, R2). Above 35: no action. |
| Run 2 start / run 4 start | ≥ 85 % / ≥ 65 % | If run 4 trails run 2 by more than 15 pp: check `run_fail` for runs 1–3 and saw deaths at game 4 |
| Showcase done | ≥ 70 % of installs | — |
| Deaths at first meet of saw / squeeze | ≤ 40 % | Above: that element's from-hoop +5 or its hazard cost +0.5 |
| Any element's share of deaths, games 4–20 | ≤ 25 % | Above: lower its weight or raise its from-hoop by 5 |
| Median hoops, games 10–19 | 30–50 | Below 30: `curve_opening` +3 pt from hoop 20–60. Above 60: `hazard_budget` +0.5 from 25 |
| Death rate per hoop (games ≥ 6) | ≤ 3 % at 20–40, ≤ 2 % at 40–150 | Find the hoop band in `run_fail`; ease that band's keyframe |
| Top 5 % best (day 30) / P99 best | ≥ 150 / ≥ 200 hoops | Below: opening floor 70 → 72 |
| Top-quartile perfect rate at 100–150 | ≥ 35 % | Below 25 %: band floor ±10 → ±11 |
| Level at end of day 0 (median) | 4–7 (first guess; no data yet) | Below 3: lower `level_points` 2–5. Above 9: raise 6–10. Re-baked in 2.6.x |
| Level-up in run 1 / by run 3 | ≥ 70 % / ≥ 90 % | Below: `level_points[1]` 25 → 15 |
| Time to level 10 / 20 (median, active players) | about day 3 / about day 14 | Outside by > 2×: scale `level_points` 10–30 |
| Level reward EQUIP rate | ≥ 30 % | Below: review the J4 item mix with the owner |
| Beat-your-best moment per Free Fly run | 10–25 % of runs | Below 5 %: no action (skill); above 40 %: check `bestRunHoops` saving |
| Interstitials per non-payer hour | monitor (cadence unchanged, O2) | — |
| D1 / D7 / D30 | ≥ 35 / 12 / 4 % | Compare by `fs_level` / `fs_gb`; A/B only once WP-H has ≥ 1,500 installs per arm |
| Coins per hoop / per session-minute (play only) | 1.6–2.0 / 45–75 | Outside: `coin_*` review (budget test first) |
| First shop purchase by game 15 | ≥ 40 % | Below: review common prices against level coins |
| Versus solo share / first-10-duel win rate | < 20 % / 55–70 % | Solo high: cross-bracket search earlier (`MatchTier.any`). Win rate off: tune the staircase (E5) |
| Runs per session | ≥ 4 | — |
| Missions: ≥ 1 done per active day / all 3 done | ≥ 60 % / ≥ 25 % | Outside: retune the tier targets (G1) |
| Day streak ≥ 7 among D7-retained players | ≥ 30 % | Below: check the streak-at-risk notification (G3) |
| Leaderboard: board opens per active day / results climbs shown per run (from run 4) | ≥ 0.5 / 10–30 % | Low opens: check the trophy entry and the climb; climbs far above 30 %: groups too weak (bracket mix) |
| Leaderboard: real players per group (median) | monitor (expect 1–3 at launch) | When most groups reach ≥ 10 real players, review the gift ranges (§6) |
| Leaderboard: gift boxes per group / boxes lost to ghosts on places 1–3 (`lbSettle`, round 23) | monitor (0–3 per group; expect many lost to ghosts at launch, O65) | If real players in thin brackets almost never reach the podium, report it to the owner (the places-1–3 rule is the owner's, O65; the ghost supply and the gift ranges are the levers) |
| Streak restore: share of STREAK LOST popups restored / ad-fail share | monitor / ≤ 10 % | Ad-fail high: check fill and the retry |
| Weekly course: share of eligible players who run it | ≥ 25 % | Below: make the missions-panel card / results line more visible (O26) |

**Dashboards:**
1. FTUE funnel on `ftue_step.name`.
2. A `run_fail` table hb × elem × motion × outcome, filtered by gb / mode.
3. Run-1 and games-≥ 6 survival curves (BigQuery).
4. Retention cohorts by `fs_level` / `fs_gb`.
5. Economy: earned / spent / bought per day; level coins vs play coins.
6. Levels: level reached by day, fallback share in `level_reward_claimed`.

**Sample sizes:**
- A run-1 median that moves from about 5 to 15 hoops is visible with about 100 installs.
- D1 35 → 40 % needs about 1,500 installs per arm; D7 12 → 15 % needs about 2,000 per arm.
- Until then, decide on in-run metrics and before/after release comparisons.

**Owner baseline (not a cohort):** 13 runs. Runs end in two groups (6 at hoops 2–8, 7 at 18–133). Best 133 hoops; perfect rate 45–62 % overall and 20–29 % past hoop 60. 8 of 13 deaths came one hoop interval after the last pass.

---

## §6 Risks

| Risk | Mitigation |
|---|---|
| 2.6 is large (L+L+L+M+M) and much of the run core is in `run_director.dart` | Planner order is fixed (showcase step 0 → debug force → first-meet → budget / calm filters → squeeze gate). The critical path in §4. Levels are a separate module (`lib/levels/`). |
| Showcase runs with a safety net go into the versus pools (O6) | They are short and land in the lowest best-score brackets (R2). The safety net is Big Hoops + shield at start + one free revive. Accepted by the owner. |
| 2.5 ghosts in the pools were recorded on the old curve (R1) | Test data only; no public player affected; `fl` bumps from launch on. |
| The softer ceiling is too easy for top players | Formations and mix chapters; post-launch tuning (opening floor and budget keys); the leaderboard is still separated by the uncapped streak. |
| Aligned tilts reduce reading challenge | Random sign ≤ 15° stays; 45° share 25 %; formations add patterns. |
| Calm stretches feel dull | Fun pickups are preferred in calm gaps; rides count as calm. |
| The dropped surplus feels unfair after a great run | Early levels are small (25–200); the bar restarts empty with the LEVEL UP celebration; level-up per run is the KPI. |
| Fresh level start annoys 2.5 testers | Coins, items and achievements are kept; only testers have 2.5 levels (owner decision). |
| The 31 emblems are late (art L) | J13: an internal build can map the 10 painted emblems; production waits for the art. |
| Level items run out for collectors | J4 fallbacks end in coins at shop price; ETERNAL WING levels pay only the coins when nothing is left. |
| Rank achievement names now differ from level names (PHOENIX is both a score achievement and level 29) | R5 keeps the console unchanged (owner chose this, Q1 2026-10-21). |
| Thin pools at launch | The test runs stay (O7); the honest solo line (T4); cross-bracket fallback (existing `MatchTier.any`). |
| **Scope: all of 2.7 + 2.8 in one 2.6 build (O20)** — long build, late art, many unapproved designs and texts, one big test surface | Waves with a green gate after each (§4); server deploy first; designs and texts collected up front in §7 so no wave waits on the owner mid-build; G6 could-items last; production waits only on ship-blocking items. |
| Round 21 grew the scope: 51 versus-card items + 18 skill items (all animated vector art), the Levels-screen tabs, the Star Road popup and up to 4 new achievements; round 23 adds 6 skill items (24 in total), the HOW TO EARN sheet, the fixed shop header and up to 6 more achievements | One painter library shared by shop, VS intro and versus bar; tabs reuse the approved levels header / list; G6 extras and the art stay last (waves 4–5); every item has an approved mockup to copy from. |
| The weekly course flips at Monday 00:00 UTC, which is not local midnight (e.g. 01:00/02:00 in the EU, Sunday evening in the Americas), while missions and the streak use local days | Countdowns always show the real time left ("LAST DAY" < 24 h); `weekly_week_test` covers several time zones; one reset moment for seed, texts and rewards. |
| Achievement points near the cap (895 of 1,000 with the four approved new achievements; **965** with the six round-23 achievements, approved O83) | Leaves 105 (or 35) points for later updates; fallback all six at 10 points → 955; the console catalogue test checks the sum. |
| Clock rollback for missions / streak | Refresh only when `today > lastDay`; small rewards. |
| **Small player base for our leaderboard (round 22, revised round 23):** most groups have 1–3 real players and many ghosts. ~~Nearly every active player gets a box most days~~ Since O65 only board places 1–3 win, and ghosts (real players' earlier days) often hold podium places, so early players in quiet brackets may **rarely win a box**; fewer boxes also means a lower gift budget. Thin ghost supply in high brackets | Owner rule (O65), accepted; the podium still shows three markers so ghosts are never revealed; watch boxes per group and boxes lost to ghosts (§5 KPI, `lbSettle`); gift boxes counted as meta in the budget test (F12, upper bound); ranges are server constants; neighbour brackets then fewer rows, never invented players (O51) |
| **No name reporting on public boards (O56):** Apple 1.2 / Play UGC reviewers may expect a report or block path for names shown to other players | Names are never free text: the fixed word spinner + the existing word filter; mention it in the review notes (S7); a report path can be added in 2.6.x if a reviewer asks |
| Imported test players reach production on the BEST RUN tab | Release-blocking cleanup C9 + `SUBMISSION.md` gate (`cleanedAt`); keep-list of the owner's uids |
| Cold start of the callables misses the 4 s results window | The climb is skipped, never waited for; `minInstances: 1` on `lbSubmitRun` if p50 > 2 s |
| Forged score-only runs on a modified client | Time bounds, `passBound`, timeline for notable runs, integrity guard, App Check; BEST RUN only from verified timelines |
| Leaderboard data kept longer than the old "60 days / used only for the race" privacy wording | 400-day TTL + PV-10 policy text + store privacy forms before production (O57) |
| Only 13 real runs behind every number | Every value is baked and owned by a test, so retuning is a one-line change plus a release. The analytics ship in the same build. |

---

## §7 Owner approvals needed before / during the build

The rules and numbers in this PRD were confirmed in the owner's review (round 4, 2026-10-21). This list covers designs, player-facing texts and console / store actions. **Round 21 (2026-10-22):** the owner reviewed every page in `design/approvals_v26/` (index: `design/approvals_v26/index.html`); the designers applied the notes, and the answers are decisions O29–O45. **Round 22 (2026-10-22):** streak restore and our own leaderboard, decisions O46–O58; new pages `leaderboard.html` and `leaderboard_gifts.html`, `day_streak.html` updated. **Round 23 (2026-10-23):** the owner's second review of 13 pages, decisions O62–O82; the notes are applied in the pages (tagged "UPDATED · ROUND 23"). **Round 24 (2026-10-23):** every open question approved as recommended plus four design notes, decisions O83–O87 (tagged "UPDATED · ROUND 24"). **Round 25 (2026-10-23):** Q32 approved and three design notes, decisions O88–O91 (tagged "UPDATED · ROUND 25"). "Blocks" says what may not be built or shipped until the item is approved: **build** = the builder needs it before coding that part; **ship** = code can be built with placeholders, but 2.6 cannot go to Play internal without it; **no** = can follow later. "Changes applied" = the owner's notes are in the page; only a final look is left.

### 7.1 Designs (screens, UI elements, stickers, icons, art)

| # | What | Where | Source | Status / blocks |
|---|---|---|---|---|
| D1 | 32 level emblems (31 + ETERNAL WING #32) | J6 | `design/levels_v26/emblems.html` | **Approved.** |
| D2 | Emblem PNG export check (@1x/2x/3x vs the mockup, bird placement, idle layers) | J6 production | to be exported | Owner checks the exports · blocks **ship** |
| D3 | Results-page item reveal (mystery box, EQUIP / LATER) | J7a | `design/levels_v26/item_reveal.html` | **Approved.** Round 21: the rays get the O41 polish (longer, transparent radial fade, slow turn, behind the item). |
| D4 | Levels screen (final, incl. ETERNAL WING row, carousel) | J7 | `design/levels_v26/levels_screen.html` | **Approved.** Beat-your-best line + flag (WP-K, `beat_your_best.html`) **approved.** |
| D5 | Missions UI: strip under START, pips on results, panel (no explanation lines, **no difficulty labels on the rows**), chest row **"ALL 3 DONE"** (O71), chest opening on Home (gold box, rays, confetti, sound), swap | G1 | `design/approvals_v26/missions.html` | **Approved (O92, 2026-10-23).** All questions decided (O32, O71); round-23 changes applied (chest row, Home without medal) · ~~final OK pending~~ · blocks **build** of G1 UI |
| D6 | Day streak UI: drawn animated flame chip, 7-day track 1–7, COLLECT popup with the Big Hoops / shield fly-in (no freezes, O46) | G2 | `design/approvals_v26/day_streak.html` | **Approved (O92, 2026-10-23).** Decided (O33, O46, O74); freeze parts removed in round 22; Home without medal (round 23) · ~~final OK pending~~ · blocks **build** of G2 UI |
| D7 | Worlds map as the **WORLDS tab** of the Levels screen (O29): locked = grey + number + lock, names hidden until next, own colours per world, SPACE FLYER title only, no stars; no Home tile; no in-run sticker (O22) | G4 | `design/approvals_v26/worlds_map.html` (in `levels_tabs.html`) | **Approved (O92, 2026-10-23).** Decided (O34); round 24: worlds run **1 → 10 top to bottom** (O87) · ~~final OK pending~~ · blocks **build** of G4 UI |
| D8 | Weekly course: the card at the top of the missions panel (▶ PLAY, no rank), mission rows without difficulty labels, the once-a-day results line, the weekly results (tiers only, **no level line**, O76; trophy box → our board), NEW WEEK BEST! | G5 | `design/approvals_v26/weekly_course.html` | **Approved (O92, 2026-10-23).** Decided (O30, O32, O76); round-23 changes applied · no open questions · ~~final OK pending~~ · blocks **build** of G5 UI |
| D9 | Versus-card cosmetics: CARDS shop tab (FRAMES / NAMES / STICKERS, **fixed header**, O79), VS intro with the small sticker, versus bar with animated name styles, art for **51 items** (17 per kind; 6 × 250, 5 × 750, 4 × 2,000, 2 × 5,000) + **9 skill items** (3 frames + 3 name styles + 3 stickers, O80) with the **HOW TO EARN** sheet | F9 | `design/approvals_v26/versus_cards.html` | **Approved (O92, 2026-10-23).** Tab, layout, the 24 first items and pricing rule **approved** (O38); Q14 / Q15 decided (O82); the 27 new items, the 9 skill items (6 new in round 23; the sample opponent "Storm" shows them) and the fixed header ~~need the owner's look~~; Q30 decided (O83); round 24: skill card items show **"? ? ?"** (O85), **Thunderstruck restyled** (O86) · ~~open **Q32**~~ · tab blocks **build**, item art blocks **ship** |
| D10 | Skill-only cosmetics: **24 items** (3 per shop kind + 9 versus-card items), LEGENDARY gold, locked / secret "? ? ?" tile, HOW TO EARN sheet, gold reveal | F10 | `design/approvals_v26/skill_cosmetics.html` | **Approved (O92, 2026-10-23).** Concept, gold, secret tiles, counters, reveal order **approved** (O39); no 2.5 grant and PROUD PEACOCK counts the card items (O81); points decided (O82); the new items and the reworked Steel Spikes / Legend Ring ~~need the owner's look~~; round 24: the card items there are secret too and Thunderstruck uses the new look (O85, O86) · ~~Q32 (the other 18 secret too?) sits on `versus_cards.html`~~ round 25: every skill tile is secret (Q32 → O88), applied · blocks **ship** |
| D11a | First-versus-win-of-the-day +20 on the versus results | G6 | `design/approvals_v26/first_win_of_day.html` | **Approved: style A** (O40). |
| D11b | Puzzle album as the **ALBUM tab** (starts empty, pieces held at the update kept, one EPIC item for the first full album, ×n laps, rays behind) | G6 | `design/approvals_v26/puzzle_album.html` | **Approved (O92, 2026-10-23).** Decided (O36, O78); tabs under the title (O69) · ~~final OK pending~~ · blocks **build** of it |
| D11c | Flight guide as the **GUIDE tab** (all 32, silhouettes, gold tab dot, BIRDWATCHER progress) | G6 | `design/approvals_v26/flight_guide.html` | **Approved (O92, 2026-10-23).** Decided (O35; BIRDWATCHER 25 points, O77); tabs under the title (O69); FG-E rows win (Q16 → O83) · ~~final OK pending~~ · blocks **build** of it |
| D11d | Star Road: track screen (25 tiers, **season-name** header, item tiers "MYSTERY" without a rarity word), missions-panel card (+ one-line 568 pt variant, rows without difficulty labels), tier-claim moment, **Home popup with GO TO STAR ROAD** (at most once a day) | G6 | `design/approvals_v26/star_road.html`, `star_road_popup.html` | **Approved (O92, 2026-10-23).** Rules **approved** (O37, O75); popup cadence decided (O75) · ~~final OK pending~~; season names approved and the rarity chip kept in the reveal (Q27, Q28 → O83); round 25: popup motion, confetti and sound polished to match the other reward popups (O91) · blocks **build** of it |
| D13 | ~~Weekly leaderboard icon~~ | G5 | — | **Dropped** (no weekly board, O30). |
| D14 | Levels screen tab bar LEVELS · WORLDS · GUIDE · ALBUM **under the title, text only** (O69; default LEVELS, gold tab dots) + the gold **NEW** tag on the Home level emblem (O70) | G4, G6 | `design/approvals_v26/levels_tabs.html` | **Approved (O92, 2026-10-23).** Asked for by the owner (O29, O69, O70); round-23 layout applied (also on a 320 × 568 frame); NEW-tag rules approved (Q26 → O83); round 24: WORLDS order 1 → 10 (O87), the grey mystery box on locked level rows drawn at full size again (mockup style fix) · ~~final OK pending~~ · blocks **build** of the tabs |
| D16 | **STREAK LOST popup**: old streak → 0, RESTORE ▶ / RESTORE · 500 / grey / LOADING VIDEO / TRY AGAIN, GIVE UP, restore and give-up moments, C2 order; also for a 1-day streak; **§4b which streak RESTORE brings back** (the last streak only, cases A / B / C) | G2 | `design/approvals_v26/day_streak.html` §4–§5 | **Approved (O92, 2026-10-23).** New in round 22 (O47–O49); Q17–Q19 decided in round 23 (O72–O74) · ~~final OK pending~~ · no open questions · blocks **build** of the restore |
| D17 | **Our leaderboard**: tabs **TODAY / BEST RUN / ACHIEVEMENTS** (native hand-off, O63; no icon, O89), timer, podium with box markers, rows with frame + name style and **only the total points on TODAY** (O62), pinned own row, no-group state, **4-step picture guide** (i box + first open; TOP THE BOARD, Flappy Spikes trophy, O67), Home trophy entry (no medal box, no badge), results climb; **no native-leaderboard link** (O64) | WP-LB | `design/approvals_v26/leaderboard.html` (new §6: the ACHIEVEMENTS tab next to the native screen) | **Approved (O92, 2026-10-23).** New in round 22 (O50–O56); Q22–Q24 and the guide-trigger question decided in round 23 (O66, O67) · ~~owner look pending~~; signed-out ACHIEVEMENTS tab decided (Q29 → O83); round 25: tab icon removed (O89), FLY AND SCORE picture shows full-bleed spike strips (O90) · blocks **build** of the board UI |
| D18 | **Leaderboard gift boxes**: GO TO COLLECT popup (podium markers, your panel, rows without the best run), box opening per tier and prize; prize = **board places 1–3 only** (O65; state "A ghost on 2nd · you 3rd · bronze"); the odds table is owner-facing only (O61) | WP-LB | `design/approvals_v26/leaderboard_gifts.html` | **Approved (O92, 2026-10-23).** New in round 22 (O54); places-1–3 rule applied (O65); Q20 / Q21 decided (O68) · ~~owner look pending~~; ghost line LG-6 dropped (Q31 → O84) · blocks **build** of the gift UI |
| D15 | Icons for the new achievements (17C spike-ring style): BULLSEYE, SKY HIGH, BIRD OF PREY, BIRDWATCHER (bird with binoculars, O77) + SECOND WIND, ALBATROSS, THREE LITTLE BIRDS, IRON BEAK, FLAWLESS, TOP BIRD (approved, O83) | J9 | `design/approvals_v26/achievement_icons.html` (art `design/achievements/ach_art_v26.js`) | **Approved (O96, 2026-10-23)**, A variants; Sol exports the PNGs in wave 5 · ~~Opus 5.5 approval page first (O94), owner notes, then Sol exports in the build · blocks **ship** (consoles need them)~~ |

### 7.2 Player-facing texts

All rows live in `design/approvals_v26/texts.html` (round-21 changes are marked there).

| # | What | Where | Source | Status / blocks |
|---|---|---|---|---|
| T1 | 31 level names + ETERNAL WING | J1, J2 | in PRD | **Approved** (decisions). |
| T2 | Reveal / levels-screen / beat-your-best copy ("NEW ITEM · ADDED TO YOUR HATS / TRAILS / GEAR / HOOPS / BIRDS", EQUIP / LATER, "10 000 PTS EACH", "N TO <name>", "N TO LEVEL 35", "BEST 42", "NEW BEST!") | J7, J7a, WP-K | in the approved mockups / PRD | **Approved** with D3/D4; fixed category words and "BEST 42" (no colon) decided (O31). |
| T3 | ~~Achievement group label "RANKS" → "SCORE"~~ | J9 | — | **Dropped** (O31: the consoles cannot group achievements). |
| T4 | Empty-pool line "No rival yet – your run can become a rival for others" | E3 | owner wording | **Approved** (O31). |
| T5 | Mission names / descriptions for every template × tier (T0–T3), "MISSIONS", "NEW IN 5 H 12 M", chest row ~~"ALL 3 DONE → BONUS CHEST"~~ **"ALL 3 DONE"** (O71), chest name, swap copy; no EASY / MEDIUM / HARD labels on rows (O71) | G1 | `texts.html` §1 | **Approved (O93, 2026-10-23).** Rules decided (O32, O71); chest name **BONUS CHEST** (Q4 → O83); ~~rows to approve~~ · blocks **build** of G1 |
| T6 | Streak texts: tile labels 1–7, drawn flame chip + n; freeze rows struck (O46); STREAK LOST popup S-24 (now the popup title), **S-28–S-40**, + round 23: **singular forms** for a 1-day streak (S-28b–S-30b, O72) | G2 | `texts.html` §2 | **Approved (O93, 2026-10-23).** Decided (O33, O46–O49, O72–O74); ~~rows to approve~~ · blocks **build** of G2 |
| T7 | State-aware notification texts N1–N7 (N8 dropped) + the fixed reminders #2 / #13 / #16 / #17 | G3, C3 | `texts.html` §3 | **Approved (O93, 2026-10-23).** Fixes **approved** (O42); N6 counts to Monday 00:00 UTC; ~~rows to approve~~ · blocks **build** of G3 |
| T8 | World names (existing scene names), taglines, the tab label "WORLDS", header lines, "SPACE FLYER" | G4 | `texts.html` §5 | **Approved (O93, 2026-10-23).** SPACE FLYER **approved** (O34); card stars and "REACH HOOP n" dropped; ~~rows to approve~~ · blocks **build** of G4 |
| T9 | Weekly course texts: the panel card ("WEEKLY COURSE · 3 DAYS LEFT · BEST HOOP 34 · ▶ PLAY"), the results line ("Try this week's course → beat hoop 34", O26), rules line, reward tiers, "NEW WEEK BEST!" (no board name, no WEEKLY 120 sticker); round 23: no level line on the weekly results, no difficulty labels (O76) | G5 | `texts.html` §4 | **Approved (O93, 2026-10-23).** Decided (O30, O32, O42, O76); ~~rows to approve~~ · blocks **build** of G5 |
| T10 | Item names: **51 versus-card items + 9 skill card items** (`versus_cards.html`: 3 frames + round 23 Skywriter, Thunderstruck, Headliner, Unstoppable, Flawless, Top of the Flock), **24 skill items** (`skill_cosmetics.html`), "NAME STYLE" sub-label, chip "LEGENDARY", the unlock line ("Unlocked by: <achievement>"), the secret line "UNLOCK: ? A SECRET ACHIEVEMENT ?", the **HOW TO EARN** sheet and stage-strip strings, ~~goal pills~~ (dropped, O88), new achievement names / descriptions (6 more, approved O83: ACH-53–ACH-58); round 24: skill card items always use the secret lines (CO-6, CO-17, CO-18, CO-20 struck, O85); round 25: every skill item does (O88): goal pills and the goal / progress forms dropped, CO-14 → "SKILL ONLY · SECRET", CO-15 → "ACHIEVEMENT: ? ? ?" | F9, F10, J9 | design pages + `texts.html` §9 | **Approved (O93, 2026-10-23).** First 24 card names and the 6 new achievements approved; ~~new item names to approve with their art~~ (CO-8 "Top of the Flock" 16 checked: tiles carry no names, fits the stage) · blocks **ship** |
| T12 | G6 texts: first-win line "+20 FIRST WIN TODAY", puzzle album, flight guide (32 rule lines incl. 6 portal themes), Star Road tier, season, card and popup texts (round 23: **13 season names** SR-SN1–SR-SN13, "MYSTERY" tile labels, no difficulty labels), Levels tab labels (text only, O69) | G6 | `texts.html` §6–§7 | **Approved (O93, 2026-10-23).** FW-1 style A approved (O40); season names SR-SN1–SR-SN13 **approved** (O83); ~~the rest to approve~~ · blocks **build** of each |
| T13 | 2.6 "What's new" release notes (Play) | §4 | `texts.html` §10 | **Marketing agent writes it (O93)**, with the store / website copy; must name the daily leaderboard + gift boxes and the optional streak-restore video (S7); owner approves · Updated for the dropped weekly board; **needs a line for the daily leaderboard + gift boxes and the streak restore (round 22)**; to approve · blocks **ship** |
| T14 | Privacy policy / Terms: GA4 user properties incl. `fs_arm`, BigQuery export (**EU multi-region, 14 months**, O43), `plv` / `look.card` / `space` in Firestore. No weekly board scores any more (O30). **Round 22: PV-10** in-game leaderboard paragraph (scores, names, avatars, card style and last-played time visible to others; ghost replays ≤ 14 days; deleted after 400 days without play or with Delete my data) and an edit of the "used only for the race" / 60-day lines. | A3, O10, E4, F9, G4, WP-LB | `texts.html` §11 | **Approved (O95);** website deploy on the day 2.6 goes to Play internal (owner OK on the day) · PV-6 decided (O43); ~~rest to approve~~ · blocks **ship** if a change is needed |
| T16 | Leaderboard and gift-box texts: LB-01–LB-21 (board, tabs, tags, climb, no-group state), **LB-36–LB-39** (picture-guide captions FLY AND SCORE / ~~CLIMB YOUR GROUP~~ **TOP THE BOARD** (O67) / WIN GIFT BOXES / BEAT THE RECORDS; the guide reuses LB-01 and LB-17) and LG-1–LG-15 (GO TO COLLECT, opening, prize lines). **Round 22b:** LB-22–LB-35 (text info sheet) and LG-16 (odds line) dropped (O59, O61); LG-7 dropped earlier. **Round 23:** the TODAY "BEST n" sub-line removed (O62), the native-board link LB-13 / LB-14 removed (O64), new tab label **LB-40 ACHIEVEMENTS** (O63), GO TO COLLECT rows "8h ago" only. **Round 24:** LG-6 dropped (O84); LB-40 signed-out behaviour decided (O83). **Round 25:** LB-40 is the plain word ACHIEVEMENTS, no ↗ (O89) | WP-LB | `texts.html` §12 | **Approved (O93, 2026-10-23).** New in round 22; ~~rows to approve~~ · blocks **build** of WP-LB UI |
| T15 | Store full description + website "Birds & ranks" text still say "Climb 10 ranks From Egg to Legend" | store, website | draft note only (O44) | A marketing agent drafts and updates them later; the owner approves before anything is published · blocks the **production** listing, not internal |

### 7.3 Console / store / cloud actions

| # | What | Where | Status / blocks |
|---|---|---|---|
| C1 | Functions + rules deploy: R3/R4 (Q3) + `look.card` validation (one `"frame\|name\|sticker"` string, F9) + the `space` flag copied into pool entries (G4) + `passHist` / soft `jump` flag (E6), one deploy | E4, E6, F9, G4, §4 wave 0 | **Approved** (O27); the `space` flag is new in round 21 (same pattern as `plv`) · wave 0 |
| C2 | ~~Create the recurring weekly leaderboard in Play Games Services and Game Center~~ | G5 | **Dropped** (O30). |
| C3 | GA4 / BigQuery: daily export (**EU multi-region**), retention 14 months (BigQuery table expiry ≈ 425 days), Google signals off, $5 budget alert, A4 custom dimensions + metrics (incl. `fs_level`, `fs_arm`) | A4, O10, O43 | **Approved** (O10, O43); the orchestrator does it when the owner is signed in · blocks **ship** (data from day one) |
| C4 | New rewarded-ad placements: mission reroll and **streak restore** (round 22, O48), both via the **existing AdMob rewarded units on Android and iOS**; ad timing otherwise unchanged (O2) | G1, G2 | Reroll **approved** (O27); streak restore decided by the owner (O48) |
| C5 | Re-check Play **Data safety** and Apple **App Privacy** against T14; update where needed (O27). **Round 22:** names, avatars and scores are shown to other users on public leaderboards (purpose "App functionality"; visible to others: yes) | T14, WP-LB | **Approved** (O27, O57) · blocks **production** |
| C6 | Achievements: the 48 existing ones unchanged (R5, Q1); no leaderboard reset (O4). **New:** create BULLSEYE, SKY HIGH, BIRD OF PREY and BIRDWATCHER (+ the six round-23 achievements SECOND WIND, ALBATROSS, THREE LITTLE BIRDS, IRON BEAK, FLAWLESS, TOP BIRD, approved O83) in Play Console and Game Center as drafts with D15 icons; the owner publishes | J9 | The four approved with their points (O39, O77, O82); the six round-23 ones approved too (O83) · blocks **ship** (ids go in code) |
| C7 | Release to Play internal / closed / production: the owner presses publish | §4 | per release step |
| C8 | WP-LB server deploy in wave 0 (indexes → rules comment → functions → TTL policies, §4) and the one-time **import of verified best runs** into the new collections on the live project (owner's OK on the day) | WP-LB, §4 wave 0 | Feature decided (O50, O52); covered by O27's "bigger functions + rules deploy": **yes** (Q25 → O83); import only after the owner's OK on the day · wave 0 |
| C9 | **Remove the generated test players from our leaderboard** (`lb_cleanup_test.ts --keep <owner uids>`, only the lb collections) and check `lbMeta/import.cleanedAt` | WP-LB | Decided (O52, F4) · **RELEASE-BLOCKING for production**, not for internal / closed |

### 7.4 Product questions

Round 6: P1 → O21 (shop items only), P2 → O22 (no sticker), P3 → O23 (all four extras ship). Round 21 (2026-10-22): the 16 texts-page questions are decided (O29–O44). Round 22: Q6 / Q7 are dropped with the freezes (O46); the server-analysis questions Q-L1–Q-L3 are decided (O54, O50, O52). **Round 23 (2026-10-23):** Q5, Q8–Q15 and Q17–Q24 are decided (O66–O82; struck below with the answer). ~~**Still open** … **Q4, Q16, Q25, Q26–Q31**~~ **Round 24 (2026-10-23):** all of them are decided as recommended (O83; Q31 → O84), struck below. ~~**Still open:** **Q32** (round 24; also on `texts.html` "OPEN QUESTIONS (round 24)" and `versus_cards.html`).~~ **Round 25 (2026-10-23):** Q32 decided as recommended (O88). **No open questions.**

| # | Question | Recommended |
|---|---|---|
| ~~Q4~~ | ~~Chest name: **BONUS CHEST** (approved mockups, release notes) or DAILY CHEST (old M-RS-4)?~~ | **Decided (round 24, O83):** BONUS CHEST everywhere).** |
| ~~Q5~~ | ~~Should Home also show a dot when a Levels tab has a gold dot?~~ | **Decided (O70):** yes, as the gold **NEW** tag on the Home level emblem (against the recommendation "no"). Its rules: Q26. |
| ~~Q6~~ | ~~Two missed days while holding 2 freezes~~ | **Dropped** (no freezes, O46). |
| ~~Q7~~ | ~~Day 7 while already holding 2 freezes~~ | **Dropped** (O46). |
| ~~Q8~~ | ~~Puzzle album: do pieces already held for the picture in progress at the 2.6 update count toward it?~~ | **Decided (O78):** yes. |
| ~~Q9~~ | ~~Star Road season names: plain "SEASON 4" or themed per world?~~ | **Decided (O75):** themed and creative, not plain and not per world; the list is Q27. |
| ~~Q10~~ | ~~Star Road popup: at most once a day, or every time a tier is reached?~~ | **Decided (O75):** at most once a day, on the first Home visit after a tier became claimable. |
| ~~Q11~~ | ~~BIRDWATCHER: 25 points, bird-with-binoculars icon?~~ | **Decided (O77):** yes. |
| ~~Q12~~ | ~~Points for BULLSEYE 40 and SKY HIGH 50?~~ | **Decided (O82):** yes. |
| ~~Q13~~ | ~~Should PROUD PEACOCK (own every shop item) also ignore the 51 versus-card items (≈ 75,000 coins)?~~ | **Decided (O81):** no — it counts them ("there are no players in 2.5"); skill items stay excluded. |
| ~~Q14~~ | ~~Add the achievement BIRD OF PREY (5 versus wins in a row, 25 points, hidden) for the Bird of Prey frame?~~ | **Decided (O82):** yes. |
| ~~Q15~~ | ~~Cosmic Orbit / Bird of Prey / Pecking Order reach up to 7 pt past the avatar box in the 38 pt versus bar: allow?~~ | **Decided (O82):** allow, drawn under the score box. |
| ~~Q16~~ | ~~The flight-guide mockup's draft rule lines repeat promises that are false since 2.3 (EGG "doubles your coins", PIGGY BANK "pays them back ×2"; HOOP line 74 chars > 64). Build from the `texts.html` FG-E rows instead?~~ | **Decided (round 24, O83):** yes, the FG-E rows win; the mockup lines are placeholders).** |
| ~~Q17~~ | ~~STREAK LOST for a 1-day streak?~~ | **Decided (O72):** yes, for every lost streak, same popup, no extra text. |
| ~~Q18~~ | ~~A second break while a restore offer is pending (lost 13, flew 2, missed again)?~~ | **Decided (O73):** only the last streak — the new offer (2) replaces the old one; a restored 13 + 2 days → 15. |
| ~~Q19~~ | ~~Chip after GIVE UP with no run since the break?~~ | **Decided (O74):** grey flame with 0 until the next finished run. |
| ~~Q20~~ | ~~Gold box rolls a feather / piece the player cannot take?~~ | **Decided (O68):** feather → puzzle piece; piece → the pre-rolled 100–300 coins. |
| ~~Q21~~ | ~~Several boxes waiting / how long does an unopened box wait?~~ | **Decided (O68):** one GO TO COLLECT per visit, oldest first; a box waits up to 400 days. |
| ~~Q22~~ | ~~What the board shows before your first run of a group-day?~~ | **Decided (O67):** "YOUR GROUP STARTS WITH YOUR NEXT RUN" + PLAY. |
| ~~Q23~~ | ~~Your rank as a badge on the Home trophy box?~~ | **Decided (O67):** no. |
| ~~Q24~~ | ~~"Join until full" can place a new player into a group that ends in minutes.~~ | **Decided (O66):** no new joiner in a group with **< 3 h** left (`LB_MIN_LEFT_MS` 3 h). |
| ~~Q25~~ | ~~Is the WP-LB deploy + import (C8) covered by O27's "bigger functions + rules deploy"?~~ | **Decided (round 24, O83):** yes; the import runs only after the owner's OK on the day, the cleanup C9 before production).** |
| ~~Q26~~ | ~~**Home NEW tag rules (O70):** when does the gold NEW tag on the Home level emblem show and clear?~~ | **Decided (round 24, O83):** as recommended — shows while a Levels tab dot is pending, clears when Levels is opened, never in runs 1–3, waits behind a LEVEL UP claim; one bool `homeLevelsTag`).** |
| ~~Q27~~ | ~~**Star Road season names (O75):** approve the 13 names, one per 28-day season, repeating yearly: SPIKE SPRING, HILLTOP HOP, SUGAR SPIKES, ROOFTOP RUSH, TICK TOCK, PAPER PLANES, BUBBLE BAY, HOOP DREAMS, PENCIL PASS, SLEEPY SKIES, FEATHER STORM, ZERO GRAVITY, SPIKE NIGHT (spares: WING IT, TAIL WIND, BEAK PEAK, NEST EGG, RING RUSH, SHARP TURN, FLAP HAPPY)?~~ | **Decided (round 24, O83):** yes, as listed; spares kept for swaps).** |
| ~~Q28~~ | ~~**Rarity chip in the Star Road item reveal:** the road no longer names the rarity (O75); keep the approved RARE / EPIC / LEGENDARY chip in the reveal after CLAIM?~~ | **Decided (round 24, O83):** keep the rarity chip in the reveal).** |
| ~~Q29~~ | ~~**ACHIEVEMENTS tab while signed out** of Play Games / Game Center?~~ | **Decided (round 24, O83):** same as the old medal box; no disabled look; never a sign-in at launch).** |
| ~~Q30~~ | ~~**The six skill-item achievements (O80):** add SECOND WIND (10), ALBATROSS (15), THREE LITTLE BIRDS (10), IRON BEAK (10), FLAWLESS (10) and TOP BIRD (15), all visible (J9)?~~ | **Decided (round 24, O83):** yes, as listed — 58 achievements, 965 points).** |
| ~~Q31~~ | ~~**GO TO COLLECT ghost line** LG-6 "Runs from earlier days win no prize.": under O65 nobody moves up, so it explains nothing about your own box and hints that a ghost is on the podium. Drop it?~~ | **Decided (round 24, O84):** dropped; nobody else gets a ghost's prize).** |
| ~~Q32~~ | ~~**"? ? ?" on the other 18 skill items?** O85 makes the 9 skill **card** items secret in the shop. The 18 skill items of the BIRDS / GEAR / HATS / HOOPS / TRAILS tabs still show their goal (e.g. "HOOP 150") unless their achievement is console-hidden. Same rule there?~~ | **Decided (round 25, O88):** yes — "? ? ?" on every skill tile in every tab (one shop rule); the achievements stay as they are in Play Games / Game Center. |

### 7.5 Both-platform and store-compliance requirements (O27)

2.6 ships Android-only (O19), but every item below is built for **both** platforms, compiles in CI (macos-14 runner) and is review-ready for iOS.

| # | Requirement | Applies to |
|---|---|---|
| S1 | ~~Weekly leaderboard in Play Games Services and Game Center~~ — **dropped** (O30): the weekly course works the same on Android and iOS and has no board; weekly runs submit to the normal `bestScore` board, try/caught like every `GameServices` call. | G5 |
| S2 | The mission-reroll and **streak-restore** rewarded ads use the existing AdMob rewarded units on both platforms, and only after UMP consent (and ATT on iOS) as today; no ad request before consent. | G1, G2, C4 |
| S3 | State-aware notifications use the existing local-notification path on both platforms; iOS permission rules respected (no notification is scheduled without permission; the launch ask stays as today, O3). | G3 |
| S4 | Missions, streak, weekly course, Star Road, the puzzle album, the flight guide and every other reward need **no purchase and no ad** to earn (Apple 3.1.1 / Google Play payments policy); the only ads are the optional mission reroll and the optional streak restore (round 22). Earning streak rewards and leaderboard gift boxes never needs an ad or a purchase. | G1–G6, WP-LB |
| S5 | No loot-box mechanics for paid currency: level / Star Road / album items are fixed-rule random draws from free progress only, never bought with coins or money; the item reveal is not sold. Versus-card cosmetics have a fixed coin price (no boxes, no IAP). Random boxes are **never sold** (O58); their odds are not shown to players (O61). | J4, G6, F9, WP-LB |
| S6 | Play Data safety and Apple App Privacy re-checked for 2.6 (C5, T14). | all |
| S7 | Store review notes list the new features (missions, streak, weekly course, Star Road, album, flight guide, **own daily leaderboard with free gift boxes, streak restore via an optional rewarded video**) as free progression; they also say that player names come from a fixed word list (no free text). | release |
| S8 | New achievements (C6) exist in Play Games Services **and** Game Center with the same ids mapping; unlocks are try/caught and re-reported on sign-in. | J9, C6 |
| S9 | The streak restore states the reward before the ad (S-29), is optional (GIVE UP is always there), runs after UMP (+ ATT) and is never shown to No-Ads owners (they pay 500 coins). | G2, O48 |
| S10 | Gift boxes are earned by rank only and never sold (no purchase, coins or ad). Their odds are **not shown** to players (O61); stores require disclosed odds only for paid random items, which 2.6 does not have. | WP-LB, O54, O58, O61 |
| S11 | No report path for names (owner, O56): names are generated from a fixed word list + the existing word filter; this is a known review risk (§6). | WP-LB |
| S12 | ~~Play Games / Game Center boards stay reachable from our board~~ **No visible entry to the Play Games / Game Center leaderboards (O64)**; they still get every score in the background (try/caught), and achievement unlocks are still reported. The native **achievements** screen is reached from the board's ACHIEVEMENTS tab on both platforms (O63). | WP-LB |

---

## Appendix — tuning keys changed or added

`tuning_defaults.dart` unless noted. "—" = new key. Retired keys are removed together with their tests.

| Key | Current | Proposed | WP |
|---|---|---|---|
| `curve_opening` | …[40,87.5],[50,81],[60,76.5],[75,72],[100,66] | [[1,118],[2,118],[6,114],[10,110],[16,105.5],[20,102],[25,98],[30,95],[40,88.5],[50,83],[60,79],[75,75.5],[100,72.5],[125,71],[150,70]] | D2 |
| `point_perfect_band` | [[1,40],[2,40],[6,36],[10,30],[16,24],[20,18],[25,14.5],[30,13.9],[35,13.2],[40,12.7],[50,11.6],[60,10.7],[75,10],[100,8]] | Hoops 0–40 **unchanged** (2.5.0+46, the 20→25 drop kept by the owner): [[1,40],[2,40],[6,36],[10,30],[16,24],[20,18],[25,14.5],[30,13.9],[35,13.2],[40,12.7],**[50,11.8],[60,11.2],[75,10.6],[100,10.2],[150,10]**]. Big Hoops growth ×1.5 unchanged. | D2 |
| `curve_tilt` | [[9,0],[10,.3],[19,.3],[20,.5],[34,.5],[35,.6],[44,.6],[45,.78]] | [[9,0],[10,.30],[49,.35],[50,.50],[100,.60],[150,.65]] | D2 |
| `tilt_rows` | (`LayoutConfig` signed weights) | from 10 {10:6,15:4}; 50 {10:30,15:30,20:20,30:20}; 60 {10:20,15:20,20:15,30:30,45:15}; 100 {10:15,15:15,20:15,30:30,45:25} | D2 |
| `tilt_align_min_deg` / `tilt_align_min_dy` | — | 20 / 40 | D2 |
| `tilt45_extra_opening` | — | 6 | D2 |
| `curve_moving` | [[19,0],[20,.15],[35,.4],[60,.6],[80,.75]] | [[24,0],[25,.15],[34,.15],[35,.25],[60,.42],[100,.52],[150,.58]] | D2 |
| Δy rows (`LayoutConfig`) | from 0/3/10/20/35/45, × band | from 0/3/20/40/65/100, × min(band, 540) | D2 |
| `dy_ref_band` / `dy_hard_factor` | — | 540 / 0.85 | D2 |
| Motion rows (`LayoutConfig`) | 20–44 rail 80 / swing 20; 45+ all six; 30–39 pt/s | 25 / 35 / 70 / 90 rows; 22–42 pt/s | D2 |
| Early pool (`director_tables.dart`) | starTrail 1, bullseye 1, angled 1, nothing 1 | starTrail 1, bullseye 1, nothing 1 | D2 |
| `spawn_switch.from` | 7 | 15 | D2 |
| `spawn_saw` from / weight | 20 / 18, `weight_from_45` 26 | 30 / via `spawn_saw_weight` | D2 |
| `spawn_saw_weight` | — | [[30,14],[60,20],[100,26]] | D2 |
| `firstPossible` (`elements.dart`) | switch 12, moving 20, saw 20, portal 40 | 15, 25, 30, 12 | D2, C3 |
| `hazard_budget` | — | [[0,0],[3,0.5],[10,2],[25,3],[50,4],[100,5],[150,5.5]] | D3 |
| `hazard_costs` (object) | — | saw 2, switch 1.5, spring / pair / train 0.5, tilt ≤20° 0.25, 30° 1, 45° 1.5, rail / swing 1, other motion 1.25, Δy > p90 +1, in squeeze +1 | D3 |
| `calm_every` | — | {first_min 30, first_max 34, mult 1.2, cap 55, len 3, min_gap 12} | D4 |
| `calm_after` | — | {revive 3, squeeze 2, ride 2} | D4 |
| `headline_window` / `headline_wait` | — | 8 / 5 | D6 |
| `formation_every` | — | [12, 20], from hoop 150 | D7 |
| `curve_speed` | [[0,150],[50,172.5],[150,187.5]] | **unchanged** | §1.4 |
| `gate_egg`, `gate_pair` | 4 | 0 | C1 |
| `gate_feather`, `gate_puzzle`, `gate_piggy`, `gate_jar` | 6 | 0 | C1 |
| `gate_fever`, `gate_lucky_spin` | 8 | 0 | C1 |
| `gate_spring` | 4 | 0 | C1 |
| `gate_saw` | 12 | **3** (game 4) | C1 |
| `gate_squeeze` | — (squeeze not gated) | **5** (game 6) | C1 |
| `showcase_max_games` / `showcase_fast_hoops` | — | 6 / 40 (the other showcase numbers live in `showcase_config.dart`) | B1 |
| `rate_min_runs` | 5 | 5, applied as max(5, showcaseDoneAt + 2) | C3 |
| `ads_grace_runs` / `ads_grace_seconds` / `ads_interstitial_min_gap_s` | 5 / 300 / 60 | **unchanged** (O2) | — |
| `ui_unlock_games` | — | 3 (`ui_unlock_best` 25 stays; level ≥ 1 also unlocks, R8) | F6 |
| `level_rewards` | [25,50,100,200,400,600,800,1000,2000,5000] | **retired** | J5 |
| `level_points` | — | [25,50,100,150,200,300,400,500,600,700,800,900,1000,1200,1400,1600,1800,2000,2200,2400,2600,2800,3000,3500,4000,4500,5000,6000,7000,8000,10000] | J1 |
| `level_coins` | — | [50,50,50,50,50,75,100,125,150,175,200,225,250,300,350,400,450,500,550,600,650,700,750,875,1000,1125,1250,1500,1750,2000,2500] | J1 |
| `level_items` | — | 31 × "layer:rarity" per J1 (level 31 "any:legendary") | J1 |
| `level_eternal_points` / `level_eternal_coins` | — | 10000 / 2500 (levels 32+, ETERNAL WING) | J2 |
| `kBestBrackets` (`lib/versus/brackets.dart`; mirror `functions/src/brackets.ts`) | in `kLevels` thresholds | [25,50,100,200,400,600,800,1000,2000,5000] (same numbers) | E4 |
| `mission_rewards` / `mission_chest_coins` | — | [20,35,55] / 40 | G1 |
| `streak_rewards` | — | [20,30,"bighoops",40,"shield",50,"feather+60"] | G2 |
| `weekly_rewards` | — | {15:40, 30:80, 60:150, 120:300} | G5 |
| ~~`streak_freeze_max`~~ | — | **removed** (no freezes, O46) | G2 |
| `streak_restore_coins` | — | 500 (No-Ads owners, O48) | G2 |
| `lb_results_min_games` / `lb_results_wait_ms` / `lb_queue_cap` | — | 3 / 4000 / 30 (server constants: WP-LB, `schema.ts`) | WP-LB |
| `starroad_stars` | — | {easy:1, medium:2, hard:3, first_run:2, all_done:3} (max 11 a day; O37) | G6 |
| `starroad_tier_stars` / `starroad_tiers` / `starroad_season_days` | — | 8 / 25 / 28 | G6 |
| `starroad_fallback_coins` | — | {rare:250, epic:500, legendary:1000}; feather / piece tier with 3 held: 50 | G6 |

**New storage keys** (append to the END of `kObfStrings` + `anchor_strings.txt`; "Delete my data" clears all of them **except the streak keys**, which stay as local progress like coins (O57, F12); the leaderboard keys are cleared together with the server data):

| Release | Keys |
|---|---|
| 2.6 | `ftueSteps`, `showcaseSeen`, `showcaseAttempt`, `showcaseRuns`, `showcaseDoneAt`, `lvlIndex` (sealed), `lvlPoints`, `lvlPending` (sealed), `lvlPayout`, `bestRunHoops`, `bestHoops`, `recentScores`, `duelStep`, `lifetimeCoinsEarned`, `lifetimeCoinsSpent`, `lifetimeCoinsBought`, `missionDay`, `missions`, `missionTier`, `missionRerollDay`, `streakDays`, `streakLastDay`, `streakPaidDay`, `worldsReached`, `weeklyBest`, `weeklyRewards`, `weeklyHintDay`, `firstWinDay`, `starRoadSeason`, `starRoadXp`, `starRoadClaimed`, `abArm_v1`, + round 21: `worldsSeen`, `guideSeenCount`, `albumCounts`, `albumRewardClaimed`, `albumRewardItem`, `starRoadPopupDay`, `vsWinStreak`, `vsWinStreakBest` (BIRD OF PREY, approved O82), + round 22: `streakLostDays`, `streakLostSeenDay`, `lbQueue`, `lbGroupId`, `lbGroupEnd`, `lbLastRank`, `lbGiftsClaimed` (sealed), `lbGiftPending`, + round 22b: `lbInfoSeen` (O60), + round 23: `homeLevelsTag` (O70, Q26), `vsBigWinsDay` (THREE LITTLE BIRDS, approved O83). **`streakFreeze` is removed** (never shipped; also out of `kObfStrings` / `anchor_strings.txt`). |

Existing keys keep their names and defaults: `homeMode` (VERSUS default), `playerLevel`, `claimedLevels`, `unclaimedLevelReward`, `levelRewardPayout` (no longer read after J5's one-time finish).
