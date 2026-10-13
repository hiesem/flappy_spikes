import '../menu/powerup_slot.dart';
import '../versus/opponent.dart';
import 'director/plans.dart';
import 'elements.dart';

/// Inputs to one run (ARCH §1.1).
class RunSetup {
  const RunSetup({
    required this.seed,
    this.starter = Powerup.none,
    this.opponent,
    this.startHoopIndex = 0,
    this.forced = const [],
    this.forcedRide,
    required this.viewHeight,
    this.enabledOverride,
    this.ignoreGates = false,
  });

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
}
