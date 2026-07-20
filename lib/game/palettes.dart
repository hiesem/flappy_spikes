import 'dart:ui';

/// One color stage: background color + foreground (tint) color.
class Palette {
  const Palette(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// Color stages from SPEC.md. Key = stage (score mod 50, snapped down to a
/// multiple of 5), with 50 being the special "multiple of 50" gold stage.
const Map<int, Palette> kPalettes = {
  0: Palette(Color(0xFFF1F1F1), Color(0xFF828282)),
  5: Palette(Color(0xFFE5F2F9), Color(0xFF667B84)),
  10: Palette(Color(0xFFF9EDE6), Color(0xFF806A62)),
  15: Palette(Color(0xFFECF6E5), Color(0xFF767E67)),
  20: Palette(Color(0xFFECEAF8), Color(0xFF6E6880)),
  25: Palette(Color(0xFF747474), Color(0xFFFFFFFF)),
  30: Palette(Color(0xFF087990), Color(0xFF0CD9FF)),
  35: Palette(Color(0xFF197500), Color(0xFF7EE400)),
  40: Palette(Color(0xFF001D89), Color(0xFF0067FF)),
  45: Palette(Color(0xFF921037), Color(0xFFFF1F64)),
  50: Palette(Color(0xFFFFB529), Color(0xFFFFFFFF)),
};

/// Maps a score to its color stage.
///
/// The stage changes every 5 points: `score % 50` snapped down to the nearest
/// multiple of 5. A score that is an exact multiple of 50 (and not zero) maps
/// to the special gold stage 50.
int stageOf(int score) {
  final int mod = score % 50;
  if (mod == 0) {
    return score == 0 ? 0 : 50;
  }
  return (mod ~/ 5) * 5;
}

/// The palette for a given stage.
Palette paletteForStage(int stage) => kPalettes[stage] ?? kPalettes[0]!;
