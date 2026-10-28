import '../game/flappy_game.dart';
// region P26-F1
import '../game/storage.dart';
import '../services/game_services.dart';
// endregion

// region P26-J2
/// Persistent end-of-run progression seam. F1, J9 and LB2 extend this helper
/// rather than the game's state transition.
abstract final class RunEndBookkeeping {
  // region P26-F1
  static Future<void> economyDaily(GameStorage storage, GameServices services) async {
    final day = storage.today;
    if (storage.economyDailyDay == day) return;
    await storage.saveEconomyDailyDay(day);
    services.track('economy_daily', {
      'earned': storage.lifetimeCoinsEarned,
      'spent': storage.lifetimeCoinsSpent,
      'bought': storage.lifetimeCoinsBought,
    });
  }
  // endregion

  static Future<int> record(FlappySpikesGame game, int score) {
    // region P26-F1
    economyDaily(game.storage, game.services);
    // endregion
    // region P26-G1b
    final run = game.run;
    if (run != null && run.countsForUpload && game.storage.gamesPlayed >= 4) {
      game.recordStreakRun(runNumber: game.storage.gamesPlayed);
    }
    // endregion
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
