import 'dart:ui';
// region P26-F9f
import '../../skins/art/card_name_art.dart';
// endregion

import '../config/hud_config.dart';
import 'run_hud.dart';

/// §5.7 a name chip under a versus box: 90 × 22 at y 92, white, plum
/// Fredoka SemiBold (the own name / the opponent's display name), 14 pt
/// since S8-08 ([HudConfig.chipNameSize]).
/// PRD-2.3 §21.2: the name follows the one name rule ([HudText.name]:
/// shrunk to fit the chip minus its padding down to 66 %, then "…").
/// Drawn by the [VersusBar].
class NameChip {
  // region P26-F9f
  NameChip(this.name, this.left, {this.style = ''})
    // endregion
    : _text = HudText.name(
        name,
        maxWidth: HudConfig.boxWidth - 2 * HudConfig.chipPad,
        size: HudConfig.chipNameSize,
        color: HudConfig.plum,
        spacing: HudConfig.chipNameSpacing,
        font: HudConfig.nameFont,
      );

  // region P26-F9f
  final String style;
  final Paint _nameAlpha = Paint();
  // endregion
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

  // region P26-F9f
  void render(Canvas canvas, double opacity, {double t = 0}) {
    // endregion
    _white.color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.drawRect(rect, _white);
    // region P26-F9f
    if (style.isNotEmpty) {
      if (opacity <= 0) return;
      canvas.saveLayer(
        rect.inflate(10),
        _nameAlpha..color = Color.fromRGBO(255, 255, 255, opacity),
      );
      CardNameArt.paint(
        canvas,
        style,
        shown,
        t: t,
        center: rect.center,
        fontSize: size,
        maxWidth: HudConfig.boxWidth - 2 * HudConfig.chipPad,
        cacheLayout: true,
      );
      canvas.restore();
      return;
    }
    // endregion
    _text.paintCentred(canvas, rect.center, opacity: opacity);
  }
}
