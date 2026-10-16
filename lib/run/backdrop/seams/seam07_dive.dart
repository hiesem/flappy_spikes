import 'dart:math' as math;

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import 'seam.dart';
import 'water.dart';

/// PRD-2.4 §3.3 seam 7, The dive (Paper Origami → Underwater; older move
/// `dive`): the camera sinks, the paper river's surface carries on as the
/// sea's surface and light rays fall from it.
///
/// PRD §3.3 known issue (the prototype's start jump): at the window's start
/// the sea, its light rays, the waterline and its paper boats appeared at
/// once over the paper river at y 528. They now fade in over the first
/// [fadeIn] of the move's ease (about 1.3 hoops, while the ground has moved
/// less than 8 pt), so the river turns into water without a jump; from
/// there on the move is the prototype's.
///
/// Tall views: the rays end at y 0 (where the Underwater sky starts them)
/// and the sea gradient meets the Underwater sky's (see `sea`).
class DiveSeam extends OlderSeam {
  const DiveSeam();

  /// The share of the eased progress `q` over which the water fades in
  /// (PRD-2.4 §3.3 seam 7 start fix).
  static const double fadeIn = .05;

  @override
  String get title => 'The dive';

  @override
  void move(Ctx c, SceneDrawer w, int ga, int gb, double q) {
    final t = c.t, lf = lift(c), en = ek(Band.near, q);
    final ys = 528 - en * lf, fade = smooth(q / fadeIn);
    w.group(c, ga, Band.layers, (b) => -ek(b, q) * lf);
    if (fade <= 0) return;
    c.save();
    c.globalAlpha = fade;
    sea(c, ys, t);
    rays(c, t, ys + (190 + c.ext) * en);
    c.globalAlpha = 1;
    c.vert = true;
    w.group(c, gb, Band.layers, (b) => (1 - ek(b, q)) * lf);
    c.vert = false;
    c.restore();
    c.save();
    c.globalAlpha = fade;
    waterline(c, ys, t);
    wraps(c, 40 - c.cam * .3 + t * 10, 150, 0, (x) {
      paperBoat(c, x, wave(x, ys, t) - 1, math.sin(t * 1.4 + x * .01) * .08);
    });
    c.restore();
  }
}
