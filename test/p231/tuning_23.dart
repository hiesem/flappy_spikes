import 'package:flappy_spikes/run/config/tuning_values.dart';

/// PRD-2.3.1 §0: the live Remote Config set (RC v21) became the in-app
/// defaults. These are the 2.3 defaults it replaced, for the tests that pin
/// a 2.3 value on purpose (a mechanism measured at its old calibration).
/// Pick the keys a test needs with [tuning23] and apply them with
/// [useTuning] (it sets `TuningValues.current`, which the config getters
/// read).
const Map<String, String> kTuning23 = {
  'coin_piggy_per': '2',
  'coin_jar': '8',
  'coin_spin_slices': '[1,2,3,5,1,2]',
  'point_perfect_band': '[[0,0]]',
  'point_bullseye_band': '[[0,12]]',
  'bonus_prizes': '[25,25,25,50,50,50,75,75,150]',
  'bonus_feather_gaps': '[10,40]',
  'puzzle_gaps': '[10,40]',
  'puzzle_reward': '[50,150,5]',
  'ride_comet_chance': '0.02',
  'ride_comet_from': '10',
  'ride_comet_spacing': '25',
  'ride_portal_first': '[40,60]',
  'ride_portal_then': '[60,80]',
  'spawn_special_chance':
      '[[0,0],[7,0],[8,0.25],[19,0.25],[20,0.35],[34,0.35],[35,0.45],[49,0.45],[50,0.6]]',
  'spawn_item_chance': '[[0,0],[4,0],[5,0.25],[19,0.25],[20,0.33]]',
  'spawn_bullseye': '{"from":6,"weight":20,"min_since":6,"cooldown":1}',
  'spawn_train': '{"from":8,"weight":14,"min_since":10,"cooldown":2}',
  'spawn_spring': '{"from":10,"weight":12,"min_since":10,"cooldown":2}',
  'spawn_switch': '{"from":12,"weight":14,"min_since":8,"cooldown":1}',
  'spawn_pair': '{"from":12,"weight":10,"min_since":15,"cooldown":2}',
  'spawn_fever': '{"from":15,"weight":6,"min_since":20,"cooldown":1}',
  'spawn_lucky_spin': '{"from":15,"weight":8,"min_since":18,"cooldown":1}',
  'spawn_star_trail': '{"from":5,"weight":30,"min_since":8}',
  'spawn_capsule': '{"from":10,"weight":20,"min_since":20}',
  'spawn_egg': '{"from":10,"weight":12,"min_since":15}',
  'spawn_piggy': '{"from":12,"weight":10,"min_since":30}',
  'spawn_jar': '{"from":15,"weight":10,"min_since":30}',
  'spawn_shield': '{"from":12,"weight":6,"min_since":0,"max_per_run":1}',
  'gate_switch': '3',
  'gate_train': '3',
  'gate_comet': '5',
  'gate_portal': '5',
  'gate_capsule': '5',
  'gate_shield': '5',
  'gate_spring': '8',
  'gate_pair': '8',
  'gate_egg': '8',
  'gate_feather': '10',
  'gate_puzzle': '10',
  'gate_piggy': '10',
  'gate_jar': '10',
  'gate_fever': '15',
  'gate_lucky_spin': '15',
  'gate_saw': '20',
};

/// PRD-2.6 wave-1 values needed by tests that pin the whole spawn set. These
/// are new keys only; they have no historical 2.3 value.
const Map<String, String> kTuning26Wave1 = {
  'spawn_saw_weight': '[[30,14],[60,20],[100,26]]',
};

/// The 2.3 values of [keys] (every changed key when [keys] is null).
Map<String, String> tuning23([Iterable<String>? keys]) =>
    keys == null ? {...kTuning23} : {for (final k in keys) k: kTuning23[k]!};

/// The 2.3 spawn set: special / item chances and rows, the early-run
/// rides, the feather / puzzle windows and the lifetime gates.
Map<String, String> tuning23Spawn() => {
  for (final e in kTuning23.entries)
    if (e.key.startsWith('spawn_') ||
        e.key.startsWith('gate_') ||
        e.key.startsWith('ride_') ||
        e.key.endsWith('_gaps'))
      e.key: e.value,
  ...kTuning26Wave1,
};

/// The test-wide set (flutter_test_config.dart: `ui_unlock_best` 0) plus
/// [extra], in `TuningValues.current`.
void useTuning(Map<String, String> extra) {
  TuningValues.current = TuningValues.resolve({
    'ui_unlock_best': '0',
    ...extra,
  });
}

/// Back to the test-wide set.
void resetTuning() => useTuning(const {});
