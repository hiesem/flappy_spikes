import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// PRD-2.4 §3 WP-W3 visual check: renders scenes 8–10 mid-scene and seams
/// 7–10 at start / ¼ / middle / ¾ / end (loop 2, as the prototype's
/// `jump`), at 568 and 730, for the side-by-side with the prototype
/// (evidence/wpW3, not in git).
void main() {
  final shots = <String, double>{
    'sea_mid': kTotal + 7.5 * kE,
    'dream_mid': kTotal + 8.5 * kE,
    'space_mid': kTotal + 9.5 * kE,
    for (final k in [7, 8, 9, 10])
      for (final p in const {'start': -.5, 'q25': -.25, 'mid': 0.0, 'q75': .25, 'end': .5}.entries)
        'seam${k}_${p.key}': kTotal + k * kE + p.value * kVWIN,
  };
  for (final h in [568.0, 730.0]) {
    test('evidence W3 @${h.round()}', () async {
      for (final e in shots.entries) {
        final img = await renderBackdrop(cam: e.value, viewHeight: h, scale: 2);
        await saveEvidence(img, 'wpW3/dart', '${e.key}_${h.round()}');
        img.dispose();
      }
    });
  }
}
