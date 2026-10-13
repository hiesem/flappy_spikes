import 'dart:math' as math;

import 'package:flame/components.dart';

import '../config/physics_config.dart';
import '../config/run_config.dart';
import 'hoop_frame.dart';

/// One rim-end contact (§3.0.4 1–3, 6).
class RimContact {
  RimContact({
    required this.ring,
    required this.side,
    required this.end,
    required this.normal,
    required this.overlap,
    required this.inside,
    required this.bounced,
    this.soft = false,
  });

  /// Ring index and side (−1 top end, +1 bottom end).
  final int ring;
  final int side;

  /// The rim-end centre (track coordinates).
  final Vector2 end;

  /// Unit normal from the rim end towards the bird.
  final Vector2 normal;

  /// How deep the circles overlapped before the push-out (pt).
  final double overlap;

  /// §3.0.4 6 The bird was on the inside half (between the two rim-end
  /// centres along the ring): the push-out sends it into the opening.
  final bool inside;

  /// The bird moved into the rim (relative to the rim's own velocity), so
  /// its velocity was reflected.
  final bool bounced;

  /// Owner 2026-10-13: the hit from inside the gap ended with the soft
  /// bump ([RunConfig.rimSoftBump]) instead of the reflection; the bird
  /// then hangs in low gravity ([RunConfig.rimHangSeconds]).
  final bool soft;

  /// The point on the rim surface (sparks).
  Vector2 get point => end + normal * RunConfig.rimRadius;
}

/// The outcome of [collideRims]: the bird's new centre and velocity plus
/// every contact, in order.
class RimResult {
  RimResult(this.position, this.velocity, this.contacts);
  final Vector2 position;
  final Vector2 velocity;
  final List<RimContact> contacts;

  bool get bounced => contacts.any((c) => c.bounced);
}

/// §3.0.4 1–2: the bird circle against every rim-end circle of [f] (plain
/// math, no Forge2D). On overlap the bird is pushed out along the contact
/// normal; if it moves into the rim relative to the rim end's own velocity
/// ([HoopFrame.velocityAt]: centre motion plus rotation) its velocity is reflected along the normal with
/// [restitution]; the tangential part is unchanged. Owner 2026-10-13: a
/// hit from inside the gap instead ends with [RunConfig.rimSoftBump] away
/// from the rim along the ring (local x kept). Ends are processed in
/// order, each against the already-corrected bird (prototype `hoopStep`).
/// Returns null without contact. Pure.
RimResult? collideRims(
  HoopFrame f,
  BirdCircle b,
  Vector2 vel, {
  double restitution = RunConfig.rimRestitution,
}) {
  var pos = b.c.clone();
  final v = vel.clone();
  List<RimContact>? contacts;
  final md = b.r + f.rimR;
  for (var ring = 0; ring < f.rings.length; ring++) {
    for (final side in const [-1, 1]) {
      final end = f.rimEnd(ring, side);
      final dx = pos.x - end.x, dy = pos.y - end.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d >= md || d == 0) continue;
      final n = Vector2(dx / d, dy / d);
      final overlap = md - d;
      final local = f.toLocal(pos);
      final inside = (local.y - f.rings[ring]).abs() < f.reach;
      pos = pos + n * overlap;
      // §3.0.4 2 relative to the rim end's own velocity (centre motion
      // plus rock / swing / orbit rotation).
      final rv = f.velocityAt(end);
      final rvx = v.x - rv.x, rvy = v.y - rv.y;
      final vn = rvx * n.x + rvy * n.y;
      final bounced = vn < 0;
      var soft = false;
      if (bounced) {
        // Owner 2026-10-13 soft rim bump: a hit from inside the gap (the
        // top rim while rising, the bottom rim while falling) loses its
        // along-ring speed toward the rim and gets a small push away from
        // it instead of the hard reflection; forward speed is kept.
        final c = math.cos(f.tilt), s = math.sin(f.tilt);
        final nlx = n.x * c + n.y * s;
        final nla = (-n.x * s + n.y * c) * -side; // into the gap
        final rly = -rvx * s + rvy * c;
        // Owner 2026-10-13 (2.3.0 (14)): every hit from inside the gap is
        // soft, slanted ones too; only a head-on hit (the normal pointing
        // back more than 45°, the bird in front of the rim end) and hits
        // from outside keep the hard reflection.
        final headOn = nlx < 0 && -nlx > nla;
        soft = inside && nla > 0 && !headOn && rly * side > 0;
        if (soft) {
          final vlx = v.x * c + v.y * s;
          final rvl = -rv.x * s + rv.y * c;
          final vly = rvl - side * RunConfig.rimSoftBump;
          v
            ..x = vlx * c - vly * s
            ..y = vlx * s + vly * c;
        } else {
          v
            ..x -= (1 + restitution) * vn * n.x
            ..y -= (1 + restitution) * vn * n.y;
        }
      }
      (contacts ??= []).add(
        RimContact(
          ring: ring,
          side: side,
          end: end,
          normal: n,
          overlap: overlap,
          inside: inside,
          bounced: bounced,
          soft: soft,
        ),
      );
    }
  }
  if (contacts == null) return null;
  return RimResult(pos, v, contacts);
}

/// PRD-2.2 §30.2 [collideRims] for a ring that moved from [prevFrame] to
/// [f] during the step while the bird went [prev] → [now]. The current
/// pose decides first (exactly [collideRims]: still rings and slow rings
/// are unchanged). Without contact there, a fast ring
/// ([HoopFrame.sweepSteps]) is checked at its intermediate sub-step poses
/// against the interpolated bird, so a rim end that sweeps across the bird
/// within one step still registers a touch (no tunnelling). Such a contact
/// is resolved at that sub-step (push-out and reflection) and the push-out
/// carried to [now]. Pure.
RimResult? collideRimsSwept(
  HoopFrame? prevFrame,
  HoopFrame f,
  BirdCircle prev,
  BirdCircle now,
  Vector2 vel, {
  double restitution = RunConfig.rimRestitution,
}) {
  final hit = collideRims(f, now, vel, restitution: restitution);
  if (hit != null || prevFrame == null) return hit;
  final n = HoopFrame.sweepSteps(prevFrame, f, prev, now);
  for (var k = 1; k < n; k++) {
    final u = k / n;
    final fk = HoopFrame.lerp(prevFrame, f, u);
    final bk = prev.c + (now.c - prev.c) * u;
    final res = collideRims(
      fk,
      BirdCircle(bk, now.r),
      vel,
      restitution: restitution,
    );
    if (res != null) {
      return RimResult(now.c + (res.position - bk), res.velocity, res.contacts);
    }
  }
  return null;
}

/// §3.0.4 3 The rim-hit spin: one full turn over 0.35 s, its direction from
/// the bird's vertical motion (rising: counter-clockwise).
double rimSpinVelocity(double vy) =>
    (vy < 0 ? -1 : 1) * 2 * math.pi / PhysicsConfig.rimSpinSeconds;
