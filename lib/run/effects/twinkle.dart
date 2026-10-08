import 'dart:math' as math;
import 'dart:ui';

/// The four-point twinkle star (ARCH §3 "Twinkle"; §5.3 sparkles): an
/// 8-vertex star whose tips are [size] apart and whose waist vertices sit at
/// `waist × tip radius` on the diagonals — with [ringWaist] it is exactly the
/// mock polygon `12,0 15,9 24,12 15,15 12,24 9,15 0,12 9,9`.
///
/// Used by the ring tier sparkles (`RingTierFx`), feather, puzzle piece and
/// switch pickups. [curve] is the shared twinkle timeline.
abstract final class Twinkle {
  /// Waist of the §5.3 ring sparkle (the mock polygon's inner vertices sit
  /// at 0.354 of the tip radius).
  static const double ringWaist = .3536;

  /// Waist of the pickup twinkles (feather, puzzle piece, switch:
  /// `collect.js sparkle()`).
  static const double pickupWaist = .28;

  static final Map<double, Path> _paths = {};

  static Path _unit(double waist) => _paths.putIfAbsent(waist, () {
    final p = Path();
    for (var i = 0; i < 8; i++) {
      final r = (i.isOdd ? waist : 1.0) * .5;
      final a = i * math.pi / 4 - math.pi / 2;
      final x = math.cos(a) * r, y = math.sin(a) * r;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p..close();
  });

  static final Paint _paint = Paint();

  /// Paints the star centred at [centre], [size] pt from tip to tip.
  static void paint(
    Canvas canvas,
    Offset centre,
    double size,
    Color color, {
    double rotation = 0,
    double waist = ringWaist,
  }) {
    if (size <= 0 || color.a <= 0) return;
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(rotation)
      ..scale(size)
      ..drawPath(_unit(waist), _paint..color = color)
      ..restore();
  }

  /// §5.3 twinkle at normalised time [k] (0..1): `(scale, rotation, alpha)`.
  /// Keyframes: k 0 → (0, 0°, 0); k 0.4 → (1.1, 45°, 1); k 1 → (0, 90°, 0),
  /// linear between them (the mock's WAAPI keyframes).
  static (double, double, double) curve(double k) {
    if (k <= 0) return (0, 0, 0);
    if (k >= 1) return (0, math.pi / 2, 0);
    if (k < .4) {
      final u = k / .4;
      return (1.1 * u, math.pi / 4 * u, u);
    }
    final u = (k - .4) / .6;
    return (1.1 * (1 - u), math.pi / 4 * (1 + u), 1 - u);
  }
}
