import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import 'seam.dart';
import 'water.dart';

/// PRD-2.4 §3.3 seam 8, Rising out (Underwater → Dreamland; older move
/// `emerge`): the sea slides down and the dream's puffy cloud bank rests on
/// the water. Ported 1:1 (WP-W1, WP-W3).
class RisingSeam extends OlderSeam {
  const RisingSeam();

  @override
  String get title => 'Rising out';

  @override
  void move(Ctx c, SceneDrawer w, int ga, int gb, double q) {
    final t = c.t, lf = lift(c);
    // both cloud rows travel together
    double sh(Band b) => -(1 - ek(b == Band.far ? Band.near : b, q)) * lf;
    final ys = 590 + sh(Band.near), lead = lf - 590;
    w.group(c, gb, const [Band.sky, Band.far, Band.mid], sh);
    c.save();
    // `lead` less the view's extra height: `sea` holds the middle colour
    // over it, so at the start the gradient is the Underwater sky's
    sea(c, ys, t, lead - c.ext);
    rays(c, t, ys + lead * (1 - ek(Band.near, q)));
    c.vert = true;
    w.group(c, ga, Band.layers, (b) => ek(b, q) * lf);
    c.vert = false;
    c.restore();
    waterline(c, ys, t);
    w.group(c, gb, const [Band.near], sh);
    // a puffy underside where the cloud bank meets the water
    final y0 = 566 + sh(Band.near), xo = c.cam * .3;
    if (y0 < kVH + 40) {
      for (var k = ((c.xl + xo) / 22).floor() - 2; k <= ((c.xr + xo) / 22).floor() + 2; k++) {
        final x = k * 22 - xo, r = 11 + hash(k * 11 + 4) * 10, bob = math.sin(t * .7 + k) * 1.5;
        c.fillStyle = const Color(0xFFE8E8E8);
        c.circ(x + 11, y0 + r * .55 + 4 + bob, r * .8);
        c.fillStyle = const Color(0xFFE1E1E1);
        c.circ(x, y0 + r * .3 + bob, r);
      }
    }
  }
}
