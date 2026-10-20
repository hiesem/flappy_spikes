import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-10-20 (2.5.0 46): the perfect band grows with Big Hoops (the
/// hoop's gap over the curve's gap, clamped to 1 … ×1.5).
void main() {
  bool perfect(int i, double offset, double? opening) =>
      PerfectBandConfig.isPerfect(
        touched: false,
        hoopIndex: i,
        offset: offset,
        opening: opening,
      );

  test('plain hoop: the curve band', () {
    final o = RunConfig.openingFor(10);
    expect(PerfectBandConfig.growthFor(10, o), 1);
    expect(perfect(10, 30, o), isTrue);
    expect(perfect(10, 31, o), isFalse);
  });

  test('Big Hoops ×1.5: band ×1.5', () {
    final o = RunConfig.openingFor(20) * RunConfig.bigHoopsMult;
    expect(PerfectBandConfig.growthFor(20, o), 1.5);
    expect(perfect(20, 27, o), isTrue);
    expect(perfect(20, 27.5, o), isFalse);
  });

  test('easing Big Hoops grows the band by the same factor', () {
    final o = RunConfig.openingFor(30) * 1.2;
    expect(PerfectBandConfig.growthFor(30, o), closeTo(1.2, 1e-9));
  });

  test('a gap capped smaller keeps the plain band; never above ×1.5', () {
    expect(PerfectBandConfig.growthFor(5, RunConfig.openingFor(5) * 0.8), 1);
    expect(PerfectBandConfig.growthFor(5, RunConfig.openingFor(5) * 3), 1.5);
    expect(PerfectBandConfig.growthFor(5, null), 1);
  });

  test('a rim touch is never perfect', () {
    expect(
      PerfectBandConfig.isPerfect(
        touched: true,
        hoopIndex: 1,
        offset: 0,
        opening: 177,
      ),
      isFalse,
    );
  });
}
