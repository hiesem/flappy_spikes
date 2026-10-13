import 'dart:ui';

import '../config/hud_config.dart';
import 'run_hud.dart';

/// §5.7 a name chip under a versus box: 90 × 22 at y 92, white, plum
/// Fredoka SemiBold 15 pt (the own name / the opponent's display name).
/// PRD-2.3 §21.2: the name follows the one name rule ([HudText.name]:
/// shrunk to fit the chip minus its padding down to 70 %, then "…").
/// Drawn by the [VersusBar].
class NameChip {
  NameChip(this.name, this.left)
    : _text = HudText.name(
        name,
        maxWidth: HudConfig.boxWidth - 2 * HudConfig.chipPad,
        size: HudConfig.chipFont,
        color: HudConfig.plum,
        spacing: .02,
        font: HudConfig.nameFont,
      );

  final double left;
  final HudText _text;

  /// The player's name (unfitted).
  final String name;

  /// PRD-2.3 §21.2 the name as drawn (tests; may end in "…").
  String get shown => _text.text;

  /// The font size the name is drawn at (tests).
  double get size => _text.size;

  /// The drawn name's width (tests).
  double get width => _text.width;
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
