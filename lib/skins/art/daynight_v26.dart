import 'dart:math' as math;
import 'dart:ui';
import 'art_paint.dart';
import 'bird_art.dart';

/// Sky changes through day, sunset, night and dawn on the supplied clock.
void paintDaynightV26(Canvas canvas, BirdShape s, double t, bool back) {
  if (back) return;
  final phase = (t * .16) % 1;
  const stops = [
    (0.0, Color(0xff4fc3f7), Color(0xff0277bd), 0.0),
    (.38, Color(0xff4fc3f7), Color(0xff0277bd), 0.0),
    (.48, Color(0xffff8a65), Color(0xffbf360c), .15),
    (.58, Color(0xff283593), Color(0xff121858), 1.0),
    (.88, Color(0xff283593), Color(0xff121858), 1.0),
    (.95, Color(0xfff48fb1), Color(0xffad1457), .3),
    (1.0, Color(0xff4fc3f7), Color(0xff0277bd), 0.0),
  ];
  var i = 1;
  while (i < stops.length - 1 && phase > stops[i].$1) {
    i++;
  }
  final a = stops[i - 1], b = stops[i], u = (phase - a.$1) / (b.$1 - a.$1);
  final sky = Color.lerp(a.$2, b.$2, u)!,
      tail = Color.lerp(a.$3, b.$3, u)!,
      night = a.$4 + (b.$4 - a.$4) * u;
  final p = Paint();
  canvas.drawPath(s.tailPath, p..color = tail);
  canvas.drawPath(s.body, p..color = sky);
  canvas.save();
  canvas.clipPath(s.body);
  canvas.translate(s.l + 15, s.top + 15);
  const stars = [
    Offset(-10, -11),
    Offset(-3, -6),
    Offset(8, -12),
    Offset(11, -4),
    Offset(-12, 0),
    Offset(3, -13),
  ];
  for (var j = 0; j < stars.length; j++) {
    ArtPaint.star(
      canvas,
      stars[j].dx,
      stars[j].dy,
      1.2 + (j % 3) * .5,
      const Color(0xffffffff).withValues(
        alpha: (night * (.6 + .4 * math.sin(t * 5 + j))).clamp(0, 1),
      ),
    );
  }
  final day = phase < .53,
      q = day ? phase / .53 : (phase - .53) / .47,
      x = -16 + q * 32,
      y = -2 - math.sin(q * math.pi) * 10;
  if (day) {
    canvas.drawCircle(Offset(x, y), 7, p..color = const Color(0x73ffe082));
    canvas.drawCircle(Offset(x, y), 4.4, p..color = const Color(0xffffb529));
    final cx = 5 - (t * 4) % 30;
    canvas.saveLayer(
      null,
      Paint()..color = const Color(0xffffffff).withValues(alpha: 1 - night),
    );
    for (final (dx, dy, r) in [
      (0.0, 0.0, 2.6),
      (3.0, -1.4, 3.2),
      (6.2, 0.0, 2.4),
    ]) {
      canvas.drawCircle(
        Offset(cx + dx, 9 + dy),
        r,
        p..color = const Color(0xffffffff),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(cx, 9, 6.2, 2.6),
      p..color = const Color(0xffffffff),
    );
    canvas.restore();
  } else {
    canvas.drawCircle(Offset(x, y), 4.2, p..color = const Color(0xfffff8e1));
    canvas.drawCircle(Offset(x + 1.8, y - 1.2), 3.6, p..color = sky);
  }
  canvas.restore();
}
