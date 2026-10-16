import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 7, Paper Origami (`drawOrigami`).
///
/// STUB (WP-W2 ports it): draws nothing over the backdrop's plain sky.
class OrigamiScene extends BackdropScene {
  const OrigamiScene();

  @override
  String get name => 'Paper Origami';

  @override
  void draw(Ctx c, Band band) {}
}
