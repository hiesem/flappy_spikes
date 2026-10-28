import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'art_paint.dart';
import 'bird_art.dart';

/// Jackpot hat; [back] is reserved for the back pass.
void paintJackpotV26(Canvas canvas, BirdShape s, double t, bool back) {
  if (back) return;
  final x = s.hx, y = s.top, cycle = (t * .36) % 1;
  final p = Paint();
  void rect(double x, double y, double w, double h, Color c) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), p..color = c);
  final dome = Path()
    ..moveTo(x - 11, y - 15)
    ..quadraticBezierTo(x, y - 24.5, x + 11, y - 15)
    ..close();
  canvas.drawPath(dome, p..color = const Color(0xffffb529));
  final domeOutline = Path()
    ..moveTo(x - 11, y - 15)
    ..quadraticBezierTo(x, y - 24.5, x + 11, y - 15);
  canvas.drawPath(
    domeOutline,
    Paint()
      ..color = const Color(0xffc98a00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8,
  );
  for (var i = 0; i < 5; i++) {
    final a = math.pi * (1 - (i + .5) / 5);
    canvas.drawCircle(
      Offset(x + math.cos(a) * 8.4, y - 15.6 - math.sin(a) * 5.8),
      1.15,
      p
        ..color = ((t * 9).floor() + i).isEven || cycle > .66
            ? const Color(0xffffffff)
            : const Color(0xffc98a00),
    );
  }
  rect(x - 11, y - 15, 22, 15, const Color(0xffe53935));
  rect(x + 6.5, y - 15, 4.5, 15, const Color(0xffb71c1c));
  rect(x - 11, y - 2.4, 22, 2.4, const Color(0xff8e0000));
  final window = Rect.fromLTWH(x - 9.4, y - 13, 18.8, 9);
  canvas.drawRect(
    window,
    p
      ..color = cycle > .66 && cycle < .97 && (t * 10).floor().isOdd
          ? const Color(0xfffff3c4)
          : const Color(0xffffffff),
  );
  canvas.save();
  canvas.clipRect(window);
  for (var k = 0; k < 3; k++) {
    final cx = x - 6.3 + k * 6.3, stop = .3 + k * .12;
    final spinning = cycle < stop && cycle > .04;
    final off = spinning ? (t * 70 + k * 5) % 9 : 0.0;
    for (final dy in spinning ? [-9.0, 0.0] : [0.0]) {
      final color = spinning
          ? const Color(0xffb0b0b0)
          : cycle >= stop
          ? const Color(0xffe53935)
          : const Color(0xffc62828);
      final text = TextPainter(
        text: TextSpan(
          text: '7',
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w600,
            fontSize: 8,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = text.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      text.paint(
        canvas,
        Offset(cx - text.width / 2, y - 5.3 + off + dy - baseline),
      );
      text.dispose();
    }
  }
  canvas.restore();
  for (final dx in [-3.15, 3.15]) {
    canvas.drawLine(
      Offset(x + dx, y - 13),
      Offset(x + dx, y - 4),
      p
        ..color = const Color(0xffe0e0e0)
        ..strokeWidth = .6,
    );
  }
  final pull = cycle < .1 ? math.sin(cycle / .1 * math.pi) : 0.0;
  rect(x + 11, y - 10.5, 2.2, 4, const Color(0xff9e9e9e));
  canvas.drawLine(
    Offset(x + 13, y - 8.5),
    Offset(x + 15, y - 15 + pull * 9),
    p
      ..color = const Color(0xffbdbdbd)
      ..strokeWidth = 1.3,
  );
  canvas.drawCircle(
    Offset(x + 15, y - 15.6 + pull * 9),
    2,
    p..color = const Color(0xffe53935),
  );
  if (cycle > .66) {
    for (var i = 0; i < 4; i++) {
      final u = ((cycle - .67 - i * .05) / .24).clamp(0.0, 1.0);
      if (u <= 0 || u >= 1) continue;
      final pos = Offset(x + (i - 1.5) * 5 * u, y - 20 - u * 15 + u * u * 12);
      canvas.drawCircle(
        pos,
        2.3,
        p..color = const Color(0xffffb529).withValues(alpha: 1 - u * u),
      );
      canvas.drawCircle(
        pos,
        1.2,
        p..color = const Color(0xffffe7a6).withValues(alpha: 1 - u * u),
      );
    }
    ArtPaint.star(
      canvas,
      x - 13,
      y - 18,
      1.5 + math.sin(t * 9).abs() * 2,
      const Color(0xffffffff),
    );
    ArtPaint.star(
      canvas,
      x + 12,
      y - 21,
      1.2 + math.cos(t * 8).abs() * 1.8,
      const Color(0xffffe082),
    );
  }
}
