# a6-progression — PRD 2.6 WP-J, WP-K, WP-F (F5/F6/F7/F9/F10/F11), WP-E client

Auditor a6 · tree `feat/2.6` @ a57a7fb · PRD `docs/p26/PRD-2.6-fun-progression.md` (lines cited as `PRD:n`).

## 1. Summary

- **Almost nothing in this area is built on the client.** `git diff --stat d0a72c2..HEAD` touches none of `lib/levels/`,
  `lib/components/levels/`, `lib/skins/`, `lib/components/skins/`, `lib/menu/`, `lib/achievements/`, `lib/run/hud/`,
  `lib/run/screens/results_screen.dart`, `lib/share/`, `lib/versus/matcher.dart`, `run_entry.dart`,
  `versus_service.dart`. The 2.5 model (10 ranks on `playerLevel`, `level_rewards`, `levelFor`) is still the live one.
- Built pieces: `lib/versus/brackets.dart` (`kBestBrackets` + `bracketFor`, with a test). Nothing calls it.
  `lib/components/ui/mystery_box.dart` is the O99 box master (M0 #2), so the J7a reveal can use it.
- **The M1 skeleton (#23) added none of this area's keys.** It has no `lvl*`, `bestRunHoops`, `recentScores`,
  `duelStep`, `lifetimeCoins*`, `vsWinStreak*` or `vsBigWinsDay` storage keys, and no `level_points` / `level_coins` /
  `level_items` / `level_eternal_*` / `ui_unlock_games` tuning keys. `level_rewards` is still live
  (`tuning_defaults.dart:116`). Everything is TODO from scratch.
- Server side (wave 0, out of scope but a dependency) is **done in code, not deployed**: `functions/src/brackets.ts`,
  `plv` in `pools.ts:247`, rules `level` 0–9999 (`firestore.rules:126`), `card.ts` allow-lists (60 ids), reference
  duel staircase `matching.ts:124-200` + `test/fixtures/versus_duel.json`, renamed `versus_matching.json` (`bracket`).
- **One real FIX in shipped code:** debug runs are still uploaded to versus. `flappy_game.dart:4269` calls
  `submitRun` with no eligibility check. `RunController.countsForUpload` (`run_controller.dart:149`) exists but nothing
  reads it. This breaks E1 "debug runs never".
- **Test env blocker (for the orchestrator):** `.dart_tool/package_config.json` points at
  `~/.local/state/df4/flappy-spikes/cache/...`, and that folder no longer exists, so every `flutter test` fails at
  loading in this worktree. I could not run any Dart test. Statuses below rest on code reading, plus the M0 issue
  verdicts for the server parts. Someone needs to run `flutter pub get` (or restore the cache) before the builds.
- Size estimate: about 20 Sol packages (≈ 45–60 h). WP-J alone ≈ 9 packages. F9/F10 art (≈ 84 vector items) is the
  biggest single risk.

## 2. Requirement table

Legend: DONE / FIX / TODO / OWNER / DEFER?. "→ WP-x" points at a work package in §4.

### WP-E client (PRD:745-805)

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| E1.1 | All non-debug runs are normal (showcase, Free Fly, versus, revive runs) | DONE | `RunController.countsForUpload` (run_controller.dart:149) = cleanStart && !debugTouched; revives/showcase don't touch it | — |
| E1.2 | Versus uploads: 2.5 rules (3/day + bests, score ≥ 3); **debug runs never** | **FIX** | `upload_queue.dart:78-95` has the rules. `flappy_game.dart:4269` submits every run with a summary, debug runs included; `countsForUpload` has no caller | Gate `versus.submitRun` (and the lb submit later) on `_run?.countsForUpload`; add `upload_rules_test` → WP-E1 |
| E1.3 | Leaderboard `submitBestScore(bestScore)` unchanged | DONE | flappy_game.dart:4268 | — |
| E1.4 | Versus revives = 2.5 ladder | DONE | not changed (revive_ladder.dart diff is #36 FREE kind only) | — |
| E2 | `fl` byte stays 2 | DONE | not changed; timeline tests exist | keep |
| E3 | VERSUS default from launch; empty pool line T4 "No rival yet – your run can become a rival for others" | **TODO** (line) | default homeMode is unchanged. No T4 string in lib (`grep "No rival yet"` = 0) | Add the sub-line under NO RIVAL FOUND in `lib/run/screens/versus_intro.dart` (text in `VersusConfig`) → WP-E1 |
| E4.1 | `lib/versus/brackets.dart` `kBestBrackets`, `bracketFor` | DONE | brackets.dart:6-15, test/versus/brackets_test.dart (not run: env) | — |
| E4.2 | `levelFor` removed from `levels.dart` | TODO | levels.dart:156 still there; 9 lib/test users (see §5) | → WP-E1 |
| E4.3 | versus_service :916/:947 → `bracketFor(best)` | TODO | versus_service.dart:916, :950 still `levelFor` | → WP-E1 |
| E4.4 | matcher: `MatchTier.level`→`bracket`, `myLevel`→`myBracket` | TODO | matcher.dart:9, :56, :73, :97, :132. Test shim `_fixtureTier` in s3_13_matching_nickname_test.dart:201-203 | Rename it and drop the shim → WP-E1 |
| E4.5 | versus_config `maxLevel`→`maxBracket` (10), `maxSearchReads` 44 | TODO | versus_config.dart:53, :106 | → WP-E1 |
| E4.6 | Opponent emblem `entry.plv ?? 0` (R4); missing plv → UNRANKED | TODO | run_entry.dart:236 `levelFor(run.best)`. PoolEntry does not parse `plv` (run_entry.dart:217-222 reads `level` only) | Parse `plv` (clamp 0–9999) → WP-E1 |
| E4.7 | Player doc `level` = lvlIndex (0–9999) | TODO | flappy_game.dart:1668/1690 write `menu.levels.level` (= 2.5 playerLevel). run_entry.dart:310 falls back to `levelFor(best)` | Follows from WP-J2. Fallback → 0 → WP-E1 |
| E4.8 | Fixture `versus_matching.json` renamed + level-25/best-80 case | DONE | fixture uses `bracket` (M0 #4 PASS) | — |
| E4.9 | Server brackets / plv / rules / MAX_BRACKET | DONE (code) / OWNER (deploy) | functions/src/brackets.ts, pools.ts:247, firestore.rules:126; #4 PASS | Deploy = owner (C1) |
| E5.1 | `duelStep` start −2, clamp [−4,+8], +1 win / −2 loss / 0 draw | TODO (client) | no Dart code; reference in matching.ts:124-160 | → WP-E2 |
| E5.2 | `recentScores` = last 10 non-debug scores (must) | TODO | no key | → WP-S0 key, WP-E2 logic |
| E5.3 | T = clamp(0.8+0.1·step, 0.4, 1.6) × median; pick band [0.75T,1.25T] → closest → rematch → solo, inside the found pool doc, own bracket first | TODO (client) | versus_service `_pickFromPool` (:903) uses `pickOpponent` (2.5) | Port `pickDuelOpponent` to `lib/versus/matcher.dart`; **use integer tenths** like matching.ts:166-171 (#6 major: float rounding at the band edge) → WP-E2 |
| E5.4 | Mirror in matching.ts with shared fixtures | DONE (server) | functions/test/matching_duel.test.ts + test/fixtures/versus_duel.json (`_doc` names `test/versus/matcher_duel_test.dart` as the Dart reader) | Dart test → WP-E2 |
| E5.5 | Analytics `versus_result` + tier, duel_step, ratio_x100, first | TODO | versus_recorder.dart:71-75 sends result/score/opp_score only | → WP-E2 |
| E6 | curves.test.ts, passHist / jump flag | DONE (server) | functions/test/curves.test.ts, passhist.test.ts (#7) | — |
| E-T | Tests: upload_rules_test, matcher_bracket_test, plv emblem, matcher_duel_test | TODO | none exist | WP-E1/E2 |

### WP-F economy (PRD:806-867)

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| F5.1 | `test/economy_budget_test.dart`: 3 bot profiles × 20 seeds × 568/711; 1.4–2.1 coins/hoop, ≤ 80 coins/run-min, ≤ 0.35 non-hoop coins/hoop | TODO | file missing. Human-noise bot exists (test/p26/bot/human_bot_test.dart, #42) | → WP-F2 |
| F5.2 | Showcase runs 1–3 pay 90–200 play coins in total | TODO | — | → WP-F2 |
| F5.3 | Level coins ≤ play coins over the medium bot's first 50 runs (report + assert) | TODO | needs WP-J1 | → WP-F2 (after J1) |
| F5.4 | Meta ≤ 25 % case incl. gift boxes / first-win / Star Road (PRD:945, F12) | TODO | meta sources are not built (G/LB) | Add a skeleton case now with the meta sources that exist; G/LB builders extend it. Flag to the orchestrator |
| F6 | `ui_unlock_games` = 3; `menuUnlocked(best, games, level)` = best≥25 ∨ games≥3 ∨ level≥1; no new animation | TODO | menu_state.dart:43 `locked => bestScore < menuUnlockBest`; config.dart:1139; lock texts flappy_game.dart:2268, :2529 | → WP-F1 |
| F7.1 | `lifetimeCoinsEarned/Spent/Bought` in wallet.dart | TODO | wallet.dart has no counters; no keys | → WP-F1 |
| F7.2 | Events `item_bought`, `first_item_bought` {key, rarity, price, balance_before, games, minutes}, daily `economy_daily` | TODO | grep = 0 hits | → WP-F1 |
| F11 | Level budget 18,800 coins + 31 items; levels 1–5 = 250 coins + 5 commons; meta ≈ 180/day excl. levels | TODO (statement) | covered by J1 table + F5 | Assert totals in level_track_test (WP-J1) |
| F9.1 | 51 card items (17/kind; 6×250, 5×750, 4×2000, 2×5000) + 9 skill items; ids = `functions/src/card.ts` | TODO | no client catalogue | → WP-F9a (catalogue + mirror test vs card.ts) |
| F9.2 | `SkinLayer.card`; `look.card` = `"f|n|s"` ≤ 48 chars, uploaded in look | TODO | look.dart has 5 layers; `lookToMap` run_entry.dart:168 has no card. Server `validCard` DONE (#5) | → WP-F9a |
| F9.3 | Painters: frames `CustomPainter`, name styles `TextPainter` (+ShaderMask, per-glyph Flappy), stickers; off the game clock | TODO | — | → WP-F9b/c/d |
| F9.4 | VS intro: frame + name style + small sticker (≈42 %, tilted) on both cards | TODO | versus_intro.dart | → WP-F9f |
| F9.5 | Versus bar: frame round the 38 pt avatar + name style (animated); no sticker; frames up to 7 pt drawn under the score box (O82) | TODO | lib/run/hud/versus_bar.dart, name_chip.dart | → WP-F9f |
| F9.6 | Results: the winner's sticker slaps on | TODO | results_screen.dart `ResultsWinnerTag` | → WP-F9f |
| F9.7 | Shop CARDS 6th tab, FRAMES/NAMES/STICKERS row, "x/20" each, tab x/60, "EARNED BY SKILL · NOT SOLD" + 3 gold tiles, sub-label "NAME STYLE" | TODO | skin_tab_bar.dart:46 divides by `SkinLayer.values.length` | → WP-F9e |
| F9.8 | Fixed shop header on every tab (O79): only the grid scrolls (clipped), 5 pt shadow, thin scroll bar | TODO | skin_shop_screen.dart | → WP-F9e |
| F9.9 | Never level / Star Road / album rewards | TODO (rule) | enforced by the WP-J1 roll (shop layers only) | test in WP-J1 |
| F10.1 | 24 skill items, `SkinItem.unlock: AchievementId?`, never sold, excluded from draws | TODO | catalog.dart SkinItem has no `unlock` | → WP-F10a |
| F10.2 | Owned ⇔ achievement earned (derived; no grant, O81) | TODO | ItemStore.isOwned (item_store.dart:39) | → WP-F10a |
| F10.3 | LEGENDARY gold + trophy mark; reveal = style A box in gold + plum ribbon + legendary extra ring, `lv_up_big` | TODO | MysteryBox master exists | → WP-F10b |
| F10.4 | Locked skill tile everywhere: "? ? ?" + "UNLOCK: ? A SECRET ACHIEVEMENT ?" (O88) | TODO | — | → WP-F10b |
| F10.5 | HOW TO EARN sheet (secret form) + stage strip "SKILL ONLY · SECRET · HOW TO EARN ›" | TODO | — | → WP-F10b |
| F10.6 | Counts in the collection bar / tab counters (+3 per shop tab, +9 CARDS) | TODO | `kCollectibleTotal = 148` catalog.dart:217 | → WP-F10a |
| F10.7 | Level reveal before skill reveal in one run | TODO | — | → WP-F10b |
| F10.8 | PROUD PEACOCK counts every sold item incl. the 51 card items, excludes skill items | TODO | achievements skin_all rule | → WP-F10a |
| F10.9 | Art: 15 shop-kind skill items (vector, animated; Day & Night / Prism per-frame body colour; Jackpot clipped reels) | TODO | lib/skins/art/* | → WP-F10c |
| F-T | Tests: economy_budget_test, shop_unlock_test, wallet_counters_test, baked_tuning ad keys unchanged | TODO (first 3) / DONE (ad keys) | test/audit17/baked_tuning_test.dart exists | — |

### WP-J levels (PRD:993-1177)

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| J1.1 | 31 `LevelDef`s (name, points, coins, item C·R) per table PRD:999-1032 | TODO | levels.dart:52-149 = 10 ranks (EGG…LEGEND, threshold/reward) | → WP-J1 |
| J1.2 | Tuning `level_points`, `level_coins`, `level_items` (values PRD:1539-1541) | TODO | absent from tuning_defaults.dart | → WP-S0 |
| J2 | ETERNAL WING 32+: 10,000 pts, 2,500 coins + 1 uniform unowned item; `level_eternal_points/coins`; no cap, no stars | TODO | `kMaxLevel = 10` levels.dart:151 | → WP-J1 |
| J3.1 | Input: final score at `endRun` | FIX→TODO | flappy_game.dart:4214 `recordRun(score)` uses the 2.5 rule (`levelAfterRun`) | → WP-J2 |
| J3.2 | All finished runs count; debug runs (`_debugTouched`, force, ignoreGates, god/bot) and killed runs don't | TODO | 2.5 recordRun has no debug check (flappy_game.dart:4214) | Use `_run?.countsForUpload` → WP-J2 |
| J3.3 | Step: p = lvlPoints + score; p ≥ need → +1 level, lvlPoints = 0 (surplus dropped); max one level per run | TODO | — | `lib/levels/level_track.dart` (pure) → WP-J1 |
| J4.1 | Coins `level_coins[l]` via `CoinSource.levelReward` | TODO | source exists (wallet.dart:10) | → WP-J2 |
| J4.2 | Item roll: C·R → C·R+1… → other C at R, R+1… → coins at `Rarity.price`; never lower; excludes owned, pending, free, card, skill items; L31 any layer; 32+ uniform | TODO | — | `lib/levels/level_reward_roll.dart` (pure) → WP-J1 |
| J4.3 | Roll at run end with `Random()`, saved in `lvlPending` **before** anything is shown | TODO | — | → WP-J2 |
| J4.4 | Payout on EQUIP/LATER or the catch-up popup; crash-safe (`lvlPayout` target balance, `ItemStore.grant` sealed write, credit, clear); exactly once | TODO | 2.5 pattern level_progress.dart:118-152 to reuse | → WP-J2 |
| J4.5 | Not auto-equipped; EQUIP / LATER (NEW sticker) | TODO | — | → WP-J4 |
| J5.1 | Keys `lvlIndex`(sealed), `lvlPoints`, `lvlPending`(sealed), `lvlPayout` at the END of `kObfStrings`, regenerate, anchor_strings | TODO | gen_obf_strings.dart:141-151 ends with the WP-A keys | → WP-S0 |
| J5.2 | Absent = level 0; coins/items/achievements kept | TODO | — | → WP-J2 (`level_fresh_start_test`) |
| J5.3 | Old keys kept in kObfStrings, not read; one-time finish of an interrupted 2.5 `levelRewardPayout` | TODO | the 2.5 claim is still live | → WP-J2 |
| J5.4 | Delete my data clears old + new keys | TODO | storage.dart resetVersusData (:1125) has no lvl keys | → WP-S0 |
| J5.5 | `level_rewards` retired with its baked-tuning rows; `LevelDef.threshold/reward` → points/coins/item | TODO | tuning_defaults.dart:116; baked_tuning_test | → WP-S0 / WP-J1 |
| J6.1 | 32 PNG emblems @1x/2x/3x in `assets/emblems/` (route b), exported from `design/levels_v26/emblems.html` | TODO / art | no `assets/emblems/` | → WP-J8 (art export, M5) |
| J6.2 | `EmblemView` switches to the image; UNRANKED stays painted; bird drawn on the plate centre at every size | TODO | emblem_view.dart, emblem_painter.dart (10 painted, `_clamp` to 10 at :103) | → WP-J7 |
| J6.3 | Idle layers in code: sweep 6.4 s all; rays ≥ 21; twinkle+glow ≥ 26; flicker 29/31; off with reduced motion | TODO | painter has sweep + `animates(level ≥ 7)` | → WP-J7 |
| J6.4 | Internal builds may map the 10 painted emblems onto 1–31 (J13) | TODO | — | WP-J1 adds `paintedEmblemFor(level)` so the UI keeps compiling |
| J7a | Results reveal sequence (≈5.5 s; bar fill, "+N OVER · DROPPED", emblem swap, LEVEL UP!, coins fly into YOUR REWARD, mystery box style A, item, EQUIP/LATER; no-level-up run settles ≈2.15 s) | TODO | results_screen.dart `LevelBar` :42-68 (`MAX LEVEL`), `ResultsLevelStage` :1111 | → WP-J3 (bar/stage), WP-J4 (reveal) |
| J7.R | Results: bar `lvlPoints/need`, rank line "NAME · LV n" / "UNRANKED", reward chip after the reveal, `Config.uiAccent` labels | TODO | — | → WP-J3 |
| J7.H | Home LEVEL UP popup = catch-up only; several pending levels listed and paid together | FIX→TODO | level_up_popup.dart (2.5 popup, coins only); flappy_game.dart:2746-2840 | → WP-J5 |
| J7.L | Levels screen per `levels_screen.html` (header with badge, bar text inside, 31 rows + ETERNAL row, states reached/current/next/locked, carousel, scroll to current, only 2 emblems animate, "10 000" separator, ALBATROSS 64) | TODO | levels_screen.dart (10 rows) | → WP-J6 |
| J7.N | Name fit 13 chars: results rank line, settings player card, versus name box/HUD (`fit_name.dart`), share card; goldens @320 for the 3 longest + "ETERNAL WING" + badge 999 | TODO | — | → WP-J7 |
| J8 | Matching never on level; player doc level = lvlIndex; opponent emblem from plv; ≥ 32 shows ETERNAL emblem | TODO | see E4.4–E4.7 | WP-E1 + WP-J2 |
| J9.1 | R5: `onLevel` → `onRunScore(score)` in `finishRun`; thresholds [25…5000] move into `achievement_catalog.dart` | TODO | achievements.dart:239, :293; catalog :529-540 reads `kLevels[L-1].threshold` | → WP-J9 |
| J9.2 | Drop the "RANKS" code comment; names unchanged | TODO | catalog comment | → WP-J9 |
| J9.3 | 10 new achievements (BULLSEYE 40, SKY HIGH 50, BIRD OF PREY 25 hidden, BIRDWATCHER 25, SECOND WIND 10, ALBATROSS 15, THREE LITTLE BIRDS 10, IRON BEAK 10, FLAWLESS 10, TOP BIRD 15); 58 achievements / 965 pts; group sums | TODO | catalog has 48 | → WP-J10. Console ids = OWNER (C6) |
| J9.4 | Counters `vsWinStreak`, `vsWinStreakBest`, `vsBigWinsDay`; only races with a rival count; SECOND WIND tracks the largest live deficit | TODO | no keys | → WP-S0 + WP-J10 |
| J9.5 | TOP BIRD from `lbSettleGroups` → client on the next board read | TODO | depends on the WP-LB client (other auditor) | → WP-J10 (hook only) |
| J10 | `level_up` {level, games, run_score, s_since_install} (drop best); `level_reward_claimed` {level, coins, item_layer, rarity, fallback}; user property `fs_level`; `run_end` + level, lvl_pts_before | TODO | game_services.dart:614-619 (2.5 shape); `setUserProperty` exists (:699) | → WP-J2 |
| J11.d | Debug panel "LEVEL UP" forces the next level's points; "+1 level" works past 31 | TODO | debug_panel.dart:254-261 (2.5) | → WP-J2 |
| J12 | Tests: level_track, level_reward_roll, level_payout, level_fresh_start, obf/anchor, achievements_rank_score, goldens | TODO | test/levels/* test the 2.5 model | Per package |
| J13 | Production needs all 31 emblems | OWNER/art | — | M5 |

### WP-K beat your best (PRD:1179-1192)

| ID | Requirement | Status | Evidence | What to do |
|---|---|---|---|---|
| K1 | Only in Free Fly with best > 0 and in solo versus (no opponent); never in debug runs | TODO | — | → WP-K |
| K2 | HUD chip "BEST 42" between the heart and pause; white plate, `uiAccent`; flips to gold/plum with the live score after NEW BEST | TODO | run_hud.dart:98-100 (the slot is free when `opponent == null`); hud_config.dart | → WP-K |
| K3 | 2 pt #FFB529 line at hoop `bestRunHoops`, strip to strip, + "BEST 42" flag; `world.addRun`; visible ≈1.25 s before; hidden when unknown | TODO | new `lib/run/effects/best_line.dart` | → WP-K |
| K4 | NEW BEST! once per run on the score: gold burst + `GoldSticker.newBest(text:'NEW BEST!')` at y≈114 for 1.2 s; chip flips 0.18 s later; line pulls in / flag shrinks if beaten earlier | TODO | gold_sticker.dart:40 (default text 'NEW BEST', so pass `'NEW BEST!'`) | → WP-K |
| K5 | Storage `bestRunHoops`, saved only on a new bestScore | TODO | **not** the same as `bestHoops` (WP-A lifetime max, storage.dart:195) | → WP-S0 + WP-K |
| K6 | Analytics `best_beaten` {mode, hoop, best_before, games}; `run_end` + `beat_best_hoop` (−1) | TODO | — | → WP-K |

## 3. Open findings from issues (still in the code)

1. **#6 major (floating-point band edge)** was fixed on the server with integer tenths (`matching.ts:166-171`). The
   client port does not exist yet. The Dart port must copy that arithmetic and pass the fixture's lower-edge cases.
2. **#4 note:** the Dart fixture readers still bridge `bracket` → `level` (`s3_13_matching_nickname_test.dart:15, 55,
   70, 201-203`). They become dead once WP-E1 renames the matcher; remove the shim there.
3. **Debug runs uploaded** (not from an issue; found now): `countsForUpload` was added by #60/#63 but never wired
   (flappy_game.dart:4269). It is also needed for J3 level counting and for the WP-LB submit.
4. **Seal coverage:** #23/#90 wrote `bestHoops` via `_sealedWrite` (storage.dart:1201) but left it out of
   `_sealHashes()` (storage.dart:621-629). J5 asks for sealed `lvlIndex` / `lvlPending`. The builder must add them to
   `_sealHashes` / `_sealedFieldsAtDefault` (and replace `prefPlayerLevel` there, which is no longer read) and test that
   a 2.5 sealed store still verifies after the update. Otherwise the seal check fires on the first 2.6 load.

## 4. Proposed work packages (ordered)

Shared rules for every package: BUILD_NOTES.md; SHARED_ELEMENTS.md (O97–O100); texts are approved as they stand
(O93, `design/approvals_v26/texts.html` §7 rows L-A1…L-A21, L-P1…L-P7, T4; §9 CO-1…CO-20, ACH-49…ACH-58); UI
geometry in `lib/game/config.dart` / `lib/run/config/*`; numbers with a space thousands separator.

**WP-S0 · Storage + tuning keys for waves 2/4 (S, 1–2 h)** — PRD:1059-1063, :1537-1543, :1558, :796, :820, :1188, :947.
Paths: `tool/gen_obf_strings.dart`, `lib/services/obf_strings.g.dart`, `tool/anchor_strings.txt`, `lib/game/storage.dart`,
`lib/run/config/tuning_defaults.dart`, `test/audit17/baked_tuning_test.dart`, `test/p231/s0_live_tuning_defaults_test.dart`.
- Append keys at the END: `lvlIndex`, `lvlPoints`, `lvlPending`, `lvlPayout`, `bestRunHoops`, `recentScores`, `duelStep`,
  `lifetimeCoinsEarned`, `lifetimeCoinsSpent`, `lifetimeCoinsBought`, `vsWinStreak`, `vsWinStreakBest`, `vsBigWinsDay`.
  Add fields, load, save methods; `lvlIndex` and `lvlPending` through `_sealedWrite` and in `_sealHashes`.
- Tuning: `level_points`, `level_coins`, `level_items` (31 × `"layer:rarity"`, L31 `"any:legendary"`),
  `level_eternal_points` 10000, `level_eternal_coins` 2500, `ui_unlock_games` 3. Retire `level_rewards` (remove its
  def and its baked rows).
- Delete my data clears all of them plus the 4 old level keys. `duelStep` absent → −2.
- Acceptance: obf/anchor test green; a 2.5 store with a seal loads with no seal alarm (new test); Delete my data
  removes each new key (extend `test/p26/m1/skeleton_test.dart`).
- Coordinate: the WP-G/LB/H keys of PRD:1558 are another auditor's; if one package adds all of them, merge them here.

**WP-J1 · Level table + pure track + reward roll (M, 3 h)** — PRD:997-1058 (J1–J4 logic only), :1147-1176, R9 (PRD:82), O21.
Deps: S0. Paths: `lib/levels/levels.dart`, new `lib/levels/level_track.dart`, new `lib/levels/level_reward_roll.dart`,
`test/levels/level_track_test.dart`, `test/levels/level_reward_roll_test.dart`.
- 31 `LevelDef(name, points, coins, layer?, rarity)` + `kEternalWing`; `levelDef(n)` returns ETERNAL WING with its
  number for n ≥ 32; `needFor(l)`; no max. Keep `paintedEmblemFor(level)` (1–31 → the 10 painted, 32+ → 10) and
  the colour fields so the UI keeps compiling (J13). Leave `levelFor` in place (WP-E1 removes it).
- `LevelTrack.step(index, points, score) → (index, points, levelledUp, surplus)`.
- `rollLevelReward(level, owned, pending, Random)` → item key or extraCoins + fallback tag (none/up/other_cat/coins).
  Only shop layers, never free items, never `SkinItem.unlock != null`, never card items.
- Acceptance (J12): cumulative 25…74,725; 24+30 → L1 with 0 points; exact hit; 31→32→33; totals 18,800 coins and
  13/10/6/2 rarity counts (F11); each fallback step; never lower rarity; seeded determinism; L31 any layer; 32+
  uniform (chi-square-light over 10k draws).

**WP-J2 · LevelProgress rewrite, payout, run-end wiring, analytics, debug (M, 4 h)** — PRD:1038-1063, :1114-1117, :1141-1146, J11 debug row.
Deps: J1, S0. Paths: `lib/levels/level_progress.dart`, `lib/skins/item_store.dart` (`grant`), `lib/game/flappy_game.dart`
(endRun region WP-L :4185-4260, player doc :1668/:1690), `lib/services/game_services.dart`, `lib/run/analytics_router.dart`
(run_end), `lib/components/debug_panel.dart`, tests `level_payout_test`, `level_fresh_start_test`.
- `recordRun(score, counts:)` with `counts = _run?.countsForUpload ?? false` (debug/killed runs count nothing). On a level
  up, roll and save `lvlPending` before anything is shown. `pending` list API; `payPending()` crash-safe (`lvlPayout`
  → `ItemStore.grant` → `wallet.add(levelReward)` → clear), re-entrant safe.
- One-time 2.5 `levelRewardPayout` finish on load. After that the old keys are never read.
- J10 events + `fs_level` user property. Player doc `level` = lvlIndex.
- The 2.5 Home popup trigger must call the new pending API (temporarily) until WP-J5.
- **Decide (DEFER?):** J4's pending record has a `star` field and J11 says "+ star rule", but O17b (PRD:136) removes
  stars. Recommend leaving `star` out.
- Acceptance: J12 payout cases (kill before/between/after credit → paid once, item owned); fresh start (2.5 store with
  playerLevel 7 + claims → level 0, coins/items kept, old keys untouched); debug run → no points; revive/versus/showcase
  run → points.

**WP-E1 · Versus brackets + plv client + debug upload gate + T4 (M, 2–3 h)** — PRD:747-781, :798-804, :1114-1117, R4 (PRD:77).
Deps: none (J2 for lvlIndex is independent). Paths: `lib/services/versus_service.dart`, `lib/versus/matcher.dart`,
`lib/versus/run_entry.dart`, `lib/run/config/versus_config.dart`, `lib/levels/levels.dart` (remove `levelFor`),
`lib/run/screens/versus_intro.dart`, `lib/game/flappy_game.dart:4269` only, tests (see §5 list) + new
`test/versus/matcher_bracket_test.dart`, `test/versus/upload_rules_test.dart`.
- Do the PRD table at PRD:765-778 (client rows). Parse `plv` (clamp 0–9999, missing → 0 = UNRANKED). The player-doc
  fallback → 0. Debug runs: no `submitRun`.
- T4 line under NO RIVAL FOUND (`texts.html` T4; in the 320 pt column).
- Acceptance: fixture matching ignores the level; level-25/best-80 → bracket 2; pool ids `{bracket}_{shard}`;
  44 reads; showcase / Free Fly / revive runs upload; debug runs never; opponent emblem = plv.

**WP-E2 · Duel staircase client (M, 2–3 h)** — PRD:782-787, :796, `test/fixtures/versus_duel.json` `_doc`.
Deps: S0, E1. Paths: `lib/versus/matcher.dart` (or new `lib/versus/duel.dart`), `lib/services/versus_service.dart`
(`_pickFromPool` :903), `lib/run/items/versus_recorder.dart`, `lib/game/flappy_game.dart` (recentScores at run end,
counting runs only), new `test/versus/matcher_duel_test.dart`.
- Integer-tenths target exactly as matching.ts:166-200. `duelStep` updates on a versus result with a rival
  (win/loss/draw from `duelOf`). `recentScores` = last 10 counting scores (all modes).
- `versus_result` + tier, duel_step, ratio_x100, first.
- Acceptance: every stepCase / targetCase / pickCase of versus_duel.json passes in Dart.

**WP-F1 · Shop unlock R8 + wallet lifetime counters + economy events (S, 2 h)** — PRD:815-823, R8 (PRD:81).
Deps: S0, J2 (level). Paths: `lib/menu/menu_state.dart`, `lib/game/config.dart` (`menuUnlockGames`), `lib/menu/wallet.dart`,
`lib/skins/item_store.dart`, `lib/services/game_services.dart`, `lib/game/flappy_game.dart` (lock copy :2268/:2529 stays),
tests `test/menu/shop_unlock_test.dart`, `test/menu/wallet_counters_test.dart`.
- `menuUnlocked(best, games, level)`. Bought = `CoinSource.iap` (+ `gift`?). Earned = every other `add`. Spent = `spend`.
  **Builder must state the gift/noadsBonus classification in the test** (PRD silent).
- `item_bought` / `first_item_bought` (fields PRD:822) in `purchase`. `economy_daily` once per local day (first launch
  or run end of a new day) with the 3 totals.
- Acceptance: each of the 3 unlock paths; counters survive reload; first_item_bought only once.

**WP-J3 · Results page: level bar, rank line, level-up stage (M, 3–4 h)** — PRD:1084-1100 (J7a rows 0–3.05 s, no-level settle 2.15 s).
Deps: J2. Paths: `lib/run/screens/results_screen.dart` (`LevelBar`, `ResultsLevelStage`, `ResultsLevelUpBanner`),
`lib/run/config/results_config.dart`, results tests (`test/run/screens/s3_14_s5_10_results_test.dart`).
Design: `design/levels_v26/item_reveal.html` (style A timing table). Texts L-A1, L-A3, L-A17, L-A18. Masters: R1 results
rays (or R2 pink for the LEVEL UP moment per the registry), `ConfettiBurst`, `CoinRewardAnimation`, `EmblemView`.
- The bar fills from `lvlPoints` by the score; "+N OVER · DROPPED" piece; emblem flash → new emblem; bar restarts; coins
  fly into YOUR REWARD; rank line; `Config.uiAccent`. A tap skips to the reveal.
- Acceptance: goldens L0 / L10 / L34; a no-level run settles at ≈2.15 s; the surplus label shows the dropped amount.

**WP-J4 · Results reveal sheet: mystery box, item, EQUIP / LATER, payout (M, 3–4 h)** — PRD:1084-1099 (3.55 s → end), J4 payout (PRD:1054-1058).
Deps: J3. Paths: new `lib/run/screens/level_reveal_sheet.dart`, `results_screen.dart` hook, `lib/skins/item_store.dart`
(equip). Masters: `P1Popup`-style sheet frame, `MysteryBox` (rarity colour; legendary second gold burst), `Twinkle` /
`ParticlePool`, `ItemTile` + art renderers / `LookPainter` for the EQUIP preview, `MenuTag` NEW, `MenuButton`. Texts L-A4…L-A8,
L-P4. Sounds: existing level cues (`Sfx.lvClaim` / `lv_up_big`).
- EQUIP: equips, the bird puts it on, "EQUIPPED ✓" +0.6 s, closes at +1.45–1.75 s. LATER: closes at once, NEW sticker.
  Both call `payPending()`. Fixed category words (never "GEARS").
- Acceptance: a widget test of the state machine; payout exactly once even if the page is killed mid-sheet; the item is
  not auto-equipped on LATER.

**WP-J5 · Home catch-up popup (S, 2 h)** — PRD:1101; C2 order PRD:533.
Deps: J2, J4 (shares the sheet). Paths: `lib/components/levels/level_up_popup.dart`, `lib/game/flappy_game.dart` (:2746-2845).
Texts L-P1, L-P2, L-P3 (drop L-P6, L-P7). Masters: P1 frame, R2 pink rays, MysteryBox.
- Shows only when `lvlPending` is non-empty at Home; lists several levels and pays them together.
- Acceptance: kill after the run-end roll → the popup shows the same item (no re-roll).

**WP-J6 · Levels screen rewrite (L → split if needed, 4 h)** — PRD:1102-1111.
Deps: J1, J2. Paths: `lib/components/levels/levels_screen.dart`, `lib/game/config.dart` (layout). Design
`design/levels_v26/levels_screen.html` (FINAL; top state = level 40). Texts L-A9…L-A16, L-A21. Masters: `EmblemView` /
`recordEmblem` (static rows), `MenuTag`, `CoinIcon`, `ItemTile` art, MysteryBox for the grey "?" box.
- **Conflict:** G4 puts a LEVELS · WORLDS · GUIDE · ALBUM tab bar above this content (`approvals_v26/levels_tabs.html`,
  O69). Build the levels list as a child component the tab bar can host.
- Acceptance: golden at L0, L10, L40; scroll-to-current; only the current row + header animate; carousel moves only on
  horizontal gestures.

**WP-J7 · Emblems in code: 32-slot EmblemView, idle layers, name fit (M, 3 h)** — PRD:1065-1082, :1112-1113.
Deps: J1. Paths: `lib/levels/emblem_painter.dart`, `lib/components/levels/emblem_view.dart`, `lib/run/hud/fit_name.dart`,
`lib/components/settings_player_card.dart`, `lib/share/share_card.dart` (L-P5 line), pubspec asset entry (only when the PNGs
exist). Image route with the painted fallback (J13); idle sweep/rays/twinkle/flicker; reduce motion.
- Acceptance: goldens at 320 pt for PORTAL PIGEON, COMET CONDOR, STORM PETREL (+ ETERNAL WING with badge 999) in the
  results rank line, settings card, versus name box, share card.

**WP-J8 · Emblem PNG export (art, M5)** — PRD:1065-1080. Sol export from `design/levels_v26/emblems.html` (SVG → PNG
@1x/2x/3x, transparent, plate-centred); separate animated layers. Not a code package; blocks production only (J13).

**WP-J9 · Rank achievements on run score (S, 1 h)** — PRD:1118-1123, R5 (PRD:78).
Deps: J1 (kLevels no longer has thresholds). Paths: `lib/achievements/achievements.dart` (:239, :293),
`lib/achievements/achievement_catalog.dart` (:529-540), `lib/game/flappy_game.dart` finishRun call (:4224),
`test/p231/s12_*`, new `test/achievements/achievements_rank_score_test.dart`.
- Acceptance: one counting run of 400 earns rank_egg…rank_glider at once; a debug run earns none; earned stay earned.

**WP-K · Beat your best (M, 3 h)** — PRD:1179-1192, R7 (PRD:80).
Deps: S0. Paths: `lib/run/hud/run_hud.dart`, `lib/run/config/hud_config.dart`, new `lib/run/effects/best_line.dart`,
`lib/run/run_controller.dart` (score watch), `lib/game/flappy_game.dart` (save `bestRunHoops` with a new best),
analytics. Design `design/levels_v26/beat_your_best.html` variant A only. Texts L-A19, L-A20. Masters: `GoldSticker.newBest`,
`PerfectBurst`/`Twinkle` for the burst, existing new-best SFX. Line via `world.addRun(...)`.
- Acceptance: PRD:1190 list (Free Fly + solo versus only; once per run; nothing at best 0; line x at 568 / 711 / tablet
  width; `bestRunHoops` saved only on a new best) + `best_beaten`, `run_end.beat_best_hoop`.
- Note: the weekly course hides this chip (texts W-10; G5, other auditor).

**WP-F2 · Economy budget test (M, 3 h)** — PRD:810-814, :824-828, :945, F12 PRD:860.
Deps: J1 (level coins), WP-B showcase (built). Paths: new `test/economy_budget_test.dart` (+ helpers under `test/p26/bot/`).
- 3 bot profiles (weak/medium/strong human-noise) × 20 seeds × 568/711; the PRD bounds; showcase runs 1–3 = 90–200;
  level coins ≤ play coins over medium's first 50 runs; a meta ≤ 25 % case holding a source list that G/LB extend.
- Risk: the bots are slow; tag it heavy or keep the seeds per CI time budget. The human-noise gate is red today
  (median 7/6 < 40), so the profiles may need D-01 calibration first.

**WP-F9a · Card catalogue + `SkinLayer.card` + `look.card` (M, 3 h)** — PRD:830-833.
Deps: none. Paths: `lib/skins/look.dart`, `lib/skins/catalog.dart` (new card lists, 51 + 9), `lib/skins/item_store.dart`,
`lib/versus/run_entry.dart` (`lookToMap` / `lookFromMap` card string), `lib/game/storage.dart` (equipped card slots).
New test `test/skins/card_catalog_mirror_test.dart` parsing `functions/src/card.ts` (the same id lists, the same order).
- Names/prices/rarity from `design/approvals_v26/versus_cards.html` "THE 51 ITEMS + 9 SKILL ITEMS".
- Acceptance: 17/kind, 6/5/4/2 split, 250/750/2000/5000; card string ≤ 48 chars with exactly 2 `|`; old runs without
  card decode to empty.

**WP-F9b/c/d · Card painters: frames / name styles / stickers (3 × M, 3–4 h each)** — PRD:830-837, O82, O86.
Deps: F9a. Paths: new `lib/skins/art/card_frame_art.dart`, `card_name_art.dart`, `card_sticker_art.dart` (+ registry
entries in SHARED_ELEMENTS.md, since the WP-LB rows reuse these painters, PRD:1202). Design `versus_cards.html` art
(20 per kind incl. skill). Animated off the game clock; ShaderMask for gradient names; per-glyph Flappy; Thunderstruck per
O86.
- Acceptance: one golden sheet per kind; frames ≤ 7 pt outside the avatar box; animations freeze with the run clock.

**WP-F9e · Shop CARDS tab + fixed header (M, 4 h)** — PRD:834-835, O79.
Deps: F9a, F9b–d (tiles). Paths: `lib/components/skins/skin_shop_screen.dart`, `skin_tab_bar.dart`, `item_tile.dart`,
`shop_widgets.dart`. Masters: `ItemTile`, `ShopActionButton`, `PriceChip`, R4 preview rays, `UnlockBanner`. Texts CO-1, CO-10.
- 6 tabs; FRAMES/NAMES/STICKERS row; "x/20" + tab "x/60"; the fixed header on all tabs with a clipped grid scroll, a 5 pt
  shadow and a thin scroll bar; sounds `sk_buy_<rarity>`, `sk_equip`.

**WP-F9f · Card display in versus (M, 3 h)** — PRD:833.
Deps: F9b–d. Paths: `lib/run/screens/versus_intro.dart`, `lib/run/hud/versus_bar.dart`, `name_chip.dart`,
`results_screen.dart` (winner sticker). The opponent card comes from `look.card` in the pool entry.

**WP-F10a · Skill items model: unlock, ownership, counters, PROUD PEACOCK (M, 3 h)** — PRD:838-856, O80/O81/O85/O88.
Deps: F9a, J10 (achievement ids). Paths: `lib/skins/catalog.dart` (`SkinItem.unlock`), `lib/skins/item_store.dart`
(`isOwned` derived from the achievement state), `lib/achievements/*` (skin_all rule), collection totals.

**WP-F10b · Skill UI: secret tiles, HOW TO EARN sheet, gold reveal, reveal order (M, 3–4 h)** — PRD:845-853.
Deps: F10a, F9e, J4. Design `skill_cosmetics.html`, `versus_cards.html`. Texts CO-2…CO-5, CO-11…CO-16, CO-19. Masters:
MysteryBox (gold + plum ribbon + legendary ring), R4 rays, `ItemTile`, `MenuTag`.

**WP-F10c · Skill item art: 15 shop-kind items (L, split 2 × 3–4 h)** — PRD:840-845, :856. Paths: `lib/skins/art/*_v23.dart`
siblings (new `*_v26.dart`). Design `skill_cosmetics.html` THE 24 ITEMS.

**WP-J10 · 10 new achievements + counters (M, 3–4 h)** — PRD:1124-1139, O82/O83.
Deps: S0, E2 (rival result), J9. Paths: `lib/achievements/achievement_catalog.dart`, `achievements.dart`,
`achievements_feature.dart`, `lib/run/items/versus_recorder.dart` (deficit/ratio/streak data), tests `test/p231/s12_catalog_test.dart`
(58 / 965, groups). Ids `fs_ach_<key>` for iOS; Play ids = OWNER (C6, drafts). BIRDWATCHER needs the flight guide (G6);
TOP BIRD needs the WP-LB client: add hooks only and leave the trigger to those packages. Icons: approved (O96), export in M5.

## 5. Risks / conflicts

- **Test env broken:** package_config points at the deleted df4 cache (see §1). Fix it before any builder starts.
- **`levelFor` removal touches many files:** lib `versus_service.dart`, `run_entry.dart`, `share_card.dart`,
  `soak.dart`; tests `test/levels/levels_test.dart`, `test/e2e/home_v3_round1_e2e_test.dart`,
  `test/p23/s21_versus_identity_test.dart`, `test/share/share_card_golden_test.dart`, `test/versus/s3_13_emulator_test.dart`,
  `test/versus/s3_13_upload_entry_test.dart`. The `kLevels` / `levelDef` / `pendingLevelUp` users (24 files incl.
  `home_screen.dart`, `results_screen.dart`, `soak.dart`, `test/p23/s14_2_economy_test.dart`, `s26_qa_interplay_test.dart`)
  break when J1 changes `LevelDef`. Run J1 → J2 → J3/J5/J6 in sequence, not in parallel.
- **`flappy_game.dart` endRun (:4169-4290)** is edited by J2, E1, E2, K, F1 and by the WP-LB/G packages. Serialize the
  edits, or extract a `RunEndBookkeeping` helper in J2 first.
- **Results page** is shared with WP-LB "the climb" (`ResultsCard` master) and G1 mission pips: one owner per region.
- **Levels screen** is shared with G4 tabs (levels_tabs.html). Build J6 as hostable content.
- **Popup queue / C2 order** (PRD:533): the LEVEL UP catch-up sits second. The popup budget (WP-C2, #38/#91) has to know
  the new pending API.
- **PRD contradiction:** J4's `lvlPending` `star` field and J11's "star rule" against O17b "no stars" (DEFER?:
  recommend dropping them).
- **PRD ambiguity:** F7 does not say how gift / noadsBonus / rewarded coins count (earned vs bought). The builder decides
  and documents it.
- **`bestRunHoops` vs `bestHoops`:** different meanings (hoops in the best-*scoring* run vs the most hoops ever). Easy
  to confuse; WP-K must not reuse `bestHoops`.
- **Seal:** adding `lvlIndex` / `lvlPending` to `_sealHashes` changes the seal record. Test the upgrade path (2.5 sealed
  store → 2.6 load) or the store will be flagged as tampered.
- **F5 bots** depend on the red human-noise gate (D-01 calibration). Do F2 after that decision is implemented.
- **Deploy dependency:** the client `plv` / `look.card` / bracket work assumes the wave-0 functions + rules deploy
  (OWNER, C1) happens before any 2.6 build reaches a device.
