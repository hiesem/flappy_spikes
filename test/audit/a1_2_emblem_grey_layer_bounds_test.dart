// Audit A1-2: a locked LEVELS row draws its emblem greyed through a layer.
// The layer had null bounds (= the whole clip, the list viewport) for every
// locked row every frame; it is now bounded to the emblem art. The result
// must stay identical to the unbounded layer (±2 levels of edge rounding).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flutter_test/flutter_test.dart';

final ui.Paint _grey = ui.Paint()
  ..colorFilter = const ui.ColorFilter.matrix(<double>[
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    0, 0, 0, .38, 0,
  ]);

Future<Uint8List> _render(void Function(ui.Canvas c) paint) async {
  const px = 400;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec)
    ..translate(px / 2, px / 2)
    ..scale(1.5);
  paint(c);
  final img = await rec.endRecording().toImage(px, px);
  final bytes = (await img.toByteData())!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

void main() {
  test('greyed emblems: bounded layer matches the unbounded one', () async {
    for (var level = 0; level <= EmblemPainter.maxLevel; level++) {
      for (final t in const [0.0, .5, 1.3, 2.9, 4.1]) {
        final bounded = await _render(
          (c) => EmblemPainter.paint(c, level, t: t, grey: true),
        );
        final reference = await _render((c) {
          c.saveLayer(null, _grey);
          EmblemPainter.paint(c, level, t: t);
          c.restore();
        });
        var m = 0;
        for (var i = 0; i < bounded.length; i++) {
          final d = (bounded[i] - reference[i]).abs();
          if (d > m) m = d;
        }
        // The host rasteriser rounds a few anti-aliased edge pixels of a
        // bounded layer by ±1-2 levels (the LEVELS screen frame itself
        // compared byte-identical); nothing moves, nothing is cut off.
        expect(m, lessThanOrEqualTo(2), reason: 'level $level t $t');
      }
    }
  });
}
