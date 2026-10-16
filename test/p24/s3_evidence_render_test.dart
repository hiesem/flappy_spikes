import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// PRD-2.4 §3 WP-W1 visual check: renders scenes 1–3 and seams 1–2 at the
/// moments compared with the prototype (evidence/wpW1, not in git).
void main() {
  const shots = <String, double>{
    'nest_mid': 126000,
    'sky_mid': 138000,
    'city_mid': 150000,
    'seam1_linger_in': 132000 - 4000,
    'seam1_start': 132000 - 1500,
    'seam1_mid': 132000,
    'seam1_q75': 132000 + 750,
    'seam1_end': 132000 + 1500,
    'seam1_linger_out': 132000 + 3000,
    'seam2_linger_in': 144000 - 4000,
    'seam2_start': 144000 - 1500,
    'seam2_q25': 144000 - 750,
    'seam2_mid': 144000,
    'seam2_q75': 144000 + 750,
    'seam2_end': 144000 + 1500,
    'seam2_linger_out': 144000 + 3000,
    'first_loop_start': -126,
    'first_loop_w5000': 5000,
  };
  for (final h in [568.0, 730.0]) {
    for (final e in shots.entries) {
      test('evidence ${e.key} @${h.round()}', () async {
        final img = await renderBackdrop(cam: e.value, viewHeight: h, scale: 2);
        await saveEvidence(img, 'wpW1/dart', '${e.key}_${h.round()}');
        img.dispose();
      });
    }
  }
}
