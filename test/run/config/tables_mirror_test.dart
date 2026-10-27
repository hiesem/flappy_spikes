import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../p231/tuning_23.dart';

/// `DirectorTables.prd2` / `RunConfig` mirror
/// `design/reference/data/spawn_tables.json` (copied to test/fixtures; ARCH
/// §4), with the PRD overrides asserted explicitly.
void main() {
  // PRD-2.3.1 §0: the in-app tables mirrored spawn_tables.json until the live
  // RC v21 set became the default (test/p231/tuning_23.dart); the live set
  // has its own checks.
  useTuning(tuning23Spawn()); // before `t` below is built
  setUp(() => useTuning(tuning23Spawn()));
  tearDownAll(resetTuning);
  final json =
      jsonDecode(File('test/fixtures/spawn_tables.json').readAsStringSync())
          as Map<String, dynamic>;
  // PRD-2.3 §15: the tables are built from the tuning defaults.
  final t = DirectorTables.prd2;

  test('§D2 layout bands and tilt rows mirror spawn_tables.json', () {
    expect(t.bands, same(LayoutConfig.bands));
    expect([
      for (final band in t.bands)
        {
          'from': band.from,
          'centre_y': [band.centre.$1, band.centre.$2],
          'abs_dy_median_p90_max': [band.dy.$1, band.dy.$2, band.dy.$3],
        },
    ], json['bands']);
    final rows = json['tilt_rows'] as Map<String, dynamic>;
    expect(tuning.obj('tilt_rows'), {
      for (final row in rows.entries)
        for (final weight in (row.value as Map).entries)
          '${row.key}_${weight.key}': weight.value,
    });
    expect(RunConfig.dyRefBand, json['dy_ref_band']);
    expect(RunConfig.hardHoopDyFactor, json['dy_hard_factor']);
  });

  test('§D2 compatibility views use the canonical tuning values', () {
    final weights = tuning.obj('tilt_rows')
      ..['10_10'] = 3
      ..['10_15'] = 7;
    useTuning({
      'tilt_rows': jsonEncode(weights),
      'dy_ref_band': '500',
      'dy_hard_factor': '0.8',
    });
    expect(LayoutConfig.tiltRows[10], {10: 3, 15: 7});
    expect({
      for (final row in LayoutConfig.tiltRows.entries)
        for (final weight in row.value.entries)
          '${row.key}_${weight.key}': weight.value,
    }, weights);
    expect(LayoutConfig.dyRefBand, RunConfig.dyRefBand);
    expect(LayoutConfig.dyRefBand, 500);
    expect(LayoutConfig.hardHoopDyFactor, RunConfig.hardHoopDyFactor);
    expect(LayoutConfig.hardHoopDyFactor, .8);
  });

  test('§D2 tilt magnitudes capped at 45°', () {
    for (final key in tuning.obj('tilt_rows').keys) {
      final step = int.parse(key.split('_')[1]);
      expect(step, greaterThan(0));
      expect(step, lessThanOrEqualTo(RunConfig.maxTiltDeg));
    }
    expect(json['tilt_cap_deg'], RunConfig.maxTiltDeg);
  });

  test('§3.0.3 budget mirrors spawn_tables.json', () {
    final budget = json['budget'] as List;
    expect(t.budget, hasLength(budget.length));
    for (var i = 0; i < budget.length; i++) {
      final j = budget[i] as Map<String, dynamic>;
      expect(t.budget[i].from, j['from']);
      expect(t.budget[i].special, j['special']);
      expect(t.budget[i].gap, j['gap']);
    }
  });

  test('§3.0.3 special hoops mirror spawn_tables.json', () {
    final names = {
      'bullseye': HoopKindId.bullseye,
      'train': HoopKindId.train,
      'spring': HoopKindId.spring,
      'switch': HoopKindId.switchRing,
      'pair': HoopKindId.pair,
      'fever': HoopKindId.fever,
      'lucky_spin': HoopKindId.luckySpin,
      'saw': HoopKindId.saw,
    };
    final specials = json['special_hoops'] as Map<String, dynamic>;
    expect(t.specials.keys.toSet(), names.values.toSet());
    for (final e in specials.entries) {
      final j = e.value as Map<String, dynamic>;
      final r = t.specials[names[e.key]]!;
      expect(r.from, j['from'], reason: e.key);
      expect(r.weight, j['w'], reason: e.key);
      expect(r.minSince, j['min_gap'], reason: e.key);
      expect(r.cooldown, j['cooldown'], reason: e.key);
      // Same unlocks as the catalogue (§3.0.7).
      expect(names[e.key]!.element.firstPossible, j['from']);
    }
    // PRD-2.6 §D2: the saw weight curve replaces the old hoop-45 step.
    final saw = t.specials[HoopKindId.saw]!;
    final sawJson =
        (specials['saw'] as Map<String, dynamic>)['w_curve'] as List;
    for (final point in sawJson) {
      expect(
        saw.weightAt(point[0] as int),
        point[1],
        reason: 'hoop ${point[0]}',
      );
    }
    expect(saw.weightAt(45), 17);
    expect(saw.weightAt(80), 23);

    // §3.0.3 / §D2 "not allowed when": squeeze-window kinds and portal
    // distance. Saw only re-enters a squeeze from hoop 100.
    expect(
      {
        for (final e in t.specials.entries)
          if (e.value.allowedInSqueezeFrom != null) e.key,
      },
      {HoopKindId.bullseye, HoopKindId.fever, HoopKindId.saw},
    );
    expect(t.specials[HoopKindId.bullseye]!.allowedInSqueezeAt(0), isTrue);
    expect(t.specials[HoopKindId.fever]!.allowedInSqueezeAt(0), isTrue);
    expect(t.specials[HoopKindId.saw]!.allowedInSqueezeAt(99), isFalse);
    expect(t.specials[HoopKindId.saw]!.allowedInSqueezeAt(100), isTrue);
    expect(
      {
        for (final e in t.specials.entries)
          if (e.value.blockedNearPortal == 3) e.key,
      },
      {HoopKindId.saw, HoopKindId.fever, HoopKindId.switchRing},
    );
  });

  test('§3.0.3 optional gap items mirror spawn_tables.json', () {
    final names = {
      'star_trail': ElementId.starTrail,
      'capsule': ElementId.capsule,
      'egg': ElementId.egg,
      'piggy': ElementId.piggy,
      'jar': ElementId.jar,
      'shield': ElementId.shield,
    };
    final items = json['gap_items'] as Map<String, dynamic>;
    expect(t.gapItems.keys.toSet(), names.values.toSet());
    for (final e in items.entries) {
      final j = e.value as Map<String, dynamic>;
      final r = t.gapItems[names[e.key]]!;
      expect(r.from, j['from'], reason: e.key);
      expect(r.weight, j['w'], reason: e.key);
      expect(r.minSince, j['min_gap'] ?? 0, reason: e.key);
      expect(r.maxPerRun, j['max_per_run'], reason: e.key);
    }
    final caps = (items['capsule'] as Map)['types'] as Map;
    expect(t.capsuleWeights, {
      CapsuleType.hourglass: caps['hourglass'],
      CapsuleType.miniBird: caps['mini_bird'],
      CapsuleType.coinFrenzy: caps['coin_frenzy'],
    });
    expect(t.gapItems[ElementId.starTrail]!.allowedInSqueeze, isTrue);
  });

  test('§3.0.3 schedules mirror spawn_tables.json', () {
    final s = json['schedules'] as Map<String, dynamic>;
    List<int> pair((int, int) r) => [r.$1, r.$2];
    expect(s['portal']['first'], [12, 25]);
    expect(s['portal']['then'], [80, 90]);
    expect(ElementId.portal.firstPossible, 12);
    expect(
      kTuningDefaults.firstWhere((d) => d.key == 'ride_portal_first').value,
      [12, 25],
    );
    expect(
      kTuningDefaults.firstWhere((d) => d.key == 'ride_portal_then').value,
      [80, 90],
    );
    // PRD-2.3 §14.5 the comet: 2 % per eligible hoop from 10, ≥ 25 apart.
    expect(t.comet.chance, s['comet_hoop']['chance']);
    expect(t.comet.from, s['comet_hoop']['from']);
    expect(t.comet.spacing, s['comet_hoop']['min_since_previous']);
    // PRD-2.2 §19 supersedes the PRD-2 heart value the fixture holds
    // (heart 3); PRD-2.3 §14.2 the feather / piece windows (10–40).
    expect(s['heart']['first'], 3);
    expect(t.heart.first, (5, 27));
    expect(pair(t.heart.then), s['heart']['then']);
    expect(pair(t.featherWindow), s['feather']['window']);
    expect(pair(t.pieceWindow), s['puzzle_piece']['window']);
    expect(t.featherChance, 0.6);
    expect(t.pieceChance, 0.6);
    expect(t.earlyPool!.from, 4);
    expect(t.earlyPool!.to, 9);
    expect(t.earlyPool!.weights, {
      EarlyPick.starTrail: 1,
      EarlyPick.bullseye: 1,
      EarlyPick.nothing: 1,
    });
  });

  test('§3.21 / §3.0.2 pair weights and moving types mirror the json', () {
    final pw = json['pair_weights'] as Map<String, dynamic>;
    final m = json['moving'] as Map<String, dynamic>;
    expect({for (final e in t.pairWeights.entries) e.key.name: e.value}, pw);
    expect([
      for (final row in LayoutConfig.motionRows)
        {
          'from': row.from,
          'types': {for (final e in row.types.entries) e.key.name: e.value},
          'half_travel_pt': [row.halfTravel.$1, row.halfTravel.$2],
          'speed_pt_s': [row.speed.$1, row.speed.$2],
        },
    ], m['rows']);
    expect(tuning.raw('curve_moving'), m['chance_curve']);
    expect(tuning.raw('curve_tilt'), m['tilt_curve']);
    expect([t.rail.axisDeg.$1, t.rail.axisDeg.$2], m['rail']['axis_deg']);
    expect([
      t.rail.halfTravel.$1,
      t.rail.halfTravel.$2,
    ], m['rail']['half_travel_pt']);
    expect([t.rail.speed.$1, t.rail.speed.$2], m['rail']['speed_pt_s']);
    expect(t.swing.amplitudeDeg, m['swing']['amplitude_deg']);
    expect(t.swing.period, m['swing']['period_s']);
  });

  test('§3.0.1 core tuning mirrors the json', () {
    final c = json['core'] as Map<String, dynamic>;
    expect(RunConfig.cruiseSpeed, c['scroll_pt_s']);
    // PRD-2.3 §14.4 the speed curve by hoop index (replaces the ramp).
    for (final k in c['speed_curve'] as List) {
      expect(RunConfig.cruise(k[0] as int), k[1]);
    }
    expect(RunConfig.spacing, c['spacing_pt']);
    expect(RunConfig.gravity, c['gravity']);
    expect(RunConfig.flapVelocity, c['flap_sets_vy']);
    expect(RunConfig.maxFallSpeed, c['max_fall']);
    expect(RunConfig.birdX, c['bird_x']);
    expect(RunConfig.birdRadius, c['bird_r']);
    expect(RunConfig.rimRadius, c['rim_end_r']);
    expect(RunConfig.rimRestitution, c['rim_restitution']);
    expect(RunConfig.forwardRecovery, c['forward_recovery_pt_s2']);
    expect(RunConfig.stageEveryHoops, c['colour_stage_every_hoops']);
    final defaults = {for (final def in kTuningDefaults) def.key: def};
    final o = json['opening'] as Map<String, dynamic>;
    expect(RunConfig.opening0, 118);
    // PRD-2.3 §14.4 / PRD-2.4 §1.2 the opening curve from hoop 1 (rides take
    // it too, PRD-2.4 §2; the portal is the one 118 exception).
    expect(defaults['curve_opening']!.value, [
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
    ]);
    expect(RunConfig.portalOpening, 118);
    expect(defaults['curve_moving']!.value, [
      [24, 0],
      [25, 0.15],
      [34, 0.15],
      [35, 0.25],
      [60, 0.42],
      [100, 0.52],
      [150, 0.58],
    ]);
    expect(defaults['curve_tilt']!.value, [
      [9, 0],
      [10, 0.30],
      [49, 0.35],
      [50, 0.50],
      [100, 0.60],
      [150, 0.65],
    ]);
    // PRD-2.2 §25 overrides the json's saw_extra_pt (see the group below).
    expect(o['saw_extra_pt'], 28);
    final comet = json['comet'] as Map<String, dynamic>;
    expect(comet['duration_s'], 10);
  });

  group('PRD overrides of the json / prototype (ARCH §2.2)', () {
    test('PRD-2.2 §25 saw rings: no extra opening (json: saw_extra_pt 28)', () {
      expect(json['opening']['saw_extra_pt'], 28);
      expect(RunConfig.sawExtraOpening, 0);
    });

    test('§3.0.1 first hoop: 60 pt past the right edge (json: "1.3 s")', () {
      expect(json['core']['first_hoop_after_tap_s'], 1.3);
      expect(RunConfig.firstHoopOffscreen, 60);
    });

    test('§3.21 pair offset 230 × viewHeight / 711 (proto: fixed ±115)', () {
      expect(RunConfig.pairOffsetAt711, 230);
    });

    test('§3.23 spring: next ring 240 pt away (proto: 175)', () {
      expect(RunConfig.springJump, 240);
    });

    test('§3.20 switch lead 1.0 s × scroll, ≥ 150 pt (proto: fixed 150)', () {
      expect(RunConfig.switchLeadSeconds, 1.0);
      expect(RunConfig.switchLeadMin, 150);
    });

    test('§3.28 piggy places 4 per gap (proto: 5)', () {
      expect(RunConfig.piggyCoinsPerGap, 4);
      expect(RunConfig.piggyCoinsPerGap * (1 + RunConfig.piggyFollowGaps), 20);
    });

    test('§3.0.9 #1 the band uses the 44 pt strips (proto: 72)', () {
      expect(RunConfig.stripHeight, 44);
      expect(711 - 2 * RunConfig.stripHeight, 623);
      expect(568 - 2 * RunConfig.stripHeight, 480);
    });
  });
}
