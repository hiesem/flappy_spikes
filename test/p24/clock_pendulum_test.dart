import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// Owner (2.4.0 40): in the Clockwork scene the pendulum's rod started in
/// mid-air below the ceiling on tall screens. It now hangs from above the
/// screen top, so the rod reaches the top edge at every view height and
/// every point of the swing (the bob keeps its place).
void main() {
  test('the pendulum rod reaches the top of the screen', () async {
    for (final vh in [568.0, 711.0, 730.0]) {
      for (final t in [0.0, .25, .5, 1.5]) {
        final img = await renderBackdrop(
          cam: 3 * kE + kE / 2,
          viewHeight: vh,
          t: t,
        );
        final px = await rgbaOf(img);
        final w = img.width;
        img.dispose();
        // The top row: the sky background is flat, the rod is the only
        // thing drawn there (lighter or darker than the background).
        final bg = px.sublist(0, 4);
        var rod = 0;
        for (var x = 0; x < w; x++) {
          final i = x * 4;
          if ((px[i] - bg[0]).abs() > 3) rod++;
        }
        expect(rod, greaterThan(0), reason: 'view $vh, t $t');
      }
    }
  });
}
