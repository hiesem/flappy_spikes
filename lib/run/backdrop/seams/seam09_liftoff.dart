import '../backdrop_ctx.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import 'seam.dart';
import 'water.dart';

/// PRD-2.4 §3.3 seam 9, Lift-off (Dreamland → Space; older move `ascend`):
/// the ground drops away, then the islands, and space comes down. Ported
/// 1:1 (WP-W1, WP-W3).
class LiftOffSeam extends OlderSeam {
  const LiftOffSeam();

  @override
  String get title => 'Lift-off';

  @override
  void move(Ctx c, SceneDrawer w, int ga, int gb, double q) {
    final lf = lift(c);
    // the dream's cloud rows sink together
    w.group(c, ga, Band.layers, (b) => ek(b == Band.far ? Band.near : b, q) * lf);
    w.group(c, gb, const [Band.sky, Band.far, Band.mid], (b) => -(1 - ek(b, q)) * lf);
    w.group(c, gb, const [Band.near], (b) => (1 - smooth((q - .6) / .4)) * 130);
  }
}
