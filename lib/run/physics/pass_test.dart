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
  const PlaneEvent(this.kind, {this.ring = 0});
  final PlaneEventKind kind;

  /// The ring crossed (pairs: 0 or 1).
  final int ring;

  @override
  String toString() => 'PlaneEvent(${kind.name}, ring $ring)';
}

/// §3.0.4 5 The pass test, in the hoop's local frame: the bird centre goes
/// from local x < 0 ([prev]) to local x ≥ 0 ([now]) while
/// |local y − ring offset| ≤ opening/2 + 7 (between the two rim-end
/// centres, so a bird pressed against the inside of a rim end is through).
/// Crossings of the plane's extension beside the ring, backward crossings
/// (a knock-back) and no crossing return null. Pure.
PlaneEvent? testPlane(HoopFrame f, BirdCircle prev, BirdCircle now) {
  final p = f.toLocal(prev.c);
  final l = f.toLocal(now.c);
  if (!(p.x < 0 && l.x >= 0)) return null;
  for (var i = 0; i < f.rings.length; i++) {
    if ((l.y - f.rings[i]).abs() <= f.reach) {
      return PlaneEvent(PlaneEventKind.pass, ring: i);
    }
  }
  return null;
}

/// §3.0.4 5 Miss: the bird is fully past the ring — bird centre − r > the
/// ring's rightmost point ([HoopFrame.rightmostX]). Pure.
bool isFullyPast(HoopFrame f, BirdCircle b) => b.c.x - b.r > f.rightmostX;
