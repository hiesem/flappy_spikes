import 'dart:ui';

import '../config/parts_config.dart';

/// Master #1 art — the 44 pt spike strip (PRD §3.0.9 #1, the mocks' strip,
/// `rides84.js spikes()`, `screen_hoops4.html .sp`): a solid band of 26 pt
/// plus triangular teeth 18 pt deep, tooth period 40 pt (tips at
/// x = 20 + 40 k + offset), one flat fill in the stage foreground colour.
/// The pattern is a repeating 40 × 44 tooth tile, so the teeth scroll by
/// [paint]'s `offset` (squeeze, ride return).
///
/// Drawn in *strip space*: y = 0 is the screen edge, y grows towards the
/// playfield (the caller flips the canvas for the floor strip). The solid
/// band always fills from the edge to [reach] − 18 so a taller strip (the
/// 72 pt physics strip before WP-1a switches `Config.spikeHeight` to 44)
/// stays full-bleed with the same teeth.
abstract final class SpikeTeethPainter {
  static const double height = PartsConfig.spikeStripHeight;
  static const double band = PartsConfig.spikeBand;
  static const double depth = PartsConfig.spikeToothDepth;
  static const double period = PartsConfig.spikeToothPeriod;

  static final Paint _paint = Paint();
  static final Path _path = Path();

  /// The x of the first tooth tip ≥ 0 for a scroll [offset].
  static double firstTip(double offset) {
    final o = ((offset % period) + period) % period;
    return (period / 2 + o) % period;
  }

  /// Paints a strip [width] wide whose tooth tips are [reach] pt from the
  /// edge (44 = the master strip). [offset] scrolls the teeth (positive =
  /// right). [opacity] fades the whole strip (ride fade).
  static void paint(
    Canvas canvas, {
    required double width,
    required Color color,
    double reach = height,
    double offset = 0,
    double opacity = 1,
    double left = 0,
  }) {
    if (opacity <= 0 || reach <= 0) return;
    final base = reach - depth;
    final a = (color.a * opacity).clamp(0.0, 1.0);
    _paint.color = color.withValues(alpha: a);
    _path.reset();
    if (base > 0) _path.addRect(Rect.fromLTWH(left, -1, width, base + 1));
    // Teeth: one triangle per period, starting one period left of the view.
    final o = ((offset % period) + period) % period;
    for (var x = left - 2 * period + o; x < left + width + period; x += period) {
      _path
        ..moveTo(x, base)
        ..lineTo(x + period / 2, reach)
        ..lineTo(x + period, base)
        ..close();
    }
    canvas.drawPath(_path, _paint);
  }
}
