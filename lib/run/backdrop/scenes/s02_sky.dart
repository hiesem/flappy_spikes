import 'dart:math' as math;
import 'dart:ui';

import '../backdrop_ctx.dart';
import '../backdrop_helpers.dart';
import '../backdrop_math.dart';
import '../backdrop_scene.dart';

/// PRD-2.4 §3.3 scene 2, Sky & Hills (`drawSky`, "1. Sky & Hills (flat)").
/// The world's greys are this scene's: the colour stage maps them
/// (PRD §3.3 "Colour stages").
class SkyScene extends BackdropScene {
  const SkyScene();

  @override
  String get name => 'Sky & Hills';

  /// The mid hills (`ridge(off, 492, 20, 58, 27, …, 1.7)`): seam 2 stands
  /// its building and cottage on them.
  static double midHill(double off, double x) =>
      ridgeY(off, x, 492, 20, 58, 27, 1.7);

  /// The far hills (`ridge(off, 446, 24, 70, 31, …, .3)`): seam 1's pond
  /// lies on them.
  static double farHill(double off, double x) =>
      ridgeY(off, x, 446, 24, 70, 31, .3);

  @override
  void draw(Ctx c, Band band) {
    final t = c.t, cam = c.cam;
    switch (band) {
      case Band.sky:
        c.fillStyle = const Color(0xFFF6F6F6);
        c.circ(mark(c, 76), 150, 60);
        c.fillStyle = const Color(0xFFFAFAFA);
        c.circ(mark(c, 76), 150, 42);
        each(c, cam * .045 + t * 4, 150, 11, (x, r, k) {
          if (r() < .3) return;
          final cx = x + r() * 50, cy = 80 + r() * 140;
          flatCloud(c, cx, cy, .6 + r() * .5, const Color(0xFFFAFAFA));
        });
        // a small flock that crosses every ~25 s
        final p = modD(t * 16 + cam * .055, kVW + 420), fx = kVW + 40 - p;
        final fy = 190 + math.sin(t * .4) * 10;
        c.strokeStyle = const Color(0xFFC4C4C4);
        c.lineWidth = 1.4;
        c.lineCap = StrokeCap.round;
        c.lineJoin = StrokeJoin.round;
        for (var i = 0; i < 3; i++) {
          final dx = _flock[i * 2], dy = _flock[i * 2 + 1];
          final w = math.sin(t * 8 + i * 1.7) * 2.6, x = fx + dx, y = fy + dy;
          c.beginPath();
          c.moveTo(x - 5, y - w);
          c.lineTo(x, y);
          c.lineTo(x + 5, y - w);
          c.stroke();
        }
      case Band.far:
        ridge(c, cam * .09, 446, 24, 70, 31, const Color(0xFFE8E8E8), .3);
      case Band.mid:
        final off = cam * .2;
        ridge(c, off, 492, 20, 58, 27, const Color(0xFFDEDEDE), 1.7);
        each(c, off, 44, 23, (x, r, k) {
          if (r() < .45) return;
          final tx = x + r() * 20, y = midHill(off, tx) + 3;
          final h = 12 + r() * 10, rr = 6 + r() * 4;
          final sway = math.sin(t * 1.4 + k) * 1.2;
          c.fillStyle = const Color(0xFFD2D2D2);
          c.fillRect(tx - 1.2, y - h, 2.4, h);
          c.fillStyle = const Color(0xFFD7D7D7);
          c.circ(tx + sway, y - h - rr * .6, rr);
        });
      case Band.near:
        ridge(c, cam * .32, 526, 8, 40, 19, const Color(0xFFD5D5D5), 2.9);
      case Band.front:
        return;
    }
  }

  static const List<double> _flock = [0, 0, 15, 7, 27, -4];
}
