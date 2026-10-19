import 'package:flame/components.dart';

import 'config/run_config.dart';
import 'run_state.dart';

/// Band / tooth-line / safe-line math of a run (§3.0.1 screen heights,
/// §3.0.2 band rule; ARCH §1.1).
class RunGeometry {
  RunGeometry(this.state, {this.stripHeight = RunConfig.stripHeight});

  final RunState state;

  /// 44 pt strips (§3.0.9 #1).
  final double stripHeight;

  double get viewHeight => state.viewHeight;

  /// Current top tooth line (squeeze-aware).
  double get topTooth => stripHeight + state.squeeze.inset;

  /// Current floor tooth line (squeeze-aware).
  double get floorTooth => viewHeight - stripHeight - state.squeeze.inset;

  /// The normal band between the un-squeezed tooth lines (623 pt at 711).
  double get band => viewHeight - 2 * stripHeight;

  /// Screen y at fraction [f] of the normal band.
  double fraction(double f) => stripHeight + f * band;

  /// §3.0.1 the normal bird position (70, viewHeight / 2) on screen.
  Vector2 normalBirdPosition() => Vector2(RunConfig.birdX, viewHeight / 2);

  /// Screen → track coordinates.
  Vector2 toTrack(Vector2 screen) =>
      Vector2(screen.x + state.camX, screen.y + state.camY);

  /// Track → screen coordinates.
  Vector2 toScreen(Vector2 track) =>
      Vector2(track.x - state.camX, track.y - state.camY);
}
