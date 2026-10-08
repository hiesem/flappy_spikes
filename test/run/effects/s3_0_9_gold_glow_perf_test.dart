import 'dart:ui';

import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-2b performance check of the §3.0.9 #5 gold glow on non-classic birds
/// (ARCH §3 "Skin interplay"): the glow blurs a layer every frame. Before
/// WP-2b that layer was unbounded (`saveLayer(null, …)` = the whole
/// target, blurred every frame); it is now bounded to the bird's art box +
/// the blur reach. The output must be the same and the frame cheaper.
const double _k = 3; // a Pixel-class 3× device, the bird at the game scale
const int _w = 960, _h = 2133; // 320 × 711 pt at 3×

Picture _frame(Look look) {
  final rec = PictureRecorder();
  final c = Canvas(rec)
    ..scale(_k)
    ..translate(70, 355);
  LookPainter.paint(c, look, t: .4, gold: true);
  return rec.endRecording();
}

Future<ByteData> _raster(Picture p) async {
  final image = await p.toImage(_w, _h);
  final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

Future<double> _ms(Look look, {required bool bounded, int frames = 12}) async {
  LookPainter.goldGlowBounded = bounded;
  // Warm up.
  await _raster(_frame(look));
  final sw = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    final image = await _frame(look).toImage(_w, _h);
    // Force the raster.
    await image.toByteData(format: ImageByteFormat.rawRgba);
    image.dispose();
  }
  return sw.elapsedMicroseconds / 1000 / frames;
}

void main() {
  tearDown(() => LookPainter.goldGlowBounded = true);

  testWidgets('§3.0.9 #5 the gold glow layer is bounded: same pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final id in ['sky', 'pixel']) {
        final look = Look(bird: id);
        LookPainter.goldGlowBounded = false;
        final a = await _raster(_frame(look));
        LookPainter.goldGlowBounded = true;
        final b = await _raster(_frame(look));
        var diff = 0;
        for (var i = 0; i < a.lengthInBytes; i++) {
          if ((a.getUint8(i) - b.getUint8(i)).abs() > 2) diff++;
        }
        expect(diff, 0, reason: '$id: bounded glow draws the same pixels');
      }
    });
  });

  testWidgets('§3.0.9 #5 gold glow frame cost: bounded vs unbounded (info)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const look = Look(bird: 'sky');
      final unbounded = await _ms(look, bounded: false);
      final bounded = await _ms(look, bounded: true);
      debugPrint(
        'GOLD GLOW raster ${_w}x$_h: unbounded ${unbounded.toStringAsFixed(2)} '
        'ms, bounded ${bounded.toStringAsFixed(2)} ms',
      );
      // Information only (CPU raster in the test runner); the bounded layer
      // must never be the slower one by a wide margin.
      expect(bounded, lessThan(unbounded * 1.5 + 2));
    });
  });
}
