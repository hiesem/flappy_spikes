import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintFirefliesV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(size);
  for (var i = 0; i < 11; i++) {
    final u = (t * .3 + i / 11) % 1,
        x = -6 - u * 58 + math.sin(t * 2.3 + i * 1.1) * 3,
        y =
            math.sin(t * 1.9 + i * 1.7) * 8 +
            math.cos(t * 1.1 + i * 2.2) * 4 -
            u * 3,
        b =
            math.pow(math.max(0, math.sin(t * 3.2 + i * 2.39)), 2).toDouble() *
            (1 - u * .45);
    circ(c, x, y, 7.5, const Color(0xffd4f53c).withValues(alpha: b * .3));
    circ(c, x, y, 3.8, const Color(0xffeeff6a).withValues(alpha: b * .65));
    circ(
      c,
      x,
      y,
      1.7,
      b > .25 ? const Color(0xfffffde7) : const Color(0xff4e5a22),
    );
  }
  c.restore();
}
