/// PRD-2.6 milestone ids emitted by the game's FTUE hooks.
abstract final class FtueStep {
  static const String firstTap = 'first_tap';
  static const String run1End = 'run1_end';
  static const String run2End = 'run2_end';
  static const String run3End = 'run3_end';
  static const String run4Start = 'run4_start';
  static const String run20End = 'run20_end';
}

/// Records first-use milestones. The wave-1 implementation persists nothing;
/// later issues consume the shared `ftueSteps` state through this seam.
abstract class FtueTracker {
  const FtueTracker();

  void step(String id, {required int gamesPlayed});
}

class InertFtueTracker extends FtueTracker {
  const InertFtueTracker();

  @override
  void step(String id, {required int gamesPlayed}) {}
}
