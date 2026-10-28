import 'dart:math' as math;
import 'dart:ui';
import 'art_paint.dart';
import 'bird_art.dart';

/// Opening peacock fan and its bobbing crest.
void paintPeacockV26(Canvas canvas, BirdShape s, double t, bool back) {
  final p = Paint();
  canvas.save();
  if (back) {
    final edge = s.hasBl ? s.bl : s.l;
    canvas.translate(edge + 15, s.neck - 9);
    final openness = .62 + .38 * math.sin(t * 1.4);
    for (var i = 0; i < 9; i++) {
      final u = i / 8 - .5,
          a = -math.pi * .74 + u * 1.9 * openness,
          l = 26 + math.cos(u * 3) * 4,
          x = -13 + math.cos(a) * l,
          y = -2 + math.sin(a) * l;
      canvas.drawLine(
        const Offset(-13, -2),
        Offset(x, y),
        p
          ..color = const Color(0xff00796b)
          ..strokeWidth = 1.1,
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(a + math.pi / 2);
      for (final (rx, ry, dy, c) in [
        (
          5.0,
          7.4,
          0.0,
          i.isOdd ? const Color(0xff26a69a) : const Color(0xff2bb673),
        ),
        (3.4, 4.8, -.6, const Color(0xffffb529)),
        (
          2.6,
          3.8,
          -.4,
          Color.lerp(
            const Color(0xff1565c0),
            const Color(0xff7c4dff),
            .5 + .5 * math.sin(t * 3 + i),
          )!,
        ),
        (1.3, 1.8, 0.0, const Color(0xff0d1b4c)),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, dy), width: rx * 2, height: ry * 2),
          p..color = c,
        );
      }
      canvas.restore();
      final tw = math.max(0.0, math.sin(t * 4 + i * 1.7));
      if (tw > .7) {
        ArtPaint.star(
          canvas,
          x + 1.5,
          y - 2,
          1 + tw * 1.8,
          const Color(0xffffffff),
        );
      }
    }
  } else {
    canvas.translate(s.eye.dx - 7, s.top + 15);
    for (var i = 0; i < 3; i++) {
      final x = 4 + i * 2.5,
          y = (i == 1 ? -22.5 : -21) + math.sin(t * 4 + i) * .6;
      canvas.drawLine(
        Offset(6 + (i - 1) * .8, -15),
        Offset(x, y),
        p
          ..color = const Color(0xff00796b)
          ..strokeWidth = .8,
      );
      canvas.drawCircle(Offset(x, y), 1.4, p..color = const Color(0xff1e88e5));
    }
  }
  canvas.restore();
}
