import 'dart:math' as math;

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_scene.dart';
import 'seam.dart';
import 'water.dart';

/// PRD-2.4 §3.3 seam 7, The dive (Paper Origami → Underwater; older move
/// `dive`): the camera sinks, the paper river's surface carries on as the
/// sea's surface and light rays fall from it.
///
/// Ported 1:1 by WP-W1. The PRD's known issue (a small jump at the start,
/// where the paper river becomes water) is WP-W3's to fix here.
class DiveSeam extends OlderSeam {
  const DiveSeam();

  @override
  String get title => 'The dive';

  @override
  void move(Ctx c, SceneDrawer w, int ga, int gb, double q) {
    final t = c.t, lf = lift(c);
    final ys = 528 - ek(Band.near, q) * lf;
    w.group(c, ga, Band.layers, (b) => -ek(b, q) * lf);
    c.save();
    sea(c, ys, t);
    rays(c, t, ys + 190 * ek(Band.near, q));
    c.vert = true;
    w.group(c, gb, Band.layers, (b) => (1 - ek(b, q)) * lf);
    c.vert = false;
    c.restore();
    waterline(c, ys, t);
    wraps(c, 40 - c.cam * .3 + t * 10, 150, 0, (x) {
      paperBoat(c, x, wave(x, ys, t) - 1, math.sin(t * 1.4 + x * .01) * .08);
    });
  }
}
