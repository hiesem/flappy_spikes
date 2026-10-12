import 'package:flame/components.dart';

import 'hoop_frame.dart';

/// What a plane crossing decided (§3.0.4 5 / 7).
enum PlaneEventKind {
  /// Forward crossing between the rim-end centres of a ring.
  pass,

  /// Fully past the ring without a pass: a miss.
  missPast,

  /// A pass crossing on a closed switch ring (the kind decides; the
  /// controller reports it with this kind).
  closedReached,
}

class PlaneEvent {
  const PlaneEvent(this.kind, {this.ring = 0, this.offset = 0});
  final PlaneEventKind kind;

  /// The ring crossed (pairs: 0 or 1).
  final int ring;

  /// PRD-2.2 §30.2 (for §11): the bird centre's local y minus the crossed
  /// ring's offset at the moment of crossing, in the ring's own (moving)
  /// frame (positive = toward the ring's local +y, i.e. below on an
  /// untilted ring).
  final double offset;

  @override
  String toString() => 'PlaneEvent(${kind.name}, ring $ring, offset $offset)';
}

/// §3.0.4 5 The pass test, in the hoop's local frame: the bird centre goes
/// from local x < 0 ([prev]) to local x ≥ 0 ([now]) while
/// |local y − ring offset| ≤ opening/2 + 7 (between the two rim-end
/// centres, so a bird pressed against the inside of a rim end is through).
/// Crossings of the plane's extension beside the ring, backward crossings
/// (a knock-back) and no crossing return null. Pure.
///
/// PRD-2.2 §30.2 relative crossing: [prev] is measured in the ring's pose
/// of the previous physics step ([prevFrame]; null = [f], a still ring)
/// and [now] in its current pose [f], so a ring that moves or turns toward
/// the bird cannot jump its plane over the bird. The local y is
/// interpolated to the crossing (`u = −p.x / (l.x − p.x)`) and checked
/// against each ring's reach. A fast ring ([HoopFrame.substeps]) is tested
/// in sub-steps (pose and bird interpolated). Borderline leans to the
/// player: a crossing at exactly the reach passes, and any in-reach forward
/// crossing in the step wins over one beside the ring.
PlaneEvent? testPlane(
  HoopFrame f,
  BirdCircle prev,
  BirdCircle now, {
  HoopFrame? prevFrame,
}) {
  final pf = prevFrame ?? f;
  final n = HoopFrame.sweepSteps(pf, f, prev, now);
  var a = pf;
  var ba = prev.c;
  for (var k = 1; k <= n; k++) {
    final u = k / n;
    final b = HoopFrame.lerp(pf, f, u);
    final bb = k == n ? now.c : prev.c + (now.c - prev.c) * u;
    final ev = _cross(a, b, ba, bb);
    if (ev != null) return ev;
    a = b;
    ba = bb;
  }
  return null;
}

/// Tolerance for "exactly at the reach" after interpolation (pt).
const double _edgeEps = 1e-9;

PlaneEvent? _cross(HoopFrame a, HoopFrame b, Vector2 ba, Vector2 bb) {
  final p = a.toLocal(ba);
  final l = b.toLocal(bb);
  if (!(p.x < 0 && l.x >= 0)) return null;
  final u = -p.x / (l.x - p.x);
  final y = p.y + u * (l.y - p.y);
  // The interpolated crossing first; then the 2.1 rule (the bird's local y
  // after the step), so a still ring never loses a pass it had (§30.3).
  for (final at in [y, l.y]) {
    for (var i = 0; i < b.rings.length; i++) {
      final off = at - b.rings[i];
      if (off.abs() <= b.reach + _edgeEps) {
        return PlaneEvent(PlaneEventKind.pass, ring: i, offset: off);
      }
    }
  }
  return null;
}

/// §3.0.4 5 Miss: the bird is fully past the ring — bird centre − r > the
/// ring's rightmost point ([HoopFrame.rightmostX]). Pure.
bool isFullyPast(HoopFrame f, BirdCircle b) => b.c.x - b.r > f.rightmostX;
