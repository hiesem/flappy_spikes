import 'dart:ui';

/// PRD-2.4 §3.3 "Colour stages": the world is drawn in Sky & Hills greys;
/// the grey line from #F1F1F1 (background, 241) to #828282 (foreground,
/// 130) maps onto the stage's background → foreground (`palMatrix()`).
///
/// A 4 × 5 [ColorFilter.matrix] (offsets in 0–255): for each channel i,
/// `out_i = m_i · (R + G + B) + a_i` with `k_i = (fg_i − bg_i) / (130 − 241)`,
/// `m_i = k_i / 3`, `a_i = bg_i − k_i · 241`.
List<double> palMatrix(Color bg, Color fg) {
  final b = [bg.r * 255, bg.g * 255, bg.b * 255];
  final f = [fg.r * 255, fg.g * 255, fg.b * 255];
  final out = <double>[];
  for (var i = 0; i < 3; i++) {
    final k = (f[i] - b[i]) / (130 - 241), a = b[i] - k * 241, m = k / 3;
    out.addAll([m, m, m, 0, a]);
  }
  out.addAll([0, 0, 0, 1, 0]);
  return out;
}

/// The grey a palette leaves unchanged (stage 0, #F1F1F1 / #828282).
bool isIdentityPalette(Color bg, Color fg) =>
    bg.toARGB32() == 0xFFF1F1F1 && fg.toARGB32() == 0xFF828282;

/// Applies [palMatrix] to one colour (tests, and the backdrop's fallbacks).
Color applyPalMatrix(List<double> m, Color c) {
  final r = c.r * 255, g = c.g * 255, b = c.b * 255;
  double ch(int row) =>
      (m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4])
          .clamp(0, 255)
          .toDouble();
  return Color.fromARGB(255, ch(0).round(), ch(1).round(), ch(2).round());
}
