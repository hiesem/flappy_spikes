import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 7, Paper Origami (`drawOrigami`, "9. Paper Origami"):
/// fold creases in the page, folded paper peaks (which pop up from the page
/// while seam 6 sets `c.fold` < 1), paper cranes, and a folded-paper river
/// with paper boats.
class OrigamiScene extends BackdropScene {
  const OrigamiScene();

  @override
  String get name => 'Paper Origami';

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        // fold creases in the page
        c.strokeStyle = const Color(0xFFEAEAEA);
        c.lineWidth = 1;
        c.beginPath();
        final m0 = mark(c, -160);
        c.moveTo(m0 - 960, -660);
        c.lineTo(m0 + 1280, 1260);
        c.moveTo(m0 + 1280, -900);
        c.lineTo(m0 - 960, 1410);
        c.moveTo(m0 + 160, c.yTop);
        c.lineTo(m0 + 160, kVH);
        c.stroke();
      case Band.far:
        _peaksBand(c, 701, cam * .06, 80, 1001, 500, 130, 230, const Color(0xFFE9E9E9),
            const Color(0xFFE1E1E1));
        each(c, cam * .1 + t * 14, 210, 1021, (x, r, k) {
          if (r() < .35) return;
          final cx = x + r() * 60, cy = 110 + r() * 170 + math.sin(t * 1.2 + k) * 6;
          crane(c, cx, cy, .9 + r() * .4, math.sin(t * 3 + k * 1.7));
        });
      case Band.mid:
        _peaksBand(c, 702, cam * .18, 64, 1011, 514, 60, 120, const Color(0xFFDEDEDE),
            const Color(0xFFD5D5D5));
      case Band.near:
        // folded-paper river with paper boats
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
          c.strokeStyle = const Color(0xFFDADADA);
          c.lineWidth = .8;
          c.beginPath();
          c.moveTo(0, -24);
          c.lineTo(0, -6);
          c.stroke();
          c.fillStyle = const Color(0xFFFAFAFA);
          c.beginPath();
          c.moveTo(-16, -6);
          c.lineTo(16, -6);
          c.lineTo(10, 4);
          c.lineTo(-10, 4);
          c.closePath();
          c.fill();
          c.fillStyle = const Color(0xFFDDDDDD);
          c.beginPath();
          c.moveTo(-16, -6);
          c.lineTo(-7, -6);
          c.lineTo(-10, 4);
          c.closePath();
          c.fill();
          c.restore();
        });
      case Band.front:
        return;
    }
  }

  /// A peaks band: a cached strip while the peaks stand (`fold` 1), drawn
  /// directly while seam 6 pops them up from the page.
  static void _peaksBand(Ctx c, int key, double off, double sp, int seed, double base,
      double hmin, double hmax, Color l, Color r) {
    if (c.fold >= 1) {
      c.strip(key, off, (off) => peaks(c, off, sp, seed, base, hmin, hmax, l, r, 1));
    } else {
      peaks(c, off, sp, seed, base, hmin, hmax, l, r, c.fold);
    }
  }

  /// `peaks(off, sp, seed, base, hmin, hmax, L, R)`: folded paper peaks, lit
  /// side [l] and shade [r], with the page below them in [l]. [fold] < 1
  /// while the peaks pop up from the page (`G.fold`, seam 6).
  static void peaks(Ctx c, double off, double sp, int seed, double base, double hmin,
      double hmax, Color l, Color rc, double fold) {
    each(c, off, sp, seed, (x, r, k) {
      if (r() < .15) return;
      final px = x + r() * 30, h = hmin + r() * (hmax - hmin), w = h * (.8 + r() * .4);
      final sk = (r() - .5) * w * .3, mid = px + sk * .4 + w * .08;
      final tx = px + sk * fold, ty = base - h * fold;
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

  /// `crane(c, x, y, s, f)`: a paper crane, wings at flap [f].
  static void crane(Ctx c, double x, double y, double s, double f) {
    final wy = -16 * f;
    c.save();
    c.translate(x, y);
    c.scale(s, s);
    c.fillStyle = const Color(0xFFE0E0E0);
    c.beginPath();
    c.moveTo(-3, -1);
    c.lineTo(4, -1);
    c.lineTo(3, wy * .9);
    c.closePath();
    c.fill();
    c.fillStyle = const Color(0xFFFAFAFA);
    c.beginPath();
    c.moveTo(-7, 0);
    c.lineTo(0, -3);
    c.lineTo(7, 0);
    c.lineTo(0, 3);
    c.closePath();
    c.fill();
    c.beginPath();
    c.moveTo(-7, 0);
    c.lineTo(-4, -1);
    c.lineTo(-15, -11);
    c.closePath();
    c.fill();
    c.beginPath();
    c.moveTo(-15, -11);
    c.lineTo(-13, -10);
    c.lineTo(-19, -7);
    c.closePath();
    c.fill();
    c.beginPath();
    c.moveTo(7, 0);
    c.lineTo(4, -1);
    c.lineTo(14, -10);
    c.closePath();
    c.fill();
    c.fillStyle = const Color(0xFFF5F5F5);
    c.strokeStyle = const Color(0xFFDCDCDC);
    c.lineWidth = .6;
    c.beginPath();
    c.moveTo(-4, 0);
    c.lineTo(4, 0);
    c.lineTo(-1, wy * 1.1);
    c.closePath();
    c.fill();
    c.stroke();
    c.restore();
  }
}
