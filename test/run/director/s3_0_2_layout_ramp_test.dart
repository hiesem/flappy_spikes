import 'dart:math' as math;

import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-1b: the §3.0.2 hoop layout ramp per hoop index — centre ranges, |Δy|
/// quantiles, zig-zag, tilt share + steps, moving share + types, and the
/// §3.11 motion parameters / fairness caps the director rolls. Pure Dart.

/// Normal hoops + both modifiers only (no specials, no comet, no portal),
/// all met (no first-meet forcing): the plain ramp.
const Set<ElementId> plain = {
  ElementId.normalHoop,
  ElementId.angledRing,
  ElementId.movingRing,
};

List<SlotPlan> course(
  int seed, {
  int n = 120,
  int start = 0,
  double vh = 711,
  Set<ElementId> enabled = plain,
}) {
  final d = RunDirector(
    seed: seed,
    enabled: enabled,
    met: ElementId.values.toSet(),
    startHoopIndex: start,
  );
  final out = <SlotPlan>[];
  double? previousY;
  for (var k = 0; k < n; k++) {
    final ctx = DirectorContext.open(vh, prevCentreY: previousY);
    final s = d.nextSlot(ctx);
    d.nextGap(ctx, s);
    out.add(s);
    previousY = s.centreY;
  }
  return out;
}

/// Every row of the ramp with its last hoop index (inclusive).
final rows = [
  for (var i = 0; i < LayoutConfig.bands.length; i++)
    (
      LayoutConfig.bands[i],
      i + 1 < LayoutConfig.bands.length
          ? LayoutConfig.bands[i + 1].from - 1
          : 1 << 30,
    ),
];

double quantile(List<double> xs, double q) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * q).round()];
}

Map<int, Map<int, int>> _tiltRows() {
  final rows = <int, Map<int, int>>{};
  for (final entry in tuning.obj('tilt_rows').entries) {
    final parts = entry.key.split('_');
    (rows[int.parse(parts[0])] ??= {})[int.parse(parts[1])] = entry.value
        .toInt();
  }
  return rows;
}

void main() {
  const seeds = 400;
  final plans = <double, List<List<SlotPlan>>>{
    for (final vh in [568.0, 711.0])
      vh: [for (var s = 1; s <= seeds; s++) course(s, vh: vh)],
  };

  group('§3.0.2 the ramp as data (LayoutConfig)', () {
    test('§3.0.2 the director tables read the layout rows and motion tables '
        'from LayoutConfig', () {
      final t = DirectorTables.prd2;
      expect(identical(t.bands, LayoutConfig.bands), isTrue);
      expect(identical(t.rail, LayoutConfig.rail), isTrue);
      expect(identical(t.swing, LayoutConfig.swing), isTrue);
    });

    test('PRD-2.6 D2 rows at 0, 3, 20, 40, 65, 100', () {
      expect(LayoutConfig.bands.map((b) => b.from), [0, 3, 20, 40, 65, 100]);
      // PRD-2.6 D2 owns modifier chances in independent curves, not Δy rows.
      final tables = DirectorTables.prd2;
      for (final (hoop, chance) in [
        (9, 0.0),
        (10, .30),
        (49, .35),
        (50, .50),
        (100, .60),
        (150, .65),
      ]) {
        expect(tables.tiltChance(hoop), closeTo(chance, 1e-12));
      }
      for (final (hoop, chance) in [
        (24, 0.0),
        (25, .15),
        (34, .15),
        (35, .25),
        (60, .42),
        (100, .52),
        (150, .58),
      ]) {
        expect(tables.movingChance(hoop), closeTo(chance, 1e-12));
      }
      for (final (i, row) in [
        (0, 0),
        (2, 0),
        (3, 1),
        (9, 1),
        (20, 2),
        (39, 2),
        (40, 3),
        (64, 3),
        (65, 4),
        (99, 4),
        (100, 5),
        (400, 5),
      ]) {
        expect(
          LayoutConfig.bandFor(i),
          same(LayoutConfig.bands[row]),
          reason: 'hoop $i',
        );
        expect(DirectorTables.prd2.bandFor(i), same(LayoutConfig.bands[row]));
      }
      expect(LayoutConfig.rail.axisDeg, (-25, 25));
      expect(LayoutConfig.rail.halfTravel, (40, 60));
      expect(LayoutConfig.rail.speed, (30, 39));
      expect(LayoutConfig.swing.amplitudeDeg, 15);
      expect(LayoutConfig.swing.period, 1.8);
    });
  });

  group('§3.0.2 layout ramp per hoop index', () {
    test('§3.0.2 every hoop index keeps its row\'s centre range, and the '
        'course uses the whole range (568 and 711)', () {
      for (final vh in plans.keys) {
        final band = vh - 2 * RunConfig.stripHeight;
        for (final (row, last) in rows) {
          final ys = <double>[];
          for (final run in plans[vh]!) {
            for (final s in run) {
              if (s.index < row.from || s.index > last) continue;
              // PRD-2.6 D2: centre rows are fractions of the full band (only
              // Δy rows use min(band, dyRef)).
              final f = (s.centreY - vh / 2) / band + 0.5;
              expect(
                f,
                greaterThanOrEqualTo(row.centre.$1 - 1e-9),
                reason: 'hoop ${s.index} @$vh',
              );
              expect(
                f,
                lessThanOrEqualTo(row.centre.$2 + 1e-9),
                reason: 'hoop ${s.index} @$vh',
              );
              ys.add(f);
            }
          }
          if (row.from == 0) continue; // hoops 0–2 barely move (dy ≤ 0.07)
          final lo = ys.reduce(math.min), hi = ys.reduce(math.max);
          expect(
            lo,
            lessThan(row.centre.$1 + 0.03),
            reason: 'row ${row.from} @$vh',
          );
          expect(
            hi,
            greaterThan(row.centre.$2 - 0.03),
            reason: 'row ${row.from} @$vh',
          );
        }
      }
    });

    test('§3.0.2 |Δy| follows the row\'s median / p90 / max pieces', () {
      for (final (row, last) in rows) {
        final dys = <double>[];
        for (final vh in plans.keys) {
          final band = math.min(
            vh - 2 * RunConfig.stripHeight,
            RunConfig.dyRefBand,
          );
          for (final run in plans[vh]!) {
            for (var k = 1; k < run.length; k++) {
              final s = run[k];
              // Row boundaries change the centre range: skip the first
              // hoop of each row.
              if (s.index <= row.from || s.index > last) continue;
              dys.add((s.centreY - run[k - 1].centreY).abs() / band);
            }
          }
        }
        final (med, p90, mx) = row.dy;
        for (final d in dys) {
          expect(d, lessThanOrEqualTo(mx + 1e-9), reason: 'row ${row.from}');
        }
        // Clamping at the range edges only shortens steps.
        expect(
          quantile(dys, .5),
          closeTo(med, med * .3 + .01),
          reason: 'median row ${row.from}',
        );
        expect(
          quantile(dys, .9),
          lessThanOrEqualTo(p90 + .01),
          reason: 'p90 row ${row.from}',
        );
        expect(
          quantile(dys, .9),
          greaterThan(p90 * .6),
          reason: 'p90 row ${row.from}',
        );
      }
    });

    test('§3.0.2 direction zig-zags: flips ≈ 65 % of the steps', () {
      var flips = 0, steps = 0;
      for (final run in plans[711.0]!) {
        for (var k = 2; k < run.length; k++) {
          final a = run[k - 1].centreY - run[k - 2].centreY;
          final b = run[k].centreY - run[k - 1].centreY;
          if (a.abs() < 1 || b.abs() < 1) continue;
          steps++;
          if (a.sign != b.sign) flips++;
        }
      }
      // Leaving the range forces extra flips.
      expect(flips / steps, inInclusiveRange(.62, .80));
    });

    test('§D2 tilt follows the curve and magnitude rows; none before 10; 45° '
        'only from 60', () {
      for (final entry in _tiltRows().entries) {
        final rowFrom = entry.key;
        final weights = entry.value;
        final rowTo = math.min(
          150,
          _tiltRows().keys
                  .where((from) => from > rowFrom)
                  .fold(1 << 30, math.min) -
              1,
        );
        // PRD-2.6 D2 defines the tilt chance and weights as a roll on the
        // row. D3 may remove a tilt afterwards and D4 forces calm slots
        // untilted, so the final course is not a sample of the roll chance.
        // Sample the sampler itself, then keep the final-plan safety checks
        // below (early rows and the 45° gate).
        var normal = 0, tilted = 0;
        final steps = <int, int>{};
        for (var hoop = rowFrom; hoop <= rowTo; hoop++) {
          for (var seed = 1; seed <= 120; seed++) {
            final sampler = LayoutSampler(
              DirectorTables.prd2,
              math.Random(seed * 1009 + hoop),
            );
            final tilt = sampler.tilt(hoop);
            normal++;
            if (tilt != 0) {
              tilted++;
              final step = tilt.round();
              steps[step] = (steps[step] ?? 0) + 1;
            }
          }
        }
        for (final vh in plans.keys) {
          for (final run in plans[vh]!) {
            for (final s in run) {
              if (s.index < rowFrom || s.index > rowTo) continue;
              if (DirectorTables.prd2.earlyPool!.covers(s.index)) continue;
              if (s.tiltDeg.abs() >= 20) {
                final dy = s.centreY - run.elementAt(s.index - 1).centreY;
                expect(dy.abs(), greaterThanOrEqualTo(40 - 1e-9));
                expect(s.tiltDeg.sign, dy.sign);
              }
            }
          }
        }
        final table = DirectorTables.prd2;
        var chance = 0.0;
        for (var i = rowFrom; i <= rowTo; i++) {
          chance += table.tiltChance(i);
        }
        chance /= rowTo - rowFrom + 1;
        expect(tilted / normal, closeTo(chance, .03), reason: 'row $rowFrom');
        expect(
          steps.keys.map((step) => step.abs()).toSet(),
          weights.keys.toSet(),
        );
        if (rowFrom < 60) expect(steps.containsKey(45), isFalse);
      }
      for (final run in plans[711.0]!) {
        for (final s in run) {
          if (s.index < 10) expect(s.tiltDeg, 0, reason: 'hoop ${s.index}');
          if (s.index < 60) expect(s.tiltDeg.abs(), isNot(45));
        }
      }
    });

    test('§D2 moving share and type weights; none before 25', () {
      for (final (row, last) in rows) {
        if (last < 25) continue;
        final from = math.max(row.from, 25);
        final to = math.min(last, 150);
        // PRD-2.6 D3/D4 can clear a motion after the D2 roll, so the final
        // course under-samples the row's moving chance. Sample the roll
        // directly, and keep the final plans' type / early-gate checks.
        var normal = 0, moving = 0;
        final types = <MotionType, int>{};
        final ctx = DirectorContext.open(711);
        for (var hoop = from; hoop <= to; hoop++) {
          final opening = RunConfig.openingFor(hoop);
          final (lo, hi) = LayoutSampler(
            DirectorTables.prd2,
            math.Random(1),
          ).limits(hoop, ctx, opening);
          for (var seed = 1; seed <= 120; seed++) {
            final sampler = LayoutSampler(
              DirectorTables.prd2,
              math.Random(seed * 1013 + hoop),
            );
            final motion = sampler.motion(hoop, ctx, (lo + hi) / 2, opening);
            normal++;
            if (motion == null) continue;
            moving++;
          }
        }
        // PRD-2.3 §14.4 the moving chance is the `curve_moving` keyframe
        // table (the row's mean over its hoops).
        final t = DirectorTables.prd2;
        var want = 0.0;
        for (var i = from; i <= to; i++) {
          want += t.movingChance(i);
        }
        want /= to - from + 1;
        expect(moving / normal, closeTo(want, .03), reason: 'row ${row.from}');
        for (final vh in plans.keys) {
          for (final run in plans[vh]!) {
            for (final s in run) {
              if (s.index < row.from || s.index > last) continue;
              if (s.motion case final motion?) {
                types[motion.type] = (types[motion.type] ?? 0) + 1;
                var motionRow = LayoutConfig.motionRows.first;
                for (final candidate in LayoutConfig.motionRows) {
                  if (s.index >= candidate.from) motionRow = candidate;
                }
                expect(
                  motionRow.types.keys,
                  contains(motion.type),
                  reason: 'hoop ${s.index}',
                );
              }
            }
          }
        }
        expect(types, isNotEmpty);
      }
      for (final run in plans[711.0]!) {
        for (final s in run) {
          if (s.index < 25) expect(s.motion, isNull, reason: 'hoop ${s.index}');
        }
      }
    });
  });

  group('§3.11 motion rolls', () {
    // A long course from hoop 25 gives every type.
    final specs = <(SlotPlan, double)>[];
    for (final vh in [568.0, 711.0]) {
      for (var seed = 1; seed <= 80; seed++) {
        for (final s in course(seed, start: 25, n: 120, vh: vh)) {
          if (s.motion != null) specs.add((s, vh));
        }
      }
    }

    test('§D2 slides use the motion-row travel and speed ranges', () {
      final seen = <MotionType>{};
      for (final (s, _) in specs) {
        final m = s.motion!;
        var row = LayoutConfig.motionRows.first;
        for (final candidate in LayoutConfig.motionRows) {
          if (s.index >= candidate.from) row = candidate;
        }
        seen.add(m.type);
        switch (m.type) {
          case MotionType.rail:
            expect(m.axisDeg.abs(), lessThanOrEqualTo(25));
          case MotionType.horizontal:
            expect(m.axisDeg, 90);
          case MotionType.diagonal:
            expect(90 - m.axisDeg.abs(), closeTo(38, 1e-9));
          default:
            continue;
        }
        if (row.from == 25) {
          expect(m.halfTravel, inInclusiveRange(30, 45));
          expect(m.speed, inInclusiveRange(22, 28));
        } else {
          expect(m.speed, inInclusiveRange(row.speed.$1, row.speed.$2));
        }
        final period = RailMotion(m).period;
        expect(
          period,
          inInclusiveRange(4 * 10 / row.speed.$2, 4 * 60 / row.speed.$1),
        );
      }
      expect(seen, MotionType.values.toSet());
    });

    test('§3.11 swing ±15° / 1.8 s from a pivot above the top spikes; orbit '
        '≈ 50 × 62 pt at ≤ 39 pt/s; rock ±15° / 3 s', () {
      for (final (s, _) in specs) {
        final m = s.motion!;
        switch (m.type) {
          case MotionType.swing:
            expect(m.amplitudeDeg, 15);
            expect(m.period, 1.8);
            // The pivot is above the top tooth line (and above the strip's
            // band when the rope is long enough).
            expect(s.centreY - m.rope, lessThan(RunConfig.stripHeight));
          case MotionType.orbit:
            expect(m.rx, 25);
            expect(m.ry, lessThanOrEqualTo(31));
            var row = LayoutConfig.motionRows.first;
            for (final candidate in LayoutConfig.motionRows) {
              if (s.index >= candidate.from) row = candidate;
            }
            expect(
              m.omega * math.max(m.rx, m.ry),
              inInclusiveRange(row.speed.$1, row.speed.$2),
            );
          case MotionType.rock:
            expect(m.amplitudeDeg, 15);
            expect(m.period, 3);
          default:
            break;
        }
      }
    });

    test('§3.11 fairness: the ring stays inside the band along its whole '
        'path, and its nearest position keeps the band\'s max jump', () {
      for (var seed = 1; seed <= 60; seed++) {
        for (final vh in [568.0, 711.0]) {
          final band = vh - 2 * RunConfig.stripHeight;
          final run = course(seed, start: 45, n: 80, vh: vh);
          for (var k = 1; k < run.length; k++) {
            final s = run[k];
            final m = s.motion;
            if (m == null) continue;
            final motion = HoopMotion.fromSpec(m);
            final reach = s.opening / 2 + RunConfig.rimRadius;
            var nearest = double.infinity;
            for (var t = 0.0; t < 12; t += 0.05) {
              final o = motion.offsetAt(t);
              final y = s.centreY + o.y;
              // The band rule holds along the path (a swing's rise of
              // ≤ L·(1 − cos 15°) may use the 18 pt margin, never more).
              final slack = m.type == MotionType.swing ? 18.0 : 0.5;
              expect(
                y - reach,
                greaterThan(RunConfig.stripHeight + 18 - slack),
                reason: '$m @$vh',
              );
              expect(
                y + reach,
                lessThan(vh - RunConfig.stripHeight - 18 + slack),
                reason: '$m @$vh',
              );
              nearest = math.min(nearest, (y - run[k - 1].centreY).abs());
            }
            expect(
              nearest,
              lessThanOrEqualTo(
                LayoutConfig.bandFor(s.index).dy.$3 * band + 1e-6,
              ),
            );
          }
        }
      }
    });

    test(
      '§3.0.3 specials, the comet hoop and ride hoops never tilt or move',
      () {
        final all = ElementId.values.toSet();
        for (var seed = 1; seed <= 30; seed++) {
          for (final s in course(seed, n: 150, enabled: all)) {
            if (s.kind != HoopKindId.normal || s.cometHang || s.duringRide) {
              expect(s.tiltDeg, 0);
              expect(s.motion, isNull);
            }
          }
        }
      },
    );
  });
}
