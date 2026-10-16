import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import '../scenes/s02_sky.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 2, The crane lifts a cottage (Sky & Hills → City
/// Skyline; `slabGirder` + `pieceBuilding`): up a building going up,
/// through the city's steel deck; the crane sets the cottage on the roof.
class CraneSeam extends FloorSeam {
  const CraneSeam();

  @override
  String get title => 'The crane lifts a cottage';
  @override
  int get dir => -1;
  @override
  double get yF => 568;
  @override
  double get thickness => 36;
  @override
  double get hang => 90;
  @override
  double get travel => 734;

  /// `slabGirder`: the city's steel deck.
  @override
  void slab(Ctx c, SeamFrame s) {
    final sT = s.sT, sB = s.sB, xo = s.cam * .3;
    const h = 78.0;
    c.fillStyle = const Color(0xFFD8D8D8);
    c.fillRect(c.xl, sT, c.xr - c.xl, sB - sT);
    c.fillStyle = const Color(0xFFD1D1D1);
    c.fillRect(c.xl, sB - 6, c.xr - c.xl, 6);
    each(c, xo, 12, 1201, (x, r, k) {
      c.fillStyle = const Color(0xFFCDCDCD);
      c.circ(x, sT + 14, 1.6);
      c.circ(x, sB - 12, 1.6);
    });
    c.strokeStyle = const Color(0xFFD3D3D3);
    c.lineWidth = 4;
    c.lineCap = StrokeCap.butt;
    c.beginPath();
    each(c, xo, 60, 1211, (x, r, k) {
      c.moveTo(x, sB);
      c.lineTo(x, sB + h);
      if (k.isOdd) {
        c.moveTo(x, sB);
        c.lineTo(x + 60, sB + h);
      } else {
        c.moveTo(x, sB + h);
        c.lineTo(x + 60, sB);
      }
    });
    c.stroke();
    c.fillStyle = const Color(0xFFD1D1D1);
    c.fillRect(c.xl, sB + h - 3, c.xr - c.xl, 7);
  }

  /// `pieceBuilding`: a building under construction with a tower crane;
  /// the hook comes down from the sky, lifts the last cottage off the hill
  /// and sets it on the roof.
  @override
  void piece(Ctx c, SeamFrame s, Band band) {
    if (band != Band.mid) return;
    final x = s.hx(.2, 150), t = s.t;
    const w = 72.0;
    if (x < c.xl - 240 || x > c.xr + 220) return;
    final off = s.cam * .2;
    final base = SkyScene.midHill(off, x) + 8 + s.oA(Band.mid);
    final top = 230 + s.oB(Band.mid), done = top + 110;
    c.fillStyle = const Color(0xFFD7D7D7);
    c.fillRect(x - w / 2, done, w, base - done);
    c.fillStyle = const Color(0xFFE3E3E3);
    for (var y = done + 10; y < base - 14; y += 18) {
      if (y < c.yTop - 20 || y > kVH + 20) continue;
      for (var i = 0; i < 5; i++) {
        c.fillRect(x - w / 2 + 6 + i * 13.5, y, 8, 9);
      }
    }
    // the steel frame of the floors still being built
    c.fillStyle = const Color(0xFFD0D0D0);
    for (final cx in [x - w / 2, x - 2, x + w / 2 - 4]) {
      c.fillRect(cx, top, 4, done - top);
    }
    for (var y = top; y <= done; y += 22) {
      c.fillRect(x - w / 2, y, w, 3);
    }
    // scaffolding on the left side
    c.strokeStyle = const Color(0xFFCDCDCD);
    c.lineWidth = 1.4;
    c.beginPath();
    final sx = x - w / 2 - 12;
    c.moveTo(sx, done - 20);
    c.lineTo(sx, base);
    c.moveTo(sx + 12, done - 20);
    c.lineTo(sx + 12, base);
    for (var y = done - 20; y < base; y += 30) {
      c.moveTo(sx, y);
      c.lineTo(sx + 12, y);
      c.moveTo(sx, y);
      c.lineTo(sx + 12, y + 30);
    }
    c.stroke();
    // tower crane on the roof
    final mx = x + 14, mt = top - 120;
    c.fillStyle = const Color(0xFFCFCFCF);
    c.fillRect(mx - 4, mt, 2.5, top - mt);
    c.fillRect(mx + 4, mt, 2.5, top - mt);
    c.strokeStyle = const Color(0xFFCFCFCF);
    c.lineWidth = 1.2;
    c.beginPath();
    for (var y = mt; y < top; y += 12) {
      c.moveTo(mx - 3, y);
      c.lineTo(mx + 5, y + 12);
    }
    c.stroke();
    c.fillRect(mx - 136, mt - 4, 180, 5);
    c.fillRect(mx - 6, mt - 18, 3, 14);
    c.fillStyle = const Color(0xFFC9C9C9);
    c.fillRect(mx + 26, mt + 1, 16, 12);
    c.fillRect(mx + 6, mt + 2, 12, 10);
    // the hook lifts the last cottage off the hill and sets it on the roof
    final u = s.u;
    final e1 = smooth((u - .36) / .34), e2 = smooth((u - .7) / .1), e3 = smooth((u - .8) / .08);
    final cx0 = x - 86;
    final gy = SkyScene.midHill(off, cx0) + 7 + s.oA(Band.mid), hangY = top - 50;
    final cx = cx0 + (x - cx0) * e2;
    final cy = e3 > 0 ? hangY + (top - 1 - hangY) * e3 : gy + (hangY - gy) * e1;
    final rot = math.sin(t * 1.3) * .08 * e1 * (1 - e3);
    final hy = cy - 50;
    c.fillStyle = const Color(0xFFC9C9C9);
    c.fillRect(cx - .6, mt, 1.2, hy - mt + math.cos(rot) * 2);
    c.save();
    c.translate(cx, hy);
    c.rotate(rot);
    c.strokeStyle = const Color(0xFFC9C9C9);
    c.lineWidth = 1;
    c.beginPath();
    c.moveTo(0, 2);
    c.lineTo(-13, 23);
    c.moveTo(0, 2);
    c.lineTo(13, 23);
    c.stroke();
    c.fillStyle = const Color(0xFFC4C4C4);
    c.beginPath();
    c.arc(0, 2, 3, 0, math.pi);
    c.fill();
    c.translate(0, 50);
    c.fillStyle = const Color(0xFFDCDCDC);
    c.fillRect(-15, -22, 30, 22);
    c.fillStyle = const Color(0xFFD0D0D0);
    c.beginPath();
    c.moveTo(-18, -21);
    c.lineTo(0, -34);
    c.lineTo(18, -21);
    c.closePath();
    c.fill();
    c.fillRect(8, -34, 4, 9);
    c.fillRect(-4, -10, 7, 10);
    c.fillStyle = const Color(0xFFE8E8E8);
    c.fillRect(5, -17, 6, 6);
    c.fillRect(-11, -17, 6, 6);
    for (var j = 0; j < 3; j++) {
      final a = modD(t * .5 + j / 3, 1);
      c.globalAlpha = 1 - a;
      c.fillStyle = const Color(0xFFE4E4E4);
      c.circ(10 + a * 10, -38 - a * 22, 2.5 + a * 3);
    }
    c.globalAlpha = 1;
    c.restore();
  }
}
