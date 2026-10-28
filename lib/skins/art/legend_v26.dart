import 'dart:math' as math;
import 'dart:ui';
import 'shapes.dart';

void paintLegendV26(
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
  void comets() {
    for (var k = 0; k < 2; k++) {
      for (var j = 8; j >= 0; j--) {
        final a = t * 1.6 + k * math.pi - j * .1;
        if ((math.cos(a) < 0) != front) continue;
        final x = math.cos(a) * (radiusX + 8), y = math.sin(a) * (ry + 6);
        if (j == 0) {
          paintStar(c, x, y, 3.6, const Color(0xffffffff), rot: t * 5);
        } else {
          circ(
            c,
            x,
            y,
            2.5 - j * .24,
            (k == 1 ? const Color(0xffffe082) : const Color(0xfffff8e1))
                .withValues(alpha: 1 - j / 9),
          );
        }
      }
    }
  }

  if (!front) {
    final p = .5 + .5 * math.sin(t * 2.2);
    c.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: (radiusX + 2) * 2,
        height: (ry + 2) * 2,
      ),
      strokePaint(
        const Color(0xffffe082).withValues(alpha: .16 + p * .12),
        12 + p * 4,
      ),
    );
    comets();
  }
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: radiusX * 2,
    height: ry * 2,
  );
  c.drawArc(
    rect,
    a0,
    math.pi,
    false,
    strokePaint(
      front ? const Color(0xffe69500) : const Color(0xffa86f00),
      lineWidth * 1.2,
    ),
  );
  c.drawArc(
    rect,
    a0,
    math.pi,
    false,
    strokePaint(
      front ? artGold : const Color(0xffc98a00),
      lineWidth * (6.4 / 7),
    ),
  );
  final arc = Path()..addArc(rect, a0, math.pi);
  // SVG's positive dash offset advances the pattern along the path.
  final dashed = Path();
  for (final metric in arc.computeMetrics()) {
    final offset = (t * 7) % 6;
    for (var start = -offset; start < metric.length; start += 6) {
      final end = math.min(metric.length, start + 2.6);
      if (end > 0) {
        dashed.addPath(
          metric.extractPath(math.max(0, start), end),
          Offset.zero,
        );
      }
    }
  }
  c.drawPath(
    dashed,
    strokePaint(
      front ? const Color(0xfffff3c4) : const Color(0xffe0a800),
      lineWidth * (2 / 7),
    ),
  );
  if (front) {
    for (var i = 0; i < 10; i++) {
      final a = math.pi / 2 + (i + .5) / 10 * math.pi,
          x = math.cos(a) * (radiusX + 3.6),
          y = math.sin(a) * (ry + 3.6);
      c.save();
      c.translate(x, y);
      c.rotate(
        math.atan2(math.cos(a) * ry, -math.sin(a) * radiusX) +
            (i.isOdd ? .7 : -.7),
      );
      c.drawPath(
        polyPath([0, -3.4, 1.5, 0, 0, 2.2, -1.5, 0]),
        fillPaint(i.isOdd ? const Color(0xffffe082) : const Color(0xffe69500)),
      );
      c.restore();
    }
    final colors = [
      const Color(0xffe53935),
      const Color(0xff1e88e5),
      const Color(0xff43a047),
    ];
    for (var i = 0; i < 3; i++) {
      final a = (135 + i * 45) * math.pi / 180,
          x = math.cos(a) * radiusX,
          y = math.sin(a) * ry,
          L = math.pow(math.max(0, math.cos(t * 2.4 - i * 2.1)), 3).toDouble();
      circ(c, x, y, 4 + L * 4, colors[i].withValues(alpha: L * .35));
      c.drawPath(
        octPath(x - 3.6, y - 3.6, 7.2, 7.2, 2.1),
        fillPaint(colors[i]),
      );
      c.drawPath(
        polyPath([x - 2.1, y - 3.6, x + .9, y - 3.6, x - 2.1, y - .6]),
        fillPaint(const Color(0xb3ffffff)),
      );
      if (L > .6) {
        paintStar(
          c,
          x + 2.6,
          y - 2.6,
          1.5 + L * 2.4,
          const Color(0xffffffff),
          rot: t * 4,
        );
      }
    }
    comets();
    for (var i = 0; i < 3; i++) {
      final u = math.max(0.0, math.sin(t * 3.1 + i * 2.2));
      if (u > .1) {
        paintStar(
          c,
          [-radiusX - 12, radiusX + 9, -radiusX - 6][i],
          [-ry + 4, -ry - 6, ry + 2][i],
          1 + u * 2.6,
          const Color(0xfffff3c4),
        );
      }
    }
  }
  c.restore();
}
