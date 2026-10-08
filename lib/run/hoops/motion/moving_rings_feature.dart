import '../../run_context.dart';
import '../../run_events.dart';
import '../../run_feature.dart';
import '../hoop.dart';
import 'hoop_motion.dart';
import 'motion_guide.dart';

/// §3.10 / §3.11 angled and moving rings in a run (WP-1b).
///
/// - **Angled:** the director's `SlotPlan.tiltDeg` is the hoop's base angle
///   (the `Hoop` is built rotated around its centre; both halves and every
///   ring decoration rotate with it). Nothing else changes: same opening
///   before the tilt, the pass test works in the hoop's local frame.
/// - **Moving:** when a hoop with a `MotionSpec` spawns (just off-screen
///   right), it gets its [HoopMotion] (`Hoop.motion`) and its [MotionGuide]
///   in the hoop-back layer at the home position. Every frame the motion is
///   posed at the current `runClock` — it stops with the clock (pause,
///   revive offer, tumble), slows with the Hourglass, and keeps going in
///   rides (§3.0.3 "tilted / moving hoops keep their motion"). The guide
///   leaves (and fades) with its hoop.
class MovingRingsFeature extends RunFeature {
  RunContext? _c;
  final List<(Hoop, HoopMotion, MotionGuide)> _moving = [];

  /// The moving hoops alive in the run (tests, debug).
  Iterable<Hoop> get movingHoops => _moving.map((e) => e.$1);

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<HoopSpawned>(_onSpawn);
  }

  void _onSpawn(HoopSpawned e) {
    final c = _c;
    final spec = e.plan.motion;
    if (c == null || spec == null) return;
    final h = e.hoop;
    final motion = HoopMotion.fromSpec(spec);
    h.motion = motion;
    motion.update(h, c.s.runClock);
    final guide = MotionGuide(
      motion: motion,
      opening: h.opening,
      home: h.basePosition,
      color: () => c.game.foregroundColor,
    );
    c.layers.back.add(guide);
    _moving.add((h, motion, guide));
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    final t = c.s.runClock;
    for (var i = _moving.length - 1; i >= 0; i--) {
      final (h, motion, guide) = _moving[i];
      if (h.isRemoving || h.isRemoved) {
        // Culled or cleared ahead (portal ride): the guide goes with it.
        guide.removeFromParent();
        _moving.removeAt(i);
        continue;
      }
      motion.update(h, t);
    }
  }

  @override
  void detach() {
    for (final (_, _, g) in _moving) {
      g.removeFromParent();
    }
    _moving.clear();
    _c = null;
  }
}
