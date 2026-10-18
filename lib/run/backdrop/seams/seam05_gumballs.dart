import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import '../scenes/s06_candy.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 5, Falling gumballs (Giant's Desk → Candy Land;
/// `slabDesk` + `pieceGumballs`): a candy jar lies tipped over on the desk
/// edge; its gumballs roll out and fall with the camera, past the drawers and
/// a desk leg, and bounce to a stop in Candy Land.
class GumballsSeam extends FloorSeam {
  const GumballsSeam();

  @override
  String get title => 'Falling gumballs';
  @override
  int get dir => 1;
  @override
  double get yF => 540;
  @override
  double get thickness => 190;
  @override
  double get hang => 60;
  @override
  double get travel => 830;

  /// The prototype's scroll speed (`SCROLL`, pt/s): the bounce's clock.
  static const double _scroll = 150;

  /// `slabDesk`: the desk top's front, its drawers, and a desk leg standing
  /// in Candy Land.
  @override
  void slab(Ctx c, SeamFrame s) {
    final sT = s.sT, sB = s.sB, xo = s.cam * .3;
    c.fillStyle = const Color(0xFFDCDCDC);
    c.fillRect(c.xl, sT, c.xr - c.xl, 40);
    c.fillStyle = const Color(0xFFD6D6D6);
    c.fillRect(c.xl, sT + 40, c.xr - c.xl, sB - sT - 60);
    // drawers with knobs
    each(c, xo, 220, 1501, (x, r, k) {
      c.fillStyle = const Color(0xFFE0E0E0);
      c.strokeStyle = const Color(0xFFD0D0D0);
      c.lineWidth = 2;
      c.beginPath();
      c.roundRect(x + 12, sT + 70, 196, 86, 4);
      c.fill();
      c.stroke();
      c.fillStyle = const Color(0xFFC9C9C9);
      c.circ(x + 110, sT + 113, 7);
      c.fillStyle = const Color(0xFFE6E6E6);
      c.circ(x + 108, sT + 111, 2.2);
    });
    c.fillStyle = const Color(0xFFD0D0D0);
    c.fillRect(c.xl, sB - 20, c.xr - c.xl, 20);
    // a desk leg standing in Candy Land
    final lx = s.hx(.3, 120), foot = 536 + s.oB(Band.near) + 6;
    if (lx > c.xl - 40 && lx < c.xr + 40) {
      c.fillStyle = const Color(0xFFD2D2D2);
      c.fillRect(lx - 13, sB, 26, foot - sB);
      c.fillStyle = const Color(0xFFCACACA);
      c.beginPath();
      c.roundRect(lx - 17, foot - 10, 34, 12, 4);
      c.fill();
    }
  }

  /// `BALLS`: eight gumballs (start, landing, landing x, radius, colour).
  static final List<_Ball> _balls = [
    for (var i = 0; i < 8; i++)
      _Ball(
        .3 + i * .028,
        .86 + hash(i * 3 + 1500) * .1,
        120 + hash(i * 3 + 1501) * 190,
        9 + hash(i * 3 + 1502) * 4,
        CandyScene.gums[i % 4],
      ),
  ];

  /// The six gumballs left in the jar (x, y, r, colour index).
  static const List<double> _inJar = [
    18, 12, 10, 0, 36, 14, 9, 1, 0, 16, 11, 2, 26, -6, 9, 3, -20, 18, 9, 1, 8, -4, 8, 0,
  ];

  /// `pieceGumballs`: the jar lies on the desk's front edge, mouth to the
  /// left; its gumballs fall with the camera and bounce to a stop.
  @override
  void piece(Ctx c, SeamFrame s, Band band) {
    if (band != Band.front) return;
    final d = s.travel, jy = 512 - s.y;
    double jx(double u) => kANCH - 40 - (u - .5) * s.win * .3;
    final x = jx(s.u);
    // (`jy > -100`: above the top of the screen, which is c.yTop)
    if (x > c.xl - 120 && x < c.xr + 120 && jy > c.yTop - 100) {
      c.save();
      c.translate(x, jy - 34);
      c.rotate(-.06);
      c.fillStyle = const Color.fromRGBO(255, 255, 255, .3);
      c.strokeStyle = const Color(0xFFD0D0D0);
      c.lineWidth = 3;
      c.beginPath();
      c.roundRect(-48, -30, 104, 62, 20);
      c.fill();
      c.stroke();
      c.fillStyle = const Color(0xFFD2D2D2);
      c.beginPath();
      c.roundRect(-58, -24, 12, 50, 4);
      c.fill();
      for (var i = 0; i < 6; i++) {
        gumball(c, _inJar[i * 4], _inJar[i * 4 + 1], _inJar[i * 4 + 2],
            CandyScene.gums[_inJar[i * 4 + 3].toInt()]);
      }
      c.strokeStyle = const Color.fromRGBO(255, 255, 255, .85);
      c.lineWidth = 4;
      c.lineCap = StrokeCap.round;
      c.beginPath();
      c.moveTo(-30, -20);
      c.lineTo(20, -20);
      c.stroke();
      c.restore();
      // its lid
      c.fillStyle = const Color(0xFFD6D6D6);
      c.beginPath();
      c.ellipse(x + 82, jy - 4, 20, 5, 0, 0, kTau);
      c.fill();
    }
    for (final b in _balls) {
      if (s.u < b.u0) continue;
      // heights in the desk's coordinates
      final x0 = jx(b.u0) - 62, y0A = 512.0 - 12, gA = 536 + d - b.r;
      if (s.u < b.ul) {
        final p = (s.u - b.u0) / (b.ul - b.u0), yA = y0A + (gA - y0A) * p * p;
        gumball(c, x0 + (b.x1 - x0) * smooth(p), yA - s.y, b.r, b.col);
      } else {
        final st = (s.u - b.ul) * s.win / _scroll;
        final bounce = 22 * math.exp(-2.4 * st) * math.sin(st * 5).abs();
        gumball(c, b.x1 - (s.u - b.ul) * s.win * .3, gA - s.y - bounce, b.r, b.col);
      }
    }
  }

  /// `gumball(c, x, y, r, col)`.
  static void gumball(Ctx c, double x, double y, double r, Color col) {
    c.fillStyle = col;
    c.circ(x, y, r);
    c.fillStyle = const Color.fromRGBO(255, 255, 255, .6);
    c.beginPath();
    c.ellipse(x - r * .35, y - r * .4, r * .3, r * .16, -.7, 0, kTau);
    c.fill();
  }
}

class _Ball {
  const _Ball(this.u0, this.ul, this.x1, this.r, this.col);
  final double u0, ul, x1, r;
  final Color col;
}
