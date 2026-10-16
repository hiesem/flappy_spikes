import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 4, Clockwork (`drawClock`).
///
/// STUB (WP-W2 ports it): draws nothing over the backdrop's plain sky.
class ClockScene extends BackdropScene {
  const ClockScene();

  @override
  String get name => 'Clockwork';

  @override
  void draw(Ctx c, Band band) {}
}
