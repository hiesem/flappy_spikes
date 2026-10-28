import '../menu/powerup_slot.dart';
import '../run/director/plans.dart';
import '../run/elements.dart';
import '../run/pickups/capsule.dart';
import '../run/pickups/star_trail.dart';
import '../run/run_context.dart';
import '../run/run_events.dart';
import '../run/run_feature.dart';
import '../run/run_state.dart';
import '../versus/opponent.dart';
import 'achievement_catalog.dart';
import 'achievements.dart';

/// PRD-2.3.1 §12.2 the in-run achievement rules: listens to the run's
/// events and calls `game.achievements`, only while the run counts
/// (`RunController.countsForAchievements`). The run-end rules outside the
/// bus (ranks, daily) live in `FlappySpikesGame.endRun`; the jackpot in
/// `BonusScreen.tapTile`; the shop in `buyTriedOnItem`.
class AchievementsFeature extends RunFeature {
  RunContext? _c;
  // region P26-J10
  int _maxDeficit = 0;
  int _maxStreak = 0;

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    final rival = c?.run.setup.opponent;
    if (c == null) return;
    if (c.s.streak > _maxStreak) _maxStreak = c.s.streak;
    if (rival != null) {
      final deficit = rival.scoreAt(c.s.runClock) - c.s.score;
      if (deficit > _maxDeficit) _maxDeficit = deficit;
    }
  }
  // endregion

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<RunStarted>(_onStarted)
      ..on<RideEnded>(_onRideEnded)
      ..on<PickupCollected>(_onPickup)
      ..on<HoopPassed>(_onPassed)
      ..on<SavedHoopPassed>(_onSavedPass)
      ..on<RunEnded>(_onEnded)
      ..on<Revived>(_onRevived)
      ..on<FeverStarted>(_onFever)
      ..on<EggHatched>(_onHatched)
      ..on<JarFilled>(_onJarFilled)
      ..on<StarTrailPerfect>(_onStars)
      ..on<PuzzleCompleted>(_onPicture);
  }

  /// Applies the rule [op] through the tracker (staged and journaled until
  /// the run ends, P1E-03 / P2-03), only while this run counts.
  void _rule(String op) {
    final c = _c;
    if (c == null || !c.run.countsForAchievements) return;
    c.game.achievements.runOp(op);
  }

  void _onStarted(RunStarted e) {
    // region P26-J10
    _maxDeficit = 0;
    _maxStreak = 0;
    // endregion
    if (e.setup.starter == Powerup.bigHoops) {
      _rule(AchOp.unlock(AchievementId.firstBigHoops));
    }
  }

  void _onRideEnded(RideEnded e) {
    final id = e.rideId;
    if (e.kind != RideKind.portal || id == null) return;
    _rule(AchOp.ride(id));
  }

  void _onPickup(PickupCollected e) {
    final item = catchFor(e);
    if (item != null) _rule(AchOp.item(item));
  }

  /// PRD-2.3.1 §19.1 the item catch a [PickupCollected] adds to the
  /// lifetime counts ([itemFor]), except that a Star Trail counts once, on
  /// its first star (its other stars add nothing).
  static AchievementId? catchFor(PickupCollected e) {
    final p = e.pickup;
    if (p is StarTrail && p.caughtCount > 1) return null;
    return itemFor(e);
  }

  /// §12.2 the item achievement of a catch (null = none: piggy coins,
  /// fireflies, the comet).
  static AchievementId? itemFor(PickupCollected e) => switch (e.element) {
    ElementId.heart => AchievementId.itemHeart,
    ElementId.shield => AchievementId.itemShield,
    ElementId.starTrail => AchievementId.itemStarTrail,
    ElementId.egg => AchievementId.itemEgg,
    ElementId.piggy => AchievementId.itemPiggy,
    ElementId.jar => AchievementId.itemJar,
    ElementId.feather => AchievementId.itemFeather,
    ElementId.puzzlePiece => AchievementId.itemPuzzle,
    ElementId.capsule => switch (e.pickup) {
      CapsulePickup(:final type) => switch (type) {
        TimedPowerup.hourglass => AchievementId.itemHourglass,
        TimedPowerup.mini => AchievementId.itemMiniBird,
        TimedPowerup.frenzy => AchievementId.itemCoinFrenzy,
        TimedPowerup.comet => null,
      },
      _ => null,
    },
    _ => null,
  };

  void _onPassed(HoopPassed e) => _hoopGoals();

  /// SPEC WP-3d: a saved saw / closed switch ring counts as passed.
  void _onSavedPass(SavedHoopPassed e) => _hoopGoals();

  void _hoopGoals() {
    final c = _c;
    if (c == null) return;
    // QA P19-04: a hoop goal is staged the moment its threshold is crossed
    // (its earned position in the run); later passes add nothing.
    final n = c.s.hoopsPassed;
    // region P26-J10
    if (c.s.streak > _maxStreak) _maxStreak = c.s.streak;
    if (_maxStreak >= 25) _rule(AchOp.unlock(AchievementId.bullseye));
    // endregion
    for (final (goal, id) in kHoopAchievements) {
      if (n >= goal) _rule(AchOp.unlock(id));
    }
  }

  void _onEnded(RunEnded e) {
    if (e.summary.duel == DuelResult.win) _rule(AchOp.versusWin);
    // region P26-J10
    final c = _c;
    final rival = c?.run.setup.opponent;
    if (c != null && rival != null && e.summary.duel != null) {
      update(0, 0);
      _rule(
        AchOp.versusResult(
          e.summary.duel == DuelResult.win,
          c.s.score,
          rival.score,
          _maxDeficit,
          _maxStreak,
          c.s.revivesThisGame,
        ),
      );
    }
    // endregion
  }

  void _onRevived(Revived e) => _rule(AchOp.unlock(AchievementId.firstRevive));

  void _onFever(FeverStarted e) =>
      _rule(AchOp.unlock(AchievementId.firstFever));

  void _onHatched(EggHatched e) =>
      _rule(AchOp.unlock(AchievementId.masterHatch));

  void _onJarFilled(JarFilled e) =>
      _rule(AchOp.unlock(AchievementId.masterJar));

  void _onStars(StarTrailPerfect e) =>
      _rule(AchOp.unlock(AchievementId.masterStars));

  void _onPicture(PuzzleCompleted e) =>
      _rule(AchOp.unlock(AchievementId.masterPicture));

  @override
  void detach() {
    _c?.events
      ?..off<RunStarted>(_onStarted)
      ..off<RideEnded>(_onRideEnded)
      ..off<PickupCollected>(_onPickup)
      ..off<HoopPassed>(_onPassed)
      ..off<SavedHoopPassed>(_onSavedPass)
      ..off<RunEnded>(_onEnded)
      ..off<Revived>(_onRevived)
      ..off<FeverStarted>(_onFever)
      ..off<EggHatched>(_onHatched)
      ..off<JarFilled>(_onJarFilled)
      ..off<StarTrailPerfect>(_onStars)
      ..off<PuzzleCompleted>(_onPicture);
    _c = null;
  }
}
