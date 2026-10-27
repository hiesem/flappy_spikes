import '../game/flappy_game.dart';

// region P26-J2
/// Persistent end-of-run progression seam. F1, J9 and LB2 extend this helper
/// rather than the game's state transition.
abstract final class RunEndBookkeeping {
  static Future<int> record(FlappySpikesGame game, int score) {
    final levels = game.menu.levels;
    levels.services = game.services;
    final recorded = levels.recordRun(
      score,
      counts: game.run?.countsForUpload ?? false,
    );
    // Published ranks use this run's score, never the progression index (J9).
    game.achievements.finishRun(
      counts: game.run?.countsForAchievements ?? false,
      score: score,
      day: game.storage.today,
    );
    return recorded;
  }
}
// endregion
