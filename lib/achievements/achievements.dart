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

  /// PRD-2.3.1 §19.2 earned, waiting in `achPending` for a run's slot.
  bool isPending(AchievementId id) => storage.achPending.contains(id.key);

  /// PRD-2.3.1 §19.2 every earned key: unlocked or pending.
  Set<String> get earned => {...storage.achUnlocked, ...storage.achPending};

  /// Idempotent unlock: stores the key, logs `achievement_unlocked`, queues
  /// the toast and reports it to the platform. Returns whether it was new.
  /// Immediate: the shop, the jackpot and the debug "unlock one" call it
  /// directly (PRD-2.3.1 §19.2 exceptions); the run rules [_earn] instead.
  bool unlock(AchievementId id) {
    if (isUnlocked(id)) return false;
    unawaited(storage.saveAchUnlocked({...storage.achUnlocked, id.key}));
    if (isPending(id)) {
      unawaited(
        storage.saveAchPending([
          for (final k in storage.achPending)
            if (k != id.key) k,
        ]),
      );
    }
    services.track('achievement_unlocked', {'id': id.key, 'pts': id.points});
    toastQueue.add(id);
    onUnlocked?.call(id);
    unawaited(syncAll());
    if (kItemAchievements.contains(id)) _checkMagpie();
    return true;
  }

  /// PRD-2.3.1 §19.2 a run rule earned [id]: it joins the end of the FIFO
  /// `achPending` queue (unless already unlocked or pending) and unlocks
  /// when a counting run end releases it ([releaseOne]). Never reported
  /// and never toasted before that.
  void _earn(AchievementId id) {
    if (isUnlocked(id) || isPending(id)) return;
    unawaited(storage.saveAchPending([...storage.achPending, id.key]));
  }

  /// PRD-2.3.1 §19.2 a counting run's one unlock slot: the oldest pending
  /// achievement unlocks. Returns it (null = nothing pending).
  AchievementId? releaseOne() {
    final pending = [...storage.achPending];
    AchievementId? next;
    while (pending.isNotEmpty && next == null) {
      final id = AchievementId.fromKey(pending.removeAt(0));
      if (id != null && !isUnlocked(id)) next = id;
    }
    unawaited(storage.saveAchPending(pending));
    if (next != null) unlock(next);
    return next;
  }

  /// PRD-2.3.1 §19.1 MAGPIE is earned once all 11 item achievements are
  /// unlocked (not merely pending).
  void _checkMagpie() {
    final n = kItemAchievements.where(isUnlocked).length;
    _progress(AchievementId.itemAll, n, kItemAchievements.length);
    if (n == kItemAchievements.length) _earn(AchievementId.itemAll);
  }

  // --- run rules (§12.2) ------------------------------------------------------

  /// P1E-03: the run rules of the current run, staged until it ends (null
  /// = no run open: rules apply at once). A run can still turn into a debug
  /// run (`debugPass`, the force menu, god mode), so nothing it earned is
  /// stored, logged or reported before [finishRun] knows it still counts.
  /// Their toasts show on the results page anyway (§12.5).
  ///
  /// QA P2-03: the staged rules are serializable ops ([AchOp]) mirrored in
  /// a provisional journal on disk (`GameStorage.achJournal`), so a clean
  /// run's completed events survive the app dying before [finishRun]: the
  /// next launch commits them ([recoverJournal]). A debug assist marks the
  /// journal excluded first ([excludeRun]); an excluded journal is
  /// discarded. Nothing is reported to the platform before a commit.
  List<String>? _staged;

  /// The open run was excluded (debug assist): its journal is discarded.
  bool _excluded = false;

  /// The deepest hoop count already written to the journal (hoop passes are
  /// folded into one op and only written when they cross a threshold).
  int _journaledHoops = 0;

  /// A new run: the toasts and staged rules of an unfinished earlier run are
  /// dropped. With [countDebugRuns] (tests) a run can never become excluded,
  /// so its rules apply at once.
  void beginRun({required bool counts}) {
    lastRunCounted = counts;
    toastQueue.clear();
    _staged = countDebugRuns ? null : [];
    _excluded = !counts;
    _journaledHoops = 0;
    unawaited(storage.saveAchJournal(const [], excluded: _excluded));
  }

  /// A run rule of the open run: staged (and journaled) until [finishRun];
  /// applied at once outside a run.
  void runOp(String op) {
    final staged = _staged;
    if (staged == null) {
      _apply(op);
      return;
    }
    final hoops = AchOp.hoopsOf(op);
    if (hoops != null) {
      // One folded op: onHoops(n) is monotonic.
      staged.removeWhere((o) => AchOp.hoopsOf(o) != null);
      staged.add(op);
      final crossed = kHoopAchievements.any(
        (h) => h.$1 > _journaledHoops && h.$1 <= hoops,
      );
      if (!crossed) return; // written at the next pause / event
      _journaledHoops = hoops;
    } else if (staged.contains(op) && !AchOp.repeats(op)) {
      return;
    } else {
      staged.add(op);
    }
    _writeJournal();
  }

  /// The app leaves the foreground with an open run (QA P2-03): writes the
  /// journal as it is, or marks it excluded when the run no longer
  /// [counts].
  void saveJournal({required bool counts}) {
    if (_staged == null) return;
    if (!counts) {
      excludeRun();
      return;
    }
    _writeJournal();
  }

  /// A debug assist in the open run (QA P2-03): the journal is marked
  /// excluded (and emptied) before the assist applies.
  void excludeRun() {
    if (_staged == null || _excluded) return;
    _excluded = true;
    _staged!.clear();
    unawaited(storage.saveAchJournal(const [], excluded: true));
  }

  void _writeJournal() {
    if (_excluded) return;
    unawaited(storage.saveAchJournal(_staged ?? const [], excluded: false));
  }

  /// The run ended (`FlappySpikesGame.endRun`): its staged rules commit, in
  /// order, only when it still [counts]; otherwise they are dropped. The
  /// journal is cleared either way. A counting run then earns its ranks
  /// ([score]) and the daily streak ([day]), and (PRD-2.3.1 §19.2) unlocks
  /// at most one achievement: the oldest pending one ([releaseOne]).
  void finishRun({required bool counts, int? score, int? day}) {
    final staged = _staged ?? const <String>[];
    _staged = null;
    _excluded = false;
    lastRunCounted = counts;
    unawaited(storage.saveAchJournal(const [], excluded: false));
    if (!counts) return;
    for (final op in staged) {
      _apply(op);
    }
    if (score != null) onRunScore(score);
    if (day != null) onRunDay(day);
    releaseOne();
  }

  /// Launch (QA P2-03): a journal left by a run the app died in commits
  /// when it was clean and is discarded when excluded. PRD-2.3.1 §19.2:
  /// what it earned joins `achPending` (no unlock, no toast, no report).
  Future<void> recoverJournal() async {
    final ops = storage.achJournal;
    final excluded = storage.achJournalExcluded;
    if (ops.isEmpty && !excluded) return;
    await storage.saveAchJournal(const [], excluded: false);
    if (excluded) return;
    for (final op in ops) {
      _apply(op);
    }
    toastQueue.clear();
  }

  void _apply(String op) {
    final (kind, arg) = AchOp.split(op);
    switch (kind) {
      case AchOp._unlock:
        final id = AchOp.idOf(arg);
        if (id != null) _earn(id);
      case AchOp._ride:
        final ride = RideId.values.where((r) => r.storageId == arg);
        if (ride.isNotEmpty) onRideFinished(ride.first);
      case AchOp._item:
        final id = AchOp.idOf(arg);
        if (id != null) onItemCaught(id);
      case AchOp._hoops:
        final n = int.tryParse(arg);
        if (n != null) onHoops(n);
      case AchOp._versusWin:
        onVersusWin();
    }
  }

  /// Ranks: every level whose threshold the run's score reached (the run's
  /// score, never the stored best: start fresh).
  void onRunScore(int score) {
    for (var l = 0; l < kRankAchievements.length && l < kLevels.length; l++) {
      if (kLevels[l].threshold <= score) _earn(kRankAchievements[l]);
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
    _earn(id);
    if (!storage.achRides.contains(ride.storageId)) {
      unawaited(storage.saveAchRides({...storage.achRides, ride.storageId}));
      _progress(
        AchievementId.rideAll,
        storage.achRides.length,
        RideId.values.length,
      );
    }
    if (RideId.values.every((r) => storage.achRides.contains(r.storageId))) {
      _earn(AchievementId.rideAll);
    }
  }

  /// PRD-2.3.1 §19.1 one catch of an item (one of [kItemAchievements]):
  /// the lifetime count (`achItemCounts`) grows; the item achievement is
  /// earned at its goal ([kItemGoals]). Progress is local only.
  void onItemCaught(AchievementId item) {
    final n = (storage.achItemCounts[item.key] ?? 0) + 1;
    unawaited(
      storage.saveAchItemCounts({...storage.achItemCounts, item.key: n}),
    );
    if (n >= itemGoal(item)) _earn(item);
  }

  /// The lifetime catches of [item] so far.
  int itemCount(AchievementId item) => storage.achItemCounts[item.key] ?? 0;

  /// Hoops passed in this run (1-based `hoopsPassed`); a jump past several
  /// thresholds unlocks each.
  void onHoops(int hoopsPassed) {
    for (final (n, id) in kHoopAchievements) {
      if (hoopsPassed >= n) _earn(id);
    }
  }

  /// A versus win (`RunEnded`, duel == win).
  void onVersusWin() {
    final wins = storage.achVersusWins + 1;
    unawaited(storage.saveAchVersusWins(wins));
    for (final (n, id) in kVersusAchievements) {
      if (n > 1) _progress(id, wins, n);
      if (wins >= n) _earn(id);
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
      if (streak >= n) _earn(id);
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

/// QA P2-03 the serializable run rules of [AchievementTracker.runOp]
/// (`kind:arg` strings, the journal's format).
abstract final class AchOp {
  static const _unlock = 'u';
  static const _ride = 'ride';
  static const _item = 'item';
  static const _hoops = 'hoops';
  static const _versusWin = 'vwin';

  static String unlock(AchievementId id) => '$_unlock:${id.key}';
  static String ride(RideId ride) => '$_ride:${ride.storageId}';
  static String item(AchievementId id) => '$_item:${id.key}';
  static String hoops(int hoopsPassed) => '$_hoops:$hoopsPassed';
  static const String versusWin = '$_versusWin:';

  static (String, String) split(String op) {
    final i = op.indexOf(':');
    return i < 0 ? (op, '') : (op.substring(0, i), op.substring(i + 1));
  }

  /// PRD-2.3.1 §19.1 item catches count each time (never folded).
  static bool repeats(String op) => split(op).$1 == _item;

  static int? hoopsOf(String op) {
    final (kind, arg) = split(op);
    return kind == _hoops ? int.tryParse(arg) : null;
  }

  static AchievementId? idOf(String key) {
    for (final id in AchievementId.values) {
      if (id.key == key) return id;
    }
    return null;
  }
}
