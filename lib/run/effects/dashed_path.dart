import 'dart:ui';

import '../../skins/art/art_paint.dart';
import '../config/parts_config.dart';

/// The shared dashed line (ARCH §3 "Dashed path", PRD §5.12): 2.5 pt,
/// 6 on / 6 off, butt caps, wrapping `ArtPaint.dashed`. Used by the moving
/// ring guides (fg, 0.75), the train track (fg 50 %, phase −40 pt/s), the
/// bullseye lines (fg 45 %), the Iris cable (fg 75 %) and the star trail line
/// (gold 45 %, 2 pt, 2 / 6). Parameters: colour, width, pattern, phase,
/// round caps.
abstract final class DashedPathPainter {
  static const List<double> pattern = [PartsConfig.dashOn, PartsConfig.dashOff];

  static final Paint _paint = Paint()..style = PaintingStyle.stroke;

  /// Strokes [path] dashed.
  static void stroke(
    Canvas canvas,
    Path path, {
    required Color color,
    double width = PartsConfig.dashWidth,
    List<double> dashes = pattern,
    double phase = 0,
    bool roundCaps = false,
  }) {
    if (width <= 0 || color.a <= 0) return;
    _paint
      ..strokeWidth = width
      ..color = color
      ..strokeCap = roundCaps ? StrokeCap.round : StrokeCap.butt;
    canvas.drawPath(ArtPaint.dashed(path, dashes, phase), _paint);
  }

  /// A straight dashed segment.
  static void line(
    Canvas canvas,
    Offset a,
    Offset b, {
    required Color color,
    double width = PartsConfig.dashWidth,
    List<double> dashes = pattern,
    double phase = 0,
  }) => stroke(
    canvas,
    Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy),
    color: color,
    width: width,
    dashes: dashes,
    phase: phase,
  );
}
