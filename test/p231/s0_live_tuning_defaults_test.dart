import 'package:flappy_spikes/run/config/tuning_codegen.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.3.1 §0 "Remote Config: the owner's live tuning is the truth": the
/// live Remote Config values (RC version 21, the tuning keys only) are the
/// in-app defaults, except where the PRD wins: `coin_bullseye` 3 (§6),
/// `shop_ad_coins` 75 (§5) and the keys new in 2.3.1 (§16, §17).
const Map<String, String> _liveV21 = {
  'coin_hoop': '1',
  'coin_perfect': '2',
  'coin_piggy_per': '3',
  'coin_jar': '5',
  'coin_spin_slices': '[1,2,3,1,2,1]',
  'coin_star_trail': '2',
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
  'point_perfect_band': '[[1,18],[25,15],[50,13],[75,10],[100,8]]',
  'point_bullseye_band': '[[1,12],[50,10],[100,8]]',
  'bonus_prizes': '[25,25,25,40,40,40,50,50,100]',
  'bonus_feather_chance': '0.6',
  'bonus_feather_gaps': '[5,30]',
  'puzzle_chance': '0.6',
  'puzzle_gaps': '[5,30]',
  'puzzle_reward': '[40,100,5]',
  'revive_ladder': '[250,500,1000,2000,4000,8000]',
  'revive_min_hoops': '6',
  'level_rewards': '[50,100,150,250,400,600,800,1000,2000,5000]',
  'shop_ad_per_day': '5',
  'shop_ad_cooldown_s': '300',
  'curve_speed': '[[0,150],[50,172.5],[150,187.5]]',
  'curve_opening': '[[1,88],[100,66]]',
  'curve_moving': '[[19,0],[20,0.15],[35,0.4],[60,0.6],[80,0.75]]',
  'curve_tilt':
      '[[9,0],[10,0.3],[19,0.3],[20,0.5],[34,0.5],[35,0.6],[44,0.6],[45,0.78]]',
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
  'gate_comet': '2',
  'gate_portal': '2',
  'gate_capsule': '2',
  'gate_shield': '2',
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
};

void main() {
  final defs = {for (final d in kTuningDefaults) d.key: d};

  test('every live RC v21 tuning value is the in-app default', () {
    for (final e in _liveV21.entries) {
      final d = defs[e.key];
      expect(d, isNotNull, reason: '${e.key} is a tuning key');
      final live = d!.type.parse(e.value, d.value);
      expect(live, isNotNull, reason: '${e.key} parses');
      expect(
        renderValue(d.type, d.value),
        renderValue(d.type, live!),
        reason: e.key,
      );
    }
  });

  test('the PRD wins over live: coin_bullseye 3, shop_ad_coins 75; the '
      '2.3.1 keys keep their PRD defaults', () {
    expect(defs['coin_bullseye']!.value, 3); // §6 (live: 2)
    expect(defs['shop_ad_coins']!.value, 75); // §5 (live: 40)
    expect(defs['ride_comet_hoop_gap']!.value, 560); // live
    expect(defs['ride_comet_tail']!.value, 100); // §16
    expect(defs['ride_comet_after_gap']!.value, 310); // §16
    expect(defs['ride_portal_max']!.value, 2); // §17
  });

  test('on the live defaults every element is still met in a full run '
      '(§3.0.8 first meet, 30 seeds × 200 slots)', () {
    final firstMeet = ElementId.values.where((e) => e.firstMeet).toList();
    for (var seed = 1; seed <= 30; seed++) {
      final d = RunDirector(
        seed: seed,
        enabled: ElementId.values.toSet(),
        met: {},
      );
      final seen = <ElementId>{};
      for (var k = 0; k < 200; k++) {
        final ctx = DirectorContext.open(711);
        final s = d.nextSlot(ctx);
        final g = d.nextGap(ctx, s);
        seen
          ..add(s.element)
          ..addAll([for (final a in s.attached) a.kind])
          ..addAll([for (final it in g.items) it.kind]);
        if (s.tiltDeg != 0) seen.add(ElementId.angledRing);
        if (s.motion != null) seen.add(ElementId.movingRing);
        for (final it in g.items) {
          if (it.extra case final CapsuleType c) seen.add(c.element);
        }
      }
      for (final e in firstMeet) {
        expect(
          seen,
          contains(e),
          reason: 'seed $seed never met ${e.storageId}',
        );
      }
    }
  });
}
