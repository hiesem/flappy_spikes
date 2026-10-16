import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// PRD-2.4 §3 WP-W2 visual check: renders scenes 4–7 mid-scene and seams
/// 3–6 at linger-in / start / ¼ / middle / ¾ / end / linger-out, at 568 and
/// 730 pt, for comparison with the prototype at the same world distances
/// (evidence/wpW2, not in git; skipped where the folder does not exist).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // the Desk's block letters are Fredoka (as in the game)
  setUpAll(() async {
    final f = FontLoader('Fredoka')..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
    await f.load();
  });
  final shots = <String, double>{
    for (var s = 4; s <= 7; s++) 'scene${s}_mid': kTotal + (s - 1) * kE + kE / 2,
    for (var k = 3; k <= 6; k++) ...{
      'seam${k}_linger_in': kTotal + k * kE - 4000,
      'seam${k}_start': kTotal + k * kE - 1500,
      'seam${k}_q25': kTotal + k * kE - 750,
      'seam${k}_mid': kTotal + k * kE,
      'seam${k}_q75': kTotal + k * kE + 750,
      'seam${k}_end': kTotal + k * kE + 1500,
      'seam${k}_linger_out': kTotal + k * kE + 3000,
    },
  };
  for (final h in [568.0, 730.0]) {
    for (final e in shots.entries) {
      test('evidence ${e.key} @${h.round()}', () async {
        final img = await renderBackdrop(cam: e.value, viewHeight: h, scale: 2);
        await saveEvidence(img, 'wpW2/dart', '${e.key}_${h.round()}');
        img.dispose();
      });
    }
  }
}
