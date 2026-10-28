import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/painting.dart' show HSLColor;
import 'bird_art.dart';

/// Magpie body, chest, tail and shimmering wing.
void paintMagpieV26(Canvas canvas, BirdShape s, double t, bool back) {
  if (back) return;
  final h = 215 + math.sin(t * 1.7) * 30;
  Color hue(double h, double sat, double light) =>
      HSLColor.fromAHSL(1, h % 360, sat, light).toColor();
  final p = Paint();
  canvas.drawPath(s.tailPath, p..color = hue(h - 20, .7, .32));
  canvas.drawPath(s.body, p..color = const Color(0xff1c1c1c));
  canvas.save();
  canvas.clipPath(s.body);
  final chest = Path()
    ..moveTo(s.l + 17, s.top + 17)
    ..lineTo(s.r, s.top + 13)
    ..lineTo(s.r, s.bot)
    ..lineTo(s.l + 15, s.bot)
    ..close();
  canvas.drawPath(chest, p..color = const Color(0xfffafafa));
  canvas.restore();
}
