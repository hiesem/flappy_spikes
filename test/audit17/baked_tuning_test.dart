import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/services/tester.dart';
import 'package:flutter_test/flutter_test.dart';

/// Audit 17 (2026-10-19): the live Remote Config tuning values (all 101
/// parameters of the template, no conditional values; the Play Games salt
/// is not a tuning value and is not listed). The owner's rule "the Firebase
/// value wins" made them the baked values; compared with the app's own
/// parser none differed from the in-app defaults, so no value changed.
const Map<String, String> _liveRc20261019 = {
  'coin_hoop': '1',
  'coin_perfect': '2',
  'coin_piggy_per': '3',
  'coin_jar': '5',
  'coin_spin_slices': '[1,2,3,1,2,1]',
  'coin_star_trail': '2',
  'coin_bullseye': '3',
  'coin_train': '1',
  'coin_switch': '0',
  'coin_pair_gift': '3',
  'coin_frenzy_ring': '1',
  'coin_versus_win': '10',
  'coin_versus_draw': '5',
  'point_pass': '1',
  'point_perfect_min': '2',
  'point_chick': '1',
  'point_fever_streak': '5',
  'point_pair_gift': '5',
  'point_perfect_band':
      '[[1,40],[2,40],[6,36],[10,30],[16,24],[20,18],[25,14.5],[30,13.9],[35,13.2],[40,12.7],[50,11.8],[60,11.2],[75,10.6],[100,10.2],[150,10]]',
  'point_bullseye_band': '[[1,12],[50,10],[100,8]]',
  'bonus_prizes': '[25,25,25,40,40,40,50,50,100]',
  'bonus_feather_chance': '0.6',
  'bonus_feather_gaps': '[5,30]',
  'puzzle_chance': '0.6',
  'puzzle_gaps': '[5,30]',
  'puzzle_reward': '[40,100,5]',
  'revive_ladder': '[250,500,1000,2000,4000,8000]',
  'revive_min_hoops': '6',
  'level_rewards': '[25,50,100,200,400,600,800,1000,2000,5000]',
  'shop_ad_coins': '75',
  'shop_ad_per_day': '5',
  'shop_ad_cooldown_s': '300',
  'curve_speed': '[[0,150],[50,172.5],[150,187.5]]',
  'curve_opening':
      '[[1,118],[2,118],[6,114],[10,110],[16,105.5],[20,102],[25,98],[30,95],[40,88.5],[50,83],[60,79],[75,75.5],[100,72.5],[125,71],[150,70]]',
  'curve_moving': '[[24,0],[25,0.15],[34,0.15],[35,0.25],[60,0.42],[100,0.52],[150,0.58]]',
  'curve_tilt':
      '[[9,0],[10,0.30],[49,0.35],[50,0.50],[100,0.60],[150,0.65]]',
  'curve_rim_soft_bump': '20',
  'curve_rim_hang_s': '0.25',
  'curve_rim_hang_gravity': '0.25',
  'squeeze_first': '[25,40]',
  'squeeze_hold': '[5,10]',
  'squeeze_gap': '[25,45]',
  'ride_comet_chance': '0.04',
  'ride_comet_from': '8',
  'ride_comet_spacing': '18',
  'ride_portal_first': '[12,25]',
  'ride_portal_then': '[80,90]',
  'ride_comet_hoop_gap': '560',
  'ride_comet_tail': '100',
  'ride_comet_after_gap': '310',
  'ride_portal_max': '2',
  'spawn_bullseye': '{"from":4,"weight":20,"min_since":2,"cooldown":1}',
  'spawn_train': '{"from":5,"weight":14,"min_since":4,"cooldown":2}',
  'spawn_spring': '{"from":6,"weight":12,"min_since":4,"cooldown":2}',
  'spawn_switch': '{"from":7,"weight":14,"min_since":3,"cooldown":1}',
  'spawn_pair': '{"from":8,"weight":10,"min_since":6,"cooldown":2}',
  'spawn_fever': '{"from":10,"weight":6,"min_since":8,"cooldown":1}',
  'spawn_lucky_spin': '{"from":10,"weight":8,"min_since":7,"cooldown":1}',
  'spawn_saw':
      '{"from":20,"weight":18,"weight_from_45":26,"min_since":3,"cooldown":1}',
  'spawn_star_trail': '{"from":3,"weight":30,"min_since":3}',
  'spawn_capsule': '{"from":6,"weight":20,"min_since":8}',
  'spawn_egg': '{"from":6,"weight":12,"min_since":6}',
  'spawn_piggy': '{"from":8,"weight":10,"min_since":12}',
  'spawn_jar': '{"from":10,"weight":10,"min_since":12}',
  'spawn_shield': '{"from":8,"weight":6,"min_since":0,"max_per_run":1}',
  'spawn_heart_first': '[5,27]',
  'spawn_heart_then': '[17,27]',
  'spawn_pair_gifts':
      '{"shield":25,"comet":20,"coins":25,"score":15,"fever":15}',
  'spawn_capsules': '{"hourglass":35,"mini_bird":35,"coin_frenzy":30}',
  'spawn_special_chance': '[[0,0],[3,0],[4,0.4],[15,0.5],[30,0.6],[50,0.7]]',
  'spawn_item_chance': '[[0,0],[2,0],[3,0.5],[20,0.55]]',
  'gate_heart': '0',
  'gate_star_trail': '0',
  'gate_bullseye': '0',
  'gate_switch': '0',
  'gate_train': '0',
  'gate_comet': '0',
  'gate_portal': '0',
  'gate_capsule': '0',
  'gate_shield': '0',
  'gate_spring': '4',
  'gate_pair': '4',
  'gate_egg': '4',
  'gate_feather': '6',
  'gate_puzzle': '6',
  'gate_piggy': '6',
  'gate_jar': '6',
  'gate_fever': '8',
  'gate_lucky_spin': '8',
  'gate_saw': '12',
  'ui_tap_reminder_s': '4',
  'ui_unlock_best': '25',
  'ads_grace_runs': '5',
  'ads_grace_seconds': '300',
  'ads_interstitial_min_gap_s': '60',
  'rate_min_runs': '5',
  'rate_cooldown_days': '30',
  'rate_delay_s': '1.5',
  'noads_gap_min': '60',
  'noads_max_per_day': '5',
  'noads_fallback_h': '3',
  // PRD-2.6 wave-1 additions (not in the 2026-10-19 live template).
  'tilt_rows':
      '{"10_10":6,"10_15":4,"50_10":30,"50_15":30,"50_20":20,"50_30":20,"60_10":20,"60_15":20,"60_20":15,"60_30":30,"60_45":15,"100_10":15,"100_15":15,"100_20":15,"100_30":30,"100_45":25}',
  'tilt_align_min_deg': '20',
  'tilt_align_min_dy': '40',
  'tilt45_extra_opening': '6',
  'dy_ref_band': '540',
  'dy_hard_factor': '0.85',
  'spawn_saw_weight': '[[30,14],[60,20],[100,26]]',
  'hazard_budget': '[[0,0],[3,0.5],[10,2],[25,3],[50,4],[100,5],[150,5.5]]',
  'hazard_costs':
      '{"saw":2,"switch":1.5,"spring":0.5,"pair":0.5,"train":0.5,"tilt_20":0.25,"tilt_30":1,"tilt_45":1.5,"rail":1,"swing":1,"other_motion":1.25,"dy_p90":1,"squeeze":1}',
  'calm_every':
      '{"first_min":30,"first_max":34,"mult":1.2,"cap":55,"len":3,"min_gap":12}',
  'calm_after': '{"revive":3,"squeeze":2,"ride":2}',
  'headline_window': '8',
  'headline_wait': '5',
  'formation_every': '[12,20]',
  'showcase_max_games': '6',
  'showcase_fast_hoops': '40',
};

void main() {
  test('every baked value equals the live RC value of 2026-10-19 (parsed '
      'with the app parser), and every key is covered', () {
    final defs = {for (final d in kTuningDefaults) d.key: d};
    expect(defs.keys.toSet(), _liveRc20261019.keys.toSet());
    final baked = TuningValues.defaults();
    for (final e in _liveRc20261019.entries) {
      final d = defs[e.key]!;
      final live = d.type.parse(e.value, d.value);
      expect(live, isNotNull, reason: '${e.key} parses');
      expect(jsonEncode(baked.raw(e.key)), jsonEncode(live), reason: e.key);
    }
  });

  test('the tester flag is off by default (release builds have no define)', () {
    expect(kTester, isFalse);
  });

  test('no tuning read is left: Remote Config is only used for the Play '
      'Games salt, and FS_TUNING is gone', () {
    final rc = <String>[];
    final tuningFlag = <String>[];
    for (final dir in ['lib', 'integration_test', 'tool']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final f in root.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('firebase_remote_config')) rc.add(f.path);
        if (src.contains('FS_TUNING')) tuningFlag.add(f.path);
      }
    }
    expect(rc, ['lib/services/pg_salt.dart']);
    expect(tuningFlag, isEmpty);
    expect(File('lib/services/tuning.dart').existsSync(), isFalse);
    expect(File('lib/services/tuning_firebase.dart').existsSync(), isFalse);
    expect(File('lib/run/config/tuning_codegen.dart').existsSync(), isFalse);
    expect(File('tool/tuning_sync.dart').existsSync(), isFalse);
  });
}
