import 'dart:ui';

import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_palette.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// PRD-2.4 §4 test 8: for all 11 stages, the colour matrix maps #F1F1F1 to
/// the stage background and #828282 to the stage foreground (±1).
void main() {
  void close(Color a, Color b, String why) {
    for (final (x, y) in [(a.r, b.r), (a.g, b.g), (a.b, b.b)]) {
      expect(((x - y) * 255).abs(), lessThanOrEqualTo(1.01), reason: why);
    }
  }

  for (final key in kStageKeys) {
    final p = paletteForStage(key);
    test('stage $key: grey line → ${p.background} / ${p.foreground}', () {
      final m = palMatrix(p.background, p.foreground);
      close(applyPalMatrix(m, const Color(0xFFF1F1F1)), p.background, 'bg');
      close(applyPalMatrix(m, const Color(0xFF828282)), p.foreground, 'fg');
    });
  }

  test('the rendered layer is recoloured (gold stage, sky pixels)', () async {
    final gold = paletteForStage(50);
    final grey = await rgbaOf(await renderBackdrop(cam: 138000));
    final px = await rgbaOf(await renderBackdrop(
      cam: 138000,
      bg: gold.background,
      fg: gold.foreground,
    ));
    var n = 0;
    for (var i = 0; i < grey.length; i += 4 * 97) {
      if (grey[i] != 0xF1 || grey[i + 1] != 0xF1 || grey[i + 2] != 0xF1) continue;
      close(Color.fromARGB(255, px[i], px[i + 1], px[i + 2]), gold.background, 'sky');
      n++;
    }
    expect(n, greaterThan(100));
  });

  test('stage 0 is the identity', () {
    expect(isIdentityPalette(const Color(0xFFF1F1F1), const Color(0xFF828282)), isTrue);
    final m = palMatrix(const Color(0xFFF1F1F1), const Color(0xFF828282));
    close(applyPalMatrix(m, const Color(0xFFD5D5D5)), const Color(0xFFD5D5D5), 'grey');
  });
}
