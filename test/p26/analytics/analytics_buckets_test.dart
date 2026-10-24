import 'package:flappy_spikes/services/analytics_buckets.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.6 WP-A2: GA4 has no medians, so `hb` / `gb` send these exact
/// bucket strings. Every boundary is part of the dashboard contract.
void main() {
  test('hoop buckets: 00-04 … 200+ at every boundary', () {
    expect(AnalyticsBuckets.hoops, [
      '00-04',
      '05-09',
      '10-14',
      '15-19',
      '20-29',
      '30-39',
      '40-59',
      '60-79',
      '80-99',
      '100-149',
      '150-199',
      '200+',
    ]);
    const cases = {
      0: '00-04',
      4: '00-04',
      5: '05-09',
      9: '05-09',
      10: '10-14',
      14: '10-14',
      15: '15-19',
      19: '15-19',
      20: '20-29',
      29: '20-29',
      30: '30-39',
      39: '30-39',
      40: '40-59',
      59: '40-59',
      60: '60-79',
      79: '60-79',
      80: '80-99',
      99: '80-99',
      100: '100-149',
      149: '100-149',
      150: '150-199',
      199: '150-199',
      200: '200+',
      1000: '200+',
    };
    for (final MapEntry(key: hoops, value: bucket) in cases.entries) {
      expect(AnalyticsBuckets.hoopBucket(hoops), bucket, reason: '$hoops');
    }
  });

  test('games buckets: 1 … 50+ at every boundary', () {
    expect(AnalyticsBuckets.games, [
      '1',
      '2',
      '3',
      '4-5',
      '6-9',
      '10-19',
      '20-49',
      '50+',
    ]);
    const cases = {
      1: '1',
      2: '2',
      3: '3',
      4: '4-5',
      5: '4-5',
      6: '6-9',
      9: '6-9',
      10: '10-19',
      19: '10-19',
      20: '20-49',
      49: '20-49',
      50: '50+',
      1000: '50+',
    };
    for (final MapEntry(key: games, value: bucket) in cases.entries) {
      expect(AnalyticsBuckets.gamesBucket(games), bucket, reason: '$games');
    }
  });
}
