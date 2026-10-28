import 'dart:math' as math;
import 'dart:ui';
import 'bird_art.dart';

/// Brass goggles and a fluttering scarf, split around the bird.
void paintGogglesV26(Canvas canvas, BirdShape s, double t, bool back) {
  final p = Paint();
  canvas.save();
  canvas.translate(s.l + 15, s.top + 15);
  void rect(double x, double y, double w, double h, Color c) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), p..color = c);
  if (back) {
    final w = math.sin(t * 8), w2 = math.sin(t * 8 + 1.2);
    final path = Path()
      ..moveTo(-14, 5.4)
      ..lineTo(-14, 10)
      ..lineTo(-24, 9.5 + w * 2)
      ..lineTo(-35, 12.5 + w2 * 3)
      ..lineTo(-33, 6 + w2 * 3)
      ..lineTo(-24, 5 + w * 2)
      ..close();
    canvas.drawPath(path, p..color = const Color(0xffe53935));
    final stripe = Path()
      ..moveTo(-24, 7 + w * 2)
      ..lineTo(-34, 9.5 + w2 * 3)
      ..lineTo(-33.6, 8 + w2 * 3)
      ..lineTo(-24, 5.8 + w * 2)
      ..close();
    canvas.drawPath(stripe, p..color = const Color(0xffffffff));
  } else {
    rect(-15, -10, 30, 3.6, const Color(0xff6d4c41));
    rect(-15, -9, 30, 1, const Color(0xff8d6e63));
    rect(-15, 5, 30, 4.8, const Color(0xffe53935));
    rect(-15, 6.8, 30, 1.2, const Color(0xffffffff));
    for (final (x, y, r, c) in [
      (-3.0, -6.8, 3.8, const Color(0xffa87400)),
      (-3.0, -6.8, 2.6, const Color(0xff26a69a)),
      (7.0, -6.0, 5.6, const Color(0xffc98a00)),
      (7.0, -6.0, 4.6, const Color(0xffffc233)),
      (7.0, -6.0, 3.6, const Color(0xff4dd0e1)),
    ]) {
      canvas.drawCircle(Offset(x, y), r, p..color = c);
    }
    final glint = Path()
      ..moveTo(4.6, -8.6)
      ..lineTo(6.6, -8.6)
      ..lineTo(4.6, -6.6)
      ..close();
    canvas.drawPath(glint, p..color = const Color(0xffffffff));
    rect(2, -7.2, 1.4, 2, const Color(0xff6d4c41));
  }
  canvas.restore();
}
