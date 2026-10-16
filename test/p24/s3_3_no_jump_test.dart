import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// PRD-2.4 §4 test 9 (WP-W1 part): frames 1 pt apart at both edges of the
/// seam windows and linger ranges of seams 1–2, and at the stage switches
/// around them, differ by no more than a few pixels. WP-W2 / WP-W3 add
/// their seams to [seams] (or call [seamEdges] in their own tests).
void main() {
  // seam k (1-based) is at world distance 12 000·k; loop 2 as well (from
  // hoop 400 the Homecoming plays, the hashes differ per loop).
  const seams = [1, 2, 7, 8, 9, 10];
  for (final h in [568.0, 730.0]) {
    for (final k in seams) {
      for (final loop in [0, 1]) {
        final sc = k * kE + loop * kTotal;
        for (final e in seamEdges()) {
          test('seam $k loop $loop edge ${e.round()} @${h.round()}', () async {
            await expectNoJump(sc + e, viewHeight: h, label: 'seam $k');
          });
        }
      }
    }
    test('the check catches a pop (a 60 pt jump) @${h.round()}', () async {
      const cam = 126000.0;
      final a = await rgbaOf(await renderBackdrop(cam: cam, viewHeight: h));
      final b = await rgbaOf(await renderBackdrop(cam: cam + 60, viewHeight: h));
      final popped = diffPixels(a, b, threshold: 3);
      final ordinary = await frameJump(cam + 3, viewHeight: h);
      expect(popped, greaterThan(ordinary * 2 + 300));
    });
    test('first loop: Nest throughout hoops 0–39 @${h.round()}', () async {
      for (final w in <double>[-130, -1, 0, 5999, 6000, 6999, 7000]) {
        await expectNoJump(w, viewHeight: h, label: 'first loop');
      }
    });
  }
}

/// The world distances (relative to a seam) where a floor move could
/// jump: the window edges (±1 500), the linger edges (±5 000) and the
/// switch to the plain stage (±6 000), each a little before and at it.
List<double> seamEdges() => [
  for (final e in [kVWIN / 2, kVWIN / 2 + kLinger, kE / 2])
    for (final s in [-1, 1]) ...[s * e - 1, s * e - .5, s * e],
];
