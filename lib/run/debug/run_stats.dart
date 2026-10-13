import '../../menu/wallet.dart';
import '../elements.dart';
import '../run_controller.dart';
import '../run_events.dart';

/// Owner 2026-10-14 (2.3.0 (18)) gameplay tuning: what one run produced —
/// passes, coins (by source), points, special hoops, gap items and rides.
/// Shown live on the debug TUNING page; the bot report
/// (`test/tools/fun_budget_test.dart`) uses the same counts.
class RunStats {
  RunStats(RunController run) {
    run.events.onAny(_on);
  }

  int passes = 0;
  int perfects = 0;
  int coins = 0;
  int points = 0;
  int specials = 0;
  int items = 0;
  int rides = 0;
  final Map<CoinSource, int> coinsBy = {};

  void _on(RunEvent e) {
    switch (e) {
      case HoopPassed(:final duringRide, :final perfect):
        if (!duringRide) {
          passes++;
          if (perfect) perfects++;
        }
      case CoinsEarned(:final amount, :final source):
        coins += amount;
        coinsBy[source] = (coinsBy[source] ?? 0) + amount;
      case ScoreChanged(:final oldScore, :final newScore):
        points += newScore - oldScore;
      case ElementSpawned(:final element, :final onScreen) when onScreen:
        if (element.kind == ElementKind.slot &&
            element != ElementId.normalHoop) {
          specials++;
        } else if (element.kind == ElementKind.gap &&
            element != ElementId.piggyCoins &&
            element != ElementId.fireflySwarm) {
          items++;
        }
      case RideStarted():
        rides++;
      default:
        break;
    }
  }

  double _per(int n) => n / (passes < 1 ? 1 : passes);

  /// One line: hoops, coins and points per hoop.
  String get economyLine =>
      'Run: $passes hoops · $coins c (${_per(coins).toStringAsFixed(2)}/h)'
      ' · $points pts (${_per(points).toStringAsFixed(2)}/h)';

  /// One line: specials, items and rides, per 10 hoops.
  String get funLine =>
      'Specials $specials · items $items · rides $rides'
      ' (${(_per(specials + items) * 10).toStringAsFixed(1)}/10h)';
}
