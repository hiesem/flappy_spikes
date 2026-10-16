import 'dart:convert';
import 'dart:io';

import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
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

  test('§3.0.2 layout bands mirror spawn_tables.json', () {
    final bands = json['bands'] as List;
    expect(t.bands, hasLength(bands.length));
    for (var i = 0; i < bands.length; i++) {
      final j = bands[i] as Map<String, dynamic>;
      final b = t.bands[i];
      expect(b.from, j['from']);
      expect([b.centre.$1, b.centre.$2], j['centre_y']);
      expect([b.dy.$1, b.dy.$2, b.dy.$3], j['abs_dy_median_p90_max']);
      expect(b.tilt, j['tilt_chance']);
      expect(b.moving, j['moving_chance']);
      expect(
        {for (final e in b.tiltWeights.entries) '${e.key}': e.value},
        (j['tilt_weights'] as Map).cast<String, int>(),
      );
    }
  });

  test('§3.0.2 tilt steps capped at 45° (60° folded in)', () {
    for (final b in t.bands) {
      for (final step in b.tiltWeights.keys) {
        expect(step.abs(), lessThanOrEqualTo(RunConfig.maxTiltDeg));
      }
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
      expect(r.weightFrom45, j['w_from_45'], reason: e.key);
      expect(r.minSince, j['min_gap'], reason: e.key);
      expect(r.cooldown, j['cooldown'], reason: e.key);
      // Same unlocks as the catalogue (§3.0.7).
      expect(names[e.key]!.element.firstPossible, j['from']);
    }
    // §3.0.3 "not allowed when": squeeze-window kinds and portal distance.
    expect(
      {
        for (final e in t.specials.entries)
          if (e.value.allowedInSqueeze) e.key,
      },
      {HoopKindId.bullseye, HoopKindId.fever, HoopKindId.saw},
    );
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
    expect(pair(t.portal.first), s['portal']['first']);
    expect(pair(t.portal.then), s['portal']['then']);
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
      EarlyPick.angled: 1,
      EarlyPick.nothing: 1,
    });
  });

  test('§3.21 / §3.0.2 pair weights and moving types mirror the json', () {
    final pw = json['pair_weights'] as Map<String, dynamic>;
    expect({for (final e in t.pairWeights.entries) e.key.name: e.value}, pw);
    final m = json['moving'] as Map<String, dynamic>;
    String name(MotionType x) => x == MotionType.horizontal ? 'horizontal' : x.name;
    expect(
      {for (final e in t.movingTypes45.entries) name(e.key): e.value},
      m['types_from_hoop_45'],
    );
    expect(
      {for (final e in t.movingTypes20.entries) name(e.key): e.value},
      m['types_hoop_20_44'],
    );
    expect([t.rail.axisDeg.$1, t.rail.axisDeg.$2], m['rail']['axis_deg']);
    expect([t.rail.halfTravel.$1, t.rail.halfTravel.$2], m['rail']['half_travel_pt']);
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
    final o = json['opening'] as Map<String, dynamic>;
    expect(RunConfig.opening0, o['at_hoop_0_pt']);
    expect(RunConfig.openingFor(0), o['at_hoop_0_pt']);
    // PRD-2.3 §14.4 / PRD-2.4 §1.2 the opening curve from hoop 1 (rides take
    // it too, PRD-2.4 §2; the portal is the one 118 exception).
    for (final k in o['curve_from_hoop_1'] as List) {
      expect(RunConfig.openingFor(k[0] as int), k[1]);
    }
    expect(RunConfig.portalOpening, 118);
    final m = json['moving'] as Map<String, dynamic>;
    for (final k in m['chance_curve'] as List) {
      expect(t.movingChance(k[0] as int), k[1]);
    }
    for (final k in m['tilt_curve'] as List) {
      expect(t.tiltChance(k[0] as int), k[1]);
    }
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
