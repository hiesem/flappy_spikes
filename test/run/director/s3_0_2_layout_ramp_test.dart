import 'dart:math' as math;

import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
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
  for (var k = 0; k < n; k++) {
    final ctx = DirectorContext.open(vh);
    final s = d.nextSlot(ctx);
    d.nextGap(ctx, s);
    out.add(s);
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

void main() {
  const seeds = 400;
  final plans = <double, List<List<SlotPlan>>>{
    for (final vh in [568.0, 711.0])
      vh: [for (var s = 1; s <= seeds; s++) course(s, vh: vh)],
  };

  group('§3.0.2 the ramp as data (LayoutConfig)', () {
    test('§3.0.2 the director tables read the layout rows and motion tables '
        'from LayoutConfig', () {
      const t = DirectorTables.prd2;
      expect(identical(t.bands, LayoutConfig.bands), isTrue);
      expect(identical(t.movingTypes20, LayoutConfig.movingTypes20), isTrue);
      expect(identical(t.movingTypes45, LayoutConfig.movingTypes45), isTrue);
      expect(identical(t.rail, LayoutConfig.rail), isTrue);
      expect(identical(t.swing, LayoutConfig.swing), isTrue);
    });

    test('§3.0.2 rows at 0, 3, 10, 20, 35, 45 with the PRD values', () {
      expect(LayoutConfig.bands.map((b) => b.from), [0, 3, 10, 20, 35, 45]);
      expect(LayoutConfig.bands.map((b) => b.tilt), [0, 0, .30, .50, .60, .78]);
      expect(LayoutConfig.bands.map((b) => b.moving), [0, 0, 0, .06, .15, .40]);
      for (final (i, row) in [
        (0, 0),
        (2, 0),
        (3, 1),
        (9, 1),
        (10, 2),
        (19, 2),
        (20, 3),
        (34, 3),
        (35, 4),
        (44, 4),
        (45, 5),
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
              final f = (s.centreY - RunConfig.stripHeight) / band;
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
          // The band rule may cut the range at 568 (opening/2 + 25 pt).
          final m = (RunConfig.openingFor(row.from) / 2 + 25) / band;
          expect(
            lo,
            lessThan(math.max(row.centre.$1, m) + 0.03),
            reason: 'row ${row.from} @$vh',
          );
          expect(
            hi,
            greaterThan(math.min(row.centre.$2, 1 - m) - 0.03),
            reason: 'row ${row.from} @$vh',
          );
        }
      }
    });

    test('§3.0.2 |Δy| follows the row\'s median / p90 / max pieces', () {
      for (final (row, last) in rows) {
        final dys = <double>[];
        for (final vh in plans.keys) {
          final band = vh - 2 * RunConfig.stripHeight;
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

    test('§3.10 tilt share and step weights per row; none before 10; 45° '
        'only from 35', () {
      for (final (row, last) in rows) {
        var normal = 0, tilted = 0, swing = 0;
        final steps = <int, int>{};
        for (final vh in plans.keys) {
          for (final run in plans[vh]!) {
            for (final s in run) {
              if (s.index < row.from || s.index > last) continue;
              // PRD-2.2 §19.2 indices 4–9 draw the early pool instead (its
              // angled ring; tested in test/p22/s19_random_opening_test).
              if (DirectorTables.prd2.earlyPool!.covers(s.index)) continue;
              normal++;
              if (s.motion?.type == MotionType.swing) {
                swing++;
                expect(
                  s.tiltDeg,
                  0,
                  reason: 'a swing hangs in line with its rope',
                );
              }
              if (s.tiltDeg != 0) {
                tilted++;
                steps[s.tiltDeg.round()] = (steps[s.tiltDeg.round()] ?? 0) + 1;
              }
            }
          }
        }
        // Swings are rolled after the tilt and force it upright.
        final want = row.tilt * (1 - swing / normal);
        expect(tilted / normal, closeTo(want, .03), reason: 'row ${row.from}');
        if (row.tilt == 0) continue;
        final total = row.tiltWeights.values.reduce((a, b) => a + b);
        for (final e in row.tiltWeights.entries) {
          expect(
            (steps[e.key] ?? 0) / tilted,
            closeTo(e.value / total, .04),
            reason: 'row ${row.from} step ${e.key}',
          );
        }
        expect(
          steps.keys.toSet().difference(row.tiltWeights.keys.toSet()),
          isEmpty,
        );
        if (row.from < 35) expect(steps.containsKey(45), isFalse);
      }
    });

    test('§3.11 moving share and type weights per row; none before 20', () {
      for (final (row, last) in rows) {
        var normal = 0, moving = 0;
        final types = <MotionType, int>{};
        for (final vh in plans.keys) {
          for (final run in plans[vh]!) {
            for (final s in run) {
              if (s.index < row.from || s.index > last) continue;
              normal++;
              final m = s.motion;
              if (m == null) continue;
              moving++;
              types[m.type] = (types[m.type] ?? 0) + 1;
            }
          }
        }
        expect(
          moving / normal,
          closeTo(row.moving, .025),
          reason: 'row ${row.from}',
        );
        if (row.moving == 0) continue;
        final table = row.from >= LayoutConfig.allMotionTypesFrom
            ? LayoutConfig.movingTypes45
            : LayoutConfig.movingTypes20;
        final total = table.values.reduce((a, b) => a + b);
        expect(types.keys.toSet().difference(table.keys.toSet()), isEmpty);
        for (final e in table.entries) {
          expect(
            (types[e.key] ?? 0) / moving,
            closeTo(e.value / total, .06),
            reason: 'row ${row.from} ${e.key}',
          );
        }
      }
    });
  });

  group('§3.11 motion rolls', () {
    // A long course from hoop 45 gives every type.
    final specs = <(SlotPlan, double)>[];
    for (final vh in [568.0, 711.0]) {
      for (var seed = 1; seed <= 80; seed++) {
        for (final s in course(seed, start: 45, n: 80, vh: vh)) {
          if (s.motion != null) specs.add((s, vh));
        }
      }
    }

    test('§3.11 slides: rail ≤ ±25° off vertical, horizontal 90°, diagonal '
        '±38° off horizontal; ±40–60 pt (less where the band is short); '
        '30–39 pt/s', () {
      final seen = <MotionType>{};
      for (final (s, _) in specs) {
        final m = s.motion!;
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
        expect(m.halfTravel, inInclusiveRange(RunConfig.railMinHalfTravel, 60));
        expect(m.speed, inInclusiveRange(30, 39));
        final period = RailMotion(m).period;
        expect(period, inInclusiveRange(4 * 10 / 39, 4 * 60 / 30));
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
            expect(m.omega * math.max(m.rx, m.ry), lessThanOrEqualTo(39));
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
