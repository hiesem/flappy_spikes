import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_types.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.3 §15 gameplay value table. Audit 17 removed the Remote Config
/// read (the Tuning service, the TUNING page, the export / import tool):
/// what is left is the baked table and the test-only override.
void main() {
  tearDown(
    () => TuningValues.current = TuningValues.resolve({'ui_unlock_best': '0'}),
  );

  group('§15 baked values', () {
    // PRD-2.3.1 §0: the section 14 values, updated to the live RC v21 set
    // (except coin_bullseye 3 and shop_ad_coins 75).
    test('tuning_defaults.dart equals the section 14 values', () {
      final t = TuningValues.defaults();
      // §14.2 coins
      expect(t.i('coin_hoop'), 1);
      expect(t.i('coin_perfect'), 2);
      expect(t.i('coin_piggy_per'), 3);
      expect(t.i('coin_jar'), 5);
      expect(t.ints('coin_spin_slices'), [1, 2, 3, 1, 2, 1]);
      expect(t.i('coin_star_trail'), 2);
      expect(t.i('coin_bullseye'), 3); // PRD-2.3.1 §6 (was 2)
      expect(t.i('coin_train'), 1);
      expect(t.i('coin_switch'), 0);
      expect(t.i('coin_pair_gift'), 3);
      expect(t.i('coin_frenzy_ring'), 1);
      expect(t.i('coin_versus_win'), 10);
      expect(t.i('coin_versus_draw'), 5);
      expect(t.ints('bonus_prizes'), [25, 25, 25, 40, 40, 40, 50, 50, 100]);
      expect(t.d('bonus_feather_chance'), .6);
      expect(t.range('bonus_feather_gaps'), (5, 30));
      expect(t.d('puzzle_chance'), .6);
      expect(t.range('puzzle_gaps'), (5, 30));
      expect(t.ints('puzzle_reward'), [40, 100, 5]);
      expect(t.ints('revive_ladder'), [250, 500, 1000, 2000, 4000, 8000]);
      expect(t.i('revive_min_hoops'), 6);
      expect(
        t.ints('level_rewards'),
        [25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000], // 2026-10-17
      );
      expect(t.i('shop_ad_coins'), 75); // PRD-2.3.1 §5 (was 40)
      expect(t.i('shop_ad_per_day'), 5);
      expect(t.i('shop_ad_cooldown_s'), 300);
      // §14.3 points
      expect(t.i('point_pass'), 1);
      expect(t.i('point_perfect_min'), 2);
      expect(t.i('point_chick'), 1);
      expect(t.i('point_fever_streak'), 5);
      // §14.4 difficulty
      expect(t.raw('curve_speed'), [
        [0, 150],
        [50, 172.5],
        [150, 187.5],
      ]);
      expect(t.raw('curve_opening'), [
        [1, 118],
        [2, 118],
        [6, 114],
        [10, 110.5],
        [16, 105.5],
        [20, 102],
        [25, 98],
        [30, 94.5],
        [35, 90.5],
        [40, 87.5],
        [50, 81],
        [60, 76.5],
        [75, 72],
        [100, 66],
      ]);
      expect(t.raw('curve_moving'), [
        [19, 0],
        [20, 0.15],
        [35, 0.40],
        [60, 0.60],
        [80, 0.75],
      ]);
      expect(t.range('squeeze_first'), (25, 40));
      expect(t.range('squeeze_hold'), (5, 10));
      expect(t.range('squeeze_gap'), (25, 45));
      // §14.5 rides
      expect(t.d('ride_comet_chance'), .04);
      expect(t.i('ride_comet_from'), 8);
      expect(t.i('ride_comet_spacing'), 18);
      expect(t.range('ride_portal_first'), (12, 25));
      expect(t.range('ride_portal_then'), (80, 90));
      expect(t.d('ride_comet_hoop_gap'), 560);
      expect(t.d('ride_comet_tail'), 100); // PRD-2.3.1 §16
      expect(t.d('ride_comet_after_gap'), 310); // PRD-2.3.1 §16
      expect(t.i('ride_portal_max'), 2); // PRD-2.3.1 §17
      // §14.6 gates
      expect(
        {
          for (final k in [
            'heart', 'star_trail', 'bullseye', 'switch', 'train', 'comet', //
            'portal', 'capsule', 'shield', 'spring', 'pair', 'egg', //
            'feather', 'puzzle', 'piggy', 'jar', 'fever', 'lucky_spin', 'saw',
          ])
            k: t.i('gate_$k'),
        },
        {
          'heart': 0, 'star_trail': 0, 'bullseye': 0, //
          'switch': 0, 'train': 0, //
          'comet': 0, 'portal': 0, 'capsule': 0, 'shield': 0, // RC v24
          'spring': 4, 'pair': 4, 'egg': 4, //
          'feather': 6, 'puzzle': 6, 'piggy': 6, 'jar': 6, //
          'fever': 8, 'lucky_spin': 8, //
          'saw': 12,
        },
      );
    });

    test('§15.3 every key is <group>_<name> snake_case, unique, and its '
        'value is valid for its type', () {
      final keys = <String>{};
      for (final d in kTuningDefaults) {
        expect(
          RegExp(r'^[a-z]+(_[a-z0-9]+)+$').hasMatch(d.key),
          isTrue,
          reason: d.key,
        );
        expect(keys.add(d.key), isTrue, reason: 'duplicate ${d.key}');
        expect(d.type.validate(d.value, d.value), isNotNull, reason: d.key);
      }
    });
  });

  group('test-only overrides', () {
    test('an override int, double, list and keyframe table reach the '
        'getters', () {
      TuningValues.current = TuningValues.resolve({
        'coin_jar': '12',
        'ride_comet_chance': '0.05',
        'bonus_prizes': '[10,20,30]',
        'curve_opening': '[[1,100],[50,80]]',
      });
      final v = TuningValues.current;
      expect(v.i('coin_jar'), 12);
      expect(v.d('ride_comet_chance'), .05);
      expect(v.ints('bonus_prizes'), [10, 20, 30]);
      expect(v.curve('curve_opening').at(25.5), closeTo(90, 1e-9));
      expect(v.i('coin_hoop'), 1);
      expect(RunConfig.openingFor(1), 100);
      expect(RunConfig.openingFor(0), 118, reason: 'hoop 0 stays 118');
    });

    test('a wrong type, broken JSON or an unknown key throws', () {
      for (final bad in <Map<String, String>>[
        {'coin_jar': 'eight'},
        {'coin_hoop': '1.5'},
        {'bonus_prizes': '[25, 25,'},
        {'curve_speed': '[[50,1],[10,2]]'},
        {'spawn_saw': '{"from": 20}'},
        {'revive_ladder': '{"a": 1}'},
        {'bonus_feather_chance': 'true'},
        {'nope_key': '1'},
      ]) {
        expect(
          () => TuningValues.resolve(bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });
  });

  group('§15.3 / §15.6 keyframe tables', () {
    final k = Keyframes([
      [10, 100],
      [20, 50],
      [30, 50],
      [31, 0],
    ]);
    test('linear between keys, flat before the first and after the last', () {
      expect(k.at(0), 100);
      expect(k.at(10), 100);
      expect(k.at(15), 75);
      expect(k.at(17.5), 62.5);
      expect(k.at(31), 0);
      expect(k.at(500), 0);
    });
    test('a plateau (two keys with the same value) and a step (two keys '
        'one hoop apart)', () {
      expect(k.at(25), 50);
      expect(k.at(30), 50);
      expect(k.at(31), 0);
      final step = Keyframes([
        [19, 0],
        [20, .15],
      ]);
      expect(step.at(19), 0);
      expect(step.at(20), .15);
      expect(step.at(0), 0);
      expect(step.at(99), .15);
    });
    test('the §14.4 curves', () {
      final v = TuningValues.defaults();
      final opening = v.curve('curve_opening');
      expect(opening.at(1), 118);
      expect(opening.at(50), closeTo(81, .2));
      expect(opening.at(100), 66);
      expect(opening.at(250), 66);
      final speed = v.curve('curve_speed');
      expect(speed.at(0), 150);
      expect(speed.at(50), 172.5);
      expect(speed.at(150), 187.5);
      expect(speed.at(300), 187.5);
    });
  });
}
