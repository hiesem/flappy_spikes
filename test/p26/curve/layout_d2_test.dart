import 'dart:math' as math;

import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flutter_test/flutter_test.dart';

const _plain = {
  ElementId.normalHoop,
  ElementId.angledRing,
  ElementId.movingRing,
};

typedef MotionRow = ({
  int from,
  Map<MotionType, int> types,
  (double, double) halfTravel,
  (double, double) speed,
});

List<SlotPlan> _course(
  int seed,
  double viewHeight, {
  int count = 260,
  bool squeeze = false,
}) {
  final director = RunDirector(
    seed: seed,
    enabled: _plain,
    met: ElementId.values.toSet(),
  );
  final plans = <SlotPlan>[];
  double? previousY;
  for (var i = 0; i < count; i++) {
    final context = DirectorContext.open(
      viewHeight,
      squeezeWindow: squeeze,
      squeezeInset: squeeze ? 54 : 0,
      prevCentreY: previousY,
    );
    final plan = director.nextSlot(context);
    director.nextGap(context, plan);
    plans.add(plan);
    previousY = plan.centreY;
  }
  return plans;
}

MotionRow _motionRowFor(int hoopIndex) {
  var row = LayoutConfig.motionRows.first;
  for (final candidate in LayoutConfig.motionRows) {
    if (hoopIndex >= candidate.from) row = candidate;
  }
  return row;
}

double _motionPeriod(MotionSpec spec) {
  final amplitude = spec.amplitudeDeg * math.pi / 180;
  return switch (spec.type) {
    MotionType.rail || MotionType.horizontal || MotionType.diagonal =>
      spec.speed <= 0 ? 1 : 4 * spec.halfTravel / spec.speed,
    MotionType.swing =>
      spec.speed > 0 && spec.rope > 0 && amplitude > 0
          ? 2 * math.pi * spec.rope * amplitude / spec.speed
          : (spec.period > 0 ? spec.period : 1),
    MotionType.orbit => spec.omega <= 0 ? 1 : 2 * math.pi / spec.omega,
    MotionType.rock => spec.period > 0 ? spec.period : 1,
  };
}

final class _DrawQueue implements math.Random {
  _DrawQueue(this.values);

  final List<double> values;
  var _next = 0;

  @override
  double nextDouble() => values[_next++];

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}

void main() {
  test('D2 data rows use point-based Δy and magnitude tilts', () {
    expect(LayoutConfig.bands.map((row) => row.from), [0, 3, 20, 40, 65, 100]);
    expect(LayoutConfig.dyRefBand, 540);
    expect(LayoutConfig.hardHoopDyFactor, 0.85);
    expect(LayoutConfig.tiltRows, {
      10: {10: 6, 15: 4},
      50: {10: 30, 15: 30, 20: 20, 30: 20},
      60: {10: 20, 15: 20, 20: 15, 30: 30, 45: 15},
      100: {10: 15, 15: 15, 20: 15, 30: 30, 45: 25},
    });
    expect(TuningValues.current.raw('tilt_rows'), {
      '10_10': 6,
      '10_15': 4,
      '50_10': 30,
      '50_15': 30,
      '50_20': 20,
      '50_30': 20,
      '60_10': 20,
      '60_15': 20,
      '60_20': 15,
      '60_30': 30,
      '60_45': 15,
      '100_10': 15,
      '100_15': 15,
      '100_20': 15,
      '100_30': 30,
      '100_45': 25,
    });
  });

  test('D2 PRD rows keep their exact centre and Δy fractions', () {
    const rows = <int, ((double, double), (double, double, double))>{
      0: ((.45, .55), (.03, .06, .07)),
      3: ((.33, .67), (.11, .27, .35)),
      20: ((.27, .70), (.12, .31, .38)),
      40: ((.24, .73), (.14, .33, .42)),
      65: ((.20, .76), (.15, .35, .46)),
      100: ((.16, .78), (.15, .37, .50)),
    };
    final bands = LayoutConfig.bands;
    expect(bands.map((row) => row.from), rows.keys);
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      final expected = rows[band.from]!;
      expect(band.centre, expected.$1, reason: 'centre row ${band.from}');
      expect(band.dy, expected.$2, reason: 'Δy row ${band.from}');
    }
    // PRD-2.6 D2 has no separate hoop-10 row: hoops 10–19 use the 3–19 row.
    expect(LayoutConfig.bandFor(10), same(LayoutConfig.bandFor(3)));
    expect(LayoutConfig.bandFor(10).centre, (.33, .67));
  });

  test('D2 centre limits use the full band above the design height', () {
    const viewHeight = 730.0;
    const band = viewHeight - 2 * RunConfig.stripHeight;
    const mid = viewHeight / 2;
    final ctx = DirectorContext.open(viewHeight);
    final sampler = LayoutSampler(DirectorTables.prd2, math.Random(1));
    final (lo, hi) = sampler.limits(100, ctx, RunConfig.openingFor(100));

    expect(lo, closeTo(mid + (.16 - .5) * band, 1e-9));
    expect(hi, closeTo(mid + (.78 - .5) * band, 1e-9));
  });

  test('D2 tilt magnitudes follow the row weights', () {
    final cases = [10, 55, 80, 150];
    for (final hoop in cases) {
      final counts = <int, int>{};
      for (var seed = 0; seed < 4000; seed++) {
        final sampler = LayoutSampler(DirectorTables.prd2, math.Random(seed));
        final tilt = sampler.tilt(hoop, force: true).abs().round();
        counts[tilt] = (counts[tilt] ?? 0) + 1;
      }
      var rowFrom = 10;
      for (final from in LayoutConfig.tiltRows.keys) {
        if (hoop >= from && from >= rowFrom) rowFrom = from;
      }
      final row = LayoutConfig.tiltRows[rowFrom]!;
      final total = row.values.reduce((a, b) => a + b);
      expect(counts.keys.toSet(), row.keys.toSet(), reason: 'hoop $hoop');
      for (final entry in row.entries) {
        expect(
          (counts[entry.key] ?? 0) / 4000,
          closeTo(entry.value / total, .025),
          reason: 'hoop $hoop tilt ${entry.key}',
        );
      }
    }
  });

  test('D2 a large tilt clamped by a small approach keeps its own sign', () {
    final signs = <int>{};
    const zeroApproach = 0.0;
    const fullLimit = 45.0;
    for (var seed = 0; seed < 200; seed++) {
      final sampler = LayoutSampler(DirectorTables.prd2, math.Random(seed));
      final double tilt = sampler.tilt(60, force: true);
      if (tilt.abs() >= 20) {
        signs.add(
          sampler.alignedTilt(tilt, zeroApproach, fullLimit).sign.toInt(),
        );
      }
    }
    expect(signs, {-1, 1});
  });

  test('D2 strong tilts align, obey Δy, and 45° rings get +6 pt', () {
    var saw45 = false;
    for (var seed = 1; seed <= 120; seed++) {
      final plans = _course(seed, 711);
      for (var i = 1; i < plans.length; i++) {
        final plan = plans[i];
        if (plan.tiltDeg.abs() < 20) continue;
        final dy = plan.centreY - plans[i - 1].centreY;
        expect(dy.abs(), greaterThanOrEqualTo(40 - 1e-9));
        expect(plan.tiltDeg.sign, dy.sign);
        if (plan.motion != null && plan.index < 150) {
          expect(plan.tiltDeg.abs(), lessThanOrEqualTo(15));
        }
        if (plan.tiltDeg.abs() == 45) {
          saw45 = true;
          expect(
            plan.opening,
            closeTo(RunConfig.openingFor(plan.index) + 6, 1e-9),
          );
        }
      }
    }
    expect(saw45, isTrue);
  });

  test('D2 tilt is limited in motion and early squeeze slots', () {
    for (final squeeze in [false, true]) {
      for (var seed = 1; seed <= 80; seed++) {
        final plans = _course(seed, 568, squeeze: squeeze);
        for (final plan in plans) {
          if (plan.index >= 150) continue;
          if (plan.motion != null || squeeze) {
            expect(
              plan.tiltDeg.abs(),
              lessThanOrEqualTo(15),
              reason: 'hoop ${plan.index} squeeze=$squeeze',
            );
          }
        }
      }
    }
  });

  test('D2 Δy is point-based and reduced after hard hoops', () {
    final shortPlans = [
      for (var seed = 1; seed <= 100; seed++) _course(seed, 568),
    ];
    final tallPlans = [
      for (var seed = 1; seed <= 100; seed++) _course(seed, 711),
    ];

    for (final plans in shortPlans) {
      for (var i = 1; i < plans.length; i++) {
        expect(
          (plans[i].centreY - plans[i - 1].centreY).abs(),
          lessThanOrEqualTo(240 + 1e-9),
        );
      }
    }
    for (final plans in tallPlans) {
      for (var i = 1; i < plans.length; i++) {
        final dy = (plans[i].centreY - plans[i - 1].centreY).abs();
        final previous = plans[i - 1];
        final hard = previous.motion != null || previous.tiltDeg.abs() >= 30;
        final limit = hard ? 270 * 0.85 : 270;
        expect(dy, lessThanOrEqualTo(limit + 1e-9));
      }
    }
    // A taller view keeps the point-space Δy cap even though the centre rows
    // (issue #97 / D2) use the full band as their denominator.
    for (var seed = 1; seed <= 100; seed++) {
      final plans = _course(seed, 730);
      for (var i = 1; i < plans.length; i++) {
        final dy = (plans[i].centreY - plans[i - 1].centreY).abs();
        final previous = plans[i - 1];
        final hard = previous.motion != null || previous.tiltDeg.abs() >= 30;
        expect(dy, lessThanOrEqualTo((hard ? 270 * 0.85 : 270) + 1e-9));
      }
    }

    final ctx = DirectorContext.open(711);
    final sampler = LayoutSampler(DirectorTables.prd2, math.Random(1));
    expect(
      sampler.maxDy(100, ctx, hardFollowUp: true),
      closeTo(270 * 0.85, 1e-9),
    );
  });

  test('D2 a hard follow-up clamps only draws above 0.85 × the row max', () {
    double centre({required double u, required bool hard}) {
      final sampler =
          LayoutSampler(
              DirectorTables.prd2,
              _DrawQueue([u, .9]), // Δy draw, then no direction flip.
            )
            ..lastY = 200
            ..lastSign = 1;
      if (hard) {
        sampler.noteModifiers(motion: const MotionSpec(type: MotionType.rail));
      }
      return sampler.nextCentre(
        100,
        DirectorContext.open(711),
        RunConfig.openingFor(100),
      );
    }

    // The normal draw is unchanged: 0.075 × 540 = 40.5 pt.
    expect(centre(u: .25, hard: false), closeTo(240.5, 1e-9));
    expect(centre(u: .25, hard: true), closeTo(240.5, 1e-9));

    // The normal draw is 241.92 pt; after a hard hoop its magnitude is
    // clamped to 0.85 × (0.50 × 540) = 229.5 pt.
    expect(centre(u: .96, hard: false), closeTo(441.92, 1e-9));
    expect(centre(u: .96, hard: true), closeTo(429.5, 1e-9));
  });

  test('D2 motion rows own their type, travel, and speed ranges', () {
    final counts = <int, Map<MotionType, int>>{};
    for (var seed = 1; seed <= 160; seed++) {
      for (final plan in _course(seed, 711)) {
        final motion = plan.motion;
        if (motion == null) continue;
        final row = _motionRowFor(plan.index);
        counts.putIfAbsent(row.from, () => {})[motion.type] =
            (counts[row.from]?[motion.type] ?? 0) + 1;
        if (motion.type
            case MotionType.rail ||
                MotionType.horizontal ||
                MotionType.diagonal) {
          if (row.from == 25) {
            expect(motion.halfTravel, inInclusiveRange(30, 45));
          }
          if (motion.type
              case MotionType.rail ||
                  MotionType.horizontal ||
                  MotionType.diagonal) {
            expect(motion.speed, inInclusiveRange(row.speed.$1, row.speed.$2));
          }
        }
      }
    }
    expect(counts.keys, {25, 35, 70, 90, 120});
    expect(counts[25]!.keys, {MotionType.rail});
    expect(counts[35]!.keys, {MotionType.rail, MotionType.swing});
    expect(counts[70]!.keys, {
      MotionType.rail,
      MotionType.swing,
      MotionType.horizontal,
      MotionType.diagonal,
    });
    expect(counts[90]!.keys, MotionType.values.toSet());
    expect(counts[120]!.keys, MotionType.values.toSet());
  });

  test('D2 a moving ring\'s rendered angle stays under 15° / 30°', () {
    final seenBefore = <MotionType>{};
    final seenAfter = <MotionType>{};
    for (var seed = 1; seed <= 50; seed++) {
      for (final plan in _course(seed, 711)) {
        final spec = plan.motion;
        if (spec == null) continue;
        (plan.index >= 150 ? seenAfter : seenBefore).add(spec.type);
        final cap = plan.index >= 150 ? 30.0 : 15.0;
        final motion = HoopMotion.fromSpec(spec);
        final period = _motionPeriod(spec);
        for (var n = 0; n <= 1000; n++) {
          motion.poseAt(period * n / 1000);
          final rendered = plan.tiltDeg * math.pi / 180 + motion.angleOffset;
          expect(
            rendered.abs() * 180 / math.pi,
            lessThanOrEqualTo(cap + 1e-6),
            reason: '$spec at hoop ${plan.index}',
          );
        }
      }
    }
    expect(seenBefore, containsAll([MotionType.swing, MotionType.orbit]));
    expect(seenAfter, containsAll([MotionType.swing, MotionType.orbit]));
  });

  test('D2 swing speed comes from its motion row and the rope geometry', () {
    var swings = 0;
    for (var seed = 1; seed <= 80; seed++) {
      for (final plan in _course(seed, 711)) {
        final spec = plan.motion;
        if (spec?.type != MotionType.swing) continue;
        swings++;
        final row = _motionRowFor(plan.index);
        expect(spec!.speed, inInclusiveRange(row.speed.$1, row.speed.$2));
        expect(spec.speed, lessThanOrEqualTo(42));

        final motion = HoopMotion.fromSpec(spec);
        final period = _motionPeriod(spec);
        var peak = 0.0;
        for (var n = 0; n <= 2000; n++) {
          motion.poseAt(period * n / 2000);
          peak = math.max(peak, motion.velocity.length);
        }
        expect(peak, closeTo(spec.speed, .01));
        expect(peak, inInclusiveRange(row.speed.$1, row.speed.$2));
        expect(peak, lessThanOrEqualTo(42));
      }
    }
    expect(swings, greaterThan(0));
  });

  test('D2 same seed and context sequence produce the same plans', () {
    expect(_course(7, 711), _course(7, 711));
  });
}
