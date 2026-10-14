import '../menu/powerup_slot.dart';
import '../run/director/plans.dart';
import '../run/elements.dart';
import '../run/pickups/capsule.dart';
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

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<RunStarted>(_onStarted)
      ..on<RideEnded>(_onRideEnded)
      ..on<PickupCollected>(_onPickup)
      ..on<HoopPassed>(_onPassed)
      ..on<RunEnded>(_onEnded)
      ..on<Revived>(_onRevived)
      ..on<FeverStarted>(_onFever)
      ..on<EggHatched>(_onHatched)
      ..on<JarFilled>(_onJarFilled)
      ..on<StarTrailPerfect>(_onStars)
      ..on<PuzzleCompleted>(_onPicture);
  }

  /// Applies [rule] through the tracker (staged until the run ends,
  /// P1E-03), only while this run counts.
  void _rule(void Function(AchievementTracker t) rule) {
    final c = _c;
    if (c == null || !c.run.countsForAchievements) return;
    c.game.achievements.runRule(rule);
  }

  void _onStarted(RunStarted e) {
    if (e.setup.starter == Powerup.bigHoops) {
      _rule((t) => t.unlock(AchievementId.firstBigHoops));
    }
  }

  void _onRideEnded(RideEnded e) {
    final id = e.rideId;
    if (e.kind != RideKind.portal || id == null) return;
    _rule((t) => t.onRideFinished(id));
  }

  void _onPickup(PickupCollected e) {
    final item = itemFor(e);
    if (item != null) _rule((t) => t.onItemCaught(item));
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

  void _onPassed(HoopPassed e) {
    final c = _c;
    if (c == null) return;
    final n = c.s.hoopsPassed; // captured now (the rule may be staged)
    _rule((t) => t.onHoops(n));
  }

  void _onEnded(RunEnded e) {
    if (e.summary.duel == DuelResult.win) _rule((t) => t.onVersusWin());
  }

  void _onRevived(Revived e) =>
      _rule((t) => t.unlock(AchievementId.firstRevive));

  void _onFever(FeverStarted e) =>
      _rule((t) => t.unlock(AchievementId.firstFever));

  void _onHatched(EggHatched e) =>
      _rule((t) => t.unlock(AchievementId.masterHatch));

  void _onJarFilled(JarFilled e) =>
      _rule((t) => t.unlock(AchievementId.masterJar));

  void _onStars(StarTrailPerfect e) =>
      _rule((t) => t.unlock(AchievementId.masterStars));

  void _onPicture(PuzzleCompleted e) =>
      _rule((t) => t.unlock(AchievementId.masterPicture));

  @override
  void detach() {
    _c?.events
      ?..off<RunStarted>(_onStarted)
      ..off<RideEnded>(_onRideEnded)
      ..off<PickupCollected>(_onPickup)
      ..off<HoopPassed>(_onPassed)
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
