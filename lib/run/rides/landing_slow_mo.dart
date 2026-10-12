import 'dart:math' as math;

import '../config/comet_config.dart';
import '../run_context.dart';

/// PRD-2.2 §17 the comet landing's quiet slow motion: from the moment
/// control returns the run world runs at 0.5× ([CometConfig.landingScale])
/// for 0.8 s, then eases back to 1× over 0.7 s (smoothstep), timed in
/// **real** seconds (1.5 s on the clock). It slows what the Hourglass slows
/// (`RunState.timeScale` / `RunClock.timeScale`: world, physics, gravity,
/// the flap, scroll, run timers; the HUD stays real time) but is quiet: no
/// vignette, no tick-tock or tape sweep, no ghost trail, and the music keeps
/// its pitch. With the Hourglass at the same time the lower scale wins
/// frame by frame (`RunState.hourglassScale` / `landingScale`). Pause
/// freezes it (the world does not update); a death, a revive or a portal
/// ride stops it at once.
class LandingSlowMo {
  LandingSlowMo(this.c);

  final RunContext c;

  /// Real seconds since the landing started (< 0: not running).
  double t = -1;

  bool get active => t >= 0;

  /// Total length (s of real time).
  static const double length = CometConfig.landingHold + CometConfig.landingEase;

  /// The landing's time scale [t] real seconds after control returned.
  static double scaleAt(double t) {
    if (t < 0 || t >= length) return 1;
    if (t < CometConfig.landingHold) return CometConfig.landingScale;
    final u = ((t - CometConfig.landingHold) / CometConfig.landingEase)
        .clamp(0.0, 1.0);
    final k = u * u * (3 - 2 * u);
    return CometConfig.landingScale + (1 - CometConfig.landingScale) * k;
  }

  void start() {
    t = 0;
    c.s.cometLanding = true;
    _write(scaleAt(0));
  }

  /// One frame of [realDt] real seconds.
  void step(double realDt) {
    if (!active) return;
    t += realDt;
    if (t >= length) {
      stop();
    } else {
      _write(scaleAt(t));
    }
  }

  /// Ends the landing now (its end, a death, a revive, a portal ride).
  void stop() {
    if (!active) return;
    t = -1;
    c.s.cometLanding = false;
    _write(1);
  }

  void _write(double v) {
    final s = c.s..landingScale = v;
    final eff = math.min(v, s.hourglassScale);
    s.timeScale = eff;
    c.run.clock.timeScale = eff;
  }
}
