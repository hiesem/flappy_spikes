import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintPhoenixringV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
  double? rx,
  double lineWidth = 7,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  final ry = size, a0 = front ? math.pi / 2 : -math.pi / 2;
  final radiusX = rx ?? ry * .26;
  for (var i = 0; i < 9; i++) {
    final a = a0 + (i + .5) * math.pi / 9,
        co = math.cos(a),
        si = math.sin(a),
        len = 9 + math.sin(t * 13 + i * 1.9) * 2.6;
    c.drawPath(
      polyPath([
        math.cos(a - .16) * radiusX,
        math.sin(a - .16) * ry,
        co * (radiusX + len),
        si * (ry + len),
        math.cos(a + .16) * radiusX,
        math.sin(a + .16) * ry,
      ]),
      fillPaint(
        front
            ? (i.isOdd ? artGold : const Color(0xffff7a1a))
            : const Color(0xffd84315),
      ),
    );
  }
  c.drawArc(
    Rect.fromCenter(center: Offset.zero, width: radiusX * 2, height: ry * 2),
    a0,
    math.pi,
    false,
    strokePaint(
      front ? const Color(0xffff5722) : const Color(0xffb23000),
      lineWidth,
    ),
  );
  if (front) {
    c.drawArc(
      Rect.fromCenter(
        center: Offset.zero,
        width: (radiusX - 1.4) * 2,
        height: (ry - 1.4) * 2,
      ),
      a0,
      math.pi,
      false,
      strokePaint(const Color(0xffffe082), 1.6),
    );
    for (var i = 0; i < 6; i++) {
      final u = (t * .7 + i / 6) % 1,
          y = ry - u * (2 * ry + 18),
          x = -radiusX - 3 + math.sin(t * 4 + i * 2) * 3;
      fillRect(
        c,
        x - 1,
        y,
        2.2,
        2.2,
        (i.isOdd ? const Color(0xffffe082) : artGold).withValues(alpha: 1 - u),
      );
    }
  }
  c.restore();
}
