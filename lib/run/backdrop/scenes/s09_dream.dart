import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 9, Dreamland (`drawDream`).
///
/// STUB (WP-W3 ports it): draws nothing over the backdrop's plain sky.
class DreamScene extends BackdropScene {
  const DreamScene();

  @override
  String get name => 'Dreamland';

  @override
  void draw(Ctx c, Band band) {}
}
