import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

double _eBack(double u) => u <= 0
    ? 0
    : u >= 1
    ? 1
    : 1 + 2.9 * math.pow(u - 1, 3) + 1.9 * math.pow(u - 1, 2);

void paintConstellationV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(size);
  final u = (t * .42) % 1, sh = u * 10;
  const pts = [
    Offset(-4, 2),
    Offset(-13, -7),
    Offset(-24, -3),
    Offset(-32, -11),
    Offset(-43, -5),
    Offset(-51, 5),
    Offset(-62, -2),
  ];
  double vis(int i) =>
      ((u - i * .075) / .06).clamp(0, 1) * (1 - ((u - .84) / .16).clamp(0, 1));
  for (var i = 1; i < pts.length; i++) {
    final o = math.min(vis(i - 1), vis(i)),
        a = pts[i - 1] - Offset(sh, 0),
        b = pts[i] - Offset(sh, 0);
    c.drawLine(
      a,
      b,
      strokePaint(const Color(0xffb39dff).withValues(alpha: o * .7), 1.6),
    );
    c.drawLine(
      a,
      b,
      strokePaint(const Color(0xffffffff).withValues(alpha: o), .6),
    );
  }
  for (var i = 0; i < pts.length; i++) {
    final v = vis(i);
    if (v <= 0) continue;
    final r =
            (i == 3
                ? 4.6
                : i.isOdd
                ? 2.6
                : 3.2) *
            (.75 + .25 * math.sin(t * 7 + i * 1.3)) *
            _eBack(v),
        x = pts[i].dx - sh,
        y = pts[i].dy;
    circ(c, x, y, r * 1.9, const Color(0xffb39dff).withValues(alpha: v * .25));
    paintStar(
      c,
      x,
      y,
      r,
      i.isOdd ? const Color(0xffffffff) : const Color(0xffffe082),
      rot: t * 1.5 + i,
    );
  }
  c.restore();
}
