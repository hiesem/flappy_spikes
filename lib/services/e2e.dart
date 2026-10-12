import '../run/director/plans.dart';
import '../run/elements.dart';

/// `--dart-define=FS_E2E=true`: the Pixel 8 `integration_test` build
/// (ARCH §7.3): a fixed run seed, fake rewarded ads with the visible
/// overlay (succeed), the App Check debug provider (WP-5b) and [E2EHooks].
const bool kE2E = bool.fromEnvironment('FS_E2E');

/// `--dart-define=FS_E2E_SEED=n`: the fixed run seed of e2e builds.
const int kE2ESeed = int.fromEnvironment('FS_E2E_SEED', defaultValue: 7);

/// `--dart-define=FS_APPCHECK_DEBUG_TOKEN=…` (WP-5b).
const String kAppCheckDebugToken = String.fromEnvironment(
  'FS_APPCHECK_DEBUG_TOKEN',
);

/// Hooks an `integration_test` sets before starting a run. Read by
/// `FlappySpikesGame` only when [kE2E] (or a test) enables them.
abstract final class E2EHooks {
  /// Elements forced into the next run (debug force queue).
  static final List<ElementId> force = [];

  /// The next run's `startHoopIndex`.
  static int startHoopIndex = 0;

  /// The next run's forced portal ride.
  static RideId? forcedRide;

  /// Fake clock offset for reminder tests (WP-4b).
  static Duration clockOffset = Duration.zero;

  /// Skip the VS intro wait (WP-5b).
  static bool skipVersusIntroWait = false;

  /// The autopilot plays the run (integration tests drive it).
  static bool autopilot = false;

  /// PRD-2.2 §7.5.6: E2E builds run without the gameplay banner unless a
  /// test asks for it.
  static bool banner = false;

  static void reset() {
    force.clear();
    startHoopIndex = 0;
    forcedRide = null;
    clockOffset = Duration.zero;
    skipVersusIntroWait = false;
    autopilot = false;
    banner = false;
  }
}
