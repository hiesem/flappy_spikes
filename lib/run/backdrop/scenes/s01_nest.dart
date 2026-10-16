import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 1, Nest Canopy (`drawNest`, "6. Nest Canopy (flat)").
class NestScene extends BackdropScene {
  const NestScene();

  @override
  String get name => 'Nest Canopy';

  @override
  void draw(Ctx c, Band band) {
    switch (band) {
      case Band.sky:
      case Band.front:
        return;
      case Band.far:
        _far(c);
      case Band.mid:
        _mid(c);
      case Band.near:
        _near(c);
    }
  }

  static void _far(Ctx c) => c.strip(101, c.cam * .055, (off) => _farTrees(c, off));

  static void _farTrees(Ctx c, double off) {
    each(c, off, 120, 711, (x, r, k) {
      if (r() < .35) return;
      // tree tops above the screen, seen while descending
      final tx = x + r() * 40, w = 16 + r() * 12;
      final top = -70 - hash(k * 7 + 1) * 280, cx0 = tx + w / 2;
      c.fillStyle = const Color(0xFFE9E9E9);
      c.fillRect(tx, top, w, kVH + 60 - top);
      c.fillStyle = const Color(0xFFE7E7E7);
      c.circ(cx0, top, w * 1.7);
      c.circ(cx0 - w * 1.1, top + w * .7, w * 1.2);
      c.circ(cx0 + w * 1.1, top + w * .6, w * 1.3);
    });
  }

  static void _mid(Ctx c) {
    final t = c.t;
    final off = c.cam * .16;
    each(c, off, 170, 721, (x, r, k) {
      if (r() < .2) return;
      final tx = x + r() * 50, w = 24 + r() * 12;
      final top = -40 - hash(k * 13 + 2) * 320, cx0 = tx + w / 2;
      c.fillStyle = const Color(0xFFDEDEDE);
      c.fillRect(tx, top, w, kVH + 60 - top);
      c.fillStyle = const Color(0xFFE1E1E1);
      c.circ(cx0, top - 6, w * 1.6);
      c.circ(cx0 - w * 1.05, top + w * .5, w * 1.15);
      c.circ(cx0 + w * 1.1, top + w * .45, w * 1.25);
      c.circ(cx0 + w * .2, top - w * 1.1, w * .9);
      c.fillStyle = const Color(0xFFD7D7D7);
      for (var j = 0; j < 4; j++) {
        c.beginPath();
        final rx = tx + 4 + r() * (w - 10);
        c.roundRect(rx, 90 + j * 110 + r() * 40, 3, 18, 1.5);
        c.fill();
      }
      final by = 190 + r() * 210, dir = r() < .5 ? -1 : 1, l = 62 + r() * 36;
      final bx0 = dir > 0 ? tx + w - 2 : tx + 2;
      final mx = bx0 + dir * l * .5, ex = bx0 + dir * l, ey = by - 12;
      c.strokeStyle = const Color(0xFFDEDEDE);
      c.lineWidth = 7;
      c.lineCap = StrokeCap.round;
      c.beginPath();
      c.moveTo(bx0, by + 6);
      c.quadraticCurveTo(mx, by, ex, ey);
      c.stroke();
      c.fillStyle = const Color(0xFFE3E3E3);
      c.circ(ex, ey - 6, 9);
      c.circ(ex + dir * 8, ey - 2, 7);
      c.circ(ex - dir * 4, ey - 10, 6);
      const s = .55;
      final qx = (1 - s) * (1 - s) * bx0 + 2 * s * (1 - s) * mx + s * s * ex;
      final qy = (1 - s) * (1 - s) * (by + 6) + 2 * s * (1 - s) * by + s * s * ey;
      if (r() < .65) {
        twigNest(c, qx, qy - 4, r, t, k);
      } else {
        birdhouse(c, qx, qy - 3);
      }
    });
    // leafy canopy and vines hanging under the top spikes
    each(c, c.cam * .1, 34, 731, (x, r, k) {
      final cx0 = x + r() * 10, cy = 34 + r() * 34, rr = 18 + r() * 12;
      if (r() < .3) {
        final l = 40 + r() * 90, sw = math.sin(t * .9 + k) * 4;
        c.strokeStyle = const Color(0xFFE2E2E2);
        c.lineWidth = 1.5;
        c.beginPath();
        c.moveTo(cx0, cy);
        c.quadraticCurveTo(cx0 + sw * .5, cy + l * .5, cx0 + sw, cy + l);
        c.stroke();
        c.fillStyle = const Color(0xFFE2E2E2);
        for (var j = 1; j <= 3; j++) {
          c.beginPath();
          c.ellipse(cx0 + sw * j / 3 + (j.isOdd ? 4 : -4), cy + l * j / 3.3, 4, 2,
              j.isOdd ? .5 : -.5, 0, kTau);
          c.fill();
        }
      }
      c.fillStyle = const Color(0xFFE5E5E5);
      c.circ(cx0, cy, rr);
      // an uneven canopy top above the screen
      final hgt = (.5 + .5 * math.sin(k * .45)) * (.55 + .45 * math.sin(k * .17 + 1)) * 190;
      for (var yy = cy - 16; yy > cy - hgt; yy -= 16) {
        c.circ(cx0 + math.sin(yy * .1 + k) * 6, yy,
            rr * (.8 + .2 * hash(k * 3 + jsRound(yy))));
      }
    });
    for (final f in _feathers) {
      final y = modD(f.sy * kVH + t * (10 + f.sp * 8), kVH + 40) - 20;
      wraps(c, f.sx * (kVW + 40) - c.cam * .12 + math.sin(t * .9 + f.ph) * 14,
          kVW + 40, 20, (x) {
        feather(c, x, y, math.sin(t * 1.2 + f.ph) * .6 + .4);
      });
    }
  }

  static void _near(Ctx c) => c.strip(102, c.cam * .3, (off) => _nearBushes(c, off));

  static void _nearBushes(Ctx c, double off) {
    each(c, off, 28, 741, (x, r, k) {
      c.fillStyle = const Color(0xFFD8D8D8);
      final cx = x + r() * 8, cy = 522 - r() * 10;
      c.circ(cx, cy, 15 + r() * 8);
    });
    c.fillStyle = const Color(0xFFD8D8D8);
    gfillSink(c, 520);
  }

  static final List<_Feather> _feathers = List.generate(
    8,
    (i) => _Feather(
      hash(i * 9 + 701),
      hash(i * 9 + 702),
      hash(i * 9 + 703),
      hash(i * 9 + 704) * kTau,
    ),
  );
}

class _Feather {
  const _Feather(this.sx, this.sy, this.sp, this.ph);
  final double sx, sy, sp, ph;
}

/// `feather(c, x, y, a)`.
void feather(Ctx c, double x, double y, double a) {
  c.save();
  c.translate(x, y);
  c.rotate(a);
  c.fillStyle = const Color(0xFFFAFAFA);
  c.beginPath();
  c.moveTo(0, -11);
  c.quadraticCurveTo(6, -3, 1, 9);
  c.lineTo(-1, 9);
  c.quadraticCurveTo(-6, -3, 0, -11);
  c.fill();
  c.strokeStyle = const Color(0xFFD2D2D2);
  c.lineWidth = .8;
  c.beginPath();
  c.moveTo(0, -9);
  c.lineTo(0, 13);
  c.stroke();
  c.restore();
}

/// `twigNest(c, x, y, r, t, k)`: eggs give a little wobble now and then.
void twigNest(Ctx c, double x, double y, Rng r, double t, int k) {
  final n = 1 + (r() * 3).floor();
  for (var i = 0; i < n; i++) {
    final wob = math.sin(t * .6 + k + i * 2) > .85 ? math.sin(t * 18 + i) * .2 : 0.0;
    c.save();
    c.translate(x - 8 + i * 8, y - 1);
    c.rotate(wob);
    c.fillStyle = const Color(0xFFFAFAFA);
    c.beginPath();
    c.ellipse(0, -5, 5, 7, 0, 0, kTau);
    c.fill();
    c.strokeStyle = const Color(0xFFDADADA);
    c.lineWidth = 1;
    c.stroke();
    c.restore();
  }
  c.fillStyle = const Color(0xFFD4D4D4);
  c.beginPath();
  c.ellipse(x, y, 22, 10, 0, 0, math.pi);
  c.closePath();
  c.fill();
  c.fillStyle = const Color(0xFFCFCFCF);
  c.beginPath();
  c.roundRect(x - 23, y - 2, 46, 4, 2);
  c.fill();
  c.strokeStyle = const Color(0xFFC8C8C8);
  c.lineWidth = 1;
  c.beginPath();
  for (var i = 0; i < 5; i++) {
    c.moveTo(x - 18 + i * 8, y + 1 + (i % 2) * 3);
    c.lineTo(x - 11 + i * 7, y + 7 - (i % 2) * 4);
  }
  c.stroke();
}

/// `birdhouse(c, x, y)`.
void birdhouse(Ctx c, double x, double y) {
  c.fillStyle = const Color(0xFFE6E6E6);
  c.fillRect(x - 9, y - 20, 18, 18);
  c.fillStyle = const Color(0xFFD2D2D2);
  c.beginPath();
  c.moveTo(x - 12, y - 19);
  c.lineTo(x, y - 30);
  c.lineTo(x + 12, y - 19);
  c.closePath();
  c.fill();
  c.fillStyle = const Color(0xFFC8C8C8);
  c.circ(x, y - 12, 3);
  c.fillRect(x - 1, y - 7, 2, 2);
}
