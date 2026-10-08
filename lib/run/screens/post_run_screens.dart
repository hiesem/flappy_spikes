import '../../game/flappy_game.dart';
import '../run_summary.dart';
import 'results_screen.dart';

/// What the revive offer ended with (§3.14).
enum ReviveOutcome { revived, declined }

/// The revive offer + phoenix (WP-2d).
abstract class ReviveScreenFactory {
  Future<ReviveOutcome> show(FlappySpikesGame game, RunSummary s);
}

/// The balloon bonus (WP-4a), shown when 3 feathers are held.
abstract class BonusScreenFactory {
  Future<void> show(FlappySpikesGame game, RunSummary s);
}

/// The results page (WP-2e: [ResultsPage]).
abstract class ResultsScreenFactory {
  /// Shows the results; completes when they are up (NEXT → `game.goHome`).
  Future<void> show(FlappySpikesGame game, RunSummary s);
}

/// The registered post-run screens (ARCH §1.11). One region per WP.
abstract final class PostRunScreens {
  // region WP-0b
  static ReviveScreenFactory? revive;
  static BonusScreenFactory? bonus;
  // WP-2e: the §5.10 results page replaced the legacy game-over adapter.
  static ResultsScreenFactory results = const ResultsPage();
  // endregion WP-0b

  // region anchors — append below (WP-2d revive, WP-2e results, WP-4a bonus
  // set these in their own register functions)
  // endregion anchors
}
