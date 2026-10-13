# Remote tuning (PRD-2.3 §15)

Remote tuning lets testers change the gameplay and economy values of PRD-2.3 §14 from the
Firebase **Remote Config** console. It exists **only in tester builds**.

## Who gets it

| Build | Flag | Remote Config | Debug panel |
|---|---|---|---|
| Debug (`flutter run`) | `--dart-define=FS_TUNING=true` (optional) | yes, with the flag | always (debug build) |
| Tester upload (Play internal / closed testing) | `--dart-define=FS_TUNING=true` | yes | yes: long-press the home title |
| **Production** | **none** | **never** (no fetch, no request) | **none** |

`kTuning` (`lib/services/tuning.dart`) is a `const bool.fromEnvironment('FS_TUNING')`. Without the
flag `main.dart` never creates the Firebase backend, so the plugin code is tree-shaken out and the
game uses the in-app defaults of `lib/run/config/tuning_defaults.dart` only. The release step must
build the production bundle **without** the flag (PRD-2.3 §8).

## How it works (§15.2)

1. **Startup** (`main.dart`, tester builds): `FirebaseRemoteConfig.activate()` applies the values
   fetched at the previous start; the service resolves them against the defaults and makes them the
   active set. Then a background `fetch()` stores new values **for the next start** (minimum fetch
   interval 1 minute). So a console change needs **two app starts**: one to fetch, one to activate.
2. **Run start**: `Tuning.instance.beginRun()` hands the active set to `TuningValues.current`, which
   every config getter reads. A value never changes during a run or a session.
3. **Fallback only**: a missing key, a wrong type or JSON that does not parse falls back to the
   in-app default (one `debugPrint` line). There are no min/max clamps; testers own their values.

Code map:

| File | What |
|---|---|
| `lib/run/config/tuning_types.dart` | `TuningType` (integer, decimal, boolean, intList, curve, object), parsing / validation, `Keyframes`, `kTuningGroups` |
| `lib/run/config/tuning_defaults.dart` | **generated**: `kTuningDefaults`, one `TuningDef` line per key |
| `lib/run/config/tuning_values.dart` | `TuningValues` (resolved set + source per key), `TuningValues.current` |
| `lib/services/tuning.dart` | `kTuning`, `TuningBackend`, the `Tuning` service (no-op default, try/caught plugin calls) |
| `lib/services/tuning_firebase.dart` | the Firebase Remote Config backend (created by `main.dart` only with the flag) |
| `lib/run/config/tuning_codegen.dart` + `tool/tuning_sync.dart` | export / import (§15.5) |
| `lib/components/debug_panel.dart` | the read-only **TUNING >** page (§15.4) |

## Formats (§15.3)

- **Key names**: `<group>_<name>`, snake_case. Groups: `coin_`, `point_`, `bonus_`, `puzzle_`,
  `revive_`, `level_`, `shop_`, `curve_`, `squeeze_`, `ride_`, `spawn_`, `gate_`, and (PRD-2.3 §0
  item 5) `ads_`, `rate_`, `noads_`, `ui_`.
- **integer / decimal**: a number (`8`, `0.02`). An integer key rejects `1.5`.
- **intList**: a JSON array of ints, e.g. `bonus_prizes = [25,25,25,50,50,50,75,75,150]`. Ranges
  are two ints `[min, max]` (both inclusive), e.g. `squeeze_first = [25,40]`.
- **curve** (keyframe table): a JSON array of `[hoop, value]` pairs with ascending hoops, e.g.
  `curve_opening = [[1,88],[100,66]]`. Linear between pairs; the first value before the first
  pair; the last value after the last pair. A **step** is two pairs one hoop apart
  (`[[19,0],[20,0.15]]`), a **plateau** two pairs with the same value.
- **object**: a JSON object with exactly the keys of its default and number values, e.g.
  `spawn_saw = {"from":20,"weight":18,"weight_from_45":26,"min_since":3,"cooldown":1}` (one
  spawn-table row: from hoop / gap, weight, minimum hoops / gaps since the same element, normal
  slots after it; `max_per_run` for the shield).

Not tunable (§15.1): visuals, layout, animation, spacing (310 pt), hoop 0's 118 pt opening, the
§3.0.3 budget rows and the early pool.

## Adding a key (one line)

Other work packages add their own keys (`ui_tap_reminder_s` for §10.3b, `ads_*` §18, `rate_*`
§23, `noads_*` §24, `ui_unlock_best` §26). Adding one is a one-line change:

1. Add **one** `TuningDef` line to `kTuningDefaults` in `lib/run/config/tuning_defaults.dart`, in
   its group:

   ```dart
   TuningDef('ui_tap_reminder_s', TuningType.decimal, 4.0, '10.3b', 'Tap reminder after this many seconds without a tap'),
   ```

2. Read it where the value is used, through a config getter, never inlined and never cached across
   runs:

   ```dart
   /// PRD-2.3 §10.3b The tap reminder shows after this long (s; `ui_tap_reminder_s`).
   static double get tapReminderSeconds => TuningValues.current.d('ui_tap_reminder_s');
   ```

   Accessors: `.i` (integer), `.d` (decimal), `.b` (boolean), `.ints` / `.range` (intList),
   `.curve(key).at(hoop)` (curve), `.obj` (object).
3. Run `dart run tool/tuning_sync.dart format` (normalises the file; the round-trip test
   `test/p23/s15_tuning_test.dart` fails until it is canonical) and
   `dart run tool/tuning_sync.dart export` (updates the template and the key table below).

## Export and import (§15.5)

From `flappy_spikes/`:

```bash
dart run tool/tuning_sync.dart export      # defaults → docs/p23/remote_config_template.json (+ the table below)
dart run tool/tuning_sync.dart import      # the console (REST, gcloud sign-in) → tuning_defaults.dart
dart run tool/tuning_sync.dart import --dry-run                 # show what would change
dart run tool/tuning_sync.dart import --from saved_template.json
dart run tool/tuning_sync.dart format      # canonical tuning_defaults.dart
```

- **export** writes every key with its default, one parameter group per key group. Import it once
  in the console (*Remote Config → ⋮ → Publish from a file*, or the REST API) to create every key.
  The orchestrator publishes it after the merge (builders never deploy).
- **import** downloads the console template through the Remote Config REST API
  (`firebaseremoteconfig.googleapis.com/v1/projects/flappy-spikes-a2b55/remoteConfig`) with the
  owner's `gcloud auth print-access-token` (falls back to application-default credentials), and
  rewrites `tuning_defaults.dart`: same keys, same order; a console value that does not parse keeps
  the default and is listed as `REJECTED`; unknown console keys are listed and ignored; conditional
  values are ignored. Review the diff and run `flutter test` (the autopilot gate included) before
  it ships.
- Checked 2026-10-13: `import --dry-run` against the live project works with the owner's gcloud
  sign-in (the live template had none of these keys yet: 0 changed).

## Debug panel (§15.4)

The debug panel opens in tester builds too (`FlappySpikesGame.debugAvailable` includes `kTuning`).

- **TUNING >**: the last fetch (result and time), then every key as
  `key = value [source]`, where the source is `remote` (from the console), `default` (no remote
  value) or `default*` (a remote value was rejected). Read-only; paged like RUN DEBUG.
- **RUN DEBUG > Runs: N (+5 / 0)** (§14.6): sets `gamesPlayed` to test the lifetime unlock gates
  (+5 per tap; from 20, where every gate is open, the next tap goes back to 0). "Reset menu state"
  does not touch `gamesPlayed`.

## Testing on the phone (§6.3)

1. Build the tester build with `--dart-define=FS_TUNING=true`.
2. Change `curve_opening` and `coin_jar` in the console, publish.
3. Start the app twice (fetch, then activate). The TUNING page shows both as `remote` and the game
   uses them.
4. Set a broken value (e.g. `coin_jar = eight`): the TUNING page shows `default*`.
5. A production build (no flag) has no debug panel (long-pressing the title does nothing) and makes
   no Remote Config request.

## Bands (owner 2026-10-13)

- `point_perfect_band` (curve by hoop index, default `[[0,0]]`): ± pt around the gap centre.
  A value ≤ 0 means no band: any pass without a rim touch is perfect (the 2.3 rule). A value > 0:
  a pass is perfect only with no rim touch **and** the bird centre crossing the hoop plane within
  ±value pt of the gap centre (e.g. `[[0,0],[20,0],[40,16]]` = no band until hoop 20, then
  narrowing to ±16 at hoop 40). Rides stay always perfect.
- `point_bullseye_band` (number, default 12): the Bullseye hit band ± pt. Only the hit check
  changes; the drawn guide lines and target stay at ±12 pt.

## Keys

The table is generated from `tuning_defaults.dart` by `dart run tool/tuning_sync.dart export`.

<!-- KEYS:START (generated by tool/tuning_sync.dart export) -->
| Key | Type | Default | Section | What |
|---|---|---|---|---|
| `coin_hoop` | integer | `1` | §14.2 | Coins for a hoop pass that is not perfect |
| `coin_perfect` | integer | `2` | §14.2 | Coins for a perfect pass (and every ride hoop) |
| `coin_piggy_per` | integer | `2` | §14.2 | Piggy Bank: every this many caught coins pay 1 (rounded down; 20 on screen = max 10) |
| `coin_jar` | integer | `8` | §14.2 | Firefly jar full (20 caught) |
| `coin_spin_slices` | intList | `[1,2,3,5,1,2]` | §14.2 | Lucky spin slices (equal chance) |
| `coin_star_trail` | integer | `2` | §14.2 | Star trail 8/8 |
| `coin_bullseye` | integer | `2` | §14.2 | Bullseye hit |
| `coin_train` | integer | `1` | §14.2 | Ring train 3/3 |
| `coin_switch` | integer | `0` | §14.2 | Switch touched |
| `coin_pair_gift` | integer | `3` | §14.2 | Pair "+N coins" gift |
| `coin_frenzy_ring` | integer | `1` | §14.2 | Coin frenzy capsule: coins per ring |
| `coin_versus_win` | integer | `10` | §14.2 | Versus win bonus |
| `coin_versus_draw` | integer | `5` | §14.2 | Versus draw bonus |
| `point_pass` | integer | `1` | §14.3 | Points for a pass that is not perfect |
| `point_perfect_min` | integer | `2` | §14.3 | Points for a perfect pass: max(this, streak) |
| `point_chick` | integer | `1` | §14.3 | Chick: extra points per hoop passed |
| `point_fever_streak` | integer | `5` | §14.3 | A perfect FEVER pass sets the streak to max(this, streak + 1) |
| `point_pair_gift` | integer | `5` | §14.3 | Pair "+N score" gift |
| `point_perfect_band` | curve | `[[0,0]]` | §14.3 | owner 2026-10-13: perfect band ±pt around the gap centre by hoop index; <= 0 = no band (any rim-free pass is perfect) |
| `point_bullseye_band` | curve | `[[0,12]]` | §14.3 | owner 2026-10-13: Bullseye hit band ±pt by hoop index (hit check only; the drawing stays 12) |
| `bonus_prizes` | intList | `[25,25,25,50,50,50,75,75,150]` | §14.2 | Balloon prizes (shuffled; the largest is the jackpot) |
| `bonus_feather_chance` | decimal | `0.6` | §14.2 | Chance per run that the golden feather appears |
| `bonus_feather_gaps` | intList | `[10,40]` | §14.2 | The feather spawns at a random gap in [min, max] |
| `puzzle_chance` | decimal | `0.6` | §14.2 | Chance per run that a puzzle piece appears |
| `puzzle_gaps` | intList | `[10,40]` | §14.2 | The piece spawns at a random gap in [min, max] |
| `puzzle_reward` | intList | `[50,150,5]` | §14.2 | Puzzle completion reward [min, max, step] |
| `revive_ladder` | intList | `[250,500,1000,2000,4000,8000]` | §14.2 | Coin revive prices after the ad revive; no revive after the last |
| `revive_min_hoops` | integer | `6` | §14.2 | A revive is offered from this many hoops passed |
| `level_rewards` | intList | `[50,100,150,250,400,600,800,1000,2000,5000]` | §14.2 | One-time coin reward of levels 1-10 |
| `shop_ad_coins` | integer | `40` | §14.2 | Shop free-coins ad: coins per ad |
| `shop_ad_per_day` | integer | `5` | §14.2 | Shop free-coins ad: ads per day |
| `shop_ad_cooldown_s` | integer | `300` | §14.2 | Shop free-coins ad: cooldown (s) |
| `curve_speed` | curve | `[[0,150],[50,172.5],[150,187.5]]` | §14.4 | Cruise speed (pt/s) by hoop index |
| `curve_opening` | curve | `[[1,88],[100,66]]` | §14.4 | Opening (pt) by hoop index from hoop 1 (hoop 0 is always 118) |
| `curve_moving` | curve | `[[19,0],[20,0.15],[35,0.4],[60,0.6],[80,0.75]]` | §14.4 | Moving-hoop chance by hoop index |
| `curve_rim_soft_bump` | decimal | `20` | §14.4 | owner 2026-10-13: speed (pt/s) a rim hit from inside the opening ends with, away from that rim (top: down, bottom: up); hits from outside keep the hard bounce |
| `curve_rim_hang_s` | decimal | `0.25` | §14.4 | owner 2026-10-13: after a soft rim bump (inside the opening, both rims) the bird hangs this long (s) in low gravity; a flap ends it |
| `curve_rim_hang_gravity` | decimal | `0.25` | §14.4 | owner 2026-10-13: gravity scale during the rim hang (0 = none, 1 = full); then 0.1 s ease back to full |
| `curve_tilt` | curve | `[[9,0],[10,0.3],[19,0.3],[20,0.5],[34,0.5],[35,0.6],[44,0.6],[45,0.78]]` | §14.4 | Tilted-hoop chance by hoop index |
| `squeeze_first` | intList | `[25,40]` | §14.4 | First squeeze at a random hoop in [min, max] |
| `squeeze_hold` | intList | `[5,10]` | §14.4 | Squeeze hold (hoops) in [min, max] |
| `squeeze_gap` | intList | `[25,45]` | §14.4 | Next squeeze this many hoops after the previous ended, [min, max] |
| `ride_comet_chance` | decimal | `0.02` | §14.5 | Comet chance per eligible normal hoop |
| `ride_comet_from` | integer | `10` | §14.5 | Comet from this hoop index |
| `ride_comet_spacing` | integer | `25` | §14.5 | Comet at least this many hoops after the previous comet |
| `ride_portal_first` | intList | `[40,60]` | §14.5 | First portal at a random hoop in [min, max] |
| `ride_portal_then` | intList | `[60,80]` | §14.5 | Next portal this many hoops after the previous, [min, max] |
| `spawn_bullseye` | object | `{"from":6,"weight":20,"min_since":6,"cooldown":1}` | §15.3 | Special hoop row: from hoop, weight, min hoops since the same, cooldown |
| `spawn_train` | object | `{"from":8,"weight":14,"min_since":10,"cooldown":2}` | §15.3 | Special hoop row |
| `spawn_spring` | object | `{"from":10,"weight":12,"min_since":10,"cooldown":2}` | §15.3 | Special hoop row |
| `spawn_switch` | object | `{"from":12,"weight":14,"min_since":8,"cooldown":1}` | §15.3 | Special hoop row |
| `spawn_pair` | object | `{"from":12,"weight":10,"min_since":15,"cooldown":2}` | §15.3 | Special hoop row |
| `spawn_fever` | object | `{"from":15,"weight":6,"min_since":20,"cooldown":1}` | §15.3 | Special hoop row |
| `spawn_lucky_spin` | object | `{"from":15,"weight":8,"min_since":18,"cooldown":1}` | §15.3 | Special hoop row |
| `spawn_saw` | object | `{"from":20,"weight":18,"weight_from_45":26,"min_since":3,"cooldown":1}` | §15.3 | Special hoop row (weight from hoop 45) |
| `spawn_star_trail` | object | `{"from":5,"weight":30,"min_since":8}` | §15.3 | Gap item row: from gap, weight, min gaps since the same |
| `spawn_capsule` | object | `{"from":10,"weight":20,"min_since":20}` | §15.3 | Gap item row |
| `spawn_egg` | object | `{"from":10,"weight":12,"min_since":15}` | §15.3 | Gap item row |
| `spawn_piggy` | object | `{"from":12,"weight":10,"min_since":30}` | §15.3 | Gap item row |
| `spawn_jar` | object | `{"from":15,"weight":10,"min_since":30}` | §15.3 | Gap item row |
| `spawn_shield` | object | `{"from":12,"weight":6,"min_since":0,"max_per_run":1}` | §15.3 | Gap item row (max per run) |
| `spawn_heart_first` | intList | `[5,27]` | §15.3 | First heart at a random gap in [min, max] |
| `spawn_heart_then` | intList | `[17,27]` | §15.3 | Next heart this many gaps later, [min, max] |
| `spawn_pair_gifts` | object | `{"shield":25,"comet":20,"coins":25,"score":15,"fever":15}` | §15.3 | Pair gift weights |
| `spawn_capsules` | object | `{"hourglass":35,"mini_bird":35,"coin_frenzy":30}` | §15.3 | Capsule type weights |
| `gate_heart` | integer | `0` | §14.6 | Heart from gamesPlayed >= N |
| `gate_star_trail` | integer | `0` | §14.6 | Star trail from gamesPlayed >= N |
| `gate_bullseye` | integer | `0` | §14.6 | Bullseye from gamesPlayed >= N |
| `gate_switch` | integer | `3` | §14.6 | Switch ring from gamesPlayed >= N |
| `gate_train` | integer | `3` | §14.6 | Ring train from gamesPlayed >= N |
| `gate_comet` | integer | `5` | §14.6 | Comet from gamesPlayed >= N |
| `gate_portal` | integer | `5` | §14.6 | Portal from gamesPlayed >= N |
| `gate_capsule` | integer | `5` | §14.6 | Capsules (hourglass, mini bird, coin frenzy) from gamesPlayed >= N |
| `gate_shield` | integer | `5` | §14.6 | Shield pickup from gamesPlayed >= N |
| `gate_spring` | integer | `8` | §14.6 | Spring from gamesPlayed >= N |
| `gate_pair` | integer | `8` | §14.6 | Pair from gamesPlayed >= N |
| `gate_egg` | integer | `8` | §14.6 | Egg from gamesPlayed >= N |
| `gate_feather` | integer | `10` | §14.6 | Golden feather and balloon bonus from gamesPlayed >= N |
| `gate_puzzle` | integer | `10` | §14.6 | Puzzle piece from gamesPlayed >= N |
| `gate_piggy` | integer | `10` | §14.6 | Piggy bank from gamesPlayed >= N |
| `gate_jar` | integer | `10` | §14.6 | Firefly jar from gamesPlayed >= N |
| `gate_fever` | integer | `15` | §14.6 | FEVER from gamesPlayed >= N |
| `gate_lucky_spin` | integer | `15` | §14.6 | Lucky spin from gamesPlayed >= N |
| `gate_saw` | integer | `20` | §14.6 | Saw from gamesPlayed >= N |
| `ui_tap_reminder_s` | decimal | `4` | §10.3b | Tap reminder after this many seconds without a tap |
| `ads_grace_runs` | integer | `5` | §18.4 | New-player grace: no interstitial until this many finished runs (or ads_grace_seconds of playtime) |
| `ads_grace_seconds` | integer | `300` | §18.4 | New-player grace: foreground playtime since install (s) that ends it |
| `ads_interstitial_min_gap_s` | integer | `60` | §18.4 | Interstitial: minimum gap (s) after the previous full-screen ad closed |
| `rate_min_runs` | integer | `5` | §23.3 | Rating prompt: the run that reaches this many finished runs asks; later only a new best |
| `rate_cooldown_days` | integer | `30` | §23.3 | Rating prompt: at most one request in this many days |
| `rate_delay_s` | decimal | `1.5` | §23.3 | Rating prompt: seconds after the results page has settled (no overlay open) |
| `noads_gap_min` | integer | `60` | §24.4 | No-Ads popup: minimum minutes between two shows (from the last show) |
| `noads_max_per_day` | integer | `5` | §24.4 | No-Ads popup: shows per local calendar day |
| `noads_fallback_h` | decimal | `3` | §24.4 | No-Ads popup: hours since the last show before the fallback shows it without a good moment |
| `ui_unlock_best` | integer | `25` | §26.1 | Shop and Skins unlock at this best score |
<!-- KEYS:END -->
