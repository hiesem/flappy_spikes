// PRD-2.3 §15.2 / audit 17 (2026-10-19): the baked gameplay values.
//
// These were the in-app defaults of the removed Remote Config tuning layer.
// On 2026-10-19 every one of the 101 values was compared with the live
// Remote Config template (parsed with the app's own parser): all were equal,
// so no value changed when the remote read was removed. They are plain
// constants now; nothing fetches or overrides them at runtime.
//
// HOW TO ADD A VALUE: add one TuningDef line below, in its group, with a
// `// §<section> <what it is>` comment above it (never a string field:
// PRD-2.5 §3.5 keeps the descriptions out of the binary), and read
// it through the config getter of its feature: `tuning.i('<key>')` (int),
// `.d` (double), `.b` (bool), `.ints` / `.range` (int list),
// `.curve(...).at(hoop)` (keyframes), `.obj` (object).
library;

import 'tuning_types.dart';

/// Every gameplay value with its baked value (the §14 values, = live RC
/// of 2026-10-19).
const List<TuningDef> kTuningDefaults = [
  // §14.2 Coins for a hoop pass that is not perfect
  TuningDef('coin_hoop', TuningType.integer, 1),
  // §14.2 Coins for a perfect pass (and every ride hoop)
  TuningDef('coin_perfect', TuningType.integer, 2),
  // §14.2 Piggy Bank: every this many caught coins pay 1 (rounded down; 20 on screen = max 10)
  TuningDef('coin_piggy_per', TuningType.integer, 3),
  // §14.2 Firefly jar full (20 caught)
  TuningDef('coin_jar', TuningType.integer, 5),
  // §14.2 Lucky spin slices (equal chance)
  TuningDef('coin_spin_slices', TuningType.intList, [1, 2, 3, 1, 2, 1]),
  // §14.2 Star trail 8/8
  TuningDef('coin_star_trail', TuningType.integer, 2),
  // §14.2 Bullseye hit
  TuningDef('coin_bullseye', TuningType.integer, 3),
  // §14.2 Ring train 3/3
  TuningDef('coin_train', TuningType.integer, 1),
  // §14.2 Switch touched
  TuningDef('coin_switch', TuningType.integer, 0),
  // §14.2 Pair "+N coins" gift
  TuningDef('coin_pair_gift', TuningType.integer, 3),
  // §14.2 Coin frenzy capsule: coins per ring
  TuningDef('coin_frenzy_ring', TuningType.integer, 1),
  // §14.2 Versus win bonus
  TuningDef('coin_versus_win', TuningType.integer, 10),
  // §14.2 Versus draw bonus
  TuningDef('coin_versus_draw', TuningType.integer, 5),
  // §14.3 Points for a pass that is not perfect
  TuningDef('point_pass', TuningType.integer, 1),
  // §14.3 Points for a perfect pass: max(this, streak)
  TuningDef('point_perfect_min', TuningType.integer, 2),
  // §14.3 Chick: extra points per hoop passed
  TuningDef('point_chick', TuningType.integer, 1),
  // §14.3 A perfect FEVER pass sets the streak to max(this, streak + 1)
  TuningDef('point_fever_streak', TuningType.integer, 5),
  // §14.3 Pair "+N score" gift
  TuningDef('point_pair_gift', TuningType.integer, 5),
  // §14.3 owner 2026-10-13: perfect band ±pt around the gap centre by hoop index; <= 0 = no band (any rim-free pass is perfect). Owner 2026-10-20 (2.5.0 46): wider for hoops 0–20; × the hoop's Big Hoops growth.
  TuningDef('point_perfect_band', TuningType.curve, [
    [1, 40],
    [2, 40],
    [6, 36],
    [10, 30],
    [16, 24],
    [20, 18],
    [25, 14.5],
    [30, 13.9],
    [35, 13.2],
    [40, 12.7],
    [50, 11.8],
    [60, 11.2],
    [75, 10.6],
    [100, 10.2],
    [150, 10],
  ]),
  // §14.3 owner 2026-10-13: Bullseye hit band ±pt by hoop index (hit check only; the drawing stays 12)
  TuningDef('point_bullseye_band', TuningType.curve, [
    [1, 12],
    [50, 10],
    [100, 8],
  ]),
  // §14.2 Balloon prizes (shuffled; the largest is the jackpot)
  TuningDef('bonus_prizes', TuningType.intList, [
    25,
    25,
    25,
    40,
    40,
    40,
    50,
    50,
    100,
  ]),
  // §14.2 Chance per run that the golden feather appears
  TuningDef('bonus_feather_chance', TuningType.decimal, 0.6),
  // §14.2 The feather spawns at a random gap in [min, max]
  TuningDef('bonus_feather_gaps', TuningType.intList, [5, 30]),
  // §14.2 Chance per run that a puzzle piece appears
  TuningDef('puzzle_chance', TuningType.decimal, 0.6),
  // §14.2 The piece spawns at a random gap in [min, max]
  TuningDef('puzzle_gaps', TuningType.intList, [5, 30]),
  // §14.2 Puzzle completion reward [min, max, step]
  TuningDef('puzzle_reward', TuningType.intList, [40, 100, 5]),
  // §14.2 Coin revive prices after the ad revive; no revive after the last
  TuningDef('revive_ladder', TuningType.intList, [
    250,
    500,
    1000,
    2000,
    4000,
    8000,
  ]),
  // §14.2 A revive is offered from this many hoops passed
  TuningDef('revive_min_hoops', TuningType.integer, 6),
  // §14.2 One-time coin reward of levels 1-10
  TuningDef('level_rewards', TuningType.intList, [
    25,
    50,
    100,
    200,
    400,
    600,
    800,
    1000,
    2000,
    5000,
  ]),
  // §14.2 Shop free-coins ad: coins per ad
  TuningDef('shop_ad_coins', TuningType.integer, 75),
  // §14.2 Shop free-coins ad: ads per day
  TuningDef('shop_ad_per_day', TuningType.integer, 5),
  // §14.2 Shop free-coins ad: cooldown (s)
  TuningDef('shop_ad_cooldown_s', TuningType.integer, 300),
  // §14.4 Cruise speed (pt/s) by hoop index
  TuningDef('curve_speed', TuningType.curve, [
    [0, 150],
    [50, 172.5],
    [150, 187.5],
  ]),
  // §14.4 Opening (pt) by hoop index from hoop 1 (hoop 0 is always 118; rides follow it, PRD-2.4 §2)
  TuningDef('curve_opening', TuningType.curve, [
    [1, 118],
    [2, 118],
    [6, 114],
    [10, 110],
    [16, 105.5],
    [20, 102],
    [25, 98],
    [30, 95],
    [40, 88.5],
    [50, 83],
    [60, 79],
    [75, 75.5],
    [100, 72.5],
    [125, 71],
    [150, 70],
  ]),
  // §14.4 Moving-hoop chance by hoop index
  TuningDef('curve_moving', TuningType.curve, [
    [24, 0],
    [25, 0.15],
    [34, 0.15],
    [35, 0.25],
    [60, 0.42],
    [100, 0.52],
    [150, 0.58],
  ]),
  // §14.4 owner 2026-10-13: speed (pt/s) a rim hit from inside the opening ends with, away from that rim (top: down, bottom: up); hits from outside keep the hard bounce
  TuningDef('curve_rim_soft_bump', TuningType.decimal, 20.0),
  // §14.4 owner 2026-10-13: after a soft rim bump (inside the opening, both rims) the bird hangs this long (s) in low gravity; a flap ends it
  TuningDef('curve_rim_hang_s', TuningType.decimal, 0.25),
  // §14.4 owner 2026-10-13: gravity scale during the rim hang (0 = none, 1 = full); then 0.1 s ease back to full
  TuningDef('curve_rim_hang_gravity', TuningType.decimal, 0.25),
  // §14.4 Tilted-hoop chance by hoop index
  TuningDef('curve_tilt', TuningType.curve, [
    [9, 0],
    [10, 0.30],
    [49, 0.35],
    [50, 0.50],
    [100, 0.60],
    [150, 0.65],
  ]),
  // §14.4 First squeeze at a random hoop in [min, max]
  TuningDef('squeeze_first', TuningType.intList, [25, 40]),
  // §14.4 Squeeze hold (hoops) in [min, max]
  TuningDef('squeeze_hold', TuningType.intList, [5, 10]),
  // §14.4 Next squeeze this many hoops after the previous ended, [min, max]
  TuningDef('squeeze_gap', TuningType.intList, [25, 45]),
  // §14.5 Comet chance per eligible normal hoop
  TuningDef('ride_comet_chance', TuningType.decimal, 0.04),
  // §14.5 Comet from this hoop index
  TuningDef('ride_comet_from', TuningType.integer, 8),
  // §14.5 owner 2026-10-14: hoop spacing (pt) while a comet flies (normal 310; 560 = about 5-6 hoops per comet instead of 8-10)
  TuningDef('ride_comet_hoop_gap', TuningType.decimal, 560.0),
  // §14.5 PRD-2.3.1 §16: the last comet hoop sits this far (pt) before the predicted end of the comet
  TuningDef('ride_comet_tail', TuningType.decimal, 100.0),
  // §14.5 PRD-2.3.1 §16: the first normal hoop after a comet is at least this far (pt) after its predicted end
  TuningDef('ride_comet_after_gap', TuningType.decimal, 310.0),
  // §14.5 Comet at least this many hoops after the previous comet
  TuningDef('ride_comet_spacing', TuningType.integer, 18),
  // §14.5 First portal at a random hoop in [min, max]
  TuningDef('ride_portal_first', TuningType.intList, [12, 25]),
  // §14.5 PRD-2.3.1 §17: at most this many portal rides per run (0 = no limit)
  TuningDef('ride_portal_max', TuningType.integer, 2),
  // §14.5 Next portal this many hoops after the previous, [min, max]
  TuningDef('ride_portal_then', TuningType.intList, [80, 90]),
  // §15.3 owner 2026-10-14: chance a hoop slot is a special hoop, by hoop index (linear between keys; PRD-2.3.1 §0: default = live RC v21)
  TuningDef('spawn_special_chance', TuningType.curve, [
    [0, 0],
    [3, 0],
    [4, 0.4],
    [15, 0.5],
    [30, 0.6],
    [50, 0.7],
  ]),
  // §15.3 owner 2026-10-14: chance a gap gets an optional item, by gap index (linear between keys; PRD-2.3.1 §0: default = live RC v21)
  TuningDef('spawn_item_chance', TuningType.curve, [
    [0, 0],
    [2, 0],
    [3, 0.5],
    [20, 0.55],
  ]),
  // §15.3 Special hoop row: from hoop, weight, min hoops since the same, cooldown
  TuningDef('spawn_bullseye', TuningType.object, {
    'from': 4,
    'weight': 20,
    'min_since': 2,
    'cooldown': 1,
  }),
  // §15.3 Special hoop row
  TuningDef('spawn_train', TuningType.object, {
    'from': 5,
    'weight': 14,
    'min_since': 4,
    'cooldown': 2,
  }),
  // §15.3 Special hoop row
  TuningDef('spawn_spring', TuningType.object, {
    'from': 6,
    'weight': 12,
    'min_since': 4,
    'cooldown': 2,
  }),
  // §15.3 Special hoop row
  TuningDef('spawn_switch', TuningType.object, {
    'from': 15,
    'weight': 14,
    'min_since': 3,
    'cooldown': 1,
  }),
  // §15.3 Special hoop row
  TuningDef('spawn_pair', TuningType.object, {
    'from': 8,
    'weight': 10,
    'min_since': 6,
    'cooldown': 2,
  }),
  // §15.3 Special hoop row
  TuningDef('spawn_fever', TuningType.object, {
    'from': 10,
    'weight': 6,
    'min_since': 8,
    'cooldown': 1,
  }),
  // §15.3 Special hoop row
  TuningDef('spawn_lucky_spin', TuningType.object, {
    'from': 10,
    'weight': 8,
    'min_since': 7,
    'cooldown': 1,
  }),
  // §15.3 / PRD-2.6 §D2 special hoop row; the saw weight comes from the
  // `spawn_saw_weight` curve below.
  TuningDef('spawn_saw', TuningType.object, {
    'from': 30,
    'weight': 14,
    'min_since': 3,
    'cooldown': 1,
  }),
  // §15.3 Gap item row: from gap, weight, min gaps since the same
  TuningDef('spawn_star_trail', TuningType.object, {
    'from': 3,
    'weight': 30,
    'min_since': 3,
  }),
  // §15.3 Gap item row
  TuningDef('spawn_capsule', TuningType.object, {
    'from': 6,
    'weight': 20,
    'min_since': 8,
  }),
  // §15.3 Gap item row
  TuningDef('spawn_egg', TuningType.object, {
    'from': 6,
    'weight': 12,
    'min_since': 6,
  }),
  // §15.3 Gap item row
  TuningDef('spawn_piggy', TuningType.object, {
    'from': 8,
    'weight': 10,
    'min_since': 12,
  }),
  // §15.3 Gap item row
  TuningDef('spawn_jar', TuningType.object, {
    'from': 10,
    'weight': 10,
    'min_since': 12,
  }),
  // §15.3 Gap item row (max per run)
  TuningDef('spawn_shield', TuningType.object, {
    'from': 8,
    'weight': 6,
    'min_since': 0,
    'max_per_run': 1,
  }),
  // §15.3 First heart at a random gap in [min, max]
  TuningDef('spawn_heart_first', TuningType.intList, [5, 27]),
  // §15.3 Next heart this many gaps later, [min, max]
  TuningDef('spawn_heart_then', TuningType.intList, [17, 27]),
  // §15.3 Pair gift weights
  TuningDef('spawn_pair_gifts', TuningType.object, {
    'shield': 25,
    'comet': 20,
    'coins': 25,
    'score': 15,
    'fever': 15,
  }),
  // §15.3 Capsule type weights
  TuningDef('spawn_capsules', TuningType.object, {
    'hourglass': 35,
    'mini_bird': 35,
    'coin_frenzy': 30,
  }),
  // §14.6 Heart from gamesPlayed >= N
  TuningDef('gate_heart', TuningType.integer, 0),
  // §14.6 Star trail from gamesPlayed >= N
  TuningDef('gate_star_trail', TuningType.integer, 0),
  // §14.6 Bullseye from gamesPlayed >= N
  TuningDef('gate_bullseye', TuningType.integer, 0),
  // §14.6 Switch ring from gamesPlayed >= N
  TuningDef('gate_switch', TuningType.integer, 0),
  // §14.6 Ring train from gamesPlayed >= N
  TuningDef('gate_train', TuningType.integer, 0),
  // §14.6 Comet from gamesPlayed >= N
  TuningDef('gate_comet', TuningType.integer, 0),
  // §14.6 Portal from gamesPlayed >= N
  TuningDef('gate_portal', TuningType.integer, 0),
  // §14.6 Capsules (hourglass, mini bird, coin frenzy) from gamesPlayed >= N
  TuningDef('gate_capsule', TuningType.integer, 0),
  // §14.6 Shield pickup from gamesPlayed >= N
  TuningDef('gate_shield', TuningType.integer, 0),
  // §14.6 Spring from gamesPlayed >= N
  TuningDef('gate_spring', TuningType.integer, 0),
  // §14.6 Pair from gamesPlayed >= N
  TuningDef('gate_pair', TuningType.integer, 0),
  // §14.6 Egg from gamesPlayed >= N
  TuningDef('gate_egg', TuningType.integer, 0),
  // §14.6 Golden feather and balloon bonus from gamesPlayed >= N
  TuningDef('gate_feather', TuningType.integer, 0),
  // §14.6 Puzzle piece from gamesPlayed >= N
  TuningDef('gate_puzzle', TuningType.integer, 0),
  // §14.6 Piggy bank from gamesPlayed >= N
  TuningDef('gate_piggy', TuningType.integer, 0),
  // §14.6 Firefly jar from gamesPlayed >= N
  TuningDef('gate_jar', TuningType.integer, 0),
  // §14.6 FEVER from gamesPlayed >= N
  TuningDef('gate_fever', TuningType.integer, 0),
  // §14.6 Lucky spin from gamesPlayed >= N
  TuningDef('gate_lucky_spin', TuningType.integer, 0),
  // §14.6 Saw from gamesPlayed >= N
  TuningDef('gate_saw', TuningType.integer, 3),
  // §14.6 Spike squeeze from gamesPlayed >= N
  TuningDef('gate_squeeze', TuningType.integer, 5),
  // §10.3b Tap reminder after this many seconds without a tap
  TuningDef('ui_tap_reminder_s', TuningType.decimal, 4.0),
  // §18.4 New-player grace: no interstitial until this many finished runs (or ads_grace_seconds of playtime)
  TuningDef('ads_grace_runs', TuningType.integer, 5),
  // §18.4 New-player grace: foreground playtime since install (s) that ends it
  TuningDef('ads_grace_seconds', TuningType.integer, 300),
  // §18.4 Interstitial: minimum gap (s) after the previous full-screen ad closed
  TuningDef('ads_interstitial_min_gap_s', TuningType.integer, 60),
  // §23.3 Rating prompt: the run that reaches this many finished runs asks; later only a new best
  TuningDef('rate_min_runs', TuningType.integer, 5),
  // §23.3 Rating prompt: at most one request in this many days
  TuningDef('rate_cooldown_days', TuningType.integer, 30),
  // §23.3 Rating prompt: seconds after the results page has settled (no overlay open)
  TuningDef('rate_delay_s', TuningType.decimal, 1.5),
  // §24.4 No-Ads popup: minimum minutes between two shows (from the last show)
  TuningDef('noads_gap_min', TuningType.integer, 60),
  // §24.4 No-Ads popup: shows per local calendar day
  TuningDef('noads_max_per_day', TuningType.integer, 5),
  // §24.4 No-Ads popup: hours since the last show before the fallback shows it without a good moment
  TuningDef('noads_fallback_h', TuningType.decimal, 3.0),
  // §26.1 Shop and Skins unlock at this best score
  TuningDef('ui_unlock_best', TuningType.integer, 25),
  // §D2 Tilt-magnitude weights: `<from>_<magnitude>` entries by hoop band
  TuningDef('tilt_rows', TuningType.object, {
    '10_10': 6,
    '10_15': 4,
    '50_10': 30,
    '50_15': 30,
    '50_20': 20,
    '50_30': 20,
    '60_10': 20,
    '60_15': 20,
    '60_20': 15,
    '60_30': 30,
    '60_45': 15,
    '100_10': 15,
    '100_15': 15,
    '100_20': 15,
    '100_30': 30,
    '100_45': 25,
  }),
  // §D2 A tilt at or above this angle follows the approach sign
  TuningDef('tilt_align_min_deg', TuningType.integer, 20),
  // §D2 Below this absolute Δy a large tilt is clamped to 15°
  TuningDef('tilt_align_min_dy', TuningType.integer, 40),
  // §D2 Extra opening on 45° rings
  TuningDef('tilt45_extra_opening', TuningType.integer, 6),
  // §D2 The Δy reference band cap
  TuningDef('dy_ref_band', TuningType.decimal, 540.0),
  // §D2 Δy reduction after a moving or strongly tilted hoop
  TuningDef('dy_hard_factor', TuningType.decimal, 0.85),
  // §D2 Saw special-hoop weight by hoop index
  TuningDef('spawn_saw_weight', TuningType.curve, [
    [30, 14],
    [60, 20],
    [100, 26],
  ]),
  // §D3 The rolling four-slot hazard budget by hoop index
  TuningDef('hazard_budget', TuningType.curve, [
    [0, 0],
    [3, 0.5],
    [10, 2],
    [25, 3],
    [50, 4],
    [100, 5],
    [150, 5.5],
  ]),
  // §D3 Slot costs used by the future hazard ledger
  TuningDef('hazard_costs', TuningType.object, {
    'saw': 2,
    'switch': 1.5,
    'spring': 0.5,
    'pair': 0.5,
    'train': 0.5,
    'tilt_20': 0.25,
    'tilt_30': 1,
    'tilt_45': 1.5,
    'rail': 1,
    'swing': 1,
    'other_motion': 1.25,
    'dy_p90': 1,
    'squeeze': 1,
  }),
  // §D4 Periodic calm-stretch scheduling
  TuningDef('calm_every', TuningType.object, {
    'first_min': 30,
    'first_max': 34,
    'mult': 1.2,
    'cap': 55,
    'len': 3,
    'min_gap': 12,
  }),
  // §D4 Calm lengths after run events
  TuningDef('calm_after', TuningType.object, {
    'revive': 3,
    'squeeze': 2,
    'ride': 2,
  }),
  // §D6 No two headlines within this hoop window
  TuningDef('headline_window', TuningType.integer, 8),
  // §D6 A due headline may wait this many hoops
  TuningDef('headline_wait', TuningType.integer, 5),
  // §D7 Formation spacing from hoop 150
  TuningDef('formation_every', TuningType.intList, [12, 20]),
  // §B1 The showcase safety net stops after this many finished games
  TuningDef('showcase_max_games', TuningType.integer, 6),
  // §B1 A showcase run passing this hoop finishes the safety net
  TuningDef('showcase_fast_hoops', TuningType.integer, 40),
  // region P26-S0
  // §J1 PRD-2.6 progression / meta defaults.
  TuningDef('level_points', TuningType.intList, [
    25,
    50,
    100,
    150,
    200,
    300,
    400,
    500,
    600,
    700,
    800,
    900,
    1000,
    1200,
    1400,
    1600,
    1800,
    2000,
    2200,
    2400,
    2600,
    2800,
    3000,
    3500,
    4000,
    4500,
    5000,
    6000,
    7000,
    8000,
    10000,
  ]),
  // §J1 PRD-2.6 progression / meta defaults.
  TuningDef('level_coins', TuningType.intList, [
    50,
    50,
    50,
    50,
    50,
    75,
    100,
    125,
    150,
    175,
    200,
    225,
    250,
    300,
    350,
    400,
    450,
    500,
    550,
    600,
    650,
    700,
    750,
    875,
    1000,
    1125,
    1250,
    1500,
    1750,
    2000,
    2500,
  ]),
  // §J2 PRD-2.6 progression / meta defaults.
  TuningDef('level_eternal_points', TuningType.integer, 10000),
  // §J2 PRD-2.6 progression / meta defaults.
  TuningDef('level_eternal_coins', TuningType.integer, 2500),
  // §F6 PRD-2.6 progression / meta defaults.
  TuningDef('ui_unlock_games', TuningType.integer, 3),
  // §G1 PRD-2.6 progression / meta defaults.
  TuningDef('mission_rewards', TuningType.intList, [20, 35, 55]),
  // §G1 PRD-2.6 progression / meta defaults.
  TuningDef('mission_chest_coins', TuningType.integer, 40),
  // §G5 PRD-2.6 progression / meta defaults.
  TuningDef('weekly_rewards', TuningType.object, {
    '15': 40,
    '30': 80,
    '60': 150,
    '120': 300,
  }),
  // §G2 PRD-2.6 progression / meta defaults.
  TuningDef('streak_restore_coins', TuningType.integer, 500),
  // §G6 PRD-2.6 progression / meta defaults.
  TuningDef('starroad_stars', TuningType.object, {
    'easy': 1,
    'medium': 2,
    'hard': 3,
    'first_run': 2,
    'all_done': 3,
  }),
  // §G6 PRD-2.6 progression / meta defaults.
  TuningDef('starroad_tier_stars', TuningType.integer, 8),
  // §G6 PRD-2.6 progression / meta defaults.
  TuningDef('starroad_tiers', TuningType.integer, 25),
  // §G6 PRD-2.6 progression / meta defaults.
  TuningDef('starroad_season_days', TuningType.integer, 28),
  // §G6 PRD-2.6 progression / meta defaults.
  TuningDef('starroad_fallback_coins', TuningType.object, {
    'rare': 250,
    'epic': 500,
    'legendary': 1000,
  }),
  // §LB PRD-2.6 progression / meta defaults.
  TuningDef('lb_results_min_games', TuningType.integer, 3),
  // §LB PRD-2.6 progression / meta defaults.
  TuningDef('lb_results_wait_ms', TuningType.integer, 4000),
  // §LB PRD-2.6 progression / meta defaults.
  TuningDef('lb_queue_cap', TuningType.integer, 30),
  // endregion
];
