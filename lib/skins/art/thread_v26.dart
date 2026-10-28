import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintThreadV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(size);
  final p = Path();
  for (var i = 0; i <= 26; i++) {
    final u = i / 26, x = -u * 66, y = math.sin(u * 9 - t * 8) * 4.2 * u;
    i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
  }
  for (final (col, w) in [
    (const Color(0xffc98a00), 3.0),
    (artGold, 2.0),
    (const Color(0xfffff3c4), .7),
  ]) {
    c.drawPath(p, strokePaint(col, w));
  }
  for (var i = 0; i < 5; i++) {
    final u = (t * .9 + i / 5) % 1,
        x = -4 - u * 60,
        y = math.sin(u * 9 - t * 8) * 4.2 * u,
        r = Rect.fromCenter(
          center: Offset(x, y),
          width: (2.8 - u * 1.2) * 2,
          height: (8 - u * 3.5) * 2,
        );
    c.drawOval(
      r,
      strokePaint(const Color(0xffc98a00).withValues(alpha: 1 - u * .9), 2.4),
    );
    c.drawOval(
      r,
      strokePaint(const Color(0xffffe082).withValues(alpha: 1 - u * .9), 1.2),
    );
  }
  for (var i = 0; i < 6; i++) {
    final u = (t * .6 + i / 6) % 1;
    paintStar(
      c,
      -u * 60,
      (i.isOdd ? -8 : 8) * u,
      2.8 * (1 - u * .5),
      const Color(0xffffffff).withValues(alpha: 1 - u),
      rot: t * 2 + i,
    );
  }
  c.restore();
}
