import '../config/physics_config.dart';
import '../run_geometry.dart';
import 'hoop_frame.dart';

/// Which strip the bird touched.
enum SpikeSide { top, floor }

/// The current top / floor tooth lines (squeeze-aware through
/// [RunGeometry]) and the spike contact (§3.1 "contact = game over") plus
/// the save bounce of §3.0.5 (ARCH §1.4). WP-3g drives the squeeze inset
/// through `RunState.squeeze.inset`, which [RunGeometry] already reads.
class SpikeWalls {
  SpikeWalls(this.geo);

  final RunGeometry geo;

  /// The top tooth line (screen y of the tips).
  double get top => geo.topTooth;

  /// The floor tooth line.
  double get floor => geo.floorTooth;

  /// The inset of each line from its unsqueezed position (pt).
  double get squeezeInset => geo.state.squeeze.inset;

  /// §3.1 the strip the bird circle touches, or null.
  SpikeSide? touches(BirdCircle b) {
    if (b.c.y - b.r <= top - PhysicsConfig.spikeContactInset) {
      return SpikeSide.top;
    }
    if (b.c.y + b.r >= floor + PhysicsConfig.spikeContactInset) {
      return SpikeSide.floor;
    }
    return null;
  }

  /// §3.0.5 save bounce (extra life / shield / invulnerable): the bird is put
  /// back on the screen side of the line; top → sent down at 30 % of its
  /// speed, floor → vy = −222 pt/s. Returns (y, vy).
  (double, double) saveBounce(SpikeSide side, double r, double vy) =>
      switch (side) {
        SpikeSide.top => (
          top + r + 0.01,
          vy.abs() * PhysicsConfig.topSaveRestitution,
        ),
        SpikeSide.floor => (floor - r - 0.01, PhysicsConfig.floorSaveVelocity),
      };
}
