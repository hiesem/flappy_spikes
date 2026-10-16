import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.4 §1 new hoop sizes and perfect band (the v23 curves, live in
/// Remote Config version 23). Test 1 of PRD-2.4 §4.
const _openingV23 = [
  [1, 118], [2, 118], [6, 114], [10, 110.5], [16, 105.5], [20, 102], //
  [25, 98], [30, 94.5], [35, 90.5], [40, 87.5], [50, 81], [60, 76.5],
  [75, 72], [100, 66],
];
const _bandV23 = [
  [1, 18], [2, 18], [6, 17.4], [10, 16.7], [16, 15.8], [20, 15.2], //
  [25, 14.5], [30, 13.9], [35, 13.2], [40, 12.7], [50, 11.6], [60, 10.7],
  [75, 10], [100, 8],
];

void main() {
  group('PRD-2.4 §1 hoop sizes and perfect band', () {
    test('§1.2 the in-app defaults are the v23 curves; the Bullseye band is '
        'unchanged (owner decision)', () {
      final defs = {for (final d in kTuningDefaults) d.key: d};
      expect(defs['curve_opening']!.value, _openingV23);
      expect(defs['point_perfect_band']!.value, _bandV23);
      expect(defs['point_bullseye_band']!.value, [
        [1, 12],
        [50, 10],
        [100, 8],
      ]);
      // The values the game reads (offline, before the first fetch).
      final v = TuningValues.defaults();
      expect(v.raw('curve_opening'), _openingV23);
      expect(v.raw('point_perfect_band'), _bandV23);
    });

    test('§1.2 openingFor: 118 at hoops 0, 1 and 2; 110.5 at 10; 98 at 25; '
        '72 at 75; 66 at 100 and 150', () {
      expect(RunConfig.openingFor(0), 118);
      expect(RunConfig.openingFor(1), 118);
      expect(RunConfig.openingFor(2), 118);
      expect(RunConfig.openingFor(10), closeTo(110.5, 1e-9));
      expect(RunConfig.openingFor(25), closeTo(98, 1e-9));
      expect(RunConfig.openingFor(75), closeTo(72, 1e-9));
      expect(RunConfig.openingFor(100), closeTo(66, 1e-9));
      expect(RunConfig.openingFor(150), closeTo(66, 1e-9));
    });

    test('§1.2 the curve is linear between its keys and eases down with no '
        'step (hoop 2 → 75: 118 → 72)', () {
      // Between 40 (87.5) and 50 (81): the midpoint is 84.25.
      expect(RunConfig.openingFor(45), closeTo(84.25, 1e-9));
      // Hoops 75 → 100 is the 2.3 curve: 72 → 66.
      expect(RunConfig.openingFor(87), closeTo(72 - 6 * 12 / 25, 1e-9));
      for (var i = 2; i < 150; i++) {
        expect(
          RunConfig.openingFor(i + 1),
          lessThanOrEqualTo(RunConfig.openingFor(i) + 1e-9),
          reason: 'the opening never grows (hoop ${i + 1})',
        );
      }
    });

    test('§1.2 perfect band: ±18 at hoops 1–2, ±16.7 at 10, ±10 at 75, ±8 '
        'from 100', () {
      expect(PerfectBandConfig.bandAt(1), closeTo(18, 1e-9));
      expect(PerfectBandConfig.bandAt(2), closeTo(18, 1e-9));
      expect(PerfectBandConfig.bandAt(10), closeTo(16.7, 1e-9));
      expect(PerfectBandConfig.bandAt(75), closeTo(10, 1e-9));
      expect(PerfectBandConfig.bandAt(100), closeTo(8, 1e-9));
      expect(PerfectBandConfig.bandAt(200), closeTo(8, 1e-9));
    });

    test('§1.2 the band stays about 30 % of the gap up to hoop 75', () {
      for (final i in [10, 25, 40, 50, 60, 75]) {
        final ratio = PerfectBandConfig.bandAt(i) * 2 / RunConfig.openingFor(i);
        expect(ratio, inInclusiveRange(0.27, 0.31), reason: "hoop $i");
      }
    });

    test('§1.2 unchanged: the speed curve and the Big Hoops multiplier', () {
      expect(RunConfig.cruise(0), 150);
      expect(RunConfig.cruise(50), 172.5);
      expect(RunConfig.cruise(150), 187.5);
      expect(RunConfig.bigHoopsMult, 1.5);
    });
  });
}
