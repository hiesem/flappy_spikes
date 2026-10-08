import 'dart:typed_data';
import 'dart:ui';

import 'package:flappy_spikes/run/effects/gold_bird.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders a look at 1 px per art unit with the art box at (0,0)–(44,36),
/// raw RGBA.
Future<ByteData> _render(Look look, {bool gold = false, bool dead = false}) async {
  final rec = PictureRecorder();
  final c = Canvas(rec)..translate(22, 18);
  LookPainter.paint(c, look, t: 0, gold: gold, dead: dead);
  final image = await rec.endRecording().toImage(44, 36);
  final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

Color _px(ByteData d, int x, int y) {
  final i = (y * 44 + x) * 4;
  return Color.fromARGB(d.getUint8(i + 3), d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2));
}

void main() {
  testWidgets('§3.0.9 #5 gold bird: body #FFB529, shade #E08A00, beak gold', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final gold = await _render(Look.defaults, gold: true);
      final pink = await _render(Look.defaults);
      expect(_px(gold, 30, 28), GoldBird.body, reason: 'body');
      expect(_px(pink, 30, 28), const Color(0xFFEC008C));
      expect(_px(gold, 2, 14), GoldBird.shade, reason: 'tail');
      expect(_px(gold, 38, 20), GoldBird.beak, reason: 'beak');
      expect(_px(gold, 28, 12), const Color(0xFFFFFFFF), reason: 'eye white');
    });
  });

  testWidgets('§3.0.9 #5 other skins keep their art and get a gold glow', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const sky = Look(bird: 'sky');
      final plain = await _render(sky);
      final gold = await _render(sky, gold: true);
      expect(_px(gold, 20, 20), _px(plain, 20, 20), reason: 'body unchanged');
      // Just outside the body square (6..36): glow only in the gold version.
      expect(_px(plain, 20, 1).a, 0);
      expect(_px(gold, 20, 1).a, greaterThan(0));
    });
  });

  testWidgets('§3.0.9 #6 dead X: white 6 × 6, line 2, replacing the eye', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dead = await _render(Look.defaults, dead: true);
      // Eye centre (28,12) on the classic bird: X crossing is white.
      expect(_px(dead, 28, 12), const Color(0xFFFFFFFF));
      // The X arms reach ±3 (6 × 6): a corner pixel is white too.
      expect(_px(dead, 25, 9).r, greaterThan(.8));
      expect(_px(dead, 25, 9).b, greaterThan(.8));
      // The alive bird has body pink there (the 4 x 4 eye is smaller).
      final alive = await _render(Look.defaults);
      expect(_px(alive, 25, 9), const Color(0xFFEC008C));
    });
  });
}
