import 'package:flutter/painting.dart';

import '../config/hud_config.dart';

/// A name fitted to its room by [fitName]: the text to draw (the full name,
/// or a prefix ending in "…") and the font size.
class FittedName {
  const FittedName(this.text, this.size);

  final String text;
  final double size;

  /// The name had to be cut ("…").
  bool get cut => text.endsWith(ellipsis);

  static const String ellipsis = '…';

  @override
  String toString() => 'FittedName($text, $size)';
}

/// The width of [text] at font size [size] (one line, no wrapping).
typedef NameMeasure = double Function(String text, double size);

/// A [NameMeasure] for a text style (the game's fonts): [letterSpacingEm]
/// in em; [trimTrailingSpacing] leaves out the spacing after the last
/// glyph (as `HudText.width` does).
NameMeasure measureName({
  required String fontFamily,
  double letterSpacingEm = 0,
  FontWeight? fontWeight,
  bool trimTrailingSpacing = false,
}) {
  return (text, size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          letterSpacing: size * letterSpacingEm,
          fontWeight: fontWeight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width - (trimTrailingSpacing ? size * letterSpacingEm : 0);
    tp.dispose();
    return w;
  };
}

/// PRD-2.3 §21.2 the one name rule for every name tag (VS intro plates, the
/// HUD name chips, the results columns, the share card's name tag):
/// 1. the name at its normal [size] when it fits [maxWidth];
/// 2. else shrunk until it fits, down to [minScale] (66 %) of [size];
/// 3. else cut at [minScale] × [size] and ended with "…".
/// Names are never otherwise changed (generated nicknames keep their
/// digits). [maxWidth] is the room: the window minus its padding and minus
/// whatever is drawn over it.
FittedName fitName(
  String name,
  double maxWidth,
  double size,
  NameMeasure measure, {
  double minScale = HudConfig.nameMinScale,
}) {
  if (name.isEmpty || maxWidth <= 0) return FittedName(name, size);
  final full = measure(name, size);
  if (full <= maxWidth) return FittedName(name, size);
  final min = size * minScale;
  // Width grows linearly with the size (letter spacing is in em), so the
  // proportional size fits; nudge down for rounding.
  var s = size * maxWidth / full;
  if (s >= min) {
    for (var i = 0; i < 8 && measure(name, s) > maxWidth && s > min; i++) {
      s = (s * .985).clamp(min, size);
    }
    if (measure(name, s) <= maxWidth) return FittedName(name, s);
  }
  // Cut at the minimum size: the longest prefix that fits with "…".
  String cut(int n) => '${name.substring(0, n).trimRight()}${FittedName.ellipsis}';
  var lo = 0, hi = name.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (measure(cut(mid), min) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return FittedName(cut(lo), min);
}
