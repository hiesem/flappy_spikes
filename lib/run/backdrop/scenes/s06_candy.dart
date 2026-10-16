import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 6, Candy Land (`drawCandy`, "2. Candy Land"): soft
/// clouds and drifting sprinkles, jelly hills, spinning lollipops and a row
/// of gumdrops.
class CandyScene extends BackdropScene {
  const CandyScene();

  @override
  String get name => 'Candy Land';

  /// `GUMS`: the gumball greys (seam 5 drops them into this scene).
  static const List<Color> gums = [
    Color(0xFFD0D0D0),
    Color(0xFFD7D7D7),
    Color(0xFFE0E0E0),
    Color(0xFFD0D0D0),
  ];

  static const List<Color> _lolly = [
    Color(0xFFC5C5C5),
    Color(0xFFC8C8C8),
    Color(0xFFC3C3C3),
  ];

  static const List<Color> _sprCols = [
    Color(0xFFC9C9C9),
    Color(0xFFD3D3D3),
    Color(0xFFDDDDDD),
    Color(0xFFCDCDCD),
  ];

  /// `SPR`: 28 sprinkles (x, y share, angle).
  static final List<double> _spr = [
    for (var i = 0; i < 28; i++) ...[hash(i * 3 + 1), hash(i * 3 + 2), hash(i * 3 + 3) * kTau],
  ];

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        // (the prototype's `vgrad` here is not forced: it draws nothing)
        each(c, cam * .045 + t * 3, 170, 41, (x, r, k) {
          if (r() < .25) return;
          final sx = x + r() * 40, sy = 90 + r() * 140;
          softCloud(c, sx, sy, .7 + r() * .45);
        });
        for (var i = 0; i < 28; i++) {
          final sx = _spr[i * 3], sy = _spr[i * 3 + 1], sa = _spr[i * 3 + 2];
          final y = 80 + sy * 360 + math.sin(t * .8 + sa * 3) * 6;
          wraps(c, sx * (kVW + 40) - cam * .14 - t * 3, kVW + 40, 20, (x) {
            c.save();
            c.translate(x, y);
            c.rotate(sa + t * .4);
            c.globalAlpha = .7;
            c.fillStyle = _sprCols[i % 4];
            c.beginPath();
            c.roundRect(-3.5, -1.2, 7, 2.4, 1.2);
            c.fill();
            c.restore();
          });
        }
      case Band.far:
        c.strip(601, cam * .1, (off) {
          jelly(c, off, 452, 24, 66, 29, const Color(0xFFE5E5E5), const Color(0xFFDADADA), .4);
        });
      case Band.mid:
        final off = cam * .22;
        each(c, off, 112, 53, (x, r, k) {
          if (r() < .3) return;
          final lx = x + r() * 30, h = 60 + r() * 55, rr = 12 + r() * 7;
          final col = _lolly[(r() * 3).floor()], dir = r() < .5 ? -1 : 1;
          final y = 506 - h + math.sin(t * 1.1 + k) * 2;
          c.strokeStyle = const Color(0xFFE4E4E4);
          c.lineWidth = 3;
          c.beginPath();
          c.moveTo(lx, y);
          c.lineTo(lx, 520);
          c.stroke();
          c.save();
          c.translate(lx, y);
          c.rotate(t * .5 * dir);
          c.fillStyle = const Color(0xFFF5F5F5);
          c.circ(0, 0, rr);
          c.strokeStyle = col;
          c.lineWidth = 3;
          c.lineCap = StrokeCap.round;
          c.beginPath();
          for (var a = 0.0; a <= 5 * math.pi; a += .2) {
            final sr = rr * .92 * a / (5 * math.pi);
            final px = math.cos(a) * sr, py = math.sin(a) * sr;
            a != 0 ? c.lineTo(px, py) : c.moveTo(px, py);
          }
          c.stroke();
          c.restore();
          c.fillStyle = const Color.fromRGBO(255, 255, 255, .7);
          c.beginPath();
          c.ellipse(lx - rr * .38, y - rr * .42, rr * .32, rr * .15, -.6, 0, kTau);
          c.fill();
        });
        c.strip(602, off, (off) {
          jelly(c, off, 500, 15, 52, 23, const Color(0xFFDDDDDD), const Color(0xFFD2D2D2), 2.2);
        });
      case Band.near:
        c.strip(603, cam * .34, (off) {
          each(c, off, 56, 67, (x, r, k) {
            if (r() < .4) return;
            final gx = x + r() * 20, s = 9 + r() * 5, col = gums[(r() * 4).floor()];
            c.fillStyle = col;
            c.beginPath();
            c.ellipse(gx, 536, s, s * 1.25, 0, math.pi, kTau);
            c.fill();
            c.fillStyle = const Color.fromRGBO(255, 255, 255, .75);
            for (var i = 0; i < 4; i++) {
              final dx = r() * s, dy = r() * s * .8;
              c.circ(gx - s * .5 + dx, 536 - s * .3 - dy, .9);
            }
            c.fillStyle = const Color.fromRGBO(255, 255, 255, .55);
            c.beginPath();
            c.ellipse(gx - s * .4, 536 - s * .8, s * .25, s * .12, -.7, 0, kTau);
            c.fill();
          });
        });
      case Band.front:
        return;
    }
  }

  /// `jelly(c, off, base, amp, f1, f2, top, bot, ph)`: a jelly hill with a
  /// gradient and a dashed white highlight.
  static void jelly(Ctx c, double off, double base, double amp, double f1, double f2,
      Color top, Color bot, double ph) {
    ridgePath(c, off, base, amp, f1, f2, ph);
    c.fillShader = c.linearGradient(0, base - amp, 0, base + 60, [top, bot], const [0, 1]);
    c.fill();
    c.beginPath();
    for (var x = c.xl; x <= c.xr + 4; x += 4) {
      final y = ridgeY(off, x, base, amp, f1, f2, ph) + 6;
      x > c.xl ? c.lineTo(x, y) : c.moveTo(x, y);
    }
    c.strokeStyle = const Color.fromRGBO(255, 255, 255, .55);
    c.lineWidth = 3;
    c.lineCap = StrokeCap.round;
    c.lineDash = const [16, 46];
    c.lineDashOffset = off;
    c.stroke();
    c.lineDash = null;
  }

  /// `softCloud(c, x, y, s)`.
  static void softCloud(Ctx c, double x, double y, double s) {
    c.fillStyle = const Color(0xFFE9E9E9);
    for (var i = 0; i < 4; i++) {
      c.circ(x + _parts[i * 3] * s, y + (_parts[i * 3 + 1] + 4) * s, _parts[i * 3 + 2] * s);
    }
    c.fillStyle = const Color(0xFFF9F9F9);
    for (var i = 0; i < 4; i++) {
      c.circ(x + _parts[i * 3] * s, y + _parts[i * 3 + 1] * s, _parts[i * 3 + 2] * s);
    }
  }

  static const List<double> _parts = [0, 6, 15, 18, 0, 19, 38, 4, 15, 52, 9, 11];
}
