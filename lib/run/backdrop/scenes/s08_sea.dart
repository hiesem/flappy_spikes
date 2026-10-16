import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 8, Underwater (`drawSea`).
///
/// STUB (WP-W3 ports it): draws nothing over the backdrop's plain sky.
class SeaScene extends BackdropScene {
  const SeaScene();

  @override
  String get name => 'Underwater';

  @override
  void draw(Ctx c, Band band) {}
}
