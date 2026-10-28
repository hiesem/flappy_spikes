import '../game/flappy_game.dart';
// region P26-G1b
import '../progression/missions.dart';
import '../run/elements.dart';
import '../run/config/tuning_values.dart';
import '../menu/wallet.dart';
import '../menu/home_mode.dart';
import '../versus/diagnostics.dart';
// endregion
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

  // region P26-G1b
  static Missions currentMissions(GameStorage storage) => Missions.fromRecords(
    day: storage.missionDay, tier: storage.missionTier,
    rerollDay: storage.missionRerollDay, records: storage.missions,
  );

  static Future<void> prepareMissions(FlappySpikesGame game) {
    final storage = game.storage;
    if (storage.gamesPlayed < 3) return Future.value();
    final previous = currentMissions(storage);
    final rolled = previous.roll(
      today: storage.today, gamesPlayed: storage.gamesPlayed,
      eligibility: MissionEligibility(
        bestHoops: storage.bestHoops,
        metElements: {for (final id in storage.metElements) ?ElementId.fromStorageId(id)},
        online: game.versus.ready &&
          (game.versus.holdsOpponent ||
           game.versus.lastSearch.state == VersusSearchState.found ||
           game.versus.lastSearch.reason == VersusSoloReason.noRival),
        lastVersusHadRival: storage.lastVersusHadRival,
      ),
    );
    if (identical(previous, rolled)) return Future.value();
    final writes = <Future<void>>[
      storage.saveMissions(rolled.toRecords()),
      storage.saveMissionTier(rolled.tier),
      storage.saveMissionRerollDay(rolled.rerollDay),
      storage.saveMissionDay(rolled.day),
    ];
    for (final mission in rolled.missions) {
      game.services.track('mission_assigned', {'mission': mission.template.id, 'tier': rolled.tier});
    }
    return Future.wait(writes);
  }

  /// Capture and journal before returning to the game loop. All public state
  /// is updated synchronously; only the durable writes continue in the future.
  static Future<void> recordMissions(FlappySpikesGame game) {
    final storage = game.storage;
    final run = game.run;
    final stats = game.runStats;
    if (run == null || stats == null || !run.countsForUpload) return Future.value();
    final before = storage.gamesPlayed - 1;
    final rival = game.homeMode == HomeMode.versus;
    if (before < 3) {
      return rival ? storage.saveLastVersusHadRival(run.setup.opponent != null) : Future.value();
    }
    stats.captureOpenedSwitches();
    final board = currentMissions(storage);
    final rolled = board.roll(
      today: storage.today, gamesPlayed: before,
      eligibility: MissionEligibility(
        bestHoops: stats.missionBestAtStart,
        metElements: {for (final id in run.state.metElements) id},
        online: stats.missionOnlineAtStart,
        lastVersusHadRival: stats.missionRivalAtStart,
      ),
    );
    final advanced = rolled.advance(stats.missionCounts(before));
    final claim = advanced.claimCoins(rewards: TuningValues.current.ints('mission_rewards'));
    final journal = <String, Object?>{
      'day': claim.state.day, 'tier': claim.state.tier,
      'rerollDay': claim.state.rerollDay, 'missions': claim.state.toRecords(),
      'balanceBefore': storage.coins, 'earnedBefore': storage.lifetimeCoinsEarned,
      'amount': claim.coins, 'applied': false,
    };
    final firstWrite = storage.saveMissionJournal(journal);
    // No asynchronous boundary separates the journal and memory credit.
    // The applied record also carries a recovery target if the wallet write
    // is interrupted, while a false record is recovered by adding the amount.
    final applied = {...journal, 'applied': true};
    final appliedWrite = storage.saveMissionJournal(applied);
    final activeJournal = storage.missionJournal;
    final writes = <Future<void>>[
      if (rival) storage.saveLastVersusHadRival(run.setup.opponent != null),
      storage.saveMissions(claim.state.toRecords()),
      storage.saveMissionTier(claim.state.tier),
      storage.saveMissionRerollDay(claim.state.rerollDay),
      storage.saveMissionDay(claim.state.day),
      if (claim.coins > 0) game.menu.wallet.add(claim.coins, CoinSource.mission),
    ];
    if (!identical(rolled, board)) {
      for (final m in rolled.missions) {
        game.services.track('mission_assigned', {'mission': m.template.id, 'tier': rolled.tier});
      }
    }
    for (final m in claim.completed) {
      game.services.track('mission_complete', {'mission': m.id});
    }
    if (!rolled.allDone && advanced.allDone) game.services.track('missions_all_done');
    return Future.wait([firstWrite, appliedWrite, ...writes]).then((_) async {
      if (identical(storage.missionJournal, activeJournal)) {
        await storage.saveMissionJournal(const {});
      }
    });
  }
  // endregion

  static Future<int> record(FlappySpikesGame game, int score) {
    // region P26-F1
    economyDaily(game.storage, game.services);
    // endregion
    // region P26-G1b
    final run = game.run;
    if (run != null && run.countsForUpload) {
      if (game.storage.gamesPlayed >= 4) {
        game.recordStreakRun(runNumber: game.storage.gamesPlayed);
      }
      game.missionSettlement = recordMissions(game);
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
