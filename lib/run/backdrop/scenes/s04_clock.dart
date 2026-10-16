import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 4, Clockwork (`drawClock`, "7. Clockwork"): the
/// tower's clock face seen from inside (the landmark, 0.04×), turning gears
/// and a pendulum that swings once a second, meshing gear pairs on posts and
/// the clock room's riveted floor.
class ClockScene extends BackdropScene {
  const ClockScene();

  @override
  String get name => 'Clockwork';

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        clockFace(c, mark(c, -108), 150, t);
      case Band.far:
        each(c, cam * .055, 160, 811, (x, r, k) {
          if (r() < .25) return;
          final rr = 50 + r() * 40;
          final gx = x + r() * 40, gy = 200 + r() * 260;
          gear(c, gx, gy, rr, t * 7 * (k.isOdd ? 1 : -1) / rr, const Color(0xFFE8E8E8));
        });
        // one swing per second
        const l = 250.0;
        final a = math.sin(t * math.pi) * .26;
        c.save();
        c.translate(mark(c, 90), 20);
        c.rotate(a);
        c.fillStyle = const Color(0xFFE2E2E2);
        c.fillRect(-1.5, 0, 3, l);
        c.circ(0, l, 18);
        c.fillStyle = const Color(0xFFE9E9E9);
        c.circ(0, l, 10);
        c.restore();
      case Band.mid:
        // pairs of meshing gears on posts
        each(c, cam * .18, 130, 821, (x, r, k) {
          if (r() < .2) return;
          final r1 = 24 + r() * 18, r2 = 16 + r() * 14, x1 = x + r() * 30;
          final y1 = 390 + r() * 90, a = -.5 + r() * 1.2;
          final x2 = x1 + math.cos(a) * (r1 + r2 - 4), y2 = y1 + math.sin(a) * (r1 + r2 - 4);
          final w = t * 15 * (k.isOdd ? 1 : -1);
          c.fillStyle = const Color(0xFFD9D9D9);
          c.fillRect(x1 - 2, y1, 4, kVH + 60 - y1);
          gear(c, x1, y1, r1, w / r1, const Color(0xFFDCDCDC));
          gear(c, x2, y2, r2, -w / r2 + .3, const Color(0xFFD6D6D6));
        });
      case Band.near:
        c.strip(401, cam * .3, (off) {
          c.fillStyle = const Color(0xFFD3D3D3);
          gfillCut(c, 512, 10);
          c.fillStyle = const Color(0xFFDCDCDC);
          gfillCut(c, 522, kVH + 40 - 522);
          each(c, off, 46, 831, (x, r, k) {
            c.fillStyle = const Color(0xFFC9C9C9);
            c.circ(x, 517, 2.4);
          });
        });
      case Band.front:
        return;
    }
  }

  /// `gear(c, x, y, R, ang, col)`: a toothed wheel with a hub and spoke
  /// holes (even-odd fill).
  static void gear(Ctx c, double x, double y, double R, double ang, Color col) {
    final n = math.max(8, jsRound(R / 3.4)), ri = R * .84, d = .12 / n * kTau;
    c.save();
    c.translate(x, y);
    c.rotate(ang);
    c.beginPath();
    for (var i = 0; i < n; i++) {
      final a0 = i / n * kTau, a2 = (i + .5) / n * kTau;
      if (i == 0) {
        c.moveTo(math.cos(a0) * ri, math.sin(a0) * ri);
      } else {
        c.lineTo(math.cos(a0) * ri, math.sin(a0) * ri);
      }
      c.lineTo(math.cos(a0 + d) * R, math.sin(a0 + d) * R);
      c.lineTo(math.cos(a2 - d) * R, math.sin(a2 - d) * R);
      c.lineTo(math.cos(a2) * ri, math.sin(a2) * ri);
    }
    c.closePath();
    final hr = R * .2, sr = R * .52, spokes = R > 40 ? 6 : 4;
    final hole = R * (R > 40 ? .16 : .19);
    c.moveTo(hr, 0);
    c.arc(0, 0, hr, 0, kTau);
    for (var i = 0; i < spokes; i++) {
      final a = i / spokes * kTau, hx = math.cos(a) * sr, hy = math.sin(a) * sr;
      c.moveTo(hx + hole, hy);
      c.arc(hx, hy, hole, 0, kTau);
    }
    c.fillStyle = col;
    c.fill(evenOdd: true);
    c.restore();
  }

  /// `clockFace(c, X, Y, t)`: the tower's clock face, seen from inside; the
  /// second hand ticks.
  static void clockFace(Ctx c, double x, double y, double t) {
    const r = 100.0;
    c.fillStyle = const Color(0xFFEBEBEB);
    c.circ(x, y, r);
    c.strokeStyle = const Color(0xFFE3E3E3);
    c.lineWidth = 6;
    c.beginPath();
    c.arc(x, y, r - 3, 0, kTau);
    c.stroke();
    c.fillStyle = const Color(0xFFDEDEDE);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * kTau;
      c.save();
      c.translate(x + math.cos(a) * (r - 16), y + math.sin(a) * (r - 16));
      c.rotate(a);
      final major = i % 3 == 0;
      c.fillRect(major ? -6 : -3, -1.5, major ? 12 : 7, 3);
      c.restore();
    }
    c.fillStyle = const Color(0xFFD6D6D6);
    _hand(c, x, y, t / 720 * kTau + 1.2, 48, 6);
    _hand(c, x, y, t / 60 * kTau + .4, 70, 4);
    c.fillStyle = const Color(0xFFCECECE);
    _hand(c, x, y, t.floor() / 60 * kTau, 78, 1.6);
    c.circ(x, y, 5);
  }

  static void _hand(Ctx c, double x, double y, double a, double l, double w) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    c.fillRect(-w / 2, -l, w, l + 8);
    c.restore();
  }
}
