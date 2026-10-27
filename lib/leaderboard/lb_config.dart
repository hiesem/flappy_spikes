import '../run/config/tuning_values.dart';

abstract final class LbConfig {
  static const functionsRegion = 'europe-west1';
  static const callTimeout = Duration(seconds: 6);
  static const submitFunction = 'lbSubmitRun';
  static const boardFunction = 'lbGetBoard';
  static const claimFunction = 'lbClaimGift';
  static const batchSize = 10;
  static int get resultsMinGames => tuning.i('lb_results_min_games');
  static Duration get resultsWait =>
      Duration(milliseconds: tuning.i('lb_results_wait_ms'));
  static int get queueCap => tuning.i('lb_queue_cap');
}
