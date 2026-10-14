import 'dart:async';
import 'dart:math' as math;

import '../game/storage.dart';
import '../levels/levels.dart';
import '../run/director/plans.dart';
import '../services/game_services.dart';
import 'achievement_catalog.dart';

/// PRD-2.3.1 §12.3 the achievement tracker, owned by the game
/// (`game.achievements`): the local truth (storage keys `ach*`), the
/// counters, the unlock toasts' queue and the platform sync (§12.4).
///
/// It never decides whether a run counts: the callers check the run's
/// `countsForAchievements` (§12.2) before calling the run rules; the shop
/// always counts. Achievements pay nothing (§12, "No rewards").
class AchievementTracker {
  AchievementTracker({required this.storage, required this.services}) {
    services.onAchievementPlayer = () => unawaited(syncAll());
  }

  final GameStorage storage;
  final GameServices services;

  /// Tests: runs with a debug / test start (the harness's `ignoreGates`,
  /// forced elements, `debugPass`) count too. Off in every real build.
  bool countDebugRuns = false;

  /// Whether the run that led to the current post-run screens counted
  /// (§12.2: the bonus screen uses the flag of its run).
  bool lastRunCounted = false;

  /// Unlocks waiting for their toast (§12.5), oldest first.
  final List<AchievementId> toastQueue = [];

  /// Called after every new unlock (the game shows shop unlocks at once).
  void Function(AchievementId id)? onUnlocked;

  bool isUnlocked(AchievementId id) => storage.achUnlocked.contains(id.key);

  /// Idempotent unlock: stores the key, logs `achievement_unlocked`, queues
  /// the toast and reports it to the platform. Returns whether it was new.
  bool unlock(AchievementId id) {
    if (isUnlocked(id)) return false;
    unawaited(storage.saveAchUnlocked({...storage.achUnlocked, id.key}));
    services.track('achievement_unlocked', {'id': id.key, 'pts': id.points});
    toastQueue.add(id);
    onUnlocked?.call(id);
    unawaited(syncAll());
    return true;
  }

  // --- run rules (§12.2) ------------------------------------------------------

  /// A new run: the toasts of an unfinished earlier run are dropped.
  void beginRun({required bool counts}) {
    lastRunCounted = counts;
    toastQueue.clear();
  }

  /// Ranks: every level whose threshold the run's score reached (the run's
  /// score, never the stored best: start fresh).
  void onRunScore(int score) {
    for (var l = 0; l < kRankAchievements.length && l < kLevels.length; l++) {
      if (kLevels[l].threshold <= score) unlock(kRankAchievements[l]);
    }
  }

  /// A finished portal ride.
  void onRideFinished(RideId ride) {
    final id = switch (ride) {
      RideId.cannon => AchievementId.rideCannon,
      RideId.space => AchievementId.rideSpace,
      RideId.volcano => AchievementId.rideVolcano,
      RideId.sea => AchievementId.rideSea,
      RideId.pinball => AchievementId.ridePinball,
      RideId.storm => AchievementId.rideStorm,
    };
    unlock(id);
    if (!storage.achRides.contains(ride.storageId)) {
      unawaited(storage.saveAchRides({...storage.achRides, ride.storageId}));
      _progress(
        AchievementId.rideAll,
        storage.achRides.length,
        RideId.values.length,
      );
    }
    if (RideId.values.every((r) => storage.achRides.contains(r.storageId))) {
      unlock(AchievementId.rideAll);
    }
  }

  /// A first-catch item (one of [kItemAchievements]).
  void onItemCaught(AchievementId item) {
    unlock(item);
    if (!storage.achItems.contains(item.key)) {
      unawaited(storage.saveAchItems({...storage.achItems, item.key}));
      _progress(
        AchievementId.itemAll,
        storage.achItems.length,
        kItemAchievements.length,
      );
    }
    if (kItemAchievements.every((a) => storage.achItems.contains(a.key))) {
      unlock(AchievementId.itemAll);
    }
  }

  /// Hoops passed in this run (1-based `hoopsPassed`); a jump past several
  /// thresholds unlocks each.
  void onHoops(int hoopsPassed) {
    for (final (n, id) in kHoopAchievements) {
      if (hoopsPassed >= n) unlock(id);
    }
  }

  /// A versus win (`RunEnded`, duel == win).
  void onVersusWin() {
    final wins = storage.achVersusWins + 1;
    unawaited(storage.saveAchVersusWins(wins));
    for (final (n, id) in kVersusAchievements) {
      if (n > 1) _progress(id, wins, n);
      if (wins >= n) unlock(id);
    }
  }

  /// A counted run finished on [day] (`storage.today`): the daily streak.
  void onRunDay(int day) {
    final last = storage.achLastPlayDay;
    if (last == day) return;
    final streak = last == day - 1 ? storage.achDayStreak + 1 : 1;
    unawaited(storage.saveAchDays(streak, day));
    for (final (n, id) in kDailyAchievements) {
      _progress(id, streak, n);
      if (streak >= n) unlock(id);
    }
  }

  /// A shop item bought: FRESH FEATHERS, and PROUD PEACOCK once [owned]
  /// reaches [total] (`kCollectibleTotal`).
  void onShopPurchase({required int owned, required int total}) {
    unlock(AchievementId.skinFirst);
    _progress(AchievementId.skinAll, owned, total);
    if (owned >= total) unlock(AchievementId.skinAll);
  }

  /// §12.4 iOS progress of a counting achievement (Android ignores it).
  void _progress(AchievementId id, int current, int target) {
    if (isUnlocked(id) || target <= 0) return;
    final pct = math.min(99.0, 100.0 * current / target);
    unawaited(services.reportAchievementProgress(id, pct));
  }

  // --- platform sync (§12.4) --------------------------------------------------

  bool _syncing = false;
  bool _syncAgain = false;

  /// Reports every unlocked key the platform has not confirmed, one at a
  /// time. A different player than [GameStorage.achReportedPlayer] first
  /// clears the confirmed set (the new account receives everything). No-op
  /// while signed out; never signs in. Concurrent calls fold into one more
  /// pass.
  Future<void> syncAll() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _syncOnce();
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    if (!services.achievementsReady) return;
    final player = services.playerId;
    if (player != null && player != storage.achReportedPlayer) {
      await storage.saveAchReported({});
      await storage.saveAchReportedPlayer(player);
    }
    for (final id in AchievementId.values) {
      if (!isUnlocked(id) || storage.achReported.contains(id.key)) continue;
      if (!services.achievementsReady) return;
      final ok = await services.unlockAchievement(id);
      if (ok) {
        await storage.saveAchReported({...storage.achReported, id.key});
      }
    }
  }

  // --- debug (§12.3) ----------------------------------------------------------

  /// Debug "Achievements: reset local": clears the keys (not the platform).
  Future<void> resetLocal() async {
    toastQueue.clear();
    await storage.resetAchievements();
  }
}
