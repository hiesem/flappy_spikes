# PRD-2.3 §14/§15 build notes (WP-TUNE)

## Playability gate (§14.4)

| Opening set | Bot | Result |
|---|---|---|
| 88→66 | 2.2 bot | 7 failures |
| 92→70 | 2.2 bot | 4 failures |
| 96→72 | 2.2 bot | 4 failures |
| 88→66 | bot fixes 1–3 | 4, then 1 failure |
| **88→66** | **final bot** | **140/140 pass** |

The PRD default **88 → 66 ships**; no fallback set was used. The fallback sets failed on the same bot weakness (the chase handover near moving and angled rings), not on the opening size. The fix is in `_farFromPlane` in `lib/run/debug/autopilot.dart`.

## Coin budget (§6.1, reported, not a gate)

20 seeded runs of 50 hoops at 711 pt, god mode. Command: `FS_BUDGET=1 flutter test test/p23/budget_report_test.dart`.

| | coins per hoop (mean) | range per run |
|---|---|---|
| Before (2.2 values) | **2.495** | 1.54–4.54 |
| After (2.3 defaults) | **2.125** | 2.02–2.24 |

The bot is almost always perfect, which pays 2 coins per hoop, so 2.00 is its floor. Every other source now adds only about 0.13 coins per hoop.

A real player who touches the rim on about half the passes earns roughly **1.6 coins per hoop**, close to the 1.5 goal. The live check is `run_end.coins_per_hoop` (§14.8).

## Tests changed because §14 changes behaviour

- **Speed, opening and director tables (§14.4/§14.5):** `config_test`, `s3_0_3_director_test`, `tables_mirror_test` with `spawn_tables.json`, `s3_0_2_layout_ramp_test`, `s7_run_parts_test`, `s3_0_4_rim_test`, `scrolling_test`.
- **Perfect = no rim touch (§14.3):** `s11_perfect_zone_test` (rewritten), `s13_points_test`, `s13_qa_p1_adversarial_test`, `s3_24_bullseye_test`, `s3_1_hoop_flow_test`.
- **Chick (§14.3):** `s3_27_egg_test`, `s23_egg_rim_test`, `s3_0_run_core_flow_test`.
- **Coin values (§14.2):**
  - item tests: `s3_26`, `s3_28`, `s3_29`, `s3_30`;
  - hoop tests: `s3_20`, `s3_21`, `s3_22`, `s3_25`;
  - also `s3_16_puzzle_test`, `s3_15_bonus_screen_test`, `p3_interactions_e2e_test`, `p45_gameplay_e2e_test`.
- **Revive ladder (§14.2):** `s3_14_revive_test`, `s3_3_s3_7_lives_test`.
- **Squeeze in hoops (§14.4):** `s3_17_squeeze_test`.
- **Hoop 0 stays 118 with Big Hoops (§0 item 3):** `s3_6_big_hoops_test`, `p1_gameplay_e2e_test`. DEVIATION 2026-10-19 (owner, 2.4.0 42): with Big Hoops hoop 0 grows too (177, gold, already on the waiting screen); `s10_waiting_start_test`.
- **Feather and piece (§14.2):** `s19_random_opening_test`, `s27_one_bonus_director_test`, `p45_gameplay_e2e_test`.
- **Level-up journeys:** `home_v3_round1_e2e_test`, `home_v3_round2_e2e_test`, `p2_gameplay_e2e_test`.
- **Spawn timing:** `s15_scroll_in_test`. A debug-forced moving ring on the very first slot can swing about 7 pt into view at 711 pt; real runs start at hoop 0, which never moves.
- **Forced-modifier gate:** `s3_10_s3_11_autopilot_test`.
- **Ride schedules (§14.5):** `s18_portal_rides_polish_test`, `s3_8_comet_test`.
- **Harness:** `helpers.dart` sets `runDebug.ignoreGates = true`, so any test of the lifetime gates must turn it off.

## New tests

`test/p23/s14_2_economy_test.dart`, `s14_4_difficulty_test.dart`, `s14_6_gates_test.dart`, `s15_tuning_test.dart` and `budget_report_test.dart`.

## Known, unchanged from 2.2

A swinging ring's swing reaches about 85 pt at 711 pt, so in principle it can creep a few points into view mid-run.
