import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintSkycrownV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(size);
  for (final (dx, h) in [(-8.0, 8.0), (0.0, 12.0), (8.0, 8.0)]) {
    c.drawPath(
      polyPath([dx - 2.8, -5, dx, -5 - h, dx + 2.8, -5]),
      fillPaint(artGold),
    );
    final big = dx == 0,
        r = Rect.fromCenter(
          center: Offset(dx, -5 - h - 3.6),
          width: big ? 6.4 : 5,
          height: big ? 9.2 : 7.2,
        );
    c.drawOval(
      r,
      strokePaint(big ? const Color(0xffb0006b) : const Color(0xff0277bd), 2.2),
    );
    c.drawOval(r, strokePaint(big ? artPink : const Color(0xff29b6f6), 1.3));
  }
  fillRect(c, -11.5, -6, 23, 6, artGold);
  fillRect(c, -11.5, -1.8, 23, 1.8, const Color(0xffe69500));
  c.drawPath(
    polyPath([-11.5, -6, -4, -6, -11.5, -3]),
    fillPaint(const Color(0x73ffffff)),
  );
  c.drawPath(
    octPath(-2.6, -5.4, 5.2, 4.4, 1.3),
    fillPaint(const Color(0xffe53935)),
  );
  fillRect(c, -7.6, -4.2, 2.2, 2.2, const Color(0xff1e88e5));
  fillRect(c, 5.4, -4.2, 2.2, 2.2, const Color(0xff43a047));
  paintStar(
    c,
    13,
    -20 + math.sin(t * 3),
    2.8,
    const Color(0xffffffff),
    rot: t * 2,
  );
  paintStar(c, -13, -14, 1.8, const Color(0xffffe082), rot: -t * 2);
  c.restore();
}
