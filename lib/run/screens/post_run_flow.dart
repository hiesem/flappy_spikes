import 'dart:async';

import '../../game/flappy_game.dart';
import '../../leaderboard/lb_models.dart';
import '../../leaderboard/lb_config.dart';
import '../../components/leaderboard/results_climb.dart';
import '../run_summary.dart';
import '../config/revive_config.dart';
import 'post_run_screens.dart';

/// The run's end (ARCH §1.11): dying (tumble, WP-1a) → the revive offer if
/// at least [reviveMinHoops] hoops were passed (WP-2d, offered by the game
/// before the run ends) → back to play, or →
/// the bonus when 3 feathers are held (WP-4a) → results (WP-2e
/// `ResultsPage`) → `game.goHome()`.
///
/// Every slot is optional; with none registered (WP-0b) the results come
/// up synchronously, exactly like the 1.0 game over.
class PostRunFlow {
  PostRunFlow(this.game, {Future<LbSubmitRunResult?>? submit})
    : _submit = submit == null ? null : timelyClimbSubmit(submit);

  final Future<LbSubmitRunResult?>? _submit;

  final FlappySpikesGame game;

  /// §3.14 the revive offer needs at least this many hoops passed.
  static int get reviveMinHoops => ReviveConfig.minHoops;

  /// After the run has ended (WP-2d: the revive offer comes *before* the
  /// run ends — `FlappySpikesGame.runDeathSettled` — so persistence and the
  /// versus upload happen once per game). Returns true when the player
  /// revived (never, here; kept for the flow's contract).
  Future<bool> run(RunSummary s) async {
    final bonus = PostRunScreens.bonus;
    if (bonus != null && game.storage.feathers >= 3) {
      await bonus.show(game, s);
    }
    await PostRunScreens.results.show(game, s);
    final page = game.resultsScreen;
    final submit = _submit;
    if (page != null && submit != null) {
      unawaited(
        submit.then((result) {
          final climb = ResultsClimb.fromSubmit(
            result,
            gamesPlayed: game.storage.gamesPlayed,
          );
          if (climb != null &&
              identical(game.resultsScreen, page) &&
              !page.leaving) {
            page.add(climb);
          }
        }),
      );
    }
    return false;
  }
}

/// Starts the deadline at run end, independently of the bonus/results pages.
Future<LbSubmitRunResult?> timelyClimbSubmit(
  Future<LbSubmitRunResult?> submit, {
  Duration? wait,
}) async {
  try {
    return await submit.timeout(
      wait ?? LbConfig.resultsWait,
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}
