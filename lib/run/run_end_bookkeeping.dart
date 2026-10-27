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
    // Commit staged achievement unlocks only for counting runs. J9 replaces
    // the legacy rank input here with the finished run's score.
    game.achievements.finishRun(
      counts: game.run?.countsForAchievements ?? false,
      level: levels.level,
      day: game.storage.today,
    );
    return recorded;
  }
}
// endregion
