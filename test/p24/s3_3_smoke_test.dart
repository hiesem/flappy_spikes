import 'dart:typed_data';

import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// PRD-2.4 §4 test 10: every scene and every seam renders at 568 and 730 pt
/// without throwing; on the taller view the ground stays anchored to the
/// bottom (the bottom 568 pt of a mid-scene frame are the 568 frame), and
/// in the scenes and seams ported so far no ground edge shows above the
/// bottom spike strip: none of the rows behind the strip (the bottom 44 pt)
/// is plain sky.
void main() {
  // WP-W2 / WP-W3 extend these as they port.
  const portedScenes = {0, 1, 2, 7, 8, 9};
  const portedSeams = {1, 2, 7, 8, 9, 10};

  final frames = <String, double>{
    for (var s = 0; s < 10; s++) 'scene ${s + 1}': kTotal + (s + .5) * kE,
    for (var k = 1; k <= 10; k++)
      for (final u in [-1.0, 0, .25, .5, .75, 1, 1.5])
        'seam $k u$u': kTotal + k * kE + (u - .5) * kVWIN,
  };

  // WP-W3: the older moves 9 (Lift-off) and 10 (Homecoming) bring Space's
  // ground in from below (and take it out) after the other bands, as the
  // prototype does: mid-move the rows behind the strip are Space's empty
  // sky, with no ground edge above the strip (checked by eye against the
  // prototype, evidence/wpW3/side).
  const groundInTransit = {'seam 9 u0.5', 'seam 9 u0.75', 'seam 10 u0.25'};

  // a seam is checked once it and both scenes it joins are ported
  bool ported(String name) {
    final n = int.parse(name.split(' ')[1]);
    return name.startsWith('scene')
        ? portedScenes.contains(n - 1)
        : portedSeams.contains(n) &&
              portedScenes.contains(n - 1) &&
              portedScenes.contains(n % 10);
  }

  for (final e in frames.entries) {
    test('${e.key} renders at 568 and 730', () async {
      Uint8List? small;
      for (final h in [568.0, 730.0]) {
        final img = await renderBackdrop(cam: e.value, viewHeight: h);
        final px = await rgbaOf(img);
        img.dispose();
        if (!ported(e.key)) continue;
        if (groundInTransit.contains(e.key)) continue;
        // no row behind the bottom strip is plain sky (#F1F1F1)
        for (var y = h.round() - 44; y < h.round(); y++) {
          var plain = true;
          for (var x = 0; x < 320 && plain; x++) {
            final i = (y * 320 + x) * 4;
            if (px[i] != 0xF1 || px[i + 1] != 0xF1 || px[i + 2] != 0xF1) plain = false;
          }
          expect(plain, isFalse, reason: '${e.key} row $y @$h is plain sky');
        }
        if (h == 568) {
          small = px;
        } else if (e.key.startsWith('scene')) {
          // anchored to the bottom: the last 568 rows are the 568 frame
          final off = (730 - 568) * 320 * 4;
          expect(diffPixels(small!, Uint8List.sublistView(px, off), threshold: 2), 0,
              reason: '${e.key} not bottom-anchored');
        }
      }
    });
  }
}
