import '../backdrop_ctx.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import 'seam.dart';
import 'water.dart';

/// PRD-2.4 §3.3 seam 10, Homecoming (Space → Nest Canopy; older move
/// `descend`): space lifts away and the treetops rise from below. Ported
/// 1:1 (WP-W1, WP-W3). It is not played in a run's first loop
/// (hoops 0–19 are pure Nest Canopy, see `BackdropWorld`).
class HomecomingSeam extends OlderSeam {
  const HomecomingSeam();

  @override
  String get title => 'Homecoming';

  @override
  void move(Ctx c, SceneDrawer w, int ga, int gb, double q) {
    final ln = liftNest(c);
    w.group(c, ga, const [Band.sky, Band.far, Band.mid], (b) => -ek(b, q) * ln);
    w.group(c, ga, const [Band.near], (b) => smooth(q / .4) * 130);
    w.group(c, gb, Band.layers, (b) => (1 - ek(b, q)) * ln);
  }
}
