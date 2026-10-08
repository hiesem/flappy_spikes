import 'mistakes.dart';
import 'run_context.dart';

/// A run feature (streak, egg, squeeze, …; ARCH §2.6). Features never call
/// each other: they read `RunState`, react to `RunEvent`s and act through
/// the [RunContext] sinks.
abstract class RunFeature {
  /// Subscribe to events; create HUD parts.
  void attach(RunContext c);

  void update(double gameDt, double realDt) {}

  /// E.g. lose egg / piggy / jar; end timed powerups.
  void onDeath(Mistake m) {}

  /// E.g. the squeeze opens in 0.5 s.
  void onRevive() {}

  void detach() {}
}
