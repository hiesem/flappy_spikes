import '../backdrop_ctx.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 6, Candy Land (`drawCandy`).
///
/// STUB (WP-W2 ports it): draws nothing over the backdrop's plain sky.
class CandyScene extends BackdropScene {
  const CandyScene();

  @override
  String get name => 'Candy Land';

  @override
  void draw(Ctx c, Band band) {}
}
