import 'dart:math' as math;

import 'package:flappy_spikes/run/config/layout_config.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/director/layout_sampler.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
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

void main() {
  test('D2 data rows use point-based Δy and magnitude tilts', () {
    expect(LayoutConfig.bands.map((row) => row.from), [
      0,
      3,
      10,
      20,
      40,
      65,
      100,
    ]);
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

  test('D2 Δy is point-based, height-capped, reduced after hard hoops, and '
      'stable above the cap', () {
    final shortPlans = [
      for (var seed = 1; seed <= 100; seed++) _course(seed, 568),
    ];
    final tallPlans = [
      for (var seed = 1; seed <= 100; seed++) _course(seed, 711),
    ];
    final widestPlans = [
      for (var seed = 1; seed <= 100; seed++) _course(seed, 730),
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
    for (var run = 0; run < tallPlans.length; run++) {
      for (var i = 1; i < tallPlans[run].length; i++) {
        final tall = tallPlans[run][i].centreY - tallPlans[run][i - 1].centreY;
        final wide =
            widestPlans[run][i].centreY - widestPlans[run][i - 1].centreY;
        expect(tall, closeTo(wide, 1e-9), reason: 'run ${run + 1}, hoop $i');
      }
    }

    final ctx = DirectorContext.open(711);
    final sampler = LayoutSampler(DirectorTables.prd2, math.Random(1));
    expect(
      sampler.maxDy(100, ctx, hardFollowUp: true),
      closeTo(270 * 0.85, 1e-9),
    );
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

  test('D2 same seed and context sequence produce the same plans', () {
    expect(_course(7, 711), _course(7, 711));
  });
}
