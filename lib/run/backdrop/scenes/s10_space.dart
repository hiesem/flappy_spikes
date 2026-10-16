import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 10, Space (`drawSpace`, "10. Space (flat)"):
/// twinkling stars, ringed planets with a small moon, a drifting
/// satellite, a comet every 16 s, tumbling asteroids and a moon-dust
/// ground with craters.
class SpaceScene extends BackdropScene {
  const SpaceScene();

  @override
  String get name => 'Space';

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        each(c, cam * .04, 26, 1101, (x, r, k) {
          final sx = x + r() * 20, sy = 50 + r() * 440;
          if (r() < .5) {
            c.fillStyle = const Color(0xFFD6D6D6);
            c.circ(sx, sy, .9 + r() * .8);
          } else {
            final s = 2 + (.5 + .5 * math.sin(t * 2 + k * 2.3)) * 2.2;
            c.fillStyle = const Color(0xFFD2D2D2);
            c.fillRect(sx - s, sy - .6, s * 2, 1.2);
            c.fillRect(sx - .6, sy - s, 1.2, s * 2);
          }
        });
        c.strip(1001, cam * .04, (off) => _planets(c, off));
        _satellite(c, t, cam);
        _comet(c, t);
      case Band.far:
        return;
      case Band.mid:
        each(c, cam * .2, 120, 1121, (x, r, k) {
          // tumbling asteroids
          if (r() < .4) return;
          final X = x + r() * 40, Y = 140 + r() * 300, R = 6 + r() * 10;
          final rot = t * (.3 + r() * .5) * (k.isOdd ? 1 : -1);
          c.save();
          c.translate(X, Y);
          c.rotate(rot);
          c.fillStyle = const Color(0xFFDADADA);
          c.beginPath();
          for (var i = 0; i < 8; i++) {
            final a = i / 8 * kTau, rr = R * (.75 + r() * .35);
            if (i == 0) {
              c.moveTo(math.cos(a) * rr, math.sin(a) * rr);
            } else {
              c.lineTo(math.cos(a) * rr, math.sin(a) * rr);
            }
          }
          c.closePath();
          c.fill();
          c.fillStyle = const Color(0xFFD1D1D1);
          c.circ(R * .2, -R * .2, R * .22);
          c.circ(-R * .3, R * .25, R * .15);
          c.restore();
        });
      case Band.near:
        c.strip(1002, cam * .3, (off) {
          ridge(c, off, 518, 6, 44, 19, const Color(0xFFDCDCDC), 1.1);
          each(c, off, 70, 1131, (x, r, k) {
            if (r() < .3) return;
            c.fillStyle = const Color(0xFFD2D2D2);
            c.beginPath();
            c.ellipse(x + r() * 30, 527 + r() * 4, 9 + r() * 7, 2.5, 0, 0, kTau);
            c.fill();
          });
        });
      case Band.front:
        return;
    }
  }

  // ringed planet with a small moon
  static void _planets(Ctx c, double off) {
    each(c, off, 520, 1111, (x, r, k) {
      final X = x + 200 + r() * 60, Y = 160 + r() * 60, R = 46 + r() * 14;
      _ring(c, X, Y, R, math.pi, kTau);
      c.fillStyle = const Color(0xFFE6E6E6);
      c.circ(X, Y, R);
      c.save();
      c.beginPath();
      c.arc(X, Y, R, 0, kTau);
      c.clip();
      c.fillStyle = const Color(0xFFE0E0E0);
      c.fillRect(X - R, Y - R * .35, R * 2, R * .18);
      c.fillRect(X - R, Y + R * .2, R * 2, R * .12);
      c.fillStyle = const Color.fromRGBO(200, 200, 200, .35);
      c.circ(X + R * .45, Y + R * .35, R);
      c.restore();
      _ring(c, X, Y, R, 0, math.pi);
      c.fillStyle = const Color(0xFFE2E2E2);
      c.circ(X - R * 1.9, Y + R * .9, 9);
    });
  }

  static void _ring(Ctx c, double X, double Y, double R, double a0, double a1) {
    c.save();
    c.translate(X, Y);
    c.rotate(-.3);
    c.strokeStyle = const Color(0xFFD9D9D9);
    c.lineWidth = 6;
    c.beginPath();
    c.ellipse(0, 0, R * 1.65, R * .32, 0, a0, a1);
    c.stroke();
    c.restore();
  }

  // satellite drifting across
  static void _satellite(Ctx c, double t, double cam) {
    final x = kVW + 40 - modD(t * 8 + cam * .055, kVW + 300), y = 300 + math.sin(t * .4) * 10;
    c.save();
    c.translate(x, y);
    c.rotate(t * .3);
    c.fillStyle = const Color(0xFFE2E2E2);
    c.fillRect(-22, -3, 14, 6);
    c.fillRect(8, -3, 14, 6);
    c.fillStyle = const Color(0xFFD6D6D6);
    c.fillRect(-15.5, -3, 1, 6);
    c.fillRect(14.5, -3, 1, 6);
    c.fillRect(-8, -.5, 16, 1);
    c.fillStyle = const Color(0xFFD8D8D8);
    c.fillRect(-5, -4, 10, 8);
    c.fillRect(-.5, -10, 1, 6);
    c.circ(0, -10, 1.6);
    c.restore();
  }

  // the comet's tail, drawn from the head (0, 0) to (70, −46)
  static final Shader _tail = Gradient.linear(
    Offset.zero,
    const Offset(70, -46),
    const [Color.fromRGBO(200, 200, 200, .8), Color.fromRGBO(200, 200, 200, 0)],
  );

  // comet every 16 s
  static void _comet(Ctx c, double t) {
    final p = modD(t, 16) / 3;
    if (p >= 1) return;
    final x = kVW + 20 - p * (kVW + 80), y = 70 + p * 200;
    c.save();
    c.translate(x, y);
    c.strokeShader = _tail;
    c.lineWidth = 3;
    c.lineCap = StrokeCap.round;
    c.beginPath();
    c.moveTo(0, 0);
    c.lineTo(70, -46);
    c.stroke();
    c.fillStyle = const Color(0xFFFAFAFA);
    c.circ(0, 0, 4);
    c.strokeStyle = const Color(0xFFCFCFCF);
    c.lineWidth = 1;
    c.beginPath();
    c.arc(0, 0, 4, 0, kTau);
    c.stroke();
    c.restore();
  }
}
