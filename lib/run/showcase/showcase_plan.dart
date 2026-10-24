import '../../menu/powerup_slot.dart';
import '../config/showcase_config.dart';

/// The frozen plan for one showcase run.
class ShowcaseRunPlan {
  const ShowcaseRunPlan({
    required this.highlightId,
    required this.step,
    required this.attempt,
    this.extraStarters = const [],
  });

  /// One of [ShowcaseConfig.highlightIds].
  final String highlightId;

  /// Zero-based script step (`0` portal, `1` comet, `2` FEVER).
  final int step;

  /// The run's attempt number for this step (1 is the first try).
  final int attempt;

  /// Starters to arm in addition to the consumed Home-slot powerup.
  final List<Powerup> extraStarters;
}

/// Builds the showcase plan at START. The wave-1 implementation is inert and
/// always returns null; WP-B owns persistence, attempt counting and scripts.
abstract class ShowcasePlan {
  const ShowcasePlan();

  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  });
}

/// The default no-op planner used while the M1 skeleton is inert.
class InertShowcasePlan extends ShowcasePlan {
  const InertShowcasePlan();

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => null;
}

/// Persists highlight and run-end state. All wave-1 methods are no-ops.
abstract class ShowcaseProgress {
  const ShowcaseProgress();

  void onHighlight(String id, {required bool scripted, required int hoop});

  void onRunEnd({required int gamesPlayed, required int hoopsPassed});
}

/// The default no-op progress sink.
class InertShowcaseProgress extends ShowcaseProgress {
  const InertShowcaseProgress();

  @override
  void onHighlight(String id, {required bool scripted, required int hoop}) {}

  @override
  void onRunEnd({required int gamesPlayed, required int hoopsPassed}) {}
}
