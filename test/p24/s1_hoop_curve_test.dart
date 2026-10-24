import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.6 D2 hoop sizes and perfect band.
const _openingD2 = [
  [1, 118], [2, 118], [6, 114], [10, 110], [16, 105.5], [20, 102], //
  [25, 98], [30, 95], [40, 88.5], [50, 83], [60, 79], [75, 75.5],
  [100, 72.5], [125, 71], [150, 70],
];
const _bandD2 = [
  [1, 40], [2, 40], [6, 36], [10, 30], [16, 24], [20, 18], // owner 2026-10-20
  [25, 14.5], [30, 13.9], [35, 13.2], [40, 12.7], [50, 11.8], [60, 11.2],
  [75, 10.6], [100, 10.2], [150, 10],
];

void main() {
  group('PRD-2.4 §1 hoop sizes and perfect band', () {
    test('§D2 the in-app defaults are the 2.6 curves; the Bullseye band is '
        'unchanged (owner decision)', () {
      final defs = {for (final d in kTuningDefaults) d.key: d};
      expect(defs['curve_opening']!.value, _openingD2);
      expect(defs['point_perfect_band']!.value, _bandD2);
      expect(defs['point_bullseye_band']!.value, [
        [1, 12],
        [50, 10],
        [100, 8],
      ]);
      // The values the game reads (offline, before the first fetch).
      final v = TuningValues.defaults();
      expect(v.raw('curve_opening'), _openingD2);
      expect(v.raw('point_perfect_band'), _bandD2);
    });

    test('§D2 openingFor: 118 at hoops 0, 1 and 2; 110 at 10; 98 at 25; '
        '75.5 at 75; 70 from 150', () {
      expect(RunConfig.openingFor(0), 118);
      expect(RunConfig.openingFor(1), 118);
      expect(RunConfig.openingFor(2), 118);
      expect(RunConfig.openingFor(10), closeTo(110, 1e-9));
      expect(RunConfig.openingFor(25), closeTo(98, 1e-9));
      expect(RunConfig.openingFor(75), closeTo(75.5, 1e-9));
      expect(RunConfig.openingFor(100), closeTo(72.5, 1e-9));
      expect(RunConfig.openingFor(150), closeTo(70, 1e-9));
    });

    test('§1.2 the curve is linear between its keys and eases down with no '
        'step (hoop 2 → 150: 118 → 70)', () {
      // Between 40 (88.5) and 50 (83): the midpoint is 85.75.
      expect(RunConfig.openingFor(45), closeTo(85.75, 1e-9));
      // Hoops 75 → 100: 75.5 → 72.5.
      expect(RunConfig.openingFor(87), closeTo(75.5 - 3 * 12 / 25, 1e-9));
      for (var i = 2; i < 150; i++) {
        expect(
          RunConfig.openingFor(i + 1),
          lessThanOrEqualTo(RunConfig.openingFor(i) + 1e-9),
          reason: 'the opening never grows (hoop ${i + 1})',
        );
      }
    });

    // Owner 2026-10-20 (2.5.0 46): hoops 0–20 wider (±40 → ±18).
    test('§D2 perfect band: ±40 at hoops 1–2, ±30 at 10, ±10.6 at 75, ±10 '
        'from 150', () {
      expect(PerfectBandConfig.bandAt(1), closeTo(40, 1e-9));
      expect(PerfectBandConfig.bandAt(2), closeTo(40, 1e-9));
      expect(PerfectBandConfig.bandAt(10), closeTo(30, 1e-9));
      expect(PerfectBandConfig.bandAt(75), closeTo(10.6, 1e-9));
      expect(PerfectBandConfig.bandAt(100), closeTo(10.2, 1e-9));
      expect(PerfectBandConfig.bandAt(200), closeTo(10, 1e-9));
    });

    test('§1.2 the band stays about 30 % of the gap from hoop 25 to 75', () {
      for (final i in [25, 40, 50, 60, 75]) {
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
