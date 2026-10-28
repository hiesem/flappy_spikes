import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintSpikesV26(
  Canvas c,
  Offset center,
  double size,
  double t, {
  bool front = true,
}) {
  c.save();
  c.translate(center.dx, center.dy);
  final ry = size, rx = ry * .26;
  for (var i = 0; i < 18; i++) {
    final a = (i + .5) / 18 * tau, co = math.cos(a), si = math.sin(a);
    if ((co < 0) != front) continue;
    final wave = math
            .pow(math.max(0, math.sin(t * 4.2 - a * 2)), 1.6)
            .toDouble(),
        len = 2.5 + wave * 10;
    final x1 = math.cos(a - .14) * rx,
        y1 = math.sin(a - .14) * ry,
        x2 = math.cos(a + .14) * rx,
        y2 = math.sin(a + .14) * ry,
        tx = co * (rx + len),
        ty = si * (ry + len);
    c.drawPath(
      polyPath([x1, y1, tx, ty, x2, y2]),
      fillPaint(front ? const Color(0xffa3aeb5) : const Color(0xff5b656b)),
    );
    c.drawPath(
      polyPath([x1, y1, tx, ty, co * rx, si * ry]),
      fillPaint(front ? const Color(0xff6e7b83) : const Color(0xff4d575d)),
    );
    if (front && wave > .55) {
      final k = (wave - .55) / .45;
      paintStar(
        c,
        tx,
        ty,
        1 + k * 2.6,
        const Color(0xffffffff),
        rot: t * 7 + i,
      );
      for (var j = 0; j < 2; j++) {
        final d = 4 + k * 9 + j * 3;
        fillRect(
          c,
          tx + co * d + (j == 1 ? 2 : -2) * si - .8,
          ty + si * d - (j == 1 ? 2 : -2) * co - .8,
          1.6,
          1.6,
          (j == 1 ? artGold : const Color(0xffffe082)).withValues(
            alpha: k * .9,
          ),
        );
      }
    }
  }
  c.drawArc(
    Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
    front ? math.pi / 2 : -math.pi / 2,
    math.pi,
    false,
    strokePaint(front ? const Color(0xffb9c3c9) : const Color(0xff4d575d), 7),
  );
  if (front) {
    final arc = Path()
      ..addArc(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        math.pi / 2,
        math.pi,
      );
    c.drawPath(
      dashPath(arc, [1.5, 8]),
      strokePaint(const Color(0xff7d8a92), 7),
    );
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 2 + (i + .5) * math.pi / 6;
      circ(
        c,
        math.cos(a) * rx,
        math.sin(a) * ry,
        1.15,
        const Color(0xffe6ebee),
      );
    }
    final a = math.pi / 2 + (t * .75 % 1.5) * math.pi;
    if (a < math.pi * 1.5 - .05) {
      final start = math.max(math.pi / 2, a - .35),
          end = math.min(math.pi * 1.5, a + .35);
      c.drawArc(
        Rect.fromCenter(
          center: Offset.zero,
          width: (rx - 1.6) * 2,
          height: (ry - 1.6) * 2,
        ),
        start,
        end - start,
        false,
        strokePaint(const Color(0xffffffff), 2.2)..strokeCap = StrokeCap.round,
      );
    }
  }
  c.restore();
}
