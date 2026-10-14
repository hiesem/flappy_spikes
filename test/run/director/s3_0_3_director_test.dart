import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../p231/tuning_23.dart';

/// Every element switched on and already met (no first-meet forcing).
final Set<ElementId> all = ElementId.values.toSet();

RunDirector director({
  int seed = 7,
  Set<ElementId>? enabled,
  Set<ElementId>? met,
  int startHoopIndex = 0,
  RideId? lastPortalRide,
  List<ElementId> forced = const [],
  RideId? forcedRide,
}) => RunDirector(
  seed: seed,
  enabled: enabled ?? all,
  met: met ?? all,
  startHoopIndex: startHoopIndex,
  lastPortalRide: lastPortalRide,
  forced: forced,
  forcedRide: forcedRide,
);

/// Plans [n] slots (+ their gaps) with [ctxFor] (default: an open 711 run).
List<(SlotPlan, GapPlan)> fly(
  RunDirector d,
  int n, {
  DirectorContext Function(int i)? ctxFor,
  double viewHeight = 711,
}) {
  final out = <(SlotPlan, GapPlan)>[];
  for (var k = 0; k < n; k++) {
    final ctx = ctxFor?.call(d.hoopIndex) ?? DirectorContext.open(viewHeight);
    final s = d.nextSlot(ctx);
    out.add((s, d.nextGap(ctx, s)));
  }
  return out;
}

void main() {
  // PRD-2.3.1 §0: the slot / gap order and the measured shares are calibrated
  // on the 2.3 spawn set (test/p231/tuning_23.dart); the live set has its own
  // checks.
  setUp(() => useTuning(tuning23Spawn()));
  tearDown(resetTuning);
  group('§3.0.3 determinism (§7: same seed → same sequence)', () {
    test('§3.0.3 same seed gives the same slot / gap sequence', () {
      final a = fly(director(seed: 1234), 150);
      final b = fly(director(seed: 1234), 150);
      expect(a.map((e) => e.$1).toList(), b.map((e) => e.$1).toList());
      expect(a.map((e) => e.$2).toList(), b.map((e) => e.$2).toList());
    });

    test('§3.0.3 a different seed gives a different course', () {
      final a = fly(director(seed: 1), 60).map((e) => e.$1.centreY).toList();
      final b = fly(director(seed: 2), 60).map((e) => e.$1.centreY).toList();
      expect(a, isNot(b));
    });

    test('§3.0.3 timing-stream rolls never change the slot sequence', () {
      final plain = fly(director(seed: 5), 80);
      final d = director(seed: 5);
      final mixed = <(SlotPlan, GapPlan)>[];
      for (var k = 0; k < 80; k++) {
        d.rollSqueezeAt(k.toDouble(), hoop: k);
        d.rollBigHoopsDuration();
        d.rollPuzzleBonus();
        mixed.addAll(fly(d, 1));
      }
      expect(mixed.map((e) => e.$1).toList(), plain.map((e) => e.$1).toList());
      expect(mixed.map((e) => e.$2).toList(), plain.map((e) => e.$2).toList());
    });

    test('§3.0.3 the three streams are seeded as layout / ^0x5bd1e995 / '
        '^0x9e3779b9', () {
      final r = RunRandom(42);
      expect(r.layout.nextDouble(), RunRandom(42).layout.nextDouble());
      expect(r.timing.nextInt(1 << 30), isNot(RunRandom(42).layout.nextInt(1 << 30)));
    });
  });

  group('§3.0.1 opening ramp', () {
    test('§3.0.1 / PRD-2.3 §14.4 118 pt at hoop 0, then 88 → 66 at hoop '
        '100; rides 118', () {
      final d = director();
      expect(d.openingFor(0, ride: false), 118);
      expect(d.openingFor(1, ride: false), 88);
      expect(d.openingFor(10, ride: false), closeTo(88 - 22 * 9 / 99, 1e-9));
      expect(d.openingFor(100, ride: false), 66);
      expect(d.openingFor(200, ride: false), 66);
      expect(d.openingFor(80, ride: true), 118);
    });

    test('§3.0.1 hoop index = slots spawned (a train is one slot)', () {
      final d = director(forced: [ElementId.train]);
      final plans = fly(d, 5);
      expect(plans.map((p) => p.$1.index), [0, 1, 2, 3, 4]);
      expect(plans.first.$1.kind, HoopKindId.train);
      expect(
        plans[1].$1.trackX - plans[0].$1.trackX,
        2 * RunConfig.trainDx + RunConfig.spacing,
      );
      expect(plans[2].$1.trackX - plans[1].$1.trackX, RunConfig.spacing);
    });

    test('§3.0.1 the first hoop is 60 pt past the right edge (track x 380)',
        () {
      expect(fly(director(), 1).single.$1.trackX, 380);
    });
  });

  group('§3.0.2 layout ramp', () {
    test('§3.0.2 hoop 0 is at exactly 0.50 of the band', () {
      for (final vh in [568.0, 711.0]) {
        final first = fly(director(), 1, viewHeight: vh).single.$1;
        expect(first.centreY, vh / 2);
      }
    });

    test('§3.0.2 |Δy| quantile pieces (u < 0.5 / < 0.9 / else)', () {
      const q = (0.1, 0.3, 0.5);
      expect(LayoutSampler.sampleDy(q, 0), 0);
      expect(LayoutSampler.sampleDy(q, 0.25), closeTo(0.05, 1e-9));
      expect(LayoutSampler.sampleDy(q, 0.5), closeTo(0.1, 1e-9));
      expect(LayoutSampler.sampleDy(q, 0.7), closeTo(0.2, 1e-9));
      expect(LayoutSampler.sampleDy(q, 0.95), closeTo(0.4, 1e-9));
    });

    test('§3.0.2 centres stay in the band row and the band rule; jumps ≤ '
        'the row max', () {
      for (var seed = 1; seed <= 40; seed++) {
        for (final vh in [568.0, 711.0]) {
          final d = director(
            seed: seed,
            enabled: {ElementId.normalHoop},
          );
          final band = vh - 2 * RunConfig.stripHeight;
          double? prev;
          for (final (s, _) in fly(d, 90, viewHeight: vh)) {
            final row = DirectorTables.prd2.bandFor(s.index);
            final m = s.opening / 2 + 7 + 18;
            final lo = RunConfig.stripHeight + row.centre.$1 * band;
            final hi = RunConfig.stripHeight + row.centre.$2 * band;
            expect(s.centreY, greaterThanOrEqualTo(lo - 1e-6));
            expect(s.centreY, lessThanOrEqualTo(hi + 1e-6));
            expect(s.centreY - RunConfig.stripHeight, greaterThanOrEqualTo(m - 1e-6));
            expect(vh - RunConfig.stripHeight - s.centreY, greaterThanOrEqualTo(m - 1e-6));
            if (prev != null) {
              expect((s.centreY - prev).abs(), lessThanOrEqualTo(row.dy.$3 * band + 1e-6));
            }
            prev = s.centreY;
          }
        }
      }
    });

    test('§3.0.2 no tilt before hoop 10, no motion before 20; steps capped '
        'at 45°; tilt / motion on normal hoops only', () {
      final allowedSteps = {-20.0, -10.0, 15.0, 30.0, 45.0};
      var tilted = 0, moving = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final d = director(seed: seed);
        for (final (s, _) in fly(d, 100)) {
          // PRD-2.2 §19.2: the early pool's angled ring may come from 4.
          if (s.index < 10 && d.earlyPicks[s.index] != EarlyPick.angled) {
            expect(s.tiltDeg, 0);
          }
          if (s.index < 4) expect(s.tiltDeg, 0);
          if (s.index < 20) expect(s.motion, isNull);
          if (s.kind != HoopKindId.normal || s.cometHang) {
            expect(s.tiltDeg, 0);
            expect(s.motion, isNull);
          }
          if (s.tiltDeg != 0) {
            tilted++;
            expect(allowedSteps, contains(s.tiltDeg));
          }
          if (s.index < 35) expect(s.tiltDeg, isNot(45));
          if (s.motion != null) {
            moving++;
            if (s.index < 45) {
              // A rail without room for its minimum travel rocks in place
              // (§3.11 fairness, WP-1b); PRD-2.2 §19 courses hit that too.
              expect(
                [MotionType.rail, MotionType.swing, MotionType.rock],
                contains(s.motion!.type),
              );
            }
          }
        }
      }
      expect(tilted, greaterThan(100));
      expect(moving, greaterThan(20));
    });

    test('§3.0.2 no moving rings in the squeeze window (tilted are fine)', () {
      var tilted = 0;
      for (var seed = 1; seed <= 20; seed++) {
        final d = director(seed: seed, startHoopIndex: 45);
        for (final (s, _) in fly(
          d,
          60,
          ctxFor: (_) => DirectorContext.open(711, squeezeWindow: true, squeezeInset: 60),
        )) {
          expect(s.motion, isNull);
          if (s.tiltDeg != 0) tilted++;
        }
      }
      expect(tilted, greaterThan(0));
    });
  });

  group('§3.0.3 slot order', () {
    test('§3.0.3 1. ride active: normal, full size, upright, still, no gap '
        'item', () {
      final d = director(startHoopIndex: 40);
      for (final (s, g) in fly(
        d,
        30,
        ctxFor: (_) => DirectorContext.open(711, rideActive: true, ride: RideKind.comet),
      )) {
        expect(s.kind, HoopKindId.normal);
        expect(s.opening, 118);
        expect(s.tiltDeg, 0);
        expect(s.motion, isNull);
        expect(s.cometHang, isFalse);
        expect(s.duringRide, isTrue);
        expect(g.items, isEmpty);
      }
    });

    test('§3.0.3 2. the first hoop after a revive is normal', () {
      for (var seed = 1; seed <= 30; seed++) {
        final d = director(seed: seed, startHoopIndex: 60);
        fly(d, 5);
        d.onRevive();
        final s = fly(d, 1).single.$1;
        expect(s.kind, HoopKindId.normal);
        expect(s.tiltDeg, 0);
        expect(s.motion, isNull);
        expect(s.cometHang, isFalse);
      }
    });

    test('§3.0.3 3. portal first at 40–60 (PRD-2.3 §14.5), then +60–80; '
        'never the same ride twice in a row (also across runs); cooldown 3 '
        'after it', () {
      for (var seed = 1; seed <= 60; seed++) {
        final d = director(seed: seed, lastPortalRide: RideId.space);
        final plans = fly(d, 260).map((e) => e.$1).toList();
        final portals = plans.where((s) => s.kind == HoopKindId.portal).toList();
        expect(portals, isNotEmpty);
        // It may wait (comet hoop < 10 back), never come early.
        expect(d.portalAt, greaterThan(portals.first.index));
        expect(portals.first.index, inInclusiveRange(40, 70));
        var lastRide = RideId.space;
        for (var k = 0; k < portals.length; k++) {
          final ride = portals[k].extra! as RideId;
          expect(ride, isNot(lastRide));
          lastRide = ride;
          if (k > 0) {
            // It may wait (comet hoop < 10 back), never come early.
            expect(portals[k].index - portals[k - 1].index, greaterThanOrEqualTo(60));
          }
          for (var c = 1; c <= 3 && portals[k].index + c < plans.length; c++) {
            expect(plans[portals[k].index + c].kind, HoopKindId.normal);
          }
        }
      }
    });

    test('§3.0.3 4. cooldown: 1 normal slot after a special, 2 after train / '
        'spring / pair', () {
      for (var seed = 1; seed <= 60; seed++) {
        final plans = fly(director(seed: seed), 150).map((e) => e.$1).toList();
        for (final s in plans) {
          if (s.kind == HoopKindId.normal || s.kind == HoopKindId.portal) continue;
          final cd = DirectorTables.prd2.specials[s.kind]!.cooldown;
          for (var c = 1; c <= cd && s.index + c < plans.length; c++) {
            final next = plans[s.index + c];
            expect(next.kind == HoopKindId.normal || next.kind == HoopKindId.portal,
                isTrue, reason: 'seed $seed: ${s.kind} at ${s.index} then ${next.kind}');
          }
        }
      }
    });

    test('§3.0.3 5. specials never before their first hoop and never closer '
        'than their min distance', () {
      for (var seed = 1; seed <= 60; seed++) {
        final last = <HoopKindId, int>{};
        final d = director(seed: seed);
        for (final (s, _) in fly(d, 150)) {
          final rule = DirectorTables.prd2.specials[s.kind];
          if (rule == null) continue;
          // PRD-2.2 §19.2: the early pool's Bullseye may come from 4.
          final pooled =
              s.kind == HoopKindId.bullseye &&
              d.earlyPicks[s.index] == EarlyPick.bullseye;
          expect(s.index, greaterThanOrEqualTo(pooled ? 4 : rule.from));
          final prev = last[s.kind];
          if (prev != null) expect(s.index - prev, greaterThanOrEqualTo(rule.minSince));
          last[s.kind] = s.index;
        }
      }
    });

    test('§3.0.3 6. comet hoop (PRD-2.3 §14.5: 2 % per eligible hoop from '
        '10, ≥ 25 apart), upright and still, star 20 pt past the plane; never '
        'while a timed powerup runs', () {
      var runsWithComet = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final comets = fly(director(seed: seed), 150)
            .map((e) => e.$1)
            .where((s) => s.cometHang)
            .toList();
        if (comets.isNotEmpty) runsWithComet++;
        if (comets.isNotEmpty) {
          expect(comets.first.index, greaterThanOrEqualTo(10));
        }
        for (var k = 1; k < comets.length; k++) {
          expect(comets[k].index - comets[k - 1].index, greaterThanOrEqualTo(25));
        }
        for (final c in comets) {
          final star = c.attached.single;
          expect(star.kind, ElementId.comet);
          expect(star.trackX, c.trackX + 20);
          expect(c.tiltDeg, 0);
          expect(c.motion, isNull);
        }
      }
      expect(runsWithComet, greaterThan(40));
      final busy = fly(
        director(),
        120,
        ctxFor: (_) => DirectorContext.open(711, timedPowerupRunning: true),
      );
      expect(busy.where((e) => e.$1.cometHang), isEmpty);
    });

    test('§3.0.3 the comet hoop and the portal keep ≥ 10 hoops apart', () {
      for (var seed = 1; seed <= 60; seed++) {
        final plans = fly(director(seed: seed), 200).map((e) => e.$1).toList();
        final portals = plans.where((s) => s.kind == HoopKindId.portal).map((s) => s.index);
        for (final c in plans.where((s) => s.cometHang)) {
          for (final p in portals) {
            expect((c.index - p).abs(), greaterThanOrEqualTo(10), reason: 'seed $seed');
          }
        }
      }
    });

    test('§3.0.3 squeeze window: only bullseye, FEVER and saw specials; no '
        'comet hoop, no portal', () {
      for (var seed = 1; seed <= 30; seed++) {
        final d = director(seed: seed, startHoopIndex: 20);
        for (final (s, g) in fly(
          d,
          80,
          ctxFor: (_) => DirectorContext.open(711, squeezeWindow: true, squeezeInset: 50),
        )) {
          expect(
            [HoopKindId.normal, HoopKindId.bullseye, HoopKindId.fever, HoopKindId.saw],
            contains(s.kind),
          );
          expect(s.cometHang, isFalse);
          for (final it in g.items) {
            expect([ElementId.heart, ElementId.starTrail], contains(it.kind),
                reason: 'only scheduled hearts + star trails in a squeeze');
          }
        }
      }
    });

    test('§3.0.3 saw: normal opening (PRD-2.2 §25; PRD-2 had +28 pt), never '
        'right next to a FEVER ring, '
        'design never the same twice in a row', () {
      for (var seed = 1; seed <= 40; seed++) {
        final plans = fly(director(seed: seed), 150).map((e) => e.$1).toList();
        SawDesign? lastSaw;
        SwitchDesign? lastSwitch;
        for (final s in plans) {
          if (s.kind == HoopKindId.saw) {
            expect(s.opening, closeTo(RunConfig.openingFor(s.index), 1e-9));
            expect(s.extra, isNot(lastSaw));
            lastSaw = s.extra! as SawDesign;
            if (s.index > 0) expect(plans[s.index - 1].kind, isNot(HoopKindId.fever));
          }
          if (s.kind == HoopKindId.switchRing) {
            expect(s.extra, isNot(lastSwitch));
            lastSwitch = s.extra! as SwitchDesign;
          }
        }
      }
    });

    test('§3.0.3 saw / FEVER / switch never within 3 hoops of the portal', () {
      for (var seed = 1; seed <= 60; seed++) {
        final plans = fly(director(seed: seed), 200).map((e) => e.$1).toList();
        final portals = plans.where((s) => s.kind == HoopKindId.portal).map((s) => s.index).toList();
        for (final s in plans) {
          if (![HoopKindId.saw, HoopKindId.fever, HoopKindId.switchRing].contains(s.kind)) {
            continue;
          }
          for (final p in portals) {
            expect((s.index - p).abs(), greaterThan(3), reason: 'seed $seed ${s.kind}');
          }
        }
      }
    });

    test('§3.20 switch ring: its switch takes the gap before (1.0 s × scroll '
        '≥ 150 pt, 70–100 pt above / below, ≤ 110 pt from the previous centre)',
        () {
      var seen = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final plans = fly(
          director(seed: seed),
          150,
          ctxFor: (_) => DirectorContext.open(711, scrollSpeed: 180),
        );
        for (var k = 0; k < plans.length; k++) {
          final s = plans[k].$1;
          if (s.kind != HoopKindId.switchRing) continue;
          seen++;
          final sw = s.attached.single;
          expect(sw.kind, ElementId.switchRing);
          expect(s.trackX - sw.trackX, 180);
          final dy = (sw.y! - s.centreY).abs();
          expect(dy, greaterThanOrEqualTo(60));
          final prev = plans[k - 1].$1;
          final prevEnd = prev.kind == HoopKindId.train
              ? prev.centreY + 2 * 16 * (prev.extra! as TrainSpec).dir
              : prev.centreY;
          expect((sw.y! - prevEnd).abs(), lessThanOrEqualTo(110 + 1e-6));
          expect(plans[k - 1].$2.items, isEmpty, reason: 'the gap before is free');
        }
      }
      expect(seen, greaterThan(20));
    });

    test('§3.21 pair: offset 230 × viewHeight / 711, two different gifts, no '
        'shield when armed, no FEVER during FEVER', () {
      for (final vh in [568.0, 711.0]) {
        final o = 230 * vh / 711;
        var pairs = 0;
        for (var seed = 1; seed <= 60; seed++) {
          for (final (s, _) in fly(
            director(seed: seed),
            150,
            viewHeight: vh,
            ctxFor: (_) => DirectorContext.open(vh, shieldArmed: true, onFire: true, fever: true),
          )) {
            if (s.kind != HoopKindId.pair) continue;
            pairs++;
            expect(s.ringOffsets, [-o / 2, o / 2]);
            final r = s.extra! as PairRewards;
            expect(r.top, isNot(r.bottom));
            for (final g in [r.top, r.bottom]) {
              expect(g, isNot(PairReward.shield));
              expect(g, isNot(PairReward.fever));
            }
            expect(s.centreY - o / 2 - s.opening / 2 - 7, greaterThanOrEqualTo(114 - 1e-6));
            expect(s.centreY + o / 2 + s.opening / 2 + 7 + 18,
                lessThanOrEqualTo(vh - RunConfig.stripHeight + 1e-6));
          }
        }
        expect(pairs, greaterThan(5));
      }
    });

    test('§3.23 spring: the next hoop is 240 pt above / below', () {
      var springs = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final plans = fly(director(seed: seed), 150).map((e) => e.$1).toList();
        for (final s in plans.where(
          (s) => s.kind == HoopKindId.spring && s.index + 1 < plans.length,
        )) {
          springs++;
          final next = plans[s.index + 1];
          final dir = s.extra == SpringDir.up ? -1 : 1;
          expect(next.centreY - s.centreY, closeTo(dir * 240, 1e-6));
        }
      }
      expect(springs, greaterThan(10));
    });

    test('§3.25 Lucky Spin prize is pre-rolled from the slices', () {
      final spins = <int>{};
      for (var seed = 1; seed <= 60; seed++) {
        for (final (s, _) in fly(director(seed: seed), 150)) {
          if (s.kind != HoopKindId.luckySpin) continue;
          final p = s.extra! as SpinPrize;
          expect(RunConfig.luckySpinSlices[p.slice], p.coins);
          spins.add(p.coins);
        }
      }
      // PRD-2.3.1 §0 (live RC v21): [1, 2, 3, 1, 2, 1] (2.3: with a +5).
      expect(spins, {1, 2, 3});
    });
  });

  group('§3.0.3 gap order', () {
    test('§3.0.3 heart (PRD-2.2 §19.1): first at a random gap 5–27, then '
        'every 17–27 gaps; ±50 pt off the line (§19.4)', () {
      for (var seed = 1; seed <= 40; seed++) {
        final hearts = <int>[];
        final d = director(seed: seed);
        final first = d.heartAt;
        expect(first, inInclusiveRange(5, 27));
        for (final (s, g) in fly(d, 120)) {
          for (final it in g.items.where((i) => i.kind == ElementId.heart)) {
            hearts.add(s.index);
            expect(it.lineOffset.abs(), lessThanOrEqualTo(50));
          }
        }
        // A taken gap pushes it to the next free one.
        expect(hearts.first, greaterThanOrEqualTo(first));
        expect(hearts.first - first, lessThan(4));
        for (var k = 1; k < hearts.length; k++) {
          expect(hearts[k] - hearts[k - 1], greaterThanOrEqualTo(17));
        }
      }
    });

    test('§3.3 no heart while an extra life is active; the schedule still '
        'moves on', () {
      final d = director();
      final plans = fly(
        d,
        60,
        ctxFor: (_) => DirectorContext.open(711, extraLifeActive: true),
      );
      expect(plans.expand((e) => e.$2.items).where((i) => i.kind == ElementId.heart), isEmpty);
      expect(d.heartAt, greaterThan(5 + 17));
    });

    test('§3.15 / §3.16 (PRD-2.2 §19.3 / §19.4) feather at most once in '
        'gaps 3–40 (only while < 3 held), piece at most once in 3–40 (a '
        'missing piece), never in the same / neighbouring gap; 30–70 % along '
        'the gap, ±50 pt off the line', () {
      for (var seed = 1; seed <= 40; seed++) {
        final d = director(seed: seed);
        final plans = fly(
          d,
          80,
          ctxFor: (_) => DirectorContext.open(711, puzzleMask: 0x5),
        );
        final feathers = [
          for (final (s, g) in plans)
            for (final it in g.items)
              if (it.kind == ElementId.feather) (s, it),
        ];
        final pieces = [
          for (final (s, g) in plans)
            for (final it in g.items)
              if (it.kind == ElementId.puzzlePiece) (s, it),
        ];
        expect(feathers, hasLength(d.featherThisRun ? 1 : 0));
        expect(pieces, hasLength(d.pieceThisRun ? 1 : 0));
        // "Pushed to the next free gap": at or after the window start.
        for (final f in feathers) {
          expect(f.$1.index, greaterThanOrEqualTo(3));
          expect(f.$1.index, greaterThanOrEqualTo(d.featherAt));
        }
        for (final p in pieces) {
          expect(p.$1.index, greaterThanOrEqualTo(3));
          expect([1, 3], contains(p.$2.extra));
        }
        if (feathers.isNotEmpty && pieces.isNotEmpty) {
          expect(
            (feathers.single.$1.index - pieces.single.$1.index).abs(),
            greaterThan(1),
          );
        }
        for (final (s, it) in [...feathers, ...pieces]) {
          expect(it.y, isNull, reason: 'on the line, resolved by the spawner');
          final u = (it.trackX - s.lastRingX) / 310;
          expect(u, inInclusiveRange(0.3 - 1e-9, 0.7 + 1e-9));
          expect(it.lineOffset.abs(), lessThanOrEqualTo(50));
        }
      }
      final none = fly(
        director(),
        40,
        ctxFor: (_) => DirectorContext.open(711, featherWanted: false, puzzleMask: 0xF),
      );
      expect(
        none.expand((e) => e.$2.items).where(
          (i) => i.kind == ElementId.feather || i.kind == ElementId.puzzlePiece,
        ),
        isEmpty,
      );
    });

    test('§3.28 running Piggy Bank: 4 coins in each of the next 4 gaps', () {
      final d = director(startHoopIndex: 30);
      final plans = fly(
        d,
        8,
        ctxFor: (_) => DirectorContext.open(711, piggyRunning: true),
      );
      final coins = [
        for (final (_, g) in plans)
          for (final it in g.items)
            if (it.kind == ElementId.piggyCoins) it,
      ];
      expect(coins, hasLength(4));
      for (final c in coins) {
        expect(c.extra, 4);
      }
    });

    test('§3.29 running Firefly Jar: a swarm of 7 in every gap', () {
      final plans = fly(
        director(startHoopIndex: 30),
        6,
        ctxFor: (_) => DirectorContext.open(711, jarRunning: true),
      );
      for (final (_, g) in plans) {
        expect(g.items.where((i) => i.kind == ElementId.fireflySwarm).single.extra, 7);
      }
    });

    test('§3.0.3 optional items respect from / min gaps / limits', () {
      for (var seed = 1; seed <= 60; seed++) {
        final last = <ElementId, int>{};
        var shields = 0;
        final d = director(seed: seed);
        for (final (s, g) in fly(d, 150)) {
          for (final it in g.items) {
            final rule = DirectorTables.prd2.gapItems[it.kind];
            if (rule == null) continue;
            // PRD-2.2 §19.2: the early pool's Star Trail may come from 4.
            final pooled =
                it.kind == ElementId.starTrail &&
                d.earlyPicks[s.index] == EarlyPick.starTrail;
            expect(s.index, greaterThanOrEqualTo(pooled ? 4 : rule.from));
            final prev = last[it.kind];
            if (prev != null) {
              expect(s.index - prev, greaterThanOrEqualTo(rule.minSince));
            }
            last[it.kind] = s.index;
            if (it.kind == ElementId.shield) shields++;
            if (it.kind == ElementId.capsule) expect(it.extra, isA<CapsuleType>());
          }
          expect(g.items.length, lessThanOrEqualTo(1));
        }
        expect(shields, lessThanOrEqualTo(1));
      }
    });

    test('§3.0.3 exclusivity: no capsule while a timed powerup runs, no '
        'egg with an egg / chick, no piggy / jar while one runs, no shield '
        'while shielded', () {
      for (var seed = 1; seed <= 30; seed++) {
        final plans = fly(
          director(seed: seed),
          150,
          ctxFor: (_) => DirectorContext.open(
            711,
            timedPowerupRunning: true,
            eggOrChick: true,
            shieldArmed: true,
          ),
        );
        for (final it in plans.expand((e) => e.$2.items)) {
          expect(
            [ElementId.capsule, ElementId.egg, ElementId.shield],
            isNot(contains(it.kind)),
          );
        }
      }
    });

    test('§3.0.3 budget: no special at hoops 0–7 and no optional item at '
        'gaps 0–4 (PRD-2.2 §19.2: but the early pool at 4–9)', () {
      for (var seed = 1; seed <= 100; seed++) {
        final d = director(seed: seed);
        for (final (s, g) in fly(d, 8)) {
          final pick = d.earlyPicks[s.index];
          if (s.kind != HoopKindId.normal) {
            expect(s.kind, HoopKindId.bullseye);
            expect(pick, EarlyPick.bullseye);
          }
          if (s.index < 4) expect(pick, isNull);
          for (final it in g.items) {
            if (it.kind == ElementId.starTrail) {
              expect(pick, EarlyPick.starTrail);
            } else {
              expect(
                [ElementId.heart, ElementId.feather, ElementId.puzzlePiece],
                contains(it.kind),
              );
            }
          }
        }
      }
    });

    test('§3.0.3 measured shares match the prototype (300 seeds × 120 slots, '
        'no rides / squeeze): specials ≈ 18 % at 8–19, ≈ 25 % at 20–49, ≈ 32 % '
        'from 50; ≈ 1 gap in 3 holds something', () {
      // Prototype (design/menu_v2/proto_gameplay.html, spawnSlot driven by
      // Playwright with the squeeze off, same sample): 0.0 / 18.1 / 25.5 /
      // 32.1 %, gaps 31.6 %. Its shares are lower in bot runs because ride
      // hoops are normal (PRD: ≈ 15 / 20 / 25 %).
      final n = <String, List<int>>{
        '0-7': [0, 0],
        '8-19': [0, 0],
        '20-49': [0, 0],
        '50+': [0, 0],
      };
      var gaps = 0, used = 0;
      for (var seed = 1; seed <= 300; seed++) {
        final plans = fly(director(seed: seed), 120);
        for (var k = 0; k < plans.length; k++) {
          final (s, g) = plans[k];
          final key = s.index < 8
              ? '0-7'
              : s.index < 20
              ? '8-19'
              : s.index < 50
              ? '20-49'
              : '50+';
          n[key]![1]++;
          if (s.kind != HoopKindId.normal) n[key]![0]++;
          gaps++;
          final nextHasSwitch = k + 1 < plans.length &&
              plans[k + 1].$1.attached.any((a) => a.kind == ElementId.switchRing);
          if (g.items.isNotEmpty || nextHasSwitch) used++;
        }
      }
      double pct(String k) => 100 * n[k]![0] / n[k]![1];
      // PRD-2.2 §19.2: the early pool's Bullseye (¼ of the draws at 4–7,
      // ≥ 6 apart) is the only special below hoop 8 now.
      expect(pct('0-7'), closeTo(9, 3));
      expect(pct('8-19'), closeTo(18.1, 4));
      expect(pct('20-49'), closeTo(25.5, 4));
      expect(pct('50+'), closeTo(32.1, 4));
      expect(100 * used / gaps, closeTo(31.6, 4));
    });
  });

  group('§3.0.8 registry gating and debug force', () {
    test('§3.0.8 unregistered elements are never offered', () {
      for (var seed = 1; seed <= 20; seed++) {
        for (final (s, g) in fly(
          director(seed: seed, enabled: {ElementId.normalHoop}),
          150,
        )) {
          expect(s.kind, HoopKindId.normal);
          expect(s.tiltDeg, 0);
          expect(s.motion, isNull);
          expect(s.cometHang, isFalse);
          expect(g.items, isEmpty);
        }
      }
    });

    test('§3.0.8 debug force: the next slot, ignoring unlock and cooldown', () {
      final d = director(forced: [ElementId.saw, ElementId.bullseye]);
      final plans = fly(d, 2).map((e) => e.$1).toList();
      expect(plans[0].kind, HoopKindId.saw);
      expect(plans[0].forced, isTrue);
      expect(plans[1].kind, HoopKindId.bullseye, reason: 'cooldown ignored');
    });

    test('§3.0.8 debug force: gap items go to the next gap; squeeze is not '
        'a director element', () {
      final d = director();
      expect(d.debugForce(ElementId.jar), isTrue);
      expect(d.debugForce(ElementId.squeeze), isFalse);
      final g = fly(d, 1).single.$2;
      expect(g.items.single.kind, ElementId.jar);
    });

    test('§3.0.8 debug force keeps exclusivity (no capsule during a timed '
        'powerup)', () {
      final d = director(forced: [ElementId.hourglass]);
      final busy = fly(
        d,
        3,
        ctxFor: (_) => DirectorContext.open(711, timedPowerupRunning: true),
      );
      expect(busy.expand((e) => e.$2.items), isEmpty);
      final g = fly(d, 1).single.$2;
      expect(g.items.single.kind, ElementId.capsule);
      expect(g.items.single.extra, CapsuleType.hourglass);
    });

    test('§3.0.8 force portal ride: the next slot is a portal with that ride',
        () {
      final d = director(forcedRide: RideId.pinball, lastPortalRide: RideId.pinball);
      final s = fly(d, 1).single.$1;
      expect(s.kind, HoopKindId.portal);
      expect(s.extra, RideId.pinball);
    });

    test('§7 startHoopIndex sets the hoop index and the opening ramp', () {
      final d = director(startHoopIndex: 20, enabled: {ElementId.normalHoop});
      final s = fly(d, 1).single.$1;
      expect(s.index, 20);
      expect(s.opening, closeTo(RunConfig.openingFor(20), 1e-9));
      expect(s.centreY, 711 / 2);
    });

    test('§6 spawned counts feed run_director_hoops / _items', () {
      final d = director();
      final plans = fly(d, 100);
      final counts = d.spawnedCounts;
      final kinds = plans.where((e) => e.$1.kind == HoopKindId.normal).length;
      expect(counts['normal_hoop'], kinds);
      expect(counts['heart'], greaterThan(0));
      expect(counts['tilted'], plans.where((e) => e.$1.tiltDeg != 0).length);
    });
  });

  group('§3.0.3 timing rolls', () {
    test('§3.17 / §3.6 / §3.16 / §3.30 ranges', () {
      final d = director();
      for (var k = 0; k < 200; k++) {
        // PRD-2.3 §14.4 the squeeze in hoops: the next 25–45 hoops on
        // (at 150 pt/s from hoop 0: 310 / 150 s per hoop, a little less as
        // the speed grows), the hold 5–10 hoops.
        const perHoop = 310 / 150;
        expect(
          d.rollSqueezeAt(10, hoop: 0),
          inInclusiveRange(10 + 25 * perHoop * .9, 10 + 45 * perHoop),
        );
        expect(
          d.rollSqueezeHold(hoop: 0),
          inInclusiveRange(5 * perHoop * .99, 10 * perHoop),
        );
        expect(d.rollBigHoopsDuration(), inInclusiveRange(30, 40));
        final bonus = d.rollPuzzleBonus();
        // PRD-2.3.1 §0 (live RC v21) the puzzle reward is 40–100 (2.3: 50–150).
        expect(bonus, inInclusiveRange(40, 100));
        expect(bonus % 5, 0);
        expect(d.rollHourglassDuration(), inInclusiveRange(10, 20));
      }
    });
  });
}
