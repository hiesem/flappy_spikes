/// GA4 buckets for the analytics events (PRD-2.6 WP-A2).
///
/// GA4 has no median aggregation, so the run events send a bucket string
/// instead of an exact value where a distribution is needed. The strings are
/// part of the dashboard contract; keep their spelling and order.
abstract final class AnalyticsBuckets {
  /// Hoop-count buckets (`hb`).
  static const List<String> hoops = [
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
  ];

  /// Games-played buckets (`gb`).
  static const List<String> games = [
    '1',
    '2',
    '3',
    '4-5',
    '6-9',
    '10-19',
    '20-49',
    '50+',
  ];

  /// The `hb` bucket for [hoops]. Negative counts (never sent by the run)
  /// fall into the first bucket.
  static String hoopBucket(int hoops) {
    if (hoops < 5) return AnalyticsBuckets.hoops[0];
    if (hoops < 10) return AnalyticsBuckets.hoops[1];
    if (hoops < 15) return AnalyticsBuckets.hoops[2];
    if (hoops < 20) return AnalyticsBuckets.hoops[3];
    if (hoops < 30) return AnalyticsBuckets.hoops[4];
    if (hoops < 40) return AnalyticsBuckets.hoops[5];
    if (hoops < 60) return AnalyticsBuckets.hoops[6];
    if (hoops < 80) return AnalyticsBuckets.hoops[7];
    if (hoops < 100) return AnalyticsBuckets.hoops[8];
    if (hoops < 150) return AnalyticsBuckets.hoops[9];
    if (hoops < 200) return AnalyticsBuckets.hoops[10];
    return AnalyticsBuckets.hoops[11];
  }

  /// The `gb` bucket for a 1-based game number. A zero / negative number
  /// (only a malformed caller) falls into the first bucket.
  static String gamesBucket(int games) {
    if (games <= 1) return AnalyticsBuckets.games[0];
    if (games == 2) return AnalyticsBuckets.games[1];
    if (games == 3) return AnalyticsBuckets.games[2];
    if (games <= 5) return AnalyticsBuckets.games[3];
    if (games <= 9) return AnalyticsBuckets.games[4];
    if (games <= 19) return AnalyticsBuckets.games[5];
    if (games <= 49) return AnalyticsBuckets.games[6];
    return AnalyticsBuckets.games[7];
  }
}
