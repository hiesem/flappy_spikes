import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 10, Space (`drawSpace`).
///
/// STUB (WP-W3 ports it): draws nothing over the backdrop's plain sky.
class SpaceScene extends BackdropScene {
  const SpaceScene();

  @override
  String get name => 'Space';

  @override
  void draw(Ctx c, Band band) {}
}
