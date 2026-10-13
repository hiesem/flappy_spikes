import 'dart:math' as math;

import '../config/run_config.dart';
import '../run_state.dart';

/// The bird's forward motion (§3.0.1, §3.0.4 4). Forge2D integrates only the
/// vertical motion (gravity 1250, a flap sets vy −370, max fall 650 —
/// `Bird`); the forward speed is a real velocity in [RunState.forwardSpeed]
/// and the camera follows it (the world scrolls at the bird's forward
/// speed, PRD §7).
abstract final class BirdMotion {
  /// §3.0.1 / PRD-2.3 §14.4 cruise by hoop index (`curve_speed`).
  static double cruise(int hoopIndex) => RunConfig.cruise(hoopIndex);

  /// §3.0.4 4 the forward speed moves toward [cruise] at 2000 pt/s² (after a
  /// knock-back it recovers; above cruise it settles back).
  static double recover(double forward, double cruise, double dt) {
    final step = RunConfig.forwardRecovery * dt;
    return forward < cruise
        ? math.min(cruise, forward + step)
        : math.max(cruise, forward - step);
  }

  /// One step of the forward motion: recovery toward the cruise of the
  /// current hoop index (PRD-2.3 §14.4), then the camera advance. Returns the distance moved.
  static double step(RunState s, double dt) {
    // region WP-3c — §3.23 the spring's flap lock runs out with game time
    if (s.flapLock > 0) s.flapLock = math.max(0, s.flapLock - dt);
    // endregion WP-3c
    // region WP-3a — the comet boost scales the cruise (PRD-2 §3.8)
    final target = cruise(s.hoopIndex) * s.cruiseMult;
    // endregion WP-3a
    s.forwardSpeed = recover(s.forwardSpeed, target, dt);
    final dx = s.forwardSpeed * dt;
    s.camX += dx;
    return dx;
  }
}
