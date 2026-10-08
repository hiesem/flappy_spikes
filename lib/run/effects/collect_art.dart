import 'dart:ui';

/// The small drawing helpers the collectables share (a port of the lab
/// mocks' global `halo` / `star4` / `rr` / `fpoly`; ARCH §3 shared parts).
/// WP-3e, PRD-2 §5.25–§5.28.
abstract final class CollectArt {
  /// A radial glow: [color] at [alpha] at the centre, transparent at [r]
  /// (mock `halo()`: a radial gradient in a [r]×2[r] box).
  static void halo(Canvas canvas, Offset c, double r, Color color, double alpha) {
    if (r <= 0 || alpha <= 0) return;
    canvas.drawRect(
      Rect.fromCircle(center: c, radius: r),
      Paint()
        ..shader = Gradient.radial(c, r, [
          color.withValues(alpha: alpha.clamp(0.0, 1.0)),
          color.withValues(alpha: 0),
        ]),
    );
  }

  static final Paint _fill = Paint();

  /// A 4-point star centred at [c] with tip distance [size] (mock `star4`:
  /// two overlapping diamonds, waist at 0.22 × size).
  static void star4(Canvas canvas, Offset c, double size, Color color) {
    if (size <= 0) return;
    _fill.color = color;
    final w = size * .22;
    canvas
      ..drawPath(
        Path()
          ..moveTo(c.dx, c.dy - size)
          ..lineTo(c.dx + w, c.dy)
          ..lineTo(c.dx, c.dy + size)
          ..lineTo(c.dx - w, c.dy)
          ..close(),
        _fill,
      )
      ..drawPath(
        Path()
          ..moveTo(c.dx - size, c.dy)
          ..lineTo(c.dx, c.dy + w)
          ..lineTo(c.dx + size, c.dy)
          ..lineTo(c.dx, c.dy - w)
          ..close(),
        _fill,
      );
  }

  /// A filled triangle (mock `fpoly`).
  static void triangle(Canvas canvas, List<Offset> pts, Color color) {
    if (pts.length < 3) return;
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    _fill.color = color;
    canvas.drawPath(p..close(), _fill);
  }

  /// A filled rounded rectangle (mock `rr`).
  static void roundRect(Canvas canvas, Rect r, double radius, Color color) {
    _fill.color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius)),
      _fill,
    );
  }
}
