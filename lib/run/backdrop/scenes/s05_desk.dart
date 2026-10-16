import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 5, Giant's Desk (`drawDesk`).
///
/// STUB (WP-W2 ports it): draws nothing over the backdrop's plain sky.
class DeskScene extends BackdropScene {
  const DeskScene();

  @override
  String get name => 'Giant\'s Desk';

  @override
  void draw(Ctx c, Band band) {}
}
