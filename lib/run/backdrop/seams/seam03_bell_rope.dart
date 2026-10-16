import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 3, The bell ringer's rope (City Skyline → Clockwork;
/// `slabTimber`, no piece): a bell rope with pigeons on it hangs down into
/// the city; the camera climbs it, every pull rings the bell above and makes
/// the pigeons flutter up, and the camera rises through the clock room
/// floor. The distant clock face is the scene's own (unchanged).
class BellRopeSeam extends FloorSeam {
  const BellRopeSeam();

  @override
  String get title => 'The bell ringer\'s rope';
  @override
  int get dir => -1;
  @override
  double get yF => 540;
  @override
  double get thickness => 70;
  @override
  double get hang => 560;
  @override
  double get travel => 750;

  /// `slabTimber`: the clock room's timber floor, the tower bell rocking
  /// under it and its rope hanging down into the city.
  @override
  void slab(Ctx c, SeamFrame s) {
    final sT = s.sT, sB = s.sB, t = s.t, xo = s.cam * .3;
    c.fillStyle = const Color(0xFFDCDCDC);
    c.fillRect(c.xl, sT, c.xr - c.xl, sB - sT);
    c.fillStyle = const Color(0xFFD7D7D7);
    for (var y = sT + 34; y < sB - 4; y += 14) {
      c.fillRect(c.xl, y, c.xr - c.xl, 1);
    }
    c.fillStyle = const Color(0xFFD3D3D3);
    c.fillRect(c.xl, sB - 5, c.xr - c.xl, 5);
    each(c, xo, 56, 1301, (x, r, k) {
      c.fillStyle = const Color(0xFFD3D3D3);
      c.fillRect(x, sB, 26, 20);
      c.fillStyle = const Color(0xFFCDCDCD);
      c.fillRect(x + 5, sB + 6, 16, 1.2);
      c.fillRect(x + 8, sB + 12, 10, 1.2);
    });
    // the tower bell, rocking
    final bx = s.hx(.3, 40), a = math.sin(t * 1.6) * .22;
    if (bx < c.xl - 80 || bx > c.xr + 80) return;
    c.fillStyle = const Color(0xFFCFCFCF);
    c.fillRect(bx - 34, sB, 68, 12);
    c.save();
    c.translate(bx, sB + 12);
    c.rotate(a);
    c.fillStyle = const Color(0xFFC9C9C9);
    c.fillRect(-2, 0, 4, 12);
    c.fillStyle = const Color(0xFFD2D2D2);
    c.beginPath();
    c.moveTo(-14, 12);
    c.quadraticCurveTo(-16, 46, -36, 70);
    c.lineTo(36, 70);
    c.quadraticCurveTo(16, 46, 14, 12);
    c.closePath();
    c.fill();
    c.fillStyle = const Color(0xFFC8C8C8);
    c.beginPath();
    c.roundRect(-38, 66, 76, 7, 3.5);
    c.fill();
    c.circ(math.sin(t * 1.6 - .5) * 10, 78, 6);
    c.fillStyle = const Color(0xFFDCDCDC);
    c.fillRect(-9, 22, 4, 36);
    // the lever the rope pulls
    c.fillStyle = const Color(0xFFC9C9C9);
    c.fillRect(0, 4, 36, 4);
    c.circ(34, 6, 3.5);
    c.restore();
    // the bell rope hangs down into the city; every pull rings the bell,
    // and the pigeons on it flutter up
    final rx = bx + math.cos(a) * 34 - math.sin(a) * 6;
    final ry = sB + 12 + math.sin(a) * 34 + math.cos(a) * 6;
    const l = 430.0;
    final sw = math.sin(t * .9) * 7;
    double atX(double f) => rx + sw * f * f;
    double atY(double f) => ry + l * f;
    c.strokeStyle = const Color(0xFFCBCBCB);
    c.lineWidth = 2.4;
    c.lineCap = StrokeCap.round;
    c.beginPath();
    c.moveTo(rx, ry);
    c.quadraticCurveTo(rx, ry + l * .6, atX(1), atY(1));
    c.stroke();
    // the woolly grip
    final tx = atX(.9), ty = atY(.9);
    c.fillStyle = const Color(0xFFD2D2D2);
    c.beginPath();
    c.roundRect(tx - 4.5, ty, 9, 34, 4);
    c.fill();
    c.fillStyle = const Color(0xFFC6C6C6);
    for (var i = 0; i < 4; i++) {
      c.fillRect(tx - 4.5, ty + 4 + i * 8, 9, 2.5);
    }
    // while the rope is pulled down
    final lift = math.max(0.0, math.cos(t * 1.6)) * (math.sin(t * 1.6) > -.3 ? 1 : 0);
    for (var i = 0; i < 3; i++) {
      final f = _pigeons[i * 2], sd = _pigeons[i * 2 + 1];
      final px = atX(f), py = atY(f), up = lift * (6 + i * 2);
      final flap = lift > .2 ? .5 + .5 * math.sin(t * 22 + i) : 0.0;
      final bx2 = px + sd * 7, by2 = py - up;
      c.save();
      c.translate(bx2, by2);
      c.scale(sd, 1);
      c.fillStyle = const Color(0xFFCDCDCD);
      c.beginPath();
      c.ellipse(0, 0, 7.5, 5.5, -.15, 0, kTau);
      c.fill();
      c.beginPath();
      c.moveTo(-6, 0);
      c.lineTo(-12, -2);
      c.lineTo(-11, 3);
      c.closePath();
      c.fill();
      c.fillStyle = const Color(0xFFD5D5D5);
      c.circ(6, -5 + math.pow(math.max(0.0, math.sin(t * 1.1 + i * 2)), 8).toDouble() * 2, 3.4);
      c.fillStyle = const Color(0xFFBDBDBD);
      c.beginPath();
      c.moveTo(9, -5.5);
      c.lineTo(12, -4.5);
      c.lineTo(9, -3.5);
      c.fill();
      c.fillStyle = const Color(0xFFC3C3C3);
      c.beginPath();
      c.moveTo(-3, -1);
      c.lineTo(4, -1);
      c.lineTo(0, -1 - 10 * flap);
      c.closePath();
      c.fill();
      c.restore();
    }
    // sound lines at each end of the swing
    final ring = math.max(0.0, (math.sin(t * 1.6)).abs() - .9) * 10;
    if (ring > 0) {
      c.strokeStyle = Color.fromRGBO(190, 190, 190, (ring * 1000).round() / 1000);
      c.lineWidth = 1.5;
      for (final sd in const [-1.0, 1.0]) {
        c.beginPath();
        c.arc(bx + sd * 30, sB + 64, 16, sd > 0 ? -.6 : math.pi - .6,
            sd > 0 ? .6 : math.pi + .6);
        c.stroke();
      }
    }
  }

  /// The pigeons on the rope: (share of the rope, facing).
  static const List<double> _pigeons = [.3, 1, .5, -1, .68, 1];
}
