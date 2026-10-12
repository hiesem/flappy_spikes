import 'dart:math' as math;
import 'dart:ui';

import '../../skins/art/art_paint.dart';
import '../../skins/art/hoop_painter.dart';
import '../config/parts_config.dart';
import '../../game/paints.dart';

/// Front / back colours of a ring.
class RingColors {
  const RingColors(this.front, this.back);

  final Color front, back;

  /// §3.0.9 #3 / §5.1 M0: pink front, plum-pink back (= the `pink` skin).
  static const RingColors pink = RingColors(Color(0xFFEC008C), Color(0xFFB0006B));

  /// §3.5 tier 2 and §5.1 Big Hoops gold.
  static const RingColors gold = RingColors(Color(0xFFFFB529), Color(0xFFD48A00));

  /// §3.5 tier 3+ bright gold.
  static const RingColors brightGold = RingColors(
    Color(0xFFFFD54A),
    Color(0xFFE0A800),
  );

  /// §5.13 miss ghost grey (front / back).
  static const RingColors ghost = RingColors(Color(0xFF969696), Color(0xFF787878));

  /// §5.13 miss flash white.
  static const RingColors white = RingColors(Color(0xFFFFFFFF), Color(0xFFFFFFFF));

  Color of({required bool front}) => front ? this.front : back;

  @override
  bool operator ==(Object other) =>
      other is RingColors && other.front == front && other.back == back;

  @override
  int get hashCode => Object.hash(front, back);
}

/// Master #3 — the hoop ring (PRD §3.0.9 #3, §5.1 M0 "clean vertical ring").
///
/// A vertical ellipse **24 pt wide** ([rx] 12) whose half height follows the
/// opening: `ry = opening / 2 + 7` (the rim-end circles of r 7 sit on the
/// stroke centre line at (0, ±ry), §3.0.1), stroke 7 pt, butt caps. Two
/// halves: the **back** (right) half is painted before the bird, the
/// **front** (left) half after it.
///
/// Colours (ARCH §3 "Skin interplay"): with no [colors] the ring draws the
/// equipped **hoop skin** through [HoopPainter] (default `pink` = the M0
/// colours) — tier 0–1. Gameplay colour states override the skin while
/// active: pass [RingColors.gold] (tier 2, Big Hoops, Coin Frenzy, passed
/// train rings), [RingColors.brightGold] (tier 3+), [RingColors.ghost] /
/// [RingColors.white] (miss flash), or a special kind's own colours.
/// [colorsForTier] gives the tier override.
///
/// Other parameters: [strokeWidth] (miss flash 8), [tilt] (radians, angled
/// rings), [dash] (miss ghost 6/6), [glow] + [glowBlur] (miss flash white
/// glow), [opacity]. Special hoops change only colours/decorations.
abstract final class RingPainter {
  /// §3.0.9 #3 Half width (pt).
  static const double rx = PartsConfig.ringWidth / 2;

  /// §3.0.9 #3 Stroke (pt).
  static const double stroke = PartsConfig.ringStroke;

  /// Half height of the stroke centre line for an [opening] (pt).
  static double ryFor(double opening) => opening / 2 + PartsConfig.rimRadius;

  /// Outer height of the drawn ring (opening + 2 × 7 + stroke).
  static double outerHeight(double opening) => 2 * ryFor(opening) + stroke;

  /// The tier override of §3.5 (null = draw the equipped skin).
  static RingColors? colorsForTier(int tier) => tier >= 3
      ? RingColors.brightGold
      : tier >= 2
      ? RingColors.gold
      : null;

  /// The two rim-end centres in ring-local coordinates (before [tilt]).
  static (Offset, Offset) rimEnds(double opening) {
    final ry = ryFor(opening);
    return (Offset(0, -ry), Offset(0, ry));
  }

  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  /// The half-ring path (stroke centre line) around [centre].
  static Path halfPath(Offset centre, double opening, {required bool front}) {
    final ry = ryFor(opening);
    final a0 = front ? math.pi / 2 : -math.pi / 2;
    return Path()
      ..arcTo(
        Rect.fromCenter(center: centre, width: 2 * rx, height: 2 * ry),
        a0,
        math.pi,
        true,
      );
  }

  /// Paints one half of the ring centred at [centre].
  static void paintHalf(
    Canvas canvas, {
    required Offset centre,
    required double opening,
    required bool front,
    String skinId = HoopPainter.fallbackId,
    RingColors? colors,
    double strokeWidth = stroke,
    double tilt = 0,
    List<double>? dash,
    double dashPhase = 0,
    Color? glow,
    double glowBlur = 24,
    double opacity = 1,
    double t = 0,
  }) {
    if (opening <= 0 || opacity <= 0) return;
    final layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(
        null,
        layerPaint(opacity.clamp(0.0, 1.0)),
      );
    }
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    if (tilt != 0) canvas.rotate(tilt);
    if (colors == null && dash == null && glow == null) {
      HoopPainter.paintHalf(
        canvas,
        skinId,
        Offset.zero,
        ryFor(opening),
        t,
        front: front,
        lineWidth: strokeWidth,
        rx: rx,
      );
    } else {
      var path = halfPath(Offset.zero, opening, front: front);
      if (dash != null) path = ArtPaint.dashed(path, dash, dashPhase);
      if (glow != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..color = glow
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur / 2),
        );
      }
      final c = colors ?? RingColors.pink;
      _stroke
        ..strokeWidth = strokeWidth
        ..color = c.of(front: front);
      canvas.drawPath(path, _stroke);
    }
    canvas.restore();
    if (layer) canvas.restore();
  }

  /// Both halves (for previews, shots and HUD art — gameplay paints the
  /// halves in two layers around the bird).
  static void paintBoth(
    Canvas canvas, {
    required Offset centre,
    required double opening,
    String skinId = HoopPainter.fallbackId,
    RingColors? colors,
    double tilt = 0,
    double t = 0,
  }) {
    for (final front in const [false, true]) {
      paintHalf(
        canvas,
        centre: centre,
        opening: opening,
        front: front,
        skinId: skinId,
        colors: colors,
        tilt: tilt,
        t: t,
      );
    }
  }
}
