import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import '../scenes/s02_sky.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 1, Treetop waterfall (Nest Canopy → Sky & Hills;
/// `slabCanopy` + `pieceFalls`): rain water caught in the canopy pours from
/// a hollow branch as a slow waterfall; the camera sinks beside it through
/// the leaves to a pond on the far hill.
class WaterfallSeam extends FloorSeam {
  const WaterfallSeam();

  @override
  String get title => 'Treetop waterfall';
  @override
  int get dir => 1;
  @override
  double get yF => 545;
  @override
  double get thickness => 150;
  @override
  double get hang => 130;
  @override
  double get travel => 865;

  /// `slabCanopy`: down a giant trunk, through the lower leaves.
  @override
  void slab(Ctx c, SeamFrame s) {
    final sT = s.sT, sB = s.sB, t = s.t, xo = s.cam * .3;
    c.fillStyle = const Color(0xFFD8D8D8);
    c.fillRect(c.xl, sT, c.xr - c.xl, sB - sT + 2);
    each(c, xo, 34, 1101, (x, r, k) {
      c.fillStyle = r() < .5 ? const Color(0xFFDCDCDC) : const Color(0xFFD4D4D4);
      final cx = x + r() * 12, cy = sT + 40 + r() * (sB - sT - 60);
      c.circ(cx, cy, 9 + r() * 9);
    });
    // vines hanging under the leaves
    each(c, xo, 70, 1121, (x, r, k) {
      if (r() < .45) return;
      final vx = x + r() * 30, l = 50 + r() * 70, sw = math.sin(t * .9 + k) * 5;
      c.strokeStyle = const Color(0xFFD0D0D0);
      c.lineWidth = 1.5;
      c.beginPath();
      c.moveTo(vx, sB);
      c.quadraticCurveTo(vx + sw * .5, sB + l * .5, vx + sw, sB + l);
      c.stroke();
      c.fillStyle = const Color(0xFFD2D2D2);
      for (var j = 1; j <= 3; j++) {
        c.beginPath();
        c.ellipse(vx + sw * j / 3 + (j.isOdd ? 4 : -4), sB + l * j / 3.3, 4, 2,
            j.isOdd ? .5 : -.5, 0, kTau);
        c.fill();
      }
    });
    c.fillStyle = const Color(0xFFD1D1D1);
    each(c, xo, 26, 1111, (x, r, k) {
      final rr = 13 + r() * 12;
      c.circ(x + 13, sB + rr * .45 + 4, rr * .85);
    });
    c.fillStyle = const Color(0xFFD8D8D8);
    each(c, xo, 26, 1111, (x, r, k) {
      final rr = 13 + r() * 12;
      c.circ(x, sB + rr * .2, rr);
    });
  }

  /// `pieceFalls`: rain water from the canopy pours out of a hollow branch,
  /// down into a pond on the far hill.
  @override
  void piece(Ctx c, SeamFrame s, Band band) {
    if (band != Band.far) return;
    final x = s.hx(.09, -5), t = s.t, o = s.oB(Band.far);
    if (x < c.xl - 160 || x > c.xr + 60) return;
    final off = s.cam * .09;
    double ridgeAtX(double xx) => SkyScene.farHill(off, xx) + o;
    final wx = x + 40, ys = -203 + o, gnd = ridgeAtX(wx) + 3;
    // the tree, its crown far above (above the top of a taller view too)
    final trunkTop = -80 + c.yTop;
    c.fillStyle = const Color(0xFFE3E3E3);
    c.fillRect(x - 12, trunkTop, 24, ridgeAtX(x) + 12 - trunkTop);
    // the hollow branch
    c.save();
    c.translate(x + 8, ys);
    c.rotate(-.18);
    c.fillStyle = const Color(0xFFE0E0E0);
    c.fillRect(0, -7, 30, 14);
    c.fillStyle = const Color(0xFFDADADA);
    c.beginPath();
    c.ellipse(30, 0, 5, 8, 0, 0, kTau);
    c.fill();
    c.fillStyle = const Color(0xFFD0D0D0);
    c.beginPath();
    c.ellipse(30, 0, 3, 5.5, 0, 0, kTau);
    c.fill();
    c.restore();
    // the falling water widens a little towards the bottom
    final l = gnd - ys, top = ys - 2;
    c.fillStyle = const Color(0xFFFBFBFB);
    c.strokeStyle = const Color(0xFFD8D8D8);
    c.lineWidth = 1.2;
    // a gently wobbling ribbon
    double edge(double y, double sd) =>
        wx + sd * (5 + 4 * (y - top) / l) + math.sin(y / 23 + t * 4 + sd) * .9;
    c.beginPath();
    c.moveTo(x + 34, top);
    c.quadraticCurveTo(wx - 4, top + 8, edge(top + 30, -1), top + 30);
    for (var y = top + 40; y < gnd; y += 10) {
      c.lineTo(edge(y, -1), y);
    }
    c.lineTo(edge(gnd, -1), gnd);
    c.lineTo(edge(gnd, 1), gnd);
    for (var y = gnd - 10; y > top + 30; y -= 10) {
      c.lineTo(edge(y, 1), y);
    }
    c.lineTo(edge(top + 30, 1), top + 30);
    c.quadraticCurveTo(wx + 4, top + 4, x + 38, top - 6);
    c.closePath();
    c.fill();
    c.stroke();
    c.fillStyle = const Color(0xFFE2E2E2);
    for (var k = 0; k < l / 34; k++) {
      final y = top + 26 + modD(t * 70 + k * 34, l - 30);
      c.fillRect(wx - 3 + (k % 3) * 2.5, y, 1.4, 9);
    }
    // a stream runs off to the left
    c.strokeStyle = const Color(0xFFF9F9F9);
    c.lineWidth = 4;
    c.lineCap = StrokeCap.round;
    c.beginPath();
    for (var xx = wx - 26; xx >= wx - 120; xx -= 4) {
      final y = ridgeAtX(xx) + 5;
      xx == wx - 26 ? c.moveTo(xx, y) : c.lineTo(xx, y);
    }
    c.stroke();
    c.fillStyle = const Color(0xFFF9F9F9);
    c.strokeStyle = const Color(0xFFDADADA);
    c.lineWidth = 1;
    c.beginPath();
    c.ellipse(wx, gnd, 30, 5, 0, 0, kTau);
    c.fill();
    c.stroke();
    c.lineWidth = 1;
    for (var j = 0; j < 2; j++) {
      final a = modD(t * .45 + j / 2, 1);
      c.strokeStyle = Color.fromRGBO(210, 210, 210, (.8 * (1 - a) * 1000).round() / 1000);
      c.beginPath();
      c.ellipse(wx, gnd, 7 + a * 20, 1.2 + a * 3, 0, 0, kTau);
      c.stroke();
    }
    // spray where it lands
    c.fillStyle = const Color(0xFFFBFBFB);
    for (var j = 0; j < 5; j++) {
      c.circ(wx - 14 + j * 7, gnd - 4 - (math.sin(t * 2.2 + j * 1.3)).abs() * 5,
          4.5 + (j % 2) * 2.5);
    }
  }
}
