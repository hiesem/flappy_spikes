import 'dart:async';
import 'dart:math' as math;

import '../game/diag.dart';
import '../game/storage.dart';
import 'ach_state.dart';
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

  /// Called after every new unlock (once it is durable).
  void Function(AchievementId id)? onUnlocked;

  // --- the one-write state transitions (QA P19-01..03) --------------------------

  /// The persisted state (`GameStorage.ach`): every transition mutates it
  /// synchronously, then [_commit] writes the whole snapshot once.
  AchState get _s => storage.ach;

  /// Side effects of the open transition (analytics, toasts, platform
  /// calls): they run only after its write landed.
  final List<void Function()> _effects = [];
  int _depth = 0;
  Future<void> _lastCommit = Future<void>.value();

  /// Runs [body] as one transition: nested calls join the outer one; the
  /// outermost writes the state once and then runs the side effects.
  T _tx<T>(T Function() body) {
    _depth++;
    try {
      return body();
    } finally {
      _depth--;
      if (_depth == 0) _lastCommit = _commit();
    }
  }

  Future<void> _commit() async {
    final effects = [..._effects];
    _effects.clear();
    await storage.saveAchState(_s);
    for (final e in effects) {
      e();
    }
  }

  /// Completes when every transition so far is durable and its side
  /// effects ran (toasts queued, analytics logged).
  Future<void> flush() => _lastCommit;

  bool isUnlocked(AchievementId id) => _s.unlocked.contains(id.key);

  /// PRD-2.3.1 §19.2 earned, waiting in `achPending` for a run's slot.
  bool isPending(AchievementId id) => _s.pending.contains(id.key);

  /// PRD-2.3.1 §19.2 every earned key: unlocked or pending.
  Set<String> get earned => {..._s.unlocked, ..._s.pending};

  /// Idempotent unlock: stores the key; once durable it logs
  /// `achievement_unlocked`, queues the toast (signed out only) and reports it to the
  /// platform. Returns whether it was new. Immediate: the shop, the jackpot
  /// and the debug "unlock one" call it directly (PRD-2.3.1 §19.2
  /// exceptions); the run rules [_earn] instead.
  bool unlock(AchievementId id) => _tx(() => _unlock(id));

  bool _unlock(AchievementId id) {
    if (isUnlocked(id)) return false;
    _s.unlocked.add(id.key);
    _s.pending.remove(id.key);
    _effects.add(() {
      services.track('achievement_unlocked', {'id': id.key, 'pts': id.points});
      // Owner 2026-10-14: a signed-in player gets the platform's own
      // popup (Play Games / Game Center), so the game's toast shows only
      // while the player isn't signed in.
      final signedIn = services.achievementsReady;
      if (!signedIn) toastQueue.add(id);
      diag(
        'FS-Ach unlocked ${id.key} (${id.iosId}) signedIn=$signedIn '
        '${signedIn ? 'platform banner' : 'game toast'}',
      );
      onUnlocked?.call(id);
      unawaited(syncAll());
    });
    if (kItemAchievements.contains(id)) _checkMagpie();
    return true;
  }

  /// PRD-2.3.1 §19.5 run-end earnings (ranks, versus, daily) collected as
  /// one batch, sorted by catalog index before they join the queue (QA
  /// P19-05). Null outside a run end.
  List<AchievementId>? _batch;

  /// PRD-2.3.1 §19.2 a run rule earned [id]: it joins the end of the FIFO
  /// `achPending` queue (unless already unlocked or pending) and unlocks
  /// when a counting run end releases it. Never reported and never
  /// toasted before that.
  void _earn(AchievementId id) {
    if (isUnlocked(id) || isPending(id)) return;
    final batch = _batch;
    if (batch != null) {
      if (!batch.contains(id)) batch.add(id);
    } else {
      _s.pending.add(id.key);
    }
  }

  /// PRD-2.3.1 §19.2 a counting run's one unlock slot: the oldest pending
  /// achievement unlocks (pending → unlocked in one write). Returns it.
  AchievementId? releaseOne() => _tx(_releaseOne);

  AchievementId? _releaseOne() {
    while (_s.pending.isNotEmpty) {
      final id = AchievementId.fromKey(_s.pending.first);
      if (id == null || isUnlocked(id)) {
        _s.pending.removeAt(0); // stale key
        continue;
      }
      _unlock(id);
      return id;
    }
    return null;
  }

  /// PRD-2.3.1 §19.1 MAGPIE is earned once all 11 item achievements are
  /// unlocked (not merely pending).
  void _checkMagpie() {
    final n = kItemAchievements.where(isUnlocked).length;
    _progress(AchievementId.itemAll, n, kItemAchievements.length);
    if (n == kItemAchievements.length) _earn(AchievementId.itemAll);
  }

  // --- run rules (§12.2) ------------------------------------------------------

  /// P1E-03 / QA P2-03: a run is open: its rules are staged as [AchOp]s in
  /// the persisted journal (`AchState.journal`) and only commit at
  /// [finishRun] (or, after an app kill, at [recoverJournal]) when the run
  /// still counts. Off with [countDebugRuns] (rules apply at once).
  bool _open = false;

  /// The open run was excluded (debug assist): nothing more is staged.
  bool _excluded = false;

  /// A new run: an empty journal is written. iOS round 2 §6 (both
  /// platforms): toasts of an earlier run that were not shown yet stay
  /// queued (they show on the next results page / Home) instead of being
  /// dropped.
  void beginRun({required bool counts}) => _tx(() {
    lastRunCounted = counts;
    _open = !countDebugRuns;
    _excluded = !counts;
    _s
      ..journal = []
      ..journalExcluded = _excluded;
  });

  /// A run rule of the open run: staged in the journal (one write) until
  /// [finishRun]; applied at once outside a run. Item catches repeat; any
  /// other op is staged once per run.
  void runOp(String op) {
    if (!_open) {
      _tx(() => _apply(op));
      return;
    }
    if (_excluded) return;
    if (_s.journal.contains(op) && !AchOp.repeats(op)) return;
    _tx(() => _s.journal.add(op));
  }

  /// The app leaves the foreground with an open run (QA P2-03): the
  /// journal is already durable; marks it excluded when the run no longer
  /// [counts].
  void saveJournal({required bool counts}) {
    if (!_open) return;
    if (!counts) excludeRun();
  }

  /// A debug assist in the open run (QA P2-03): the journal is emptied and
  /// marked excluded in one write before the assist applies.
  void excludeRun() {
    if (!_open || _excluded) return;
    _excluded = true;
    _tx(() {
      _s
        ..journal = []
        ..journalExcluded = true;
    });
  }

  // region P26-J2
  /// The run ended (`FlappySpikesGame.endRun`). One transition, one write:
  /// the journal is consumed; a counting run commits its staged rules in
  /// earning order, then its run-end batch (the versus win, the one-run
  /// [score] thresholds of PRD-2.6 J9, and the daily streak for [day])
  /// sorted by catalog index behind
  /// the older pending, then (PRD-2.3.1 §19.2) unlocks at most one: the
  /// oldest pending.
  void finishRun({required bool counts, int? score, int? day}) => _tx(() {
    final staged = _open ? [..._s.journal] : const <String>[];
    _open = false;
    _excluded = false;
    lastRunCounted = counts;
    _s
      ..journal = []
      ..journalExcluded = false;
    if (!counts) return;
    for (final op in staged) {
      if (op != AchOp.versusWin) _apply(op);
    }
    _batch = [];
    try {
      for (final op in staged) {
        if (op == AchOp.versusWin) _apply(op);
      }
      if (score != null) onRunScore(score);
      if (day != null) onRunDay(day);
    } finally {
      final batch = _batch!..sort((a, b) => a.index.compareTo(b.index));
      _batch = null;
      batch.forEach(_earn);
    }
    _releaseOne();
  });
  // endregion

  /// Launch (QA P2-03): a journal left by a run the app died in. One
  /// write: a clean journal's earnings join `achPending` (PRD-2.3.1 §19.2:
  /// no unlock, no toast, no report) and its catches count, and the journal
  /// is consumed; an excluded one is discarded.
  Future<void> recoverJournal() async {
    final ops = [..._s.journal];
    final excluded = _s.journalExcluded;
    if (ops.isEmpty && !excluded) return;
    _tx(() {
      _s
        ..journal = []
        ..journalExcluded = false;
      if (excluded) return;
      for (final op in ops) {
        _apply(op);
      }
    });
    await flush();
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
      case AchOp._hoops: // a 2.3.1 (20) journal
        final n = int.tryParse(arg);
        if (n != null) onHoops(n);
      case AchOp._versusWin:
        onVersusWin();
      // region P26-J10
      case AchOp._versusResult:
        final values = arg.split(',').map(int.tryParse).toList();
        if (values.length == 6 && values.every((v) => v != null)) {
          onVersusResult(
            win: values[0] == 1,
            score: values[1]!,
            rivalScore: values[2]!,
            deficit: values[3]!,
            streak: values[4]!,
            revives: values[5]!,
          );
        }
      // endregion
    }
  }

  // region P26-J9
  /// PRD-2.6 J9 / round-2 decision: published rank achievements retain
  /// their single-run score thresholds, independently of progression.
  void onRunScore(int score) => _tx(() {
    for (var i = 0; i < kRankAchievements.length; i++) {
      if (score >= kRankScoreThresholds[i]) _earn(kRankAchievements[i]);
    }
  });
  // endregion

  /// A finished portal ride.
  void onRideFinished(RideId ride) => _tx(() {
    final id = switch (ride) {
      RideId.cannon => AchievementId.rideCannon,
      RideId.space => AchievementId.rideSpace,
      RideId.volcano => AchievementId.rideVolcano,
      RideId.sea => AchievementId.rideSea,
      RideId.pinball => AchievementId.ridePinball,
      RideId.storm => AchievementId.rideStorm,
    };
    _earn(id);
    if (_s.rides.add(ride.storageId)) {
      _progress(AchievementId.rideAll, _s.rides.length, RideId.values.length);
    }
    if (RideId.values.every((r) => _s.rides.contains(r.storageId))) {
      _earn(AchievementId.rideAll);
    }
  });

  /// PRD-2.3.1 §19.1 one catch of an item (one of [kItemAchievements]):
  /// the lifetime count (`achItemCounts`) grows; the item achievement is
  /// earned at its goal ([kItemGoals]). Progress is local only.
  void onItemCaught(AchievementId item) => _tx(() {
    final n = (_s.itemCounts[item.key] ?? 0) + 1;
    _s.itemCounts[item.key] = n;
    if (n >= itemGoal(item)) _earn(item);
  });

  /// The lifetime catches of [item] so far.
  int itemCount(AchievementId item) => _s.itemCounts[item.key] ?? 0;

  /// Hoops passed in this run (1-based `hoopsPassed`); a jump past several
  /// thresholds earns each, in catalog order.
  void onHoops(int hoopsPassed) => _tx(() {
    for (final (n, id) in kHoopAchievements) {
      if (hoopsPassed >= n) _earn(id);
    }
  });

  /// A versus win (`RunEnded`, duel == win).
  void onVersusWin() => _tx(() {
    final wins = ++_s.versusWins;
    for (final (n, id) in kVersusAchievements) {
      if (n > 1) _progress(id, wins, n);
      if (wins >= n) _earn(id);
    }
  });

  // region P26-J10
  /// Called by the guide and leaderboard after their respective completion events.
  void onFlightGuideComplete() => unlock(AchievementId.birdwatcher);
  void onLeaderboardDayWon() => unlock(AchievementId.topBird);

  /// A counting race with a rival; solo runs never call this method.
  /// A draw breaks consecutive wins: it is a race that was not won (O82).
  void onVersusResult({
    required bool win,
    required int score,
    required int rivalScore,
    required int deficit,
    required int streak,
    required int revives,
  }) => _tx(() {
    final next = win ? storage.vsWinStreak + 1 : 0;
    unawaited(storage.saveVsWinStreak(next));
    if (next > storage.vsWinStreakBest) {
      unawaited(storage.saveVsWinStreakBest(next));
    }
    if (!win) return;
    if (next >= 5) _earn(AchievementId.birdOfPrey);
    if (deficit >= 100) _earn(AchievementId.secondWind);
    if (rivalScore >= 100 && score >= 2 * rivalScore) {
      _earn(AchievementId.albatross);
    }
    if (score >= 1000) _earn(AchievementId.ironBeak);
    if (streak >= 20 && revives == 0) _earn(AchievementId.flawless);
    if (score >= 500) {
      final day = storage.today.toString();
      final count = (storage.vsBigWinsDay[day] ?? 0) + 1;
      unawaited(storage.saveVsBigWinsDay({day: count}));
      if (count >= 3) _earn(AchievementId.threeLittleBirds);
    }
  });
  // endregion

  /// A counted run finished on [day] (`storage.today`): the daily streak.
  void onRunDay(int day) => _tx(() {
    final last = _s.lastPlayDay;
    if (last == day) return;
    final streak = last == day - 1 ? _s.dayStreak + 1 : 1;
    _s
      ..dayStreak = streak
      ..lastPlayDay = day;
    for (final (n, id) in kDailyAchievements) {
      _progress(id, streak, n);
      if (streak >= n) _earn(id);
    }
  });

  /// A shop item bought: FRESH FEATHERS, and PROUD PEACOCK once [owned]
  /// reaches [total] (`kCollectibleTotal`). Immediate (no run slot).
  void onShopPurchase({required int owned, required int total}) => _tx(() {
    _unlock(AchievementId.skinFirst);
    _progress(AchievementId.skinAll, owned, total);
    if (owned >= total) _unlock(AchievementId.skinAll);
  });

  /// §12.4 iOS progress of a counting achievement (Android ignores it),
  /// sent after the transition's write.
  void _progress(AchievementId id, int current, int target) {
    if (isUnlocked(id) || target <= 0) return;
    final pct = math.min(99.0, 100.0 * current / target);
    _effects.add(() {
      if (!isUnlocked(id)) {
        unawaited(services.reportAchievementProgress(id, pct));
      }
    });
  }

  // --- platform sync (§12.4) --------------------------------------------------

  bool _syncing = false;
  bool _syncAgain = false;

  /// Reports every unlocked key the platform has not confirmed, one at a
  /// time. A different player than [GameStorage.achReportedPlayer] first
  /// clears the confirmed set (the new account receives everything). No-op
  /// while signed out; never signs in. Concurrent calls fold into one more
  /// pass. Pending achievements are never reported.
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
    if (!services.achievementsReady) {
      diag('FS-Ach sync: not signed in, nothing reported');
      return;
    }
    // Only what is durably unlocked is reported.
    await flush();
    final player = services.playerId;
    if (player != null && player != _s.reportedPlayer) {
      _tx(() {
        _s
          ..reported = {}
          ..reportedPlayer = player;
      });
      await flush();
    }
    for (final id in AchievementId.values) {
      if (!isUnlocked(id) || _s.reported.contains(id.key)) continue;
      if (!services.achievementsReady) return;
      final ok = await services.unlockAchievement(id);
      if (ok) {
        _tx(() => _s.reported.add(id.key));
        await flush();
      }
    }
  }

  // --- debug (§12.3) ----------------------------------------------------------

  /// Debug "Achievements: reset local": clears the keys (not the platform).
  Future<void> resetLocal() async {
    toastQueue.clear();
    await flush();
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
  // region P26-J10
  static const _versusResult = 'vresult';
  static String versusResult(
    bool win,
    int score,
    int rival,
    int deficit,
    int streak,
    int revives,
  ) => '$_versusResult:${win ? 1 : 0},$score,$rival,$deficit,$streak,$revives';
  // endregion

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
