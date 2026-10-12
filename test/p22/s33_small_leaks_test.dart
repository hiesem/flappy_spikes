import 'dart:ui';

import 'package:flappy_spikes/game/paints.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.2 §33.4 item 6: the small ones — the rumble recorder is capped,
/// the collect text cache frees its painters, per-frame layer / fill
/// paints are shared scratch objects.
void main() {
  test('Rumble.fired never grows past its cap', () {
    var now = 0.0;
    final r = Rumble(hardware: false, clock: () => now);
    for (var i = 0; i < Rumble.firedCap * 3; i++) {
      now += 1;
      r.knock();
      expect(r.fired.length, lessThanOrEqualTo(Rumble.firedCap));
    }
    expect(r.fired.length, greaterThan(Rumble.firedCap ~/ 2));
    expect(r.fired.last, RumbleKind.knock);
  });

  testWidgets('CollectText: past 400 strings the cache is cleared and its '
      'painters disposed (no growth)', (tester) async {
    CollectText.clearCache();
    final first = CollectText.of('x0', 12, const Color(0xFFFFFFFF));
    for (var i = 1; i <= 400; i++) {
      CollectText.of('x$i', 12, const Color(0xFFFFFFFF));
    }
    expect(CollectText.cachedCount, 401);
    CollectText.of('one more', 12, const Color(0xFFFFFFFF));
    expect(CollectText.cachedCount, 1);
    expect(first.debugDisposed, isTrue);
    CollectText.clearCache();
  });

  test('layerPaint / fillPaint reuse one object and set the colour', () {
    final a = layerPaint(.25);
    final b = layerPaint(.75);
    expect(identical(a, b), isTrue);
    expect(b.color.a, closeTo(.75, 1e-3));
    final f = fillPaint(const Color(0xFF123456));
    expect(identical(f, a), isFalse);
    expect(f.color.toARGB32(), 0xFF123456);
    expect(f.style, PaintingStyle.fill);
    expect(f.maskFilter, isNull);
    expect(f.shader, isNull);
  });
}
