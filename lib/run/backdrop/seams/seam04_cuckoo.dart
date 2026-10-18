import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import 'seam.dart';

/// PRD-2.4 §3.3 seam 4, The cuckoo (Clockwork → Giant's Desk; `slabCuckoo`
/// + `pieceCuckoo`): the camera sinks through the carved base of a cuckoo
/// clock, past its pine-cone weights and pendulum; a little door opens and
/// the wooden cuckoo flies down alongside the bird and lands on the desk
/// ruler.
class CuckooSeam extends FloorSeam {
  const CuckooSeam();

  @override
  String get title => 'The cuckoo';
  @override
  int get dir => 1;
  @override
  double get yF => 540;
  @override
  double get thickness => 80;
  @override
  double get hang => 210;
  @override
  double get travel => 870;

  /// `slabCuckoo`: the clock's carved base with the cuckoo's door, the
  /// chains with their pine-cone weights and the pendulum.
  @override
  void slab(Ctx c, SeamFrame s) {
    final sT = s.sT, sB = s.sB, t = s.t, u = s.u, xo = s.cam * .3;
    c.fillStyle = const Color(0xFFDCDCDC);
    c.fillRect(c.xl, sT, c.xr - c.xl, sB - sT);
    c.fillStyle = const Color(0xFFD3D3D3);
    c.fillRect(c.xl, sT + 32, c.xr - c.xl, 5);
    c.fillRect(c.xl, sB - 8, c.xr - c.xl, 3);
    each(c, xo, 28, 1401, (x, r, k) {
      c.fillStyle = const Color(0xFFD6D6D6);
      c.beginPath();
      c.arc(x + 14, sB, 14, 0, math.pi);
      c.fill();
      c.fillStyle = const Color(0xFFCFCFCF);
      c.circ(x + 14, sB + 9, 2);
    });
    // the cuckoo's door
    final dx = s.hx(.3, -92), open = smooth((u - .25) / .05);
    c.fillStyle = const Color(0xFFD0D0D0);
    c.beginPath();
    c.roundRect4(dx - 13, sT + 42, 26, 30, 13, 13, 2, 2);
    c.fill();
    c.fillStyle = const Color(0xFFC6C6C6);
    c.beginPath();
    c.roundRect4(dx - 10, sT + 45, 20, 27, 10, 10, 1, 1);
    c.fill();
    c.fillStyle = const Color(0xFFE2E2E2);
    c.beginPath();
    c.roundRect4(dx - 10, sT + 45, 20 * (1 - open * .85), 27, 10, 10, 1, 1);
    c.fill();
    // chains with pine-cone weights
    _chain(c, sB, s.hx(.3, -10), 120, math.sin(t * .7) * 2);
    _chain(c, sB, s.hx(.3, 22), 150, math.sin(t * .7 + 1) * 2);
    // pendulum, one swing a second like the clockwork's
    final px = s.hx(.3, 70), a = math.sin(t * math.pi) * .2;
    const l = 170.0;
    c.save();
    c.translate(px, sB);
    c.rotate(a);
    c.fillStyle = const Color(0xFFD2D2D2);
    c.fillRect(-1.5, 0, 3, l);
    c.fillStyle = const Color(0xFFCECECE);
    c.circ(0, l, 17);
    c.fillStyle = const Color(0xFFD8D8D8);
    c.beginPath();
    c.ellipse(0, l, 9, 12, 0, 0, kTau);
    c.fill();
    c.restore();
  }

  static void _chain(Ctx c, double sB, double x, double l, double sw) {
    final ex = x + sw, ey = sB + l;
    c.fillStyle = const Color(0xFFCACACA);
    for (var i = 0.0; i < l; i += 6) {
      c.circ(x + sw * i / l, sB + i, 1.5);
    }
    c.fillStyle = const Color(0xFFCFCFCF);
    c.beginPath();
    c.ellipse(ex, ey + 18, 9, 20, 0, 0, kTau);
    c.fill();
    c.strokeStyle = const Color(0xFFC5C5C5);
    c.lineWidth = 1;
    for (var j = 0; j < 5; j++) {
      c.beginPath();
      c.arc(ex, ey + 4 + j * 7, 6, .3, math.pi - .3);
      c.stroke();
    }
    c.fillStyle = const Color(0xFFC8C8C8);
    c.fillRect(ex - 1, ey - 2, 2, 5);
  }

  /// `pieceCuckoo`: out of the door, alongside the bird, then down onto the
  /// ruler as it comes up; it hops there until it has scrolled away.
  @override
  void piece(Ctx c, SeamFrame s, Band band) {
    if (band != Band.front || s.u < .29) return;
    final d = s.travel, t = s.t;
    double doorX(double u) => kANCH - 92 - (u - .5) * s.win * .3;
    double doorY(double u) => 540 - d * smooth(u) + 58;
    double ruler(double u) => 505 + d * (1 - smooth(math.min(1, u)));
    const ul = .86;
    if (s.u < ul) {
      final p = smooth((s.u - .3) / .14), d0x = doorX(s.u), d0y = doorY(s.u);
      final x = d0x + (250 - d0x) * p, y = d0y + (300 - d0y) * p;
      final k = smooth((s.u - .62) / (ul - .62));
      final bob = math.sin(t * 2.2) * 6 * (1 - k) * smooth((s.u - .3) / .06);
      cuckoo(c, x, y + (ruler(s.u) - y) * k + bob - 8, .5 + .5 * math.sin(t * 15), 1.1);
    } else {
      final hop = math.pow(math.max(0.0, math.sin(t * 2.6)), 10).toDouble() * 5;
      cuckoo(c, 250 - (s.u - ul) * s.win * .3, ruler(s.u) - 8 - hop, hop > .5 ? .6 : 0, 1.1);
    }
  }

  /// `cuckoo(c, x, y, flap, s)`: the wooden cuckoo.
  static void cuckoo(Ctx c, double x, double y, double flap, [double s = 1]) {
    c.save();
    c.translate(x, y);
    c.scale(s, s);
    c.fillStyle = const Color(0xFFCFCFCF);
    c.beginPath();
    c.moveTo(-6, -1);
    c.lineTo(-17, -6);
    c.lineTo(-16, 3);
    c.closePath();
    c.fill();
    c.beginPath();
    c.ellipse(0, 0, 9.5, 7, -.12, 0, kTau);
    c.fill();
    c.fillStyle = const Color(0xFFD7D7D7);
    c.circ(8, -6, 5);
    c.fillStyle = const Color(0xFFBFBFBF);
    c.beginPath();
    c.moveTo(12, -7.5);
    c.lineTo(18, -5.5);
    c.lineTo(12, -4);
    c.closePath();
    c.fill();
    c.circ(9.4, -7.2, 1);
    c.fillStyle = const Color(0xFFC5C5C5);
    c.beginPath();
    c.moveTo(-4, -2);
    c.lineTo(5, -2);
    c.lineTo(-2, -2 - 11 * flap);
    c.closePath();
    c.fill();
    c.restore();
  }
}
