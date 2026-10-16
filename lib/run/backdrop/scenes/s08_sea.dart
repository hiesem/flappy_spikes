import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import '../seams/water.dart';

/// PRD-2.4 §3.3 scene 8, Underwater (`drawSea`, "4. Underwater (soft)"):
/// the sea's gradient and light rays, sunken paper peaks, coral, fish
/// schools, kelp and folded paper seaweed, rising bubbles, and paper boats
/// that sank, half in the sand.
class SeaScene extends BackdropScene {
  const SeaScene();

  @override
  String get name => 'Underwater';

  @override
  void draw(Ctx c, Band band) {
    final cam = c.cam;
    switch (band) {
      case Band.sky:
        vgrad(c, const [Color(0xFFF2F2F2), Color(0xFFE9E9E9)], const [0, 1], force: true);
        // the rays start at the 568 design's top (y 0), as the older moves
        // that bring the sea in and out (seams 7 and 8) leave them
        if (!c.vert) rays(c, c.t, 0);
      case Band.far:
        c.strip(801, cam * .08,
            (off) => ridge(c, off, 512, 20, 60, 23, const Color(0xFFE4E4E4), .8));
        _fish(c);
        c.strip(802, cam * .1, (off) => _coralAndPeaks(c, off));
      case Band.mid:
        _mid(c);
      case Band.near:
        c.strip(803, cam * .3, (off) {
          each(c, off, 130, 3121, (x, r, k) {
            // paper boats that sank, half in the sand
            if (hash(k * 29 + 3) >= early(c, x + 65, .3, .3)) return;
            paperBoat(c, x + r() * 60, 536, (r() - .5) * .9);
          });
          ridge(c, off, 536, 7, 36, 17, const Color(0xFFDEDEDE), 2.4);
        });
      case Band.front:
        return;
    }
  }

  static void _fish(Ctx c) {
    final t = c.t;
    each(c, c.cam * .1 + t * 12, 250, 131, (x, r, k) {
      if (r() < .35) return;
      final y0 = 150 + r() * 250;
      c.fillStyle = const Color(0xFFD5D5D5);
      for (var i = 0; i < 5; i++) {
        final fx = x + (i % 3) * 14 + r() * 6;
        final fy = y0 + (i ~/ 3) * 9 - (i % 3) * 3 + math.sin(t * 2 + i) * 1.5;
        final w = math.sin(t * 9 + i) * 1.5;
        c.beginPath();
        c.ellipse(fx, fy, 6, 3, 0, 0, kTau);
        c.fill();
        c.beginPath();
        c.moveTo(fx + 4, fy);
        c.lineTo(fx + 10, fy - 3 + w);
        c.lineTo(fx + 10, fy + 3 + w);
        c.closePath();
        c.fill();
      }
    });
  }

  static void _coralAndPeaks(Ctx c, double off) {
    each(c, off, 84, 111, (x, r, k) {
      if (r() < .45) return;
      final cx0 = x + r() * 30, h = 18 + r() * 16;
      c.strokeStyle = const Color(0xFFDEDEDE);
      c.lineCap = StrokeCap.round;
      c.lineWidth = 4;
      for (var b = -2; b <= 2; b++) {
        final ex = cx0 + b * h * .32, ey = 508 - h * (1 - b.abs() * .18);
        c.beginPath();
        c.moveTo(cx0, 512);
        c.quadraticCurveTo(cx0 + b * 3, 508 - h * .5, ex, ey);
        c.stroke();
        c.fillStyle = const Color(0xFFDEDEDE);
        c.circ(ex, ey, 3);
      }
    });
    each(c, off, 90, 3101, (x, r, k) {
      // folded paper peaks that sank with the paper world
      if (hash(k * 17 + 5) >= early(c, x + 45, .1, .3)) return;
      final px = x + r() * 30, h = 70 + r() * 100, w = h * (.8 + r() * .4);
      final sk = (r() - .5) * w * .3, mid = px + sk * .4 + w * .08;
      c.fillStyle = const Color(0xFFE3E3E3);
      c.beginPath();
      c.moveTo(px - w / 2, 514);
      c.lineTo(px + sk, 514 - h);
      c.lineTo(mid, 514);
      c.closePath();
      c.fill();
      c.fillStyle = const Color(0xFFDCDCDC);
      c.beginPath();
      c.moveTo(mid, 514);
      c.lineTo(px + sk, 514 - h);
      c.lineTo(px + w / 2, 514);
      c.closePath();
      c.fill();
    });
  }

  static void _mid(Ctx c) {
    final t = c.t, off = c.cam * .2;
    each(c, off, 40, 121, (x, r, k) {
      if (r() < .35) return;
      final n = 1 + (r() * 2).floor();
      for (var i = 0; i < n; i++) {
        _kelp(c, x + i * 7 + r() * 8, 546, 70 + r() * 120, t, k * 3 + i);
      }
    });
    each(c, off, 46, 3111, (x, r, k) {
      // folded paper seaweed among the kelp
      if (hash(k * 23 + 9) >= early(c, x + 23, .2, .32)) return;
      final sx = x + r() * 20, n = 5 + (r() * 8).floor();
      c.lineJoin = StrokeJoin.miter;
      c.lineCap = StrokeCap.butt;
      c.beginPath();
      for (var j = 0; j <= n; j++) {
        final px = sx + (j.isOdd ? -5 : 5) + math.sin(t * 1.1 + k + j * .4) * j * .5;
        final py = 546.0 - j * 10;
        if (j == 0) {
          c.moveTo(px, py);
        } else {
          c.lineTo(px, py);
        }
      }
      c.strokeStyle = const Color(0xFFE4E4E4);
      c.lineWidth = 7;
      c.stroke();
      c.strokeStyle = const Color(0xFFD4D4D4);
      c.lineWidth = 1;
      c.stroke();
    });
    bubbles(c, dream: false);
  }

  // `kelp(c, x, base, h, t, seed)`; the points go to a reused buffer.
  static final Float64List _pts = Float64List(64);

  static void _kelp(Ctx c, double x, double base, double h, double t, int seed) {
    final n = (h / 10).floor(), p = _pts;
    for (var j = 0; j <= n; j++) {
      p[j * 2] = x + math.sin(t * 1.1 + seed + j * .35) * j * .55;
      p[j * 2 + 1] = base - j * 10;
    }
    c.strokeStyle = const Color(0xFFD9D9D9);
    c.lineCap = StrokeCap.round;
    c.lineJoin = StrokeJoin.round;
    for (var j = 0; j < n; j++) {
      c.lineWidth = 5 - 3 * j / n;
      c.beginPath();
      c.moveTo(p[j * 2], p[j * 2 + 1]);
      c.lineTo(p[j * 2 + 2], p[j * 2 + 3]);
      c.stroke();
    }
    c.fillStyle = const Color(0xFFDDDDDD);
    for (var j = 2; j < n; j += 3) {
      final px = p[j * 2], py = p[j * 2 + 1], s = j.isOdd ? 1 : -1;
      c.beginPath();
      c.ellipse(px + s * 5, py, 6, 2.6, s * -.5, 0, kTau);
      c.fill();
    }
  }
}

/// `BUB`: the 22 bubbles the sea and (as leftovers) the dream share.
class Bubble {
  const Bubble(this.sx, this.sy, this.sp, this.sz, this.ph);
  final double sx, sy, sp, sz, ph;
}

final List<Bubble> kBubbles = List.generate(
  22,
  (i) => Bubble(
    hash(i * 5 + 101),
    hash(i * 5 + 102),
    hash(i * 5 + 103),
    hash(i * 5 + 104),
    hash(i * 5 + 105) * kTau,
  ),
);

/// The rising bubbles (`BUB.forEach(…)` of `drawSea` / `drawDream`). The
/// sea's have a white outline and highlight; in the [dream] they are
/// leftovers from the sea: grey-outlined, faded by `early(x, .18, .4)`.
void bubbles(Ctx c, {required bool dream}) {
  final t = c.t;
  for (final b in kBubbles) {
    wraps(c, b.sx * (kVW + 20) - c.cam * .18, kVW + 20, 10, (x0) {
      final x = x0 + math.sin(t * 1.6 + b.ph) * 3;
      final e = dream ? early(c, x, .18, .4) : 1.0;
      if (e <= .01) return;
      final y = kVH - modD(t * (14 + b.sp * 16) + b.sy * kVH, kVH + 30);
      final r = 1.6 + b.sz * 3.2;
      final ga = c.globalAlpha;
      c.globalAlpha = ga * e;
      c.fillStyle = const Color.fromRGBO(255, 255, 255, .3);
      c.circ(x, y, r);
      c.strokeStyle = dream
          ? const Color.fromRGBO(200, 200, 200, .9)
          : const Color.fromRGBO(255, 255, 255, .95);
      c.lineWidth = 1.1;
      c.beginPath();
      c.arc(x, y, r, 0, kTau);
      c.stroke();
      if (!dream) {
        c.fillStyle = const Color(0xFFFFFFFF);
        c.circ(x - r * .35, y - r * .35, r * .25);
      }
      c.globalAlpha = ga;
    });
  }
}
