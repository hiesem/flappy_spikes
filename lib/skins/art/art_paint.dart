import 'dart:math' as math;
import 'dart:ui';

/// Shared canvas primitives ported 1:1 from `design/menu_v2/skin_art.js`
/// (the `circ` / `star` / `heart` / `poly` / `hash` / `lerpC` helpers) and one
/// Canvas2D feature `dart:ui` lacks: dashed strokes.
///
/// Pure painting: no Flame, no game state. The skin-art painters
/// (`LookPainter`, [HoopPainter], [TrailEmitter]) share these so every layer
/// is drawn with the flat, chunky geometry of the approved mocks.
class ArtPaint {
  ArtPaint._();

  /// `TAU` in skin_art.js.
  static const double tau = math.pi * 2;

  /// `hash(i)`: the mock's deterministic `[0,1)` pseudo-random value. Used by
  /// the galaxy and black-hole hoops so their twinkles depend only on `t`.
  static double hash(double i) {
    final s = math.sin(i * 127.1 + 311.7) * 43758.5453;
    return s - s.floorToDouble();
  }

  /// `circ(ctx,x,y,r,c)` — a filled circle.
  static void circ(Canvas canvas, double x, double y, double r, Color color) {
    if (r <= 0 || color.a == 0) return;
    canvas.drawCircle(Offset(x, y), r, Paint()..color = color);
  }

  /// `star(ctx,x,y,r,c,rot)` — the mock's 8-pointed star: alternating radii
  /// `r` and `r * 0.38`, starting on the +x axis.
  static void star(
    Canvas canvas,
    double x,
    double y,
    double r,
    Color color, [
    double rot = 0,
  ]) {
    if (r <= 0 || color.a == 0) return;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isOdd ? r * .38 : r;
      final angle = i * math.pi / 4;
      final px = math.cos(angle) * radius;
      final py = math.sin(angle) * radius;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas
      ..save()
      ..translate(x, y)
      ..rotate(rot)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  /// `heart(ctx,x,y,s,c)` — a bezier heart in a 20x20 box scaled by `s / 10`.
  static void heart(Canvas canvas, double x, double y, double s, Color color) {
    final path = Path()
      ..moveTo(0, 4)
      ..cubicTo(-7, -1, -5, -7, 0, -3.5)
      ..cubicTo(5, -7, 7, -1, 0, 4)
      ..close();
    canvas
      ..save()
      ..translate(x, y)
      ..scale(s / 10, s / 10)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  /// `poly(pts)` — the mock's closed polygon.
  static Path poly(List<Offset> points) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// `lerpC(a,b,u)` — component-wise interpolation of two sRGB colours,
  /// matching Canvas2D's `rgb()` result (truncated, not rounded).
  static Color lerpColor(Color a, Color b, double u) {
    int mix(double from, double to) =>
        (((from + (to - from) * u).clamp(0.0, 1.0)) * 255).truncate();
    return Color.fromARGB(255, mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b));
  }

  /// Emulates Canvas2D `setLineDash` + `lineDashOffset`: returns [source] with
  /// [pattern] (alternating dash/gap lengths, repeated) applied, starting
  /// [offset] units into the pattern. The mock uses this for the candy,
  /// checker, lava and black-hole rings.
  ///
  /// Dashes are placed by cycle index rather than by walking the pattern
  /// positionally, so rounding at a dash boundary can never stall the walk.
  static Path dashed(Path source, List<double> pattern, double offset) {
    final out = Path();
    if (pattern.isEmpty) return out;
    var period = 0.0;
    for (final value in pattern) {
      period += value;
    }
    if (period <= 0) return out;
    for (final metric in source.computeMetrics()) {
      final length = metric.length;
      var edge = 0.0;
      for (var i = 0; i < pattern.length; i += 2) {
        final dash = pattern[i];
        if (dash > 0) {
          final last = edge - offset + dash;
          final first =
              edge - offset + ((-last) / period).ceilToDouble() * period;
          for (var start = first; start < length; start += period) {
            final from = math.max(start, 0.0);
            final to = math.min(start + dash, length);
            if (to > from) {
              out.addPath(metric.extractPath(from, to), Offset.zero);
            }
          }
        }
        edge += dash + (i + 1 < pattern.length ? pattern[i + 1] : 0);
      }
    }
    return out;
  }
}
