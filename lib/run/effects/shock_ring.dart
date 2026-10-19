import 'dart:ui';

import '../config/parts_config.dart';
import '../hoops/ring_painter.dart';
import 'particle_pool.dart';

/// The expanding ring outline (ARCH §3 "ShockRing"): one class for every
/// "ring grows and fades" effect — the §5.1 non-perfect pass pulse (master
/// #8 of the WP list), the §5.13 red miss shockwave, the gold pickup rings,
/// the pair pick pulse, the phoenix shockwave, the FEVER pass ring and the
/// shield's forming ring burst.
///
/// An ellipse with half axes [rx] × [ry] (a circle when equal) around the
/// component position, tilted by [tilt], scaled [scaleFrom] → [scaleTo],
/// its stroke [strokeFrom] → [strokeTo] (the stroke is *not* scaled) and its
/// opacity [alphaFrom] → [alphaTo], linear over [length] seconds after an
/// optional delay. Use the named presets; elements change only these
/// parameters.
class ShockRing extends PooledEffect {
  ShockRing({super.priority});

  static EffectPool<ShockRing> newPool() => EffectPool(ShockRing.new);

  double rx = 20, ry = 20, tilt = 0;
  double scaleFrom = 1, scaleTo = 2;
  double strokeFrom = 4, strokeTo = 4;
  double alphaFrom = 1, alphaTo = 0;
  double length = .5;
  Color color = PartsConfig.pink;

  // region WP-3c — additive growth + glow (PRD-2 §5.18 FEVER pass rings)
  /// Points added to both radii over the life (the FEVER rings grow
  /// `rx + u × 160`, `ry + u × 160`), on top of the scale.
  double grow = 0;

  /// Glow blur (pt) in the ring colour; 0 = none.
  double glowBlur = 0;
  // endregion WP-3c

  @override
  double get duration => length;

  /// Generic start.
  ShockRing play(
    Offset at, {
    required double rx,
    double? ry,
    required Color color,
    required double length,
    double scaleFrom = 1,
    double scaleTo = 2,
    double strokeFrom = 4,
    double? strokeTo,
    double alphaFrom = 1,
    double alphaTo = 0,
    double tilt = 0,
    double delay = 0,
    double grow = 0,
    double glowBlur = 0,
  }) {
    position.setValues(at.dx, at.dy);
    this
      ..grow = grow
      ..glowBlur = glowBlur
      ..rx = rx
      ..ry = ry ?? rx
      ..color = color
      ..length = length
      ..scaleFrom = scaleFrom
      ..scaleTo = scaleTo
      ..strokeFrom = strokeFrom
      ..strokeTo = strokeTo ?? strokeFrom
      ..alphaFrom = alphaFrom
      ..alphaTo = alphaTo
      ..tilt = tilt;
    restart(delay: delay);
    return this;
  }

  /// §5.1 non-perfect pass pulse: the ring shape (24 pt wide, opening-tall,
  /// 4 pt border in the ring's front colour), scale 0.8 → 1.9, opacity
  /// 0.9 → 0 in ≈ 0.55 s.
  ShockRing passPulse(
    Offset centre, {
    required double opening,
    Color color = PartsConfig.pink,
    double tilt = 0,
  }) => play(
    centre,
    rx: RingPainter.rx + PartsConfig.pulseStroke / 2,
    ry: RingPainter.ryFor(opening) + PartsConfig.pulseStroke / 2,
    color: color,
    length: PartsConfig.pulseDuration,
    scaleFrom: PartsConfig.pulseScaleFrom,
    scaleTo: PartsConfig.pulseScaleTo,
    strokeFrom: PartsConfig.pulseStroke,
    alphaFrom: PartsConfig.pulseAlpha,
    tilt: tilt,
  );

  /// §5.13 miss shockwave: the same ring shape in `#FF1F3D`, scale 1 → 2.6,
  /// stroke 6 → 1 pt, opacity 1 → 0 over 0.55 s (used by `MissFlash`, 1a).
  ShockRing missWave(Offset centre, {required double opening, double tilt = 0}) =>
      play(
        centre,
        rx: RingPainter.rx,
        ry: RingPainter.ryFor(opening),
        color: const Color(0xFFFF1F3D),
        length: .55,
        scaleFrom: 1,
        scaleTo: 2.6,
        strokeFrom: 6,
        strokeTo: 1,
        tilt: tilt,
      );

  /// Current (scale, stroke, alpha) — for tests.
  (double, double, double) valuesAt(double k) => (
    scaleFrom + (scaleTo - scaleFrom) * k,
    strokeFrom + (strokeTo - strokeFrom) * k,
    alphaFrom + (alphaTo - alphaFrom) * k,
  );

  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  @override
  void renderAt(Canvas canvas, double k) {
    final (s, w, a) = valuesAt(k);
    if (a <= 0 || w <= 0) return;
    _paint
      ..strokeWidth = w
      ..color = color.withValues(alpha: color.a * a.clamp(0.0, 1.0))
      ..maskFilter = glowBlur > 0
          ? MaskFilter.blur(BlurStyle.normal, glowBlur / 2)
          : null;
    canvas.save();
    if (tilt != 0) canvas.rotate(tilt);
    final g = grow * k;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * (rx * s + g),
      height: 2 * (ry * s + g),
    );
    if (glowBlur > 0) {
      canvas.drawOval(rect, _paint);
      _paint.maskFilter = null;
    }
    canvas.drawOval(rect, _paint);
    canvas.restore();
  }
}
