import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 3, City Skyline (`drawCity`, "3. City Skyline").
class CityScene extends BackdropScene {
  const CityScene();

  @override
  String get name => 'City Skyline';

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        // (the prototype's `vgrad` here is not forced: it draws nothing)
        c.fillStyle = const Color(0xFFEEEEEE);
        c.circ(mark(c, -68), 356, 70);
        each(c, cam * .04 + t * 5, 180, 71, (x, r, k) {
          if (r() < .35) return;
          final px = x + r() * 60, py = 92 + r() * 130, pw = 40 + r() * 50;
          pill(c, px, py, pw, 9 + r() * 5, const Color(0xFFF8F8F8));
        });
        // blimp
        final bx = kVW + 60 - modD(t * 10 + cam * .05, kVW + 360);
        final by = 128 + math.sin(t * .5) * 4;
        c.save();
        c.translate(bx, by);
        c.fillStyle = const Color(0xFFE3E3E3);
        c.beginPath();
        c.moveTo(24, 0);
        c.lineTo(36, -9);
        c.lineTo(36, 9);
        c.closePath();
        c.fill();
        c.beginPath();
        c.ellipse(0, 0, 30, 10, 0, 0, kTau);
        c.fill();
        c.save();
        c.clip();
        c.fillStyle = const Color(0xFFD3D3D3);
        c.fillRect(4, -10, 4, 20);
        c.restore();
        c.fillStyle = const Color(0xFFD9D9D9);
        c.beginPath();
        c.roundRect(-6, 9, 12, 4, 2);
        c.fill();
        c.restore();
      case Band.far:
        c.strip(301, cam * .06, (off) {
          each(c, off, 30, 81, (x, r, k) {
            final w = 22 + r() * 14, h = 80 + r() * 120;
            c.fillStyle = const Color(0xFFE6E6E6);
            c.fillRect(x, 545 - h, w, h + 80);
            if (r() < .25) c.fillRect(x + w / 2 - 1, 545 - h - 14, 2, 14);
          });
        });
      case Band.mid:
        each(c, cam * .16, 52, 91, (x, r, k) {
          final w = 36 + r() * 12, h = 70 + r() * 110, top = 548 - h;
          c.fillStyle = const Color(0xFFDBDBDB);
          c.fillRect(x, top, w, h + 80);
          final cols = ((w - 6) / 9).floor(), rows = ((h - 14) / 12).floor();
          for (var i = 0; i < cols; i++) {
            for (var j = 0; j < rows; j++) {
              final id = k * 977 + i * 31 + j * 7;
              final p = t / 4 + hash(id) * 4, n = p.floor(), f = p - n;
              final a = _lit(id, n)
                  ? math.min(1.0, f * 3)
                  : (_lit(id, n - 1) ? math.max(0.0, 1 - f * 3) : 0.0);
              c.fillStyle = const Color(0xFFE5E5E5);
              c.fillRect(x + 5 + i * 9, top + 8 + j * 12, 5, 7);
              if (a > 0) {
                c.globalAlpha = a;
                c.fillStyle = const Color(0xFFEEEEEE);
                c.fillRect(x + 5 + i * 9, top + 8 + j * 12, 5, 7);
                c.globalAlpha = 1;
              }
            }
          }
          final roof = r();
          if (roof < .22) {
            // water tower
            final wx = x + w * .3;
            c.fillStyle = const Color(0xFFD3D3D3);
            c.fillRect(wx, top - 6, 1.5, 6);
            c.fillRect(wx + 9, top - 6, 1.5, 6);
            c.beginPath();
            c.roundRect(wx - 1, top - 17, 12.5, 12, 2);
            c.fill();
            c.beginPath();
            c.moveTo(wx - 2, top - 17);
            c.lineTo(wx + 5.25, top - 22);
            c.lineTo(wx + 12.5, top - 17);
            c.fill();
          } else if (roof < .45) {
            // antenna with a blinking light
            final ax = x + w * .6;
            c.fillStyle = const Color(0xFFD3D3D3);
            c.fillRect(ax, top - 22, 1.6, 22);
            final al = .35 + .65 * math.max(0.0, math.sin(t * 2.4 + k));
            c.fillStyle = Color.fromRGBO(196, 196, 196, (al * 1000).round() / 1000);
            c.circ(ax + .8, top - 23, 1.9);
          }
        });
      case Band.near:
        each(c, cam * .3, 34, 101, (x, r, k) {
          if (r() < .3) return;
          if (r() < .72) {
            final rr = 7 + r() * 4;
            c.fillStyle = const Color(0xFFCFCFCF);
            c.fillRect(x - 1, 522, 2, 110);
            c.circ(x, 520 - rr * .3, rr);
          } else {
            c.fillStyle = const Color(0xFFCBCBCB);
            c.fillRect(x - .8, 500, 1.6, 130);
            c.fillRect(x - .8, 500, 7, 1.6);
            c.fillStyle = const Color(0xFFEBEBEB);
            c.circ(x + 6, 503, 2.2);
          }
        });
      case Band.front:
        return;
    }
  }

  static bool _lit(int id, int m) => hash(id + m * 101) > .88;
}
