import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintNestV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(size);
  final phase = (t * .42) % 1,
      up = phase < .12
          ? 1 - math.pow(1 - phase / .12, 3).toDouble()
          : phase < .5
          ? 1.0
          : phase < .6
          ? 1 - math.pow((phase - .5) / .1, 3).toDouble()
          : 0.0,
      peep = phase > .16 && phase < .46 && math.sin(t * 15) > 0;
  c.drawOval(
    Rect.fromCenter(center: const Offset(0, -4.5), width: 24, height: 9.2),
    fillPaint(const Color(0xff5d4037)),
  );
  if (up <= 0) {
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, -6), width: 7.2, height: 8.4),
      fillPaint(const Color(0xfffff8e1)),
    );
    c.drawPath(
      polyPath([-2.4, -7, -1, -8.4, .4, -7, 1.8, -8.6, 3, -7.2]),
      fillPaint(const Color(0xffe0d7c0)),
    );
  } else {
    final y = -5 - up * 8;
    circ(c, 0, y, 5, const Color(0xffffd54f));
    c.drawPath(
      polyPath([-1, y - 4.6, .4, y - 7.4, 1.6, y - 4.6]),
      fillPaint(const Color(0xffffc107)),
    );
    fillRect(c, 1.2, y - 2.4, 1.6, 1.6, const Color(0xff3e2723));
    c.drawPath(
      polyPath([4.4, y - 1.2, 7.8, y - .2, 4.4, y + .8]),
      fillPaint(const Color(0xffff7a1a)),
    );
    if (peep) {
      final hy = y - 6 - (t * 6 % 3);
      final heart = Path()
        ..moveTo(9, hy + 2)
        ..cubicTo(4, hy - 1, 6, hy - 4, 9, hy - 2)
        ..cubicTo(12, hy - 4, 14, hy - 1, 9, hy + 2)
        ..close();
      c.drawPath(heart, fillPaint(const Color(0xffff4fb7)));
    }
  }
  final p = Path()
    ..moveTo(-13, -5)
    ..quadraticBezierTo(0, 4, 13, -5)
    ..lineTo(12.5, -.6)
    ..quadraticBezierTo(0, 6, -12.5, -.6)
    ..close();
  c.drawPath(p, fillPaint(const Color(0xff8d6e63)));
  for (var i = 0; i < 5; i++) {
    final x = -12 + i * 5.0, y = -3.6 + (i - 2).abs() * .2;
    final p = Path()
      ..moveTo(x, y)
      ..relativeQuadraticBezierTo(2.6, 2.4, 5.2, 0);
    c.drawPath(p, strokePaint(const Color(0xffa1887f), 1));
  }
  c.drawLine(
    const Offset(-13, -4),
    const Offset(-17, -8),
    strokePaint(const Color(0xff6d4c41), 1.1),
  );
  c.drawLine(
    const Offset(12, -3.5),
    const Offset(17, -6),
    strokePaint(const Color(0xff6d4c41), 1.1),
  );
  c.drawLine(
    const Offset(9, -1),
    const Offset(14, 1.5),
    strokePaint(const Color(0xff795548), 1),
  );
  c.restore();
}
