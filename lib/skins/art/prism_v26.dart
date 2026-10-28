import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/painting.dart' show HSLColor;
import 'bird_art.dart';

/// Cut-glass bird with an animated rainbow fan and travelling light.
void paintPrismV26(Canvas canvas, BirdShape s, double t, bool back) {
  final p = Paint();
  canvas.save();
  canvas.translate(s.l + 15, s.top + 15);
  if (back) {
    const colors = [
      Color(0xffff3b30),
      Color(0xffff9500),
      Color(0xffffcc00),
      Color(0xff34c759),
      Color(0xff00a2ff),
      Color(0xff7c4dff),
    ];
    for (var i = 0; i < 6; i++) {
      final sp = .1 + .025 * math.sin(t * 2 + i),
          a = math.pi + (i - 2.5) * sp + math.sin(t * 1.3) * .08,
          l = 26 + math.sin(t * 3 + i) * 3;
      final path = Path()
        ..moveTo(-17, -4)
        ..lineTo(-17 + math.cos(a - .05) * l, -4 + math.sin(a - .05) * l)
        ..lineTo(-17 + math.cos(a + .05) * l, -4 + math.sin(a + .05) * l)
        ..close();
      canvas.drawPath(
        path,
        p..color = colors[i].withValues(alpha: .5 + .3 * math.sin(t * 4 + i)),
      );
    }
    canvas.drawLine(
      const Offset(34, -24),
      const Offset(9, -7),
      p
        ..color = const Color(
          0xffffffff,
        ).withValues(alpha: .6 + .35 * math.sin(t * 5))
        ..strokeWidth = 1.8,
    );
    canvas.restore();
    return;
  }
  canvas.translate(-s.l - 15, -s.top - 15);
  canvas.drawPath(s.tailPath, p..color = const Color(0xffbde6fa));
  canvas.save();
  canvas.clipPath(s.body);
  canvas.translate(s.l, s.top);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 30, 30),
    p..color = const Color(0xffeaf8ff),
  );
  void facet(List<Offset> pts, Color color) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path..close(), p..color = color);
  }

  facet([
    const Offset(0, 0),
    const Offset(17, 0),
    const Offset(9, 15),
  ], const Color(0xffd2efff));
  facet([
    const Offset(17, 0),
    const Offset(30, 0),
    const Offset(30, 13),
    const Offset(9, 15),
  ], const Color(0xfff7fdff));
  facet([
    const Offset(0, 0),
    const Offset(9, 15),
    const Offset(0, 21),
  ], const Color(0xffbfe6fa));
  facet([
    const Offset(0, 21),
    const Offset(9, 15),
    const Offset(19, 30),
    const Offset(0, 30),
  ], const Color(0xffdcf3ff));
  facet([
    const Offset(9, 15),
    const Offset(30, 13),
    const Offset(30, 30),
    const Offset(19, 30),
  ], const Color(0xffc8eafb));
  final sx = -21 + ((t * .8) % 1.8) * 40;
  facet([
    Offset(sx, 0),
    Offset(sx + 5, 0),
    Offset(sx - 9, 30),
    Offset(sx - 14, 30),
  ], const Color(0xccffffff));
  canvas.drawLine(
    const Offset(9, 15),
    const Offset(30, 13),
    p
      ..color = HSLColor.fromAHSL(1, (t * 90) % 360, .9, .7).toColor()
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(9, 15),
    const Offset(19, 30),
    p
      ..color = HSLColor.fromAHSL(1, (t * 90 + 120) % 360, .9, .72).toColor()
      ..strokeWidth = .8,
  );
  facet([
    const Offset(6, 7),
    const Offset(22, 18),
    const Offset(6, 18),
  ], const Color(0x6b6eb9e4));
  facet([
    const Offset(6, 18),
    const Offset(22, 18),
    const Offset(6, 25),
  ], const Color(0x61a0d7f5));
  canvas.restore();
  canvas.restore();
}
