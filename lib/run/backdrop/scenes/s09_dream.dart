import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';
import 's08_sea.dart';

/// PRD-2.4 §3.3 scene 9, Dreamland (`drawDream`, "5. Dreamland (paper
/// cut)"): a paper crescent moon on a string, sparkles, glowing orbs, the
/// sea's last bubbles, floating islands with houses, trees and waterfalls,
/// a paper plane and two paper cloud rows.
class DreamScene extends BackdropScene {
  const DreamScene();

  @override
  String get name => 'Dreamland';

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        // (the prototype's `vgrad` here is not forced: it draws nothing)
        bubbles(c, dream: true); // bubbles from the sea, still rising
        for (var i = 0; i < _orbs.length; i++) {
          final o = _orbs[i];
          wraps(c, o.sx * (kVW + 120) - cam * .05 + t * (i.isOdd ? 3 : -2), kVW + 120, 60,
              (x) {
            c.save();
            c.translate(x, o.y);
            c.fillShader = o.glow;
            c.circ(0, 0, o.r);
            c.restore();
          });
        }
        each(c, cam * .04, 44, 141, (x, r, k) {
          if (r() < .35) return;
          final sx = x + r() * 20, sy = 64 + r() * 300;
          final s = (2.5 + r() * 3) * (.55 + .45 * math.sin(t * 1.6 + k * 1.9));
          _sparkle(c, sx, sy, s);
        });
        // the paper moon on its string (a landmark, 0.04×)
        c.save();
        c.translate(mark(c, 90), -10);
        c.rotate(math.sin(t * .7) * .06);
        c.strokeStyle = const Color(0xFFD0D0D0);
        c.lineWidth = 1;
        c.beginPath();
        // on a taller view the string reaches up to the top of the screen
        c.moveTo(0, c.yTop);
        c.lineTo(0, 100);
        c.stroke();
        c.fillStyle = const Color(0xFFDDDDDD);
        c.canvas.drawPath(_moonShadow, c.fillPaint);
        c.fillStyle = const Color(0xFFF6F6F6);
        c.canvas.drawPath(_moon, c.fillPaint);
        c.restore();
      case Band.far:
        c.strip(901, cam * .1,
            (off) => _paperRow(c, off, 470, 24, const Color(0xFFE8E8E8), const Color(0xFFDFDFDF), 151));
        each(c, cam * .12, 230, 161, (x, r, k) {
          if (r() < .25) return;
          _island(c, x + r() * 60, 150 + r() * 110 + math.sin(t * .7 + k * 1.3) * 5, .62, r, t, k);
        });
        // a paper plane
        final p = modD(t * 26, kVW + 700) - 120;
        if (p < kVW + 60) {
          final x = p, y = 230 + math.sin(t * .9) * 16 - p * .05;
          c.save();
          c.translate(x, y);
          c.rotate(-.12 + math.cos(t * .9) * .08);
          c.fillStyle = const Color(0xFFFFFFFF);
          c.beginPath();
          c.moveTo(14, 0);
          c.lineTo(-10, -7);
          c.lineTo(-6, 0);
          c.closePath();
          c.fill();
          c.fillStyle = const Color(0xFFDADADA);
          c.beginPath();
          c.moveTo(14, 0);
          c.lineTo(-6, 0);
          c.lineTo(-10, 5);
          c.closePath();
          c.fill();
          c.restore();
        }
      case Band.mid:
        each(c, cam * .24, 290, 171, (x, r, k) {
          if (r() < .3) return;
          _island(c, x + r() * 60, 310 + r() * 110 + math.sin(t * .7 + k * 1.3 + 2) * 5, 1, r, t,
              k + 9);
        });
      case Band.near:
        c.strip(902, cam * .3,
            (off) => _paperRow(c, off, 520, 19, const Color(0xFFE1E1E1), const Color(0xFFD6D6D6), 181));
      case Band.front:
        return;
    }
  }

  // `crescent(col)`: a 22-pt disc less a 19-pt disc, drawn at (-32, 90)
  // (the moon) and (-30, 93) (its shadow) in the string's frame.
  static Path _crescent(double dx, double dy) => Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: Offset(dx + 32, dy + 32), radius: 22)),
        Path()..addOval(Rect.fromCircle(center: Offset(dx + 42, dy + 25), radius: 19)),
      );

  static final Path _moon = _crescent(-32, 90);
  static final Path _moonShadow = _crescent(-32 + 2, 90 + 3);

  static final List<_Orb> _orbs = List.generate(6, (i) {
    final sx = hash(i * 7 + 501), sy = hash(i * 7 + 502), sz = hash(i * 7 + 503);
    final v = i.isOdd ? 226 : 231, r = 26 + sz * 30;
    return _Orb(
      sx,
      90 + sy * 360,
      r,
      Gradient.radial(Offset.zero, r, [
        Color.fromRGBO(v, v, v, .75),
        Color.fromRGBO(v, v, v, 0),
      ]),
    );
  });

  // `sparkle(c, x, y, s)`.
  static void _sparkle(Ctx c, double x, double y, double s) {
    c.beginPath();
    c.moveTo(x, y - s);
    c.quadraticCurveTo(x, y, x + s, y);
    c.quadraticCurveTo(x, y, x, y + s);
    c.quadraticCurveTo(x, y, x - s, y);
    c.quadraticCurveTo(x, y, x, y - s);
    c.fillStyle = const Color(0xFFFFFFFF);
    c.fill();
    c.strokeStyle = const Color(0xFFD7D7D7);
    c.lineWidth = .8;
    c.stroke();
  }

  // `paperRow(c, off, base, r0, col, sh, seed)`.
  static void _paperRow(
      Ctx c, double off, double base, double r0, Color col, Color sh, int seed) {
    each(c, off, 30, seed, (x, r, k) {
      final rr = r0 * (.8 + r() * .5);
      c.fillStyle = sh;
      c.circ(x + 3, base - r() * 10 + 3, rr);
    });
    c.fillRect(c.xl, base + 3, c.xr - c.xl, math.max(48, kVH - base));
    each(c, off, 30, seed, (x, r, k) {
      final rr = r0 * (.8 + r() * .5);
      c.fillStyle = col;
      c.circ(x, base - r() * 10, rr);
    });
    c.fillRect(c.xl, base, c.xr - c.xl, math.max(48, kVH - base));
  }

  static final Shader _fall = Gradient.linear(
    Offset.zero,
    const Offset(0, 52),
    const [Color.fromRGBO(255, 255, 255, .95), Color.fromRGBO(255, 255, 255, 0)],
  );

  static const List<double> _roots = [-14, 18, 14, 12, 20, 11, -2, 40, 9];
  static const List<double> _trees = [-12, 8, 4, 11, 18, 7];

  // `island(c, x, y, s, r, t, k)`.
  static void _island(Ctx c, double x, double y, double s, Rng r, double t, int k) {
    c.save();
    c.translate(x, y);
    c.scale(s, s);
    c.fillStyle = const Color(0xFFE2E2E2);
    c.beginPath();
    c.moveTo(-34, 0);
    c.quadraticCurveTo(-22, 22, -4, 40);
    c.lineTo(0, 46);
    c.quadraticCurveTo(14, 26, 34, 0);
    c.closePath();
    c.fill();
    c.fillStyle = const Color(0xFFDADADA);
    c.beginPath();
    c.moveTo(6, 0);
    c.lineTo(34, 0);
    c.quadraticCurveTo(14, 26, 0, 46);
    c.closePath();
    c.fill();
    c.strokeStyle = const Color(0xFFD1D1D1);
    c.lineWidth = 1.2;
    c.lineCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final rx = _roots[i * 3], ry = _roots[i * 3 + 1], l = _roots[i * 3 + 2];
      final sw = math.sin(t * 1.3 + k + i) * 2;
      c.beginPath();
      c.moveTo(rx, ry);
      c.quadraticCurveTo(rx + sw, ry + l * .6, rx + sw * 1.5, ry + l);
      c.stroke();
    }
    if (r() < .3) {
      // waterfall
      c.fillShader = _fall;
      c.fillRect(-29, 0, 4, 52);
      c.fillStyle = const Color.fromRGBO(218, 218, 218, .8);
      for (var j = 0; j < 4; j++) {
        c.fillRect(-28, modD(t * 30 + j * 13, 52), 2, 4);
      }
    }
    c.fillStyle = const Color(0xFFD6D6D6);
    c.beginPath();
    c.ellipse(0, 0, 36, 6, 0, 0, kTau);
    c.fill();
    final d = r();
    if (d < .45) {
      c.fillStyle = const Color(0xFFF6F6F6);
      c.fillRect(-7, -14, 13, 11);
      c.fillStyle = const Color(0xFFD2D2D2);
      c.beginPath();
      c.moveTo(-9, -14);
      c.lineTo(-.5, -22);
      c.lineTo(8, -14);
      c.closePath();
      c.fill();
      c.fillStyle = const Color(0xFFD9D9D9);
      c.fillRect(-2, -10, 3.5, 4);
      c.fillStyle = const Color(0xFFCDCDCD);
      c.fillRect(14, -14, 2, 10);
      c.circ(15, -17, 6);
    } else if (d < .8) {
      c.fillStyle = const Color(0xFFCDCDCD);
      for (var i = 0; i < 3; i++) {
        final tx = _trees[i * 2], rr = _trees[i * 2 + 1];
        c.fillRect(tx - 1, -4 - rr, 2, rr);
        c.circ(tx, -4 - rr * 1.2, rr * .7);
      }
    }
    c.restore();
  }
}

class _Orb {
  const _Orb(this.sx, this.y, this.r, this.glow);
  final double sx, y, r;
  final Shader glow;
}
