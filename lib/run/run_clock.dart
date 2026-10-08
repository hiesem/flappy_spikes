/// `runClock` (PRD-2 §3.0.1): the one run timer of 2.0. It runs in play and
/// rides, stops in pause / the revive offer / the phoenix rise, and slows
/// with the Hourglass (it counts game time).
class RunClock {
  /// Seconds of run time.
  double t = 0;

  /// Stopped until the first tap; the controller stops it for pause /
  /// revive / phoenix and at death.
  bool running = false;

  /// Hourglass: 0.45 (eased by WP-3f), else 1. `RunScaledWorld` applies
  /// it to the whole run world, so [tick] already receives game time.
  double timeScale = 1;

  /// Adds [gameDt] (real dt × [timeScale]) while [running].
  void tick(double gameDt) {
    if (running) t += gameDt;
  }
}
