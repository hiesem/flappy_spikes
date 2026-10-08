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
/// normal; if it moves into the rim relative to the rim's own velocity
/// ([HoopFrame.velocity]) its velocity is reflected along the normal with
/// [restitution]; the tangential part is unchanged. Ends are processed in
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
      final rvx = v.x - f.velocity.x, rvy = v.y - f.velocity.y;
      final vn = rvx * n.x + rvy * n.y;
      final bounced = vn < 0;
      if (bounced) {
        v
          ..x -= (1 + restitution) * vn * n.x
          ..y -= (1 + restitution) * vn * n.y;
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
        ),
      );
    }
  }
  if (contacts == null) return null;
  return RimResult(pos, v, contacts);
}

/// §3.0.4 3 The rim-hit spin: one full turn over 0.35 s, its direction from
/// the bird's vertical motion (rising: counter-clockwise).
double rimSpinVelocity(double vy) =>
    (vy < 0 ? -1 : 1) * 2 * math.pi / PhysicsConfig.rimSpinSeconds;
