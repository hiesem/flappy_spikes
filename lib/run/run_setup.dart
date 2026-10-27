import '../menu/powerup_slot.dart';
import '../versus/opponent.dart';
import 'config/run_config.dart';
import 'director/plans.dart';
import 'elements.dart';
import 'showcase/showcase_plan.dart';

/// Inputs to one run (ARCH §1.1).
class RunSetup {
  // region P26-G5a
  const RunSetup({
    required this.seed,
    Powerup starter = Powerup.none,
    OpponentRun? opponent,
    this.startHoopIndex = 0,
    this.forced = const [],
    this.forcedRide,
    required this.viewHeight,
    this.enabledOverride,
    this.ignoreGates = false,
    this.oneBigBonus = RunConfig.oneBigBonus,
    this.debugStarter = false,
    ShowcaseRunPlan? showcase,
    List<Powerup> extraStarters = const [],
    this.weekly = false,
    this.weeklyStartedAt,
  }) : starter = weekly ? Powerup.none : starter,
       opponent = weekly ? null : opponent,
       showcase = weekly ? null : showcase,
       extraStarters = weekly ? const [] : extraStarters;

  /// Monday UTC of the course selected at START, frozen for run-end rewards.
  final DateTime? weeklyStartedAt;

  /// G5 opens every lifetime gate without marking the run as debug.
  final bool weekly;
  bool get gatesOpen => weekly || ignoreGates;
  bool get allowsRevive => !weekly;

  /// LB2 submit hook: weekly is an ordinary counting run.
  String submissionMode(String homeMode) => weekly ? 'weekly' : homeMode;
  // endregion

  /// Per-run seed (§3.0.3; tests fix it, e2e uses `kE2ESeed`).
  final int seed;

  /// The home-slot powerup consumed for this run (§3.6, §3.7).
  final Powerup starter;

  /// Prefetched versus opponent; null = solo.
  final OpponentRun? opponent;

  /// §7 test / debug override: the first slot's hoop index.
  final int startHoopIndex;

  /// §3.0.8 debug force queue.
  final List<ElementId> forced;

  /// §3.0.8 debug: the next portal's ride.
  final RideId? forcedRide;

  final double viewHeight;

  /// Tests: the elements the director may offer, instead of the registries.
  final Set<ElementId>? enabledOverride;

  /// PRD-2.3 §14.6 tests / e2e / soak: every element regardless of the
  /// lifetime unlock gates (`GatesConfig`). Off in every real run.
  final bool ignoreGates;

  /// PRD-2.3 §17.3 the one-big-bonus planner rule; tests turn it off only
  /// for the §17.6 bonus-count baseline.
  final bool oneBigBonus;

  /// PRD-2.3.1 §12.2 the [starter] came from the Home debug panel's
  /// "Slot: force …" (a debug start: the run never counts for achievements).
  final bool debugStarter;

  /// PRD-2.6 WP-B the frozen showcase plan, null in a normal run.
  final ShowcaseRunPlan? showcase;

  /// PRD-2.6 WP-B additional starters (Big Hoops / shield) to arm at START.
  final List<Powerup> extraStarters;
}
