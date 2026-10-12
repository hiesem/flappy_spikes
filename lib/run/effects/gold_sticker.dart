import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../config/parts_config.dart';
import 'easing.dart';
import '../../game/paints.dart';

/// The gold sticker (ARCH §3 "GoldSticker"): plum Opificio text on a flat
/// gold `#FFB529` box, tilted a few degrees, popping in — NEW BEST on the
/// results page, BONUS UNLOCKED! under the feather tray, PICTURE COMPLETE
/// under the puzzle pill. Anchored on its centre.
///
/// * [GoldSticker.newBest] (`screen_results_levels.html #nb`): 13 pt,
///   letter-spacing 0.12 em, padding 3 × 12, −4°, pop 0.38 s with the CSS
///   `OUT` curve: scale 0.3 → 1, rotation −14° → −4°, opacity 0 → 1.
/// * [GoldSticker.collect] (`collect.js drawTray`): 14 pt, letter-spacing
///   1.7 pt, box = text + 26 × 24, −0.05 rad (≈ −3°), pop 0.35 s
///   ease-out-back on the scale.
class GoldSticker extends PositionComponent {
  GoldSticker({
    required this.text,
    this.fontSize = 13,
    this.letterSpacing = 13 * .12,
    this.padH = 12,
    this.padV = 3,
    this.minHeight = 0,
    this.tilt = -4 * math.pi / 180,
    this.popLength = .38,
    this.popFromTilt = -14 * math.pi / 180,
    this.backOut = false,
    super.position,
    super.priority,
  }) : super(anchor: Anchor.center);

  factory GoldSticker.newBest({String text = 'NEW BEST', Vector2? position}) =>
      GoldSticker(text: text, position: position);

  factory GoldSticker.collect(String text, {Vector2? position}) => GoldSticker(
    text: text,
    fontSize: 14,
    letterSpacing: 1.7,
    padH: 13,
    padV: 0,
    minHeight: 24,
    tilt: -.05,
    popLength: .35,
    popFromTilt: -.05,
    backOut: true,
    position: position,
  );

  final String text;
  final double fontSize, letterSpacing, padH, padV, minHeight, tilt;
  final double popLength, popFromTilt;

  /// Pop curve: ease-out-back (collect stickers) or CSS `OUT` (NEW BEST).
  final bool backOut;

  /// Overall opacity (the tray fades it with itself).
  double opacity = 1;

  double _t = 0;
  late final TextPainter _tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
        color: PartsConfig.plum,
      ),
    ),
    textDirection: p.TextDirection.ltr,
  )..layout();

  /// Box size (pt).
  Size get box => Size(
    _tp.width + 2 * padH,
    math.max(minHeight, _tp.height + 2 * padV),
  );

  /// (scale, rotation, alpha) at [t] seconds after the pop starts.
  (double, double, double) popAt(double t) {
    final u = popLength <= 0 ? 1.0 : (t / popLength).clamp(0.0, 1.0);
    final e = backOut ? Ease.outBack(u) : Ease.cssOut(u);
    final scale = .3 + .7 * e;
    final rot = popFromTilt + (tilt - popFromTilt) * e;
    return (scale, rot, backOut ? 1.0 : u);
  }

  void restart() => _t = 0;

  @override
  Future<void> onLoad() async {
    final b = box;
    size = Vector2(b.width, b.height);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final (s, r, a) = popAt(_t);
    final alpha = (a * opacity).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    final b = box;
    canvas.save();
    canvas.translate(b.width / 2, b.height / 2);
    canvas.rotate(r);
    canvas.scale(s);
    canvas.translate(-b.width / 2, -b.height / 2);
    final layer = alpha < 1;
    if (layer) {
      canvas.saveLayer(null, layerPaint(alpha));
    }
    canvas.drawRect(Offset.zero & b, fillPaint(PartsConfig.gold));
    _tp.paint(
      canvas,
      Offset((b.width - _tp.width) / 2 + letterSpacing / 2, (b.height - _tp.height) / 2),
    );
    if (layer) canvas.restore();
    canvas.restore();
  }
}
