import 'dart:ui';

import '../config/hud_config.dart';
import 'run_hud.dart';

/// §5.7 a name chip under a versus box: 90 × 22 at y 92, white, plum
/// Fredoka SemiBold 15 pt, ellipsis on overflow ("You" / the opponent's
/// display name). Drawn by the [VersusBar].
class NameChip {
  NameChip(String name, this.left)
    : _text = HudText(
        name,
        size: HudConfig.chipFont,
        color: HudConfig.plum,
        spacing: .02,
        font: HudConfig.nameFont,
        maxWidth: HudConfig.boxWidth - 6,
      );

  final double left;
  final HudText _text;

  /// The name shown (tests).
  String get name => _text.text;
  static final Paint _white = Paint();

  Rect get rect => Rect.fromLTWH(
    left,
    HudConfig.chipTop,
    HudConfig.boxWidth,
    HudConfig.chipHeight,
  );

  void render(Canvas canvas, double opacity) {
    _white.color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.drawRect(rect, _white);
    _text.paintCentred(canvas, rect.center, opacity: opacity);
  }
}
