import 'package:flappy_spikes/run/config/pair_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/config/special_hoops_config.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/items/scoring.dart';
import 'package:flappy_spikes/services/leaderboard_limits.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.5 §3.7 WP-BOARD (D6) the leaderboard maximum, derived from the
/// game's own scoring code with the default tuning: a deliberately generous
/// one-hour run in which every slot is a 3-ring Ring Train, every pass is
/// perfect with an unbroken streak and the chick, every slot also pays a
/// pair gift and a maximal coin bonus, plus one puzzle payout.
/// [kLeaderboardMaxScore] (the Play Games / Game Center limit and the
/// client's submit guard) must stay ≥ 1.5 × that bound, so a scoring change
/// that raises it fails here first.
void main() {
  test(
    'PRD-2.5 §3.7 kLeaderboardMaxScore ≥ 1.5 × the one-hour all-perfect bound',
    () {
      // The top cruise speed of the `curve_speed` table (187.5 pt/s).
      var top = 0.0;
      for (var hoop = 0; hoop <= 10000; hoop++) {
        final v = RunConfig.cruise(hoop);
        if (v > top) top = v;
      }
      expect(top, 187.5);
      expect(RunConfig.spacing, 310);

      const seconds = 3600;
      final slots = (seconds * top / RunConfig.spacing).ceil();
      expect(slots, 2178);
      final passes = TrainConfig.rings * slots;
      expect(passes, 6534);

      final chick = TuningValues.current.i('point_chick');
      var points = 0;
      for (var streak = 1; streak <= passes; streak++) {
        points +=
            ScoringFeature.pointsFor(perfect: true, streak: streak) + chick;
      }
      expect(points, 21356380);
      points +=
          slots * PairConfig.score +
          slots * VersusConfig.bonusCap +
          VersusConfig.puzzleBonusCap;
      expect(points, 21542010);

      final required = (points * 1.5).ceil();
      // ignore: avoid_print
      print(
        'leaderboard bound: $points points in one hour; × 1.5 = $required; '
        'kLeaderboardMaxScore = $kLeaderboardMaxScore',
      );
      expect(kLeaderboardMaxScore, greaterThanOrEqualTo(required));
      // The value set in Play Console (Limits) and App Store Connect (Score Range).
      expect(kLeaderboardMaxScore, 32500000);
      // It only cuts absurd values (2^31 − 1, 999 999 999).
      expect(kLeaderboardMaxScore, lessThan(999999999));
    },
  );
}
