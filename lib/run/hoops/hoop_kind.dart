import 'package:flame/components.dart';

import '../director/plans.dart';
import '../elements.dart';
import '../run_context.dart';
import '../run_state.dart';
import 'hoop.dart';

export '../director/plans.dart' show HoopKindId;

/// §3.0.4 how a kind's rim ends react.
enum RimMode { bounce, deadly, ignored }

/// What a kind decides when the bird reaches the plane (§3.0.4 5 / 7).
enum PlaneVerdict { pass, mistake }

/// A rim-end contact (WP-1a's `RimContact` carries more; kinds see this).
class RimTouch {
  const RimTouch({required this.point, required this.normal, this.ring = 0});
  final Vector2 point;

  /// From the rim end towards the bird.
  final Vector2 normal;
  final int ring;
}

/// A resolved pass (§3.0.4).
class PassInfo {
  const PassInfo({
    required this.ring,
    this.perfect = false,
    this.rimTouched = false,
    this.duringRide = false,
  });
  final int ring;
  final bool perfect;
  final bool rimTouched;
  final bool duringRide;
}

/// Where the autopilot aims (§7: switch first, nearer pair ring, spring
/// launch line, saw centre).
class AutopilotTarget {
  const AutopilotTarget(this.y, {this.preTarget});

  /// Screen y to hold when crossing the plane.
  final double y;

  /// Optional earlier point (track x, y) to fly through first (the switch).
  final Vector2? preTarget;
}

/// One hoop kind's rules as a small strategy object (PRD-2 §7, ARCH §2.5).
/// Generic pass / miss / rim handling lives in the run controller (WP-1a);
/// kinds only add their specifics.
abstract class HoopKind {
  HoopKindId get id;
  ElementId get element => id.element;

  /// normal, bullseye, luckySpin, train, rideRing: yes; saw, switch, FEVER,
  /// pair, spring, portal: no (call, ARCH §2.5).
  bool get usesTierLook;

  /// Saw: +28 (the director already includes it in `SlotPlan.opening`).
  double extraOpening(SlotPlan p) => 0;

  /// Rides → ignored; saw → deadly; else bounce.
  RimMode rimMode(Hoop h, RunState s) =>
      s.ride != null ? RimMode.ignored : RimMode.bounce;

  /// Saw: 5 (Live Wire / Frost) or 6 (Black Hole).
  double rimRadius(Hoop h) => 7;

  void onSpawn(Hoop h, RunContext c) {}

  /// Adds the back / front visuals (via `RingPainter` or design painters).
  void buildVisual(Hoop h, RunContext c);

  /// A closed switch → [PlaneVerdict.mistake].
  PlaneVerdict onPlane(Hoop h, int ring, RunContext c) => PlaneVerdict.pass;

  void onPass(Hoop h, PassInfo p, RunContext c) {}
  void onMiss(Hoop h, RunContext c) {}
  void onRim(Hoop h, RimTouch rc, RunContext c) {}
  void update(Hoop h, double dt, RunContext c) {}

  /// Default: the centre of the ring nearest the bird's current y.
  AutopilotTarget autopilotTarget(Hoop h, RunState s, double birdY) {
    var best = h.position.y + h.rings.first;
    for (final o in h.rings) {
      final y = h.position.y + o;
      if ((y - birdY).abs() < (best - birdY).abs()) best = y;
    }
    return AutopilotTarget(best);
  }
}
