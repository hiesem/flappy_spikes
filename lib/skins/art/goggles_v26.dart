import 'dart:math' as math;
import 'dart:ui';
import 'bird_art.dart';

/// Brass goggles and a fluttering scarf, split around the bird.
void paintGogglesV26(Canvas canvas, BirdShape s, double t, bool back) {
  final p = Paint();
  canvas.save();
  final backEdge = s.hasBl ? s.bl : s.l;
  void rect(double x, double y, double w, double h, Color c) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), p..color = c);
  if (back) {
    canvas.translate(backEdge + 1, s.neck - 3.6);
    final w = math.sin(t * 8), w2 = math.sin(t * 8 + 1.2);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 4.6)
      ..lineTo(-10, 4.1 + w * 2)
      ..lineTo(-21, 7.1 + w2 * 3)
      ..lineTo(-19, .6 + w2 * 3)
      ..lineTo(-10, -.4 + w * 2)
      ..close();
    canvas.drawPath(path, p..color = const Color(0xffe53935));
    final stripe = Path()
      ..moveTo(-10, 1.6 + w * 2)
      ..lineTo(-20, 4.1 + w2 * 3)
      ..lineTo(-19.6, 2.6 + w2 * 3)
      ..lineTo(-10, .4 + w * 2)
      ..close();
    canvas.drawPath(stripe, p..color = const Color(0xffffffff));
  } else {
    rect(s.l, s.eye.dy - 4, s.r - s.l, 3.6, const Color(0xff6d4c41));
    rect(s.l, s.eye.dy - 3, s.r - s.l, 1, const Color(0xff8d6e63));
    rect(backEdge, s.neck - 4, s.r - backEdge, 4.8, const Color(0xffe53935));
    rect(backEdge, s.neck - 2.2, s.r - backEdge, 1.2, const Color(0xffffffff));
    canvas.translate(s.eye.dx - 7, s.eye.dy + 6);
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
