import 'dart:math' as math;
import 'dart:ui';

import 'package:flappy_spikes/run/backdrop/backdrop_ctx.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_helpers.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_scene.dart';

/// TEST FIXTURE (WP-W3): the prototype's `drawOrigami` near band (the
/// folded-paper river with its boats) and mid peaks, so the seam-7 start
/// (PRD-2.4 §3.3 known issue) can be checked on this branch while the real
/// Paper Origami port (WP-W2, `scenes/s07_origami.dart`) is built in
/// parallel. Not the game's scene: once W2's port is merged the world's own
/// no-jump test covers seam 7 with it.
class OrigamiFixture extends BackdropScene {
  const OrigamiFixture();

  @override
  String get name => 'Paper Origami (fixture)';

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.mid:
        _peaks(c, cam * .18, 64, 1011, 514, 60, 120, const Color(0xFFDEDEDE),
            const Color(0xFFD5D5D5));
      case Band.far:
        _peaks(c, cam * .06, 80, 1001, 500, 130, 230, const Color(0xFFE9E9E9),
            const Color(0xFFE1E1E1));
      case Band.near:
        final ro = cam * .3;
        c.fillStyle = const Color(0xFFE4E4E4);
        gfillSink(c, 516);
        each(c, ro, 24, 1031, (x, r, k) {
          final b = math.sin(t * 1.5 + k * .8) * 1.5;
          c.fillStyle = k.isOdd ? const Color(0xFFDADADA) : const Color(0xFFE0E0E0);
          c.beginPath();
          c.moveTo(x, 528 + b);
          c.lineTo(x + 12, 516 + b);
          c.lineTo(x + 24, 528 + b);
          c.closePath();
          c.fill();
        });
        each(c, ro, 150, 1041, (x, r, k) {
          if (r() < .4) return;
          c.save();
          c.translate(x + r() * 60, 514 + math.sin(t * 1.5 + k) * 2);
          c.rotate(math.sin(t * 1.2 + k) * .06);
          c.fillStyle = const Color(0xFFF5F5F5);
          c.beginPath();
          c.moveTo(-8, -6);
          c.lineTo(0, -24);
          c.lineTo(8, -6);
          c.closePath();
          c.fill();
          c.fillStyle = const Color(0xFFFAFAFA);
          c.beginPath();
          c.moveTo(-16, -6);
          c.lineTo(16, -6);
          c.lineTo(10, 4);
          c.lineTo(-10, 4);
          c.closePath();
          c.fill();
          c.restore();
        });
      case Band.sky:
      case Band.front:
        return;
    }
  }

  static void _peaks(Ctx c, double off, double sp, int seed, double base, double hmin,
      double hmax, Color l, Color rc) {
    each(c, off, sp, seed, (x, r, k) {
      if (r() < .15) return;
      final px = x + r() * 30, h = hmin + r() * (hmax - hmin), w = h * (.8 + r() * .4);
      final sk = (r() - .5) * w * .3, mid = px + sk * .4 + w * .08;
      final tx = px + sk * c.fold, ty = base - h * c.fold;
      c.fillStyle = l;
      c.beginPath();
      c.moveTo(px - w / 2, base);
      c.lineTo(tx, ty);
      c.lineTo(mid, base);
      c.closePath();
      c.fill();
      c.fillStyle = rc;
      c.beginPath();
      c.moveTo(mid, base);
      c.lineTo(tx, ty);
      c.lineTo(px + w / 2, base);
      c.closePath();
      c.fill();
    });
    c.fillStyle = l;
    c.fillRect(c.xl, base - .5, c.xr - c.xl, kVH + 60 - base);
  }
}
