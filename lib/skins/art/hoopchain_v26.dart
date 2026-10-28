import 'dart:math' as math;
import 'dart:ui';
import 'art_paint.dart';
import 'bird_art.dart';

/// Gold hoop links and swinging pendant.
void paintHoopchainV26(Canvas canvas, BirdShape s, double t, bool back) {
  if (back) return;
  final p = Paint()..style = PaintingStyle.stroke;
  canvas.save();
  final backEdge = s.hasBl ? s.bl : s.l;
  final startX = backEdge + (s.r - backEdge) * 13 / 30;
  final width = s.r - startX;
  final top = s.neck - 6.4;
  for (var i = 0; i <= 9; i++) {
    final u = i / 9,
        x = startX + width * u,
        y = top + math.sin(u * math.pi) * 6.4;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: 2.3, height: 3.8),
      p
        ..color = i.isOdd ? const Color(0xffffc233) : const Color(0xffc98a00)
        ..strokeWidth = 1.3,
    );
  }
  final u = 5 / 9;
  canvas.translate(startX + width * u, top + math.sin(u * math.pi) * 6.4 + 1.4);
  canvas.rotate(math.sin(t * 3.2) * math.pi / 10);
  canvas.drawLine(
    Offset.zero,
    const Offset(0, 2.4),
    p
      ..color = const Color(0xffc98a00)
      ..strokeWidth = .9,
  );
  for (final (w, h, c, sw) in [
    (7.6, 12.0, const Color(0xffb07800), 2.8),
    (7.6, 12.0, const Color(0xffffb529), 1.6),
    (4.4, 8.4, const Color(0xffec008c), 1.0),
  ]) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 8.4), width: w, height: h),
      p
        ..color = c
        ..strokeWidth = sw,
    );
  }
  ArtPaint.star(
    canvas,
    3,
    4,
    1.2 + math.max(0, math.sin(t * 5)) * 1.8,
    const Color(0xffffffff),
    t * 3,
  );
  canvas.restore();
}
