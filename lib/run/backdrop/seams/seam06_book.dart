import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import '../scenes/s07_origami.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 6, Up the book's pages (Candy Land → Paper Origami;
/// `slabBook` + `pieceWrappers`): the camera climbs the page edges of a
/// giant book with a ribbon bookmark; sweet wrappers float up and fold into
/// paper cranes, and at the top the paper mountains pop up from the page
/// ([fold], read by the Origami scene as `c.fold`).
class BookSeam extends FloorSeam {
  const BookSeam();

  @override
  String get title => 'Up the book\'s pages';
  @override
  int get dir => -1;
  @override
  double get yF => 540;
  @override
  double get thickness => 250;
  @override
  double get hang => 130;
  @override
  double get travel => 960;

  /// `slabBook`: the cover's edge, the stacked page edges, the spine, and
  /// the ribbon bookmark hanging below.
  @override
  void slab(Ctx c, SeamFrame s) {
    final sT = s.sT, sB = s.sB, t = s.t;
    c.fillStyle = const Color(0xFFE4E4E4);
    c.fillRect(c.xl, sT, c.xr - c.xl, 40);
    c.fillStyle = const Color(0xFFF3F3F3);
    c.fillRect(c.xl, sT + 40, c.xr - c.xl, sB - sT - 62);
    c.fillStyle = const Color(0xFFE3E3E3);
    for (var y = sT + 43; y < sB - 24; y += 4) {
      c.fillRect(c.xl, y, c.xr - c.xl, 1);
    }
    c.fillStyle = const Color(0xFFD6D6D6);
    c.beginPath();
    c.roundRect(c.xl - 10, sB - 22, c.xr - c.xl + 20, 22, 6);
    c.fill();
    c.fillStyle = const Color(0xFFCFCFCF);
    c.fillRect(c.xl, sB - 6, c.xr - c.xl, 6);
    // ribbon bookmark
    final rx = s.hx(.3, -30), sw = math.sin(t * .8) * 6;
    if (rx > c.xl - 40 && rx < c.xr + 40) {
      c.fillStyle = const Color(0xFFDADADA);
      c.beginPath();
      c.moveTo(rx - 5, sT + 38);
      c.lineTo(rx + 5, sT + 38);
      c.lineTo(rx + 5 + sw, sB + 110);
      c.lineTo(rx + sw, sB + 101);
      c.lineTo(rx - 5 + sw, sB + 110);
      c.closePath();
      c.fill();
    }
  }

  /// `g(S)`: the paper peaks pop up from the page (`fold`).
  @override
  double? fold(SeamFrame s) => smooth((s.u - .55) / .35);

  /// `pieceWrappers`: sweet wrappers float up, turn edge-on and come back
  /// folded into paper cranes, then drift away.
  @override
  void piece(Ctx c, SeamFrame s, Band band) {
    if (band != Band.front) return;
    final t = s.t;
    for (var i = 0; i < 6; i++) {
      final u0 = .12 + i * .07, p = (s.u - u0) / .3;
      if (p < 0 || p > 1.6) continue;
      final ty = 130 + hash(i * 5 + 1600) * 240, x0 = 170 + hash(i * 5 + 1601) * 130;
      final rise = smooth(p / .6), away = math.max(0.0, p - .85);
      final x = x0 + math.sin(t * .9 + i) * 10 - away * 260;
      final y = kVH + 30 + (ty - kVH - 30) * rise - away * 700;
      // turns edge-on and comes back folded
      final flip = clampD((p - .62) / .14, 0, 1);
      final cs = math.cos(flip * math.pi).abs();
      final sx = cs == 0 ? .02 : cs;
      c.save();
      c.translate(x, y);
      c.scale(math.max(.05, sx), 1);
      if (flip < .5) {
        c.rotate(math.sin(t * 1.4 + i) * .5);
        _wrapper(c, 1);
      } else {
        OrigamiScene.crane(c, 0, 0, 1, math.sin(t * 6 + i));
      }
      c.restore();
    }
  }

  /// `wrapper(c, s)`: a twisted sweet wrapper, empty.
  static void _wrapper(Ctx c, double s) {
    c.fillStyle = const Color(0xFFE6E6E6);
    c.strokeStyle = const Color(0xFFD4D4D4);
    c.lineWidth = 1;
    c.beginPath();
    c.roundRect(-8 * s, -5 * s, 16 * s, 10 * s, 3 * s);
    c.fill();
    c.stroke();
    c.fillStyle = const Color(0xFFDCDCDC);
    for (final d in const [-1.0, 1.0]) {
      c.beginPath();
      c.moveTo(d * 8 * s, 0);
      c.lineTo(d * 16 * s, -7 * s);
      c.lineTo(d * 15 * s, 7 * s);
      c.closePath();
      c.fill();
    }
  }
}
