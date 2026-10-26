# a7-meta-ui-release — WP-G, WP-LB client/UI, WP-I, §4 waves 3–5 + rollout, §7, §7.5

Auditor: a7 · tree `feat/2.6` @ a57a7fb · PRD = `docs/p26/PRD-2.6-fun-progression.md` (line refs below are into it).

## 1. Summary

- **Almost nothing in this area is built.** Waves 3–5 never started. `lib/progression/`, `lib/leaderboard/`,
  `lib/components/progression/`, `lib/components/leaderboard/`, `lib/components/levels/tabs/` do not exist
  (`ls` → "No such file"). None of the G / LB storage keys exist: `grep -rn "lbQueue|missionDay|streakDays|
  worldsReached|albumCounts|guideSeen|starRoad|homeLevelsTag|weeklyBest|firstWinDay|vsWinStreak" lib tool` → only a
  comment-free hit in `lib/game/home_moments.dart`. No `lb_*`, `mission_*`, `streak_*`, `weekly_*`, `starroad_*` tuning
  keys in `lib/run/config/tuning_defaults.dart`.
- **What exists and is reusable:** (a) the C2 arbiter `lib/game/home_moments.dart` with the full 2.6 enum order
  (`streakLost, levelUp, streakReward, leaderboardCollect, missionsChest, starRoad, noAds, rating`) and typed
  `HomeVisitRequests` — production only feeds `levelUpCatchUp / noAds / rating` (`flappy_game.dart:1042-1056`);
  (b) `bestHoops` storage + raise-only save (`storage.dart:195,1197`), written from counting runs
  (`analytics_router.dart:701-704`); (c) the box master `lib/components/ui/mystery_box.dart` and the registry
  `docs/p26/SHARED_ELEMENTS.md` (rays R1–R4, box, confetti, coin fly, P1 popup, MenuTag, GoldSticker …);
  (d) WP-LB **server** (M0: `functions/src/board*.ts`, callables in `functions/src/index.ts:224-242`) — not deployed;
  (e) reminders infra `lib/services/reminders.dart` (2 slots/day × 7 days, rotation, payloads) with the C3 text fixes.
- **Still old behaviour that 2.6 must change:** Home trophy box opens the **native** leaderboards
  (`home_screen.dart:159` → `game.showLeaderboard`), the medal box is still there (`home_screen.dart:162-180`,
  `config.dart:1499-1520`), reminders have no decay (`reminders.dart:415-421`: 2 slots every day for 7 days).
- **Upstream dependencies not built either (other auditors):** WP-J (31 levels; `kLevels` still has 11 entries,
  `lib/levels/levels.dart:52`), WP-K beat-your-best line (no code), F9 card painters / F10 skill items (no
  Thunderstruck/Skywriter etc. in lib), J9 new achievement ids (catalog has 48). Levels tabs, weekly results,
  N7 notification, SPACE FLYER card title, album/Star Road item rewards, board rows all hang on them.
- **§7:** every design (D3–D18 except D2) and every text (T1–T12, T14, T16) is approved (O92/O93/O96); remaining
  owner items are D2 (emblem export check), T13 (release notes, marketing agent), T15, C1/C3/C5/C6/C7/C8/C9 and the
  privacy-page deploy (O95).
- **Tests:** after the orchestrator's `pub get --offline`, `test/p26/home/home_moments_test.dart` passes (7/7). It is
  the only existing test in this area. Everything else in scope has no tests, because the code does not exist yet.

## 2. Requirement table

Status: DONE / FIX / TODO / OWNER / DEFER?. "absent" = grep over `lib/ test/ tool/` finds nothing.

### WP-G1 Daily missions (PRD 870–879)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| G1.1 | unlock from game 4 (O28) | TODO | absent | `missions.dart` gate `gamesPlayed ≥ 3` before the run starts |
| G1.2 | 3/day easy/med/hard, roll only when `today > missionDay` (rollback safe) | TODO | absent | pure model + `missions_test` |
| G1.3 | rewards 20/35/55 auto-claimed at run end; `CoinSource.mission` | TODO | `CoinSource` has no `mission` (`lib/menu/wallet.dart:6-32`) | add sources + payout at run end |
| G1.4 | BONUS CHEST: feather if ≤1 held, else piece if ≤2, else 40; opens next Home visit (C2 `missionsChest`); `CoinSource.missionChest` | TODO | `HomeVisitRequests.missionsChest` never set (`flappy_game.dart:1042-1056`) | chest pending flag + C2 source + moment |
| G1.5 | chest moment: MysteryBox gold (O99), existing ray (O98), confetti, sparkle ring, `pairBoxOpen`+`bnPrizeM` | TODO | absent | reuse `MysteryBox`, rays R1 or R3, `ConfettiBurst`, `Twinkle` |
| G1.6 | templates M01–M15 × T0–T3 from `texts.html` §1 (PRD says "progression §3.3": the table is in texts.html) | TODO | absent | encode table as data |
| G1.7 | M15 world targets 20/40/80, not at T0; M05 counts capsules/shield/comet star/pair gift, not hearts/armed BH/streak-gift starts (O32) | TODO | absent | event filters in counter |
| G1.8 | M10 only when online and last versus run found a rival | TODO | absent | needs a stored "lastVersusHadRival" bit |
| G1.9 | tiers by `bestHoops` T0<15, T1 15–39, T2 40–99, T3 ≥100, fixed at first roll; `missionTier` | TODO | `bestHoops` exists (`storage.dart:195`) | read at roll |
| G1.10 | only met elements; no template twice a day; not yesterday's hard; ≤1 mode-only mission | TODO | absent | roll rules + tests |
| G1.11 | every non-debug run counts (versus, free fly, weekly), revive runs fully | TODO | absent | hook at run end via `countsForAchievements` |
| G1.12 | UI: strip under START (568 kept, emblem shrinks), panel 54 pt rows, no difficulty labels, no explanation lines, "ALL 3 DONE" chest row, "NEW IN 5 H 12 M" | TODO | absent | `missions_panel.dart` + Home strip; design `missions.html` §1–§2 |
| G1.13 | results pips (§3 of design) | TODO | absent | results-page row |
| G1.14 | reroll: one/day rewarded ad, any unfinished mission; SWAP hidden after use; `missionRerollDay`; needs a new `AdPlacement` (e.g. `missionReroll`) | TODO | `AdPlacement` has 4 values (`ads_service.dart:15-21`) | add placement |
| G1.15 | analytics `mission_assigned/complete`, `missions_all_done`, `mission_reroll` | TODO | absent | |
| G1.16 | `missions_test` items (PRD 957) | TODO | absent | |

### WP-G2 Day streak + STREAK LOST (PRD 881–899)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| G2.1 | 1 finished run / local day keeps it; miss breaks; **no freezes** | TODO | absent | `day_streak.dart` pure model |
| G2.2 | rewards 20,30,BH,40,shield,50,feather(→piece→50)+60; paid on COLLECT; free BH/shield kept until next run | TODO | absent (`streak_rewards` tuning absent) | model + Home `streakReward` source + `CoinSource.streak` |
| G2.3 | flame chip (drawn, 3-layer flicker, embers, grey when not flown, gold dot, reduced motion) right under coin pill | TODO | absent | `streak_strip.dart`; design `day_streak.html` §1 |
| G2.4 | streak card: tiles 1–7, "ENDS AT MIDNIGHT"/"NEXT REWARD TOMORROW" | TODO | absent | design §3, texts S-rows |
| G2.5 | BH/shield fly-in to slot button (0.6 s, 1.14× pop, flash, ~22 confetti, `skHoop`/`puShieldGet`, FREE tag) | TODO | absent | reuse `FetchFlight`/`ConfettiBurst` |
| G2.6 | STREAK LOST trigger `today > streakLastDay+1`, every n ≥ 1 (O72), first in C2, never in runs 1–3 | TODO | budget selects `streakLost` first (`home_moments.dart:163`) but no source, and no runs-1–3 guard in the budget | source + guard |
| G2.7 | content S-28/29/30 (+ singular b-forms), RESTORE / GIVE UP / × | TODO | absent | `streak_lost_popup.dart`, design §4 |
| G2.8 | payment: `AdPlacement.streakRestore` ('streak_restore') after UMP/ATT; No-Ads → RESTORE·500 (`streak_restore_coins`, `CoinSource.streakRestore` spend), grey <500 with S-37 | TODO | no placement | add |
| G2.9 | no video: LOADING ≈8 s → TRY AGAIN + S-36; never lost on ad failure | TODO | absent | |
| G2.10 | pending across days (`streakLostSeenDay`), × → next visit; runs meanwhile build k | TODO | absent | |
| G2.11 | RESTORE: `streakDays = n+k`, `streakLastDay = max(last, yesterday)` | TODO | absent | |
| G2.12 | only the last streak (O73, cases A/B/C, `day_streak.html` §4b) | TODO | absent | test all three cases |
| G2.13 | GIVE UP → k (grey 0 if none, O74) | TODO | absent | |
| G2.14 | moments: relight on rays (existing ray, O98), count 0→n, 1.28× pop, ~24 confetti, `rvIgnite`, S-38, chip pop; give-up drain + `skClose` | TODO | absent | |
| G2.15 | `achDayStreak` unchanged | DONE | `storage.dart:359` untouched | keep separate |
| G2.16 | Delete My Data keeps streak keys (O57) | TODO | — | assert in delete test |
| G2.17 | analytics `day_streak`, `streak_lost_shown`, `streak_restore`, `streak_restore_ad_fail`, `streak_give_up` | TODO | absent | |
| G2.18 | `day_streak_test`, `streak_restore_test` (PRD 958) | TODO | absent | |

### WP-G3 Notifications (PRD 900–910)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| G3.1 | state-aware texts chosen at scheduling time, priority N1→N7 | TODO | scheduler only rotates the 20 generic messages (`reminders.dart:446-…`) | `ReminderState`/plan gets a truth snapshot |
| G3.2 | N1 streak at risk (evening, streak ≥ 2) — **N1a only** | TODO | — | see conflict §5.1 (N1b mentions a freeze) |
| G3.3 | N2/N2s missions left (+coins sum), N3 new missions | TODO | — | needs G1 |
| G3.4 | N4 2 feathers, N5 3 pieces | TODO | — | storage already has feathers/puzzlePieces |
| G3.5 | N6a/b/c weekly ending (<24 h before Mon 00:00 UTC) | TODO | — | needs G5 week clock |
| G3.6 | N7 level almost reached (needed ≤ average run score) | TODO | — | needs WP-J points + `recentScores` |
| G3.7 | no Star Road notification (N8 dropped) | TODO (just don't build) | — | |
| G3.8 | decay: 2/day days 1–3 after last run, 1/day days 4–7, none after | TODO | `windowSlots = 7*2` fixed (`reminders.dart:415-421`) | change slot builder |
| G3.9 | `notif_opened {type}` | TODO | payload has no type (`reminders.dart:253-300`) | add type to payload |
| G3.10 | S3: no schedule without permission, launch ask unchanged | DONE (existing) | `requestPermissionIfNeeded` path unchanged | keep; test |
| G3.11 | reminder truth / decay tests | TODO | absent | |

### WP-G4 Levels tabs + Worlds (PRD 912–921)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| G4.1 | 4 text tabs LEVELS·WORLDS·GUIDE·ALBUM at x14–306, y134–162, 70×28, 4 pt gap; open = #EC008C/white Opificio 11, others #FCD9EE; gold dot top-right; top row only back | TODO | `levels_screen.dart` single screen | `lib/components/levels/tabs/levels_tabs.dart`; design `levels_tabs.html` |
| G4.2 | header box moved down 32 pt (14,172 · 292×84), list from y264; title names the tab; always opens on LEVELS; back → Home; `Sfx.skTab` | TODO | — | depends on WP-J J7 levels screen |
| G4.3 | worlds = 10 scenes, one per 20 hoops, SPACE at 180; 1 at top → 10 bottom, opens scrolled to furthest (O87) | TODO | — | `worlds_tab.dart`, `worlds_map.html` |
| G4.4 | cards reached/next/locked (grey + number + lock only), own menu palette per world, header lines (texts §5 WO-*) | TODO | — | |
| G4.5 | no in-run sticker; gold dot on WORLDS until opened, then burst + `lvUp` | TODO | — | `worldsReached`, `worldsSeen` |
| G4.6 | Home NEW tag on emblem (`MenuTag("NEW")`, `newTagWobble`), `homeLevelsTag` bool; set at run end on new dot, cleared on opening Levels; never runs 1–3; waits behind LEVEL UP | TODO | — | |
| G4.7 | SPACE FLYER title on versus card (VS intro + results race card); client writes `space: true` into the players doc | TODO | server copies `space` (`functions/src/pools.ts:145-150,248`); client never writes it (grep `space` in lib: none) | client field + card line |
| G4.8 | analytics `world_reached` | TODO | | |

### WP-G5 Weekly course (PRD 922–929)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| G5.1 | seed = hash(UTC ISO year, ISO week, compiled salt); week flips Mon 00:00 UTC | TODO | absent | `weekly_course.dart` + `weekly_week_test` |
| G5.2 | rules: normal curve, every gate open, no home slot, no revive, unlimited tries | TODO | `RunSetup` has `ignoreGates` (`run_setup.dart:51`) but no weekly flag | add `RunSetup.weekly` (+ mode 'weekly' for LB submit) |
| G5.3 | rewards 15/30/60/120 → 40/80/150/300 (`weekly_rewards`), `weeklyBest`, `weeklyRewards` reset weekly | TODO | | |
| G5.4 | no weekly board; submits to `bestScore` as any run | TODO (only don't build) | | |
| G5.5 | entry: card at top of missions panel ("WEEKLY COURSE · 3 DAYS LEFT · BEST HOOP 34 · ▶ PLAY"); once-a-day results line (`weeklyHintDay`; at 568 only on runs where no mission moved) | TODO | | design `weekly_course.html` §1 |
| G5.6 | weekly results: banner + tiers, no level line (O76), trophy → our board, HOME + ▶ FLY AGAIN | TODO | | §3 of design |
| G5.7 | in-run "WEEK n" flag on the beat-your-best line, NEW WEEK BEST! (GoldSticker) | TODO | WP-K not built | depends WP-K |
| G5.8 | unlock gamesPlayed ≥ 6 and bestHoops ≥ 40 | TODO | | |
| G5.9 | analytics `weekly_run`, `weekly_reward` | TODO | | |

### WP-G6 Extras (PRD 931–943)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| G6.1 | first versus win of the day +20 (`CoinSource.firstWinDay`, `firstWinDay`), gold line FW-1 under reward row, NEXT moves 10 pt with missions strip; only "YOU WIN!" | TODO | absent | `first_win_of_day.html` style A |
| G6.2 | album: 8 pictures, `albumCounts` (all 0 at update), `albumRewardClaimed`, `albumRewardItem`; in-progress pieces count (O78); first full album → unowned EPIC any category (R9 fallback up, then coins); ×n laps | TODO | puzzle round exists (`storage.dart:300-303`, `puzzle_config.dart`) | `album_tab.dart`, `puzzle_album.html`, PA-* |
| G6.3 | flight guide: all 32 (10/7/5/7/3), silhouettes "? ? ?", "Not met yet.", FG-E rule lines win (Q16); per-theme portal ids in `metElements`; SPIKES met from run 1; `guideSeenCount` gold dot; BIRDWATCHER at 32 (25 pts) | TODO | no guide UI anywhere; `metElements` has only `portal` | `guide_tab.dart`, `flight_guide.html` |
| G6.4 | Star Road stars 1/2/3, +2 first run of day, +3 all done, max 11; 8/tier, 25 tiers, 28-day seasons | TODO | absent | `star_road.dart` model + `star_road_test` |
| G6.5 | rewards table, tier 5 feather, 15 piece (50 if 3 held), 10/20/25 RARE/EPIC/LEGENDARY unowned else 250/500/1000; "MYSTERY" only, rarity chip in reveal (O75/Q28) | TODO | | |
| G6.6 | `SEASON_NAMES[13]`, season n → (n−1) mod 13; header "SEASON n" + name; auto-claim at season end, summary in panel | TODO | | texts SR-SN1–13 |
| G6.7 | entry card in missions panel ("4 / 8 STARS TO TIER 11"; 44 pt one-liner when panel overflows); no 5th Levels tab | TODO | | |
| G6.8 | Home popup once/day (`starRoadPopupDay`), never runs 1–3, never with chest; O91 motion/sound | FIX/TODO | C2 has a `starRoad` slot but day memory is in-instance only (`home_moments.dart:107,147,169-173`), not persisted | persist via `starRoadPopupDay`; build popup |
| G6.9 | claim sounds `bn_coin` / `lv_claim` / `lv_up_big`; coin confetti | TODO | | |
| G6.10 | reveal rays = existing ray as is (O98) | TODO | registry `SHARED_ELEMENTS.md` R1–R4 | enforce |
| G6.11 | meta ≤ 25 % economy case incl. missions, streak, gifts, first win, Star Road (PRD 945) | TODO | (F5 test owner: WP-F auditor) | add meta case |

### WP-LB client + UI (PRD 1197–1208, 1242–1260)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| LB4.1 | `lib/leaderboard/lb_models.dart` matching the deployed server shapes | TODO | dir absent; server shapes `functions/src/board.ts:56-146`, `schema.ts:530-545` | see §5.3 (claim result shape) |
| LB4.2 | `lb_queue.dart` ≤ 30 runs, oldest first ≤ 10/call, flush on Home/resume/after run; drop after group-day, best candidates kept 7 d | TODO | | |
| LB4.3 | `lb_service.dart` Noop/Fake/Firebase, shared App Check/auth start-up serialized with versus, try/catch, 6 s box | TODO | App Check helper exists `firebase_versus_backend.dart:94-115` | reuse |
| LB4.4 | submit at run end after `submitBestScore` (`flappy_game.dart:4268`) only when `countsForAchievements` && `IntegrityGuard.trusted`; `t:1` for debug/profile/tester/e2e; `tl`/`fl` only when notable and `fitsLimits` | TODO | | `lb_submit_rules_test` |
| LB4.5 | `gift_apply.dart`: id sealed into `lbGiftsClaimed` before wallet write; `lbGiftPending` across kill; feather→piece→coins fallbacks; item → coins fallback; `CoinSource.leaderboardGift` | TODO | | `gift_apply_test` |
| LB4.6 | `lb_config.dart` + tuning `lb_results_min_games` 3, `lb_results_wait_ms` 4000, `lb_queue_cap` 30 | TODO | absent in tuning_defaults | |
| LB4.7 | main.dart: Firebase service on mobile (not soak), Noop otherwise | TODO | versus pattern `main.dart:116-137` | mirror |
| LB4.8 | Delete My Data: after `versus.deleteMyData()` ok → `leaderboard.resetLocal()`; `resetVersusData` clears 7 lb keys, keeps streak keys | TODO | `flappy_game.dart:4530-4542`, `storage.dart:1125` | |
| LB1.1 | board screen tabs TODAY (default) · BEST RUN · ACHIEVEMENTS (plain words, 11.5 pt) | TODO | | `board_screen.dart`, `leaderboard.html` §2–§3, §6 |
| LB1.2 | TODAY: ≤50 rows, timer, points only — **no BEST n** (O62); podium top 3 with gold/silver/bronze box markers only on podium | TODO | server sends `best` per row (`board.ts:113`) — client must not draw it | |
| LB1.3 | BEST RUN: top 50 + own pinned row, exact rank / "#~1 2xx" approximate | TODO | | |
| LB1.4 | rows: rank, avatar in versus-card frame, name style (F9 painters), tag (PLAYING NOW / time tag), one pink pill; own row pink, pinned; no likes/platform icon/report | TODO | F9 painters absent | plain fallback until F9 |
| LB1.5 | ACHIEVEMENTS tab → `game.showAchievements()` (`flappy_game.dart:4779`), board stays on its tab; signed-out = medal-box sign-in flow (Q29→O83) | TODO | | `lb_achievements_tab` event |
| LB1.6 | no-group state "YOUR GROUP STARTS WITH YOUR NEXT RUN" + PLAY (O67) | TODO | | |
| LB1.7 | picture guide overlay: LB-01, LB-36–39, trophy `fsTrophy()`, gold arrows, TAP TO CONTINUE; motion + sounds; auto on first open from trophy only, `lbInfoSeen`; later i box; real full-bleed spike strips (O90) | TODO | | `board_info_sheet.dart`, `leaderboard.html` §4 |
| LB1.8 | Home trophy → `game.openBoard()`; gold glow ring pulsing 2→4 pt; no badge | FIX | trophy → `showLeaderboard` (`home_screen.dart:159`) | |
| LB1.9 | medal box removed (O63): `homeAchievementsRectFor`, `homeMedal*`, medal button, `medalWiggle` | FIX | still present `home_screen.dart:81,162-180,322-325`, `config.dart:1499-1520` | remove + `home_screen_test` |
| LB1.10 | no native-board entry (O64); `submitBestScore` every run kept | TODO | `showLeaderboard` still wired | drop UI caller |
| LB1.11 | results climb: games ≥ 4, answer ≤ 4 s with better rank; slide-up `vsWhoosh`, `vsTick` per place, 0.55/1.1/2.3 s, GoldSticker "YOU CLIMBED N SPOTS!" `vsChime`; never holds the results page | TODO | | `results_climb.dart`, `leaderboard.html` §1 |
| LB1.12 | GO TO COLLECT (C2 after streak reward): podium, rows 4–5 "8h ago", LG-4/LG-5, no LG-6; one per visit oldest first | TODO | C2 slot + `oldestGift` exist (`home_moments.dart:166-170,180-189`); no source | `gift_popup.dart`, `leaderboard_gifts.html` §1 |
| LB1.13 | box opening: MysteryBox tier colour + pink ribbon, TAP TO OPEN, shake `skTick`, lid `pairBoxOpen` + `bnPrizeS/M/Big`, ray, confetti, COLLECT `col4Coins` + coin fly; item → `item_reveal.html` style A EQUIP/LATER | TODO | | §2 of gifts page |
| LB.A | analytics `lb_submit`, `lb_join`, `lb_board_open`, `lb_climb`, `lb_info_open`, `lb_achievements_tab`, `lb_gift_shown`, `lb_gift_collect` | TODO | | |
| LB.T | Dart tests: `lb_queue_test`, `lb_submit_rules_test`, `results_climb_test`, `board_screen_test`, `home_screen_test`, `gift_apply_test`, `home_moments_test` (COLLECT after streak reward), `delete_my_data_test`, obf/anchor test | TODO | none exist | |
| LB.E2E | Pixel e2e submit → row shows (`FS_LIVE_VERSUS`, `--no-uninstall`) | OWNER/orch | needs wave-0 deploy | after deploy |

### WP-I Docs (PRD 982–992)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| I.1 | SPEC DEVIATION: curve, tilt sign, Δy, hazard, calm, squeeze; showcase, gates | DONE (wave 1) | `SPEC.md:1898-1990` | re-check after M1 repairs |
| I.2 | SPEC DEVIATION: levels (31 + ETERNAL WING, points, items), brackets decoupled, `plv`; beat-your-best HUD | TODO | not in SPEC.md | after WP-J/K/E |
| I.3 | ARCH module map: `lib/progression/`, `lib/levels/` new models (+ `lib/leaderboard/`) | TODO | ARCH has only "2.6 wave 1 module map" (`ARCH.md:1754`) | |
| I.4 | mark PRD-2.3 §14.6, §26 and PRD-home-v3 §4 superseded | TODO | no "superseded…2.6" in `/home/killerhis/Projects/flappyspikes/PRD-2.3-update.md` / `PRD-home-v3.md` (workspace root, **outside the git repo**) | orchestrator edit (not a repo change) |
| I.5 | AGENTS.md: GA4/BigQuery (O10), functions + rules deploy for R3/R4, "test runs stay in pools" (O7) | TODO | no hits in either AGENTS.md | |

### §4 wave 5 art / goldens (PRD 1280)
| ID | requirement | status | evidence | what to do |
|---|---|---|---|---|
| W5.1 | 32 emblem PNGs @1x/2x/3x in `assets/emblems/`, `EmblemView` switches (J6) | TODO | `assets/emblems` absent; painter still 10 levels | after WP-J; D2 owner check |
| W5.2 | cosmetic art 51 card + 24 skill items (vector) | TODO | none in lib (F9/F10 auditor) | |
| W5.3 | 10 new achievement icons from `achievement_icons.html#export=<size>` (A variants for BULLSEYE / IRON BEAK / TOP BIRD) → in-game 160 px `assets/images/achievements/`, Play 512 `store/achievements/play/`, iOS 1024 `store/achievements/ios/` | TODO | 48 in-game / 48 play / 50 iOS files, none new | |
| W5.4 | goldens for new screens | TODO | | |
| W5.5 | full Pixel e2e | OWNER/orch | | |

### §7 approvals (status per O92–O96)
| ID | status | note |
|---|---|---|
| D1, D3, D4, D11a | approved (earlier rounds) | build reference |
| D5–D8, D9 tab, D10, D11b–d, D14, D16–D18 | approved O92 | build may start |
| D9/D10 item art | approved drawings; art export = W5.2 | blocks ship |
| D2 emblem export check | **OWNER** after W5.1 | blocks ship |
| D15 achievement icons | approved O96 | export = W5.3; console upload = C6 |
| D13 | dropped | — |
| T1–T12 (minus T3 dropped), T14, T16 | approved (O93, O95) | build from `texts.html` |
| T13 release notes | **OWNER / marketing agent** (O93) | must name daily board + gift boxes + optional restore video (S7); blocks ship |
| T15 store/website rank text | **OWNER / marketing** | blocks production listing |
| C1 functions+rules deploy (wave 0) | **OWNER/orch** (approved O27) | not deployed |
| C2 weekly board | dropped | — |
| C3 GA4/BigQuery settings | **OWNER/orch** (signed-in session) | blocks ship |
| C4 reroll + restore placements | code (G1.14, G2.8); uses existing AdMob units — no console action | |
| C5 Data safety / App Privacy | **OWNER** | blocks production |
| C6 10 new achievements in Play + Game Center as drafts | **OWNER/orch** (needs W5.3 icons + J9 ids) | blocks ship |
| C7 release clicks | **OWNER** | |
| C8 lb deploy + import | **OWNER/orch** with owner's OK on the day | |
| C9 test-player cleanup | **OWNER/orch** | release-blocking for production |
| §7.4 Q4–Q32 | all decided (O83/O84/O88) | no open product questions |

### §7.5 compliance (O27)
| ID | type | status | note |
|---|---|---|---|
| S1 | code (none) | TODO trivially | weekly submits to bestScore only |
| S2 | code | TODO | reroll + restore after UMP/ATT: route through existing `RewardedAds.show` (`ads_service.dart:124-139`, `_can` at :236) |
| S3 | code | partial | permission path exists; new state texts must reuse it |
| S4 | code + test | TODO | test that no G/LB reward path calls ads/IAP except reroll/restore |
| S5 | code | TODO | no coin/IAP path to any random draw |
| S6 | OWNER | — | = C5 |
| S7 | OWNER/marketing | — | review notes |
| S8 | code | partial | re-report on sign-in exists (`achievements.dart:389-400` `syncAll`); new ids are J9 |
| S9 | code | TODO | S-29 before ad, GIVE UP always, No-Ads never video |
| S10, S11, S12 | code | TODO | no odds text, no report action, no native-board link (`board_screen_test`) |
| CI | orch | — | `.github/workflows/build.yml:4-7` triggers on main/feat/ios/PR only: feat/2.6 needs a PR or `workflow_dispatch` per wave for the iOS compile |

### §4 rollout (PRD 1284–1291)
| step | who |
|---|---|
| 1 wave-0 deploy (indexes → rules → functions → TTL → import) | OWNER/orch (C1, C8) |
| 2 Play internal upload (Android only, O19) | orch builds AAB; OWNER presses publish (C7) |
| 3 owner plays fresh + upgraded 2.5 install | OWNER |
| 4 fix | code |
| 5 closed testing (no pool purge / board reset) | OWNER |
| 6 cleanup C9 + `lbMeta/import.cleanedAt`; privacy page PV-10 deploy (on the internal day, O95); Data safety / App Privacy (C5) | OWNER/orch |
| 7 production publish | OWNER |
| code-side gate | `SUBMISSION.md` "lbMeta/import.cleanedAt set" gate (LB3 cleanup bullet) — TODO, check `SUBMISSION.md` (not present in this repo: workspace root) |

## 3. Open findings from issues in this area

None of the df4 issues (#2–#127) touched WP-G, the LB client/UI or wave 5; the only related code is the C2 arbiter
(#38/#91, **#91 and its review #116 merged with a red verify and no tester verdict** — see WP-C auditor). Findings I
checked in code that matter to this area:
1. `HomeMomentBudget` keeps the Star Road once-a-day memory in the instance (`home_moments.dart:107,147`), so an app
   restart allows a second popup the same day → must be backed by `starRoadPopupDay` (G6.8).
2. `HomeMomentBudget._select` has no "never in runs 1–3" guard for `streakLost` (`home_moments.dart:163`); the Star Road
   gate is `gamesPlayed >= 3` (:171), i.e. the Home visit right after run 3 passes. Decide in G2/G6: sources must not
   raise requests while `gamesPlayed ≤ 3` (missions unlock at game 4, so ≥ 4 is the consistent bound).
3. Trophy still opens native leaderboards and the medal box is still on Home (LB1.8/LB1.9).

## 4. Proposed work packages (ordered; one Sol builder each)

Common rules for every WP: read `docs/p26/BUILD_NOTES.md`, `docs/p26/SHARED_ELEMENTS.md` (O97–O100: reuse masters,
rays R1–R4 as they are, `MysteryBox` for every box); strings only from `docs/p26/design/approvals_v26/texts.html`;
design page = layout/size/colour/timing; Opificio caps; reduced motion off-switch; every new run-end hook only for
counting runs (`countsForAchievements`); `flutter analyze` clean + named tests green.

**M3-0 · G/LB storage, tuning and enum skeleton** (≈2 h) — PRD 947, 1249, 1251, appendix 1544–1558.
Paths: `tool/gen_obf_strings.dart` (append), `lib/services/obf_strings.g.dart` (regen), anchor_strings.txt,
`lib/game/storage.dart`, `lib/run/config/tuning_defaults.dart`, `lib/menu/wallet.dart`, `lib/services/ads_service.dart`.
Do: all G keys (missionDay, missions, missionTier, missionRerollDay, streakDays, streakLastDay, streakPaidDay,
streakLostDays, streakLostSeenDay, worldsReached, worldsSeen, weeklyBest, weeklyRewards, weeklyHintDay, firstWinDay,
albumCounts, albumRewardClaimed, albumRewardItem, guideSeenCount, starRoadSeason, starRoadXp, starRoadClaimed,
starRoadPopupDay, homeLevelsTag) + LB keys (lbQueue, lbGroupId, lbGroupEnd, lbLastRank, lbGiftsClaimed sealed,
lbGiftPending, lbInfoSeen) with typed fields + save methods; Delete-my-data clears all **except streak keys**; tuning
`mission_rewards`, `mission_chest_coins`, `streak_rewards`, `weekly_rewards`, `streak_restore_coins`, `starroad_*`,
`lb_results_min_games`, `lb_results_wait_ms`, `lb_queue_cap` with `// §` comments; `CoinSource.mission, missionChest,
streak, streakRestore, firstWinDay, leaderboardGift, starRoad, album` (+ analytics names); `AdPlacement.missionReroll
('mission_reroll'), streakRestore('streak_restore')`. Coordinate with WP-J/F/E M2 builders: they append keys
(lvl*, recentScores, vsWinStreak*, vsBigWinsDay, abArm_v1) to the same files — run M3-0 serially with them.
Accept: obf/anchor tests green; new `test/p26/meta/storage_keys_test.dart` (round-trip, Delete-my-data clears lb +
G keys, keeps streak keys); tuning fixture tests updated.

**M2-LB1 · Leaderboard client model + service** (≈3–4 h) — PRD 1242–1247, 1251; server `functions/src/board.ts:56-146`.
Paths: `lib/leaderboard/{lb_models,lb_service,lb_config}.dart`, `lib/main.dart`, `lib/game/flappy_game.dart`
(constructor field only). Do: Dart models mirroring the server payloads (`LbBoardRow`, `LbBoardPayload`,
`LbGetBoardResult`, `LbSubmitRunResult`, `LbClaimGiftResult {ok,id,tier,prize{kind,coins,item,rarity,seed}}`);
`LeaderboardService` abstract + `NoopLeaderboardService` + `FakeLeaderboardService` (scriptable) +
`FirebaseLeaderboardService` (cloud_functions europe-west1, shares `FirebaseVersusBackend.activateAppCheck` and the
versus auth start-up, serialized with versus, 6 s timeout, every call try/caught). Wire in main.dart like versus
(mobile && !kSoak). Accept: `test/p26/lb/lb_models_test.dart` parses fixture JSON copied from the functions tests;
Noop never throws; timeout returns null within 6 s (fake clock).

**M2-LB2 · Submit queue + run-end submit + Delete My Data** (≈3 h) — PRD 1243, 1245–1246; deps M3-0, M2-LB1.
Paths: `lib/leaderboard/lb_queue.dart`, `flappy_game.dart` around `:4268` and `:4530-4542`, `lib/game/storage.dart`.
Do: queue ≤ `lb_queue_cap`, flush oldest ≤ 10/call on Home arrival, resume and after each run; drop entries after
their group-day except best candidates (7 d); submit only when `countsForAchievements && IntegrityGuard.trusted`;
`t:1` for debug/profile/FS_TESTER/FS_E2E; `tl/fl` from `RunEntry.fromSummary` only when notable and `fitsLimits`;
mode free/versus/weekly; keep `submitBestScore` every run; store `group`, `rank` into lbGroupId/End/LastRank;
`resetLocal()` after successful `versus.deleteMyData()`. Accept: `lb_queue_test`, `lb_submit_rules_test` (PRD 1258),
`delete_my_data_test` (lb keys cleared, streak kept); `lb_submit` analytics.

**M2-LB3 · gift_apply** (≈2–3 h) — PRD 1210–1212, 1243, F12 (860); deps LB1.
Paths: `lib/leaderboard/gift_apply.dart`. Do: claim → seal id into `lbGiftsClaimed` before wallet write;
`lbGiftPending` keeps an unshown result across a kill; feather if takeable else piece else pre-rolled coins; item
(shop, ≤ 750, common/rare, not card/skill items) else coins; `CoinSource.leaderboardGift`. Accept: `gift_apply_test`
(credited once across a simulated kill; each fallback); `lb_gift_collect` payload.

**M3-G1a · Missions model** (≈3–4 h) — PRD 870–879, 957; texts §1 (M01–M15 × T0–T3, M-UI, M-RS, M-RR); deps M3-0.
Paths: `lib/progression/missions.dart`, `test/p26/meta/missions_test.dart`. Do: pure model: daily roll seeded by
local day (stable), tier from `bestHoops` at first roll, met-elements filter, no repeat, not yesterday's hard, ≤ 1
mode-only, M10 condition, M15/M05 definitions (O32), rollback-safe, progress from a run summary/event counts, chest
roll (feather ≤1 / piece ≤2 / 40), reroll once a day on any unfinished. Accept: all `missions_test` bullets (PRD 957).

**M3-G1b · Missions wiring + payout** (≈3 h) — PRD 873, 877; deps G1a. Paths: `flappy_game.dart` run end /
`lib/run/screens/post_run_flow.dart`, `lib/progression/missions.dart`. Do: count every counting run from game 4
(all modes, revive runs fully), auto-pay mission coins at run end exactly once (kill-safe), set chest pending →
`HomeVisitRequests.missionsChest`; store `lastVersusHadRival`; analytics events. Accept: paid once after kill;
debug runs count nothing; chest request reaches C2.

**M3-G1c · Missions UI: strip, panel, results pips** (≈4 h) — design `missions.html` §1–§3; PRD 877; deps G1b.
Paths: `lib/components/progression/missions_panel.dart`, `lib/components/home/home_screen.dart` (strip only),
`lib/game/config.dart` (`*RectFor` helpers), `lib/run/screens/results_screen.dart` (pips row). Do: strip under START
(568 kept; tight-gap emblem shrink), panel title/countdown/rows 54 pt without difficulty labels and explanation lines,
"ALL 3 DONE" + gold chest icon (MysteryBox), slots for the weekly card (top) and Star Road card (filled by G5b/G6e);
results pips. Accept: `missions_ui_test` (no EASY/MEDIUM/HARD text, no explanation lines, 568 + 711 layouts).

**M3-G1d · Chest moment + reroll** (≈3 h) — PRD 873, 878; design `missions.html` §4; deps G1c.
Do: Home chest popup via `homeMoments.show(HomeMoment.missionsChest)`, MysteryBox gold lid open, existing ray (R3 gold),
confetti + Twinkle ring, `pairBoxOpen` + `bnPrizeM`, prize via feather/piece/coin masters; SWAP via
`AdPlacement.missionReroll` (UMP/ATT through RewardedAds), hidden after use. Accept: chest never on results page;
never with Star Road popup in one visit; reroll once/day; No-ad-fill leaves mission unchanged.

**M3-G2a · Day streak + restore model** (≈3 h) — PRD 881–899, 958; `day_streak.html` §4b; deps M3-0.
Paths: `lib/progression/day_streak.dart`, tests `day_streak_test`, `streak_restore_test`. Do: pure model incl.
rewards track, `streakPaidDay`, lost-offer logic (n ≥ 1, O73 replace, cases A/B/C, GIVE UP → k / grey 0, RESTORE n+k,
`streakLastDay = max(last, yesterday)`), `streakLostSeenDay` per-day re-offer, never runs 1–3. Accept: every bullet
of PRD 958 except UI/ads (those in G2c).

**M3-G2b · Flame chip, streak card, COLLECT reward** (≈4 h) — design `day_streak.html` §1–§3; texts §2; deps G2a.
Paths: `lib/components/progression/streak_strip.dart`, home_screen (chip mount), C2 `streakReward` source. Do: drawn
flame (3 layers 1.2/0.9/0.6 s, embers ≤ 1 pt, grey still flame, gold dot), card 1–7, COLLECT popup (P1Popup),
coins via CoinReward; free BH/shield fly-in to the slot (FetchFlight, 1.14× pop, flash, ~22 confetti, sounds, FREE
tag) and kept until next run. Accept: paid on COLLECT only; reduced motion = still; goldens chip lit/grey.

**M3-G2c · STREAK LOST popup + restore** (≈4 h) — PRD 888–898, S9; design §4; texts S-24, S-28–S-40 (+ b-forms);
deps G2a, M3-0. Paths: `lib/components/progression/streak_lost_popup.dart`, flappy_game C2 source. Do: popup first in C2,
RESTORE ▶ via `AdPlacement.streakRestore` (LOADING ≈8 s → TRY AGAIN + S-36), No-Ads RESTORE · 500 (grey < 500 + S-37,
`CoinSource.streakRestore` spend, coins fly into the button), GIVE UP, ×; moments (relight on existing ray, 0→n,
1.28×, ~24 confetti, `rvIgnite`, S-38; drain + `skClose`); analytics. Accept: `streak_restore_test` UI cases
(no video for No-Ads, failed ad keeps the offer next visit and next day, singular text for n=1).

**M3-G3 · State-aware notifications + decay** (≈4 h) — PRD 900–910, S3; texts §3 (N1a, N2/N2s, N3, N4, N5, N6a/b/c,
N7; **not N1b, not N8**); deps G1b, G2a, G5a (week clock), WP-J (N7; else ship N7 behind a null-safe input).
Paths: `lib/services/reminders.dart`. Do: truth snapshot input to `plan()`, priority, true-at-send rules (N1 evening of
the day after last run day, N2 only same mission day, N3 later day …), decay 2/day d1–3, 1/day d4–7, none after; payload
`type`; `notif_opened {type}`. Accept: reminder truth / decay tests; existing reminder tests unchanged in behaviour for
generic slots.

**M4-LB4 · Board screen + Home entry** (≈4 h) — PRD 1199–1205, O62–O64, O67, O89; `leaderboard.html` §2, §3, §5, §6;
texts §12 LB-01–LB-21, LB-40; deps LB1, LB2. Paths: `lib/components/leaderboard/{board_screen,board_row,podium}.dart`,
`home_screen.dart`, `config.dart`, `flappy_game.dart` (`openBoard`). Do: tabs TODAY/BEST RUN/ACHIEVEMENTS, timer,
podium + box markers (MysteryBox gold/silver/bronze) only on podium, rows (avatar `StickerAvatars`, F9 frame/name
painters when available else plain), pinned pink own row, no-group state + PLAY, ACHIEVEMENTS → `showAchievements`;
trophy → `openBoard`, glow ring 2→4 pt; **remove medal box + constants**; drop the native-board UI caller.
Accept: `board_screen_test` + `home_screen_test` bullets (PRD 1258); no "BEST" text on TODAY; no odds/report/link.

**M4-LB5 · Picture guide** (≈3 h) — PRD 1203, O59/O60/O67/O90; `leaderboard.html` §4 (`fsTrophy()`), texts LB-36–39,
LB-01, LB-17; deps LB4. Paths: `board_info_sheet.dart`. Accept: opens itself only on first open from the trophy
(`lbInfoSeen`), never over a results climb, i box reopens; spike strips via `SpikeTeethPainter` full bleed.

**M4-LB6 · Results climb** (≈3 h) — PRD 1206; `leaderboard.html` §1; deps LB2, LB4. Paths: `results_climb.dart`,
`post_run_flow.dart`. Accept: `results_climb_test` (≥ 1 place and game ≥ 4 → board; late > 4 s / no climb / ≤ 3 → none,
page never held); GoldSticker text from texts.

**M4-LB7 · GO TO COLLECT + gift opening** (≈4 h) — PRD 1208, O54/O65/O68/O84; `leaderboard_gifts.html` §1–§2; texts
LG-1–LG-15 (not LG-6/7/16); deps LB3, LB4, WP-J item reveal (J7a). Paths: `gift_popup.dart`, flappy_game C2 source.
Accept: `home_moments_test` (COLLECT right after streak reward; one per visit, oldest first); kill during opening →
reward once.

**M4-G4a · Levels tabs shell + Home NEW tag** (≈3 h) — PRD 914, 916; `levels_tabs.html`; texts §5/§6 tab labels;
deps WP-J levels screen (J7). Paths: `lib/components/levels/tabs/levels_tabs.dart`, `levels_screen.dart`,
home_screen (tag). Accept: geometry per PRD 914 at 568/711; opens on LEVELS; back → Home; dots; NEW tag rules (Q26).

**M4-G4b · Worlds tab + SPACE FLYER** (≈3–4 h) — PRD 912–921; `worlds_map.html`; texts §5; deps G4a, F9 card (title
line). Paths: `worlds_tab.dart`, run-end `worldsReached`, versus players-doc write (`space: true`), VS intro / race
card. Accept: order 1→10, scrolled to furthest, locked cards show no name; gold dot until opened; title only after SPACE.

**M4-G5a · Weekly course model + run rules** (≈3 h) — PRD 924–929; deps M3-0. Paths:
`lib/progression/weekly_course.dart`, `lib/run/run_setup.dart` (+`weekly`), director wiring (gates open, no slot, no
revive). Accept: `weekly_week_test` (flip Mon 00:00 UTC in several time zones: seed, countdowns, reset); rewards once.

**M4-G5b · Weekly UI** (≈3–4 h) — PRD 926–928; `weekly_course.html` §1–§3; texts §4 W-*; deps G5a, G1c, WP-K, LB4.
Accept: panel card, results hint once/day (`weeklyHintDay`, 568 rule), weekly results without level line, trophy →
board, WEEK n flag + NEW WEEK BEST!.

**M4-G6a · First win of the day** (≈1–2 h) — PRD 932; `first_win_of_day.html` style A; FW-1. Accept: only YOU WIN!,
once per local day, NEXT shift with strip.

**M4-G6b · Flight guide tab** (≈4 h) — PRD 934; `flight_guide.html`; texts FG-*, FG-E1–32; deps G4a, J9 (BIRDWATCHER id).
Do: per-theme portal ids in `metElements`, SPIKES met from run 1, 32 entries with silhouettes, `guideSeenCount` dot,
BIRDWATCHER unlock. Accept: count = 32; unmet "? ? ?" + "Not met yet."; dot logic.

**M4-G6c · Puzzle album tab** (≈3 h) — PRD 933; `puzzle_album.html`; PA-*; deps G4a, WP-J R9 item roll + J7a reveal.
Accept: `album_test` (starts empty, in-progress pieces count, first full album pays one EPIC once, later ×n only).

**M4-G6d · Star Road model** (≈3 h) — PRD 935–942; deps G1b. Paths: `lib/progression/star_road.dart`.
Accept: `star_road_test` (stars incl. +2 first run, max 11/day, 8×25, 28-day roll-over, season name index, auto-claim at
season end, popup once a day via `starRoadPopupDay`).

**M4-G6e · Star Road screen + panel card + claims** (≈4 h) — `star_road.html`; SR-*, SR-SN*; deps G6d, G1c, J7a.
Accept: MYSTERY tiles without rarity word; one-line 44 pt card when the panel overflows; claim sounds.

**M4-G6f · Star Road Home popup** (≈3 h) — PRD 940 (O91); `star_road_popup.html`; deps G6e. Accept: once/day, never
runs 1–3, never with chest, motion/sound list O91, reduced motion.

**M4-ECON · meta ≤ 25 % budget case** (≈1–2 h) — PRD 945; with the WP-F auditor's F5 test.

**M5-ART1 · 10 achievement icons export** (≈2 h) — O96; `docs/p26/design/approvals_v26/achievement_icons.html`
`#export=<size>` (rec variant) + `design/achievements/build_v26.py`; deps J9 final ids. Output 160 px in-game,
512 Play, 1024 iOS, names `ach_<id>.png`. Then C6 (owner/orch console drafts).

**M5-ART2 · 32 emblem PNGs** — WP-J/J6 auditor owns; D2 owner check.

**M5-DOC · WP-I** (≈2 h) — PRD 982–992: SPEC deviations for levels/brackets/plv/beat-your-best, ARCH module map for
`lib/progression/`, `lib/levels/`, `lib/leaderboard/`; AGENTS.md (repo copy) lines for GA4/BigQuery, wave-0 deploy,
O7. Superseded marks in workspace-root PRDs = orchestrator.

**M5-GOLD · goldens** for chip, panel, board, popups at 568/711 (after the UI WPs).

## 5. Risks / conflicts

1. **texts.html N1b still present** ("…Save your freeze for a busy day!", N1b-T/N1b-B "PROPOSED") although freezes are
   gone (O46). Build N1a only; ask the orchestrator to strike N1b on the page (no owner decision needed: O46 rules).
2. **PRD G1 says "use progression §3.3"** for mission targets; that report is not in the repo. The approved table is
   `texts.html` §1 (M01–M15 × T0–T3) — point builders there.
3. **Claim result shape:** PRD LB3 says `lbClaimGift → {tier, kind, coins, seed}`; the built server returns
   `{ok, id, tier, prize: {kind, coins, item?, rarity?, seed?}}` (`board.ts:141-146`, `schema.ts:530-536`). The client
   must follow the server (or the server auditor aligns the PRD).
4. **TODAY rows carry `best`** from the server (`board.ts:113`); O62 says no BEST n on TODAY — fine if the client
   ignores it; the server auditor may want to strip it.
5. **`bestHoops` has no 2.5 backfill** (`storage.dart:493`): upgraded players start at T0 missions and the weekly
   course stays locked (needs bestHoops ≥ 40) until they fly 40 hoops in 2.6. Matches the PRD text; mention to the
   owner in the release notes, not blocking.
6. **Shared hot files:** `storage.dart`, `tool/gen_obf_strings.dart`/anchors, `tuning_defaults.dart`,
   `flappy_game.dart` (run end ~4220–4290, `_beginHomeVisit` 1037), `home_screen.dart`, `results_screen.dart`,
   `post_run_flow.dart` are touched by WP-J/K/E/F M2 builders and by every WP above. Serialize key additions (M3-0
   with M2 key WPs) and keep each WP's edits inside a `// region P26-G…` / `// region P26-LB` block.
7. **Dependency chain on unbuilt waves:** Levels tabs need WP-J's new levels screen; weekly UI needs WP-K; board rows
   and SPACE FLYER need F9 painters; album/Star Road/gift items need the J4/R9 roll and J7a reveal; BIRDWATCHER / TOP
   BIRD need J9 ids. Plan M2 (J, K, E, F) before M4.
8. **C2 guard gaps** (§3 items 1–2) must be closed when G2/G6 sources are added; the C2 module itself merged without a
   tester (#91/#116).
9. **iOS CI** does not run on `feat/2.6` pushes (`build.yml:4-7`); O27 requires an iOS compile per wave.
