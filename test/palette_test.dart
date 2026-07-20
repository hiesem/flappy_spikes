import 'dart:ui';

import 'package:flappy_spikes/game/palettes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stageOf', () {
    test('score 0 maps to the default stage 0', () {
      expect(stageOf(0), 0);
    });

    test('stage changes every 5 points', () {
      expect(stageOf(1), 0);
      expect(stageOf(4), 0);
      expect(stageOf(5), 5);
      expect(stageOf(9), 5);
      expect(stageOf(10), 10);
      expect(stageOf(14), 10);
      expect(stageOf(45), 45);
      expect(stageOf(46), 45);
      expect(stageOf(49), 45);
    });

    test('exact multiples of 50 map to the gold stage 50', () {
      expect(stageOf(50), 50);
      expect(stageOf(100), 50);
      expect(stageOf(150), 50);
    });

    test('stage wraps with score mod 50 after a multiple of 50', () {
      expect(stageOf(51), 0);
      expect(stageOf(54), 0);
      expect(stageOf(55), 5);
      expect(stageOf(95), 45);
      expect(stageOf(99), 45);
      expect(stageOf(101), 0);
      expect(stageOf(105), 5);
    });
  });

  group('paletteForStage', () {
    // Full table from SPEC.md "Color system".
    const expected = <int, List<int>>{
      0: [0xFFF1F1F1, 0xFF828282],
      5: [0xFFE5F2F9, 0xFF667B84],
      10: [0xFFF9EDE6, 0xFF806A62],
      15: [0xFFECF6E5, 0xFF767E67],
      20: [0xFFECEAF8, 0xFF6E6880],
      25: [0xFF747474, 0xFFFFFFFF],
      30: [0xFF087990, 0xFF0CD9FF],
      35: [0xFF197500, 0xFF7EE400],
      40: [0xFF001D89, 0xFF0067FF],
      45: [0xFF921037, 0xFFFF1F64],
      50: [0xFFFFB529, 0xFFFFFFFF],
    };

    expected.forEach((stage, colors) {
      test('stage $stage matches SPEC colors', () {
        final palette = paletteForStage(stage);
        expect(palette.background, Color(colors[0]));
        expect(palette.foreground, Color(colors[1]));
      });
    });

    test('unknown stage falls back to the default palette', () {
      expect(paletteForStage(7).background, kPalettes[0]!.background);
      expect(paletteForStage(7).foreground, kPalettes[0]!.foreground);
    });
  });
}
