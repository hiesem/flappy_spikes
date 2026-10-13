import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'p23_render.dart';

/// PRD-2.3 §19.6 "Port check against the page": renders the 60 new items in
/// Flutter exactly like `tool/skins_port/harness.html` renders them with the
/// approved JavaScript, and — when the page render exists
/// (`node tool/skins_port/render_js.mjs 1.3` writes
/// `build/skins_port/js_1.3.png`) — writes the side-by-side contact sheet
/// (page left, Flutter right, 4 pairs per row in tag order H1…T15) to
/// `build/skins_port/SKINS_PORT.png`. `docs/p23/SKINS_PORT.png` is a copy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('port check: Flutter render + side-by-side sheet', (
    tester,
  ) async {
    const t = 1.3, w = 160.0, h = 110.0, s = 2.0;
    await tester.runAsync(() async {
      final dart = await renderGrid(
        [for (final (l, id) in p23Items) (c) => paintPortCell(c, l, id, t)],
        w: w,
        h: h,
        scale: s,
      );
      await writePng(dart, 'build/skins_port/dart_$t.png');
      final js = File('build/skins_port/js_$t.png');
      if (!js.existsSync()) return;
      final codec = await ui.instantiateImageCodec(js.readAsBytesSync());
      final jsImage = (await codec.getNextFrame()).image;
      const cw = w * s, ch = h * s, gap = 6.0;
      final n = p23Items.length, rows = (n / 4).ceil();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final sw = 4 * (2 * cw + gap), sh = rows * (ch + gap);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, sw, sh),
        Paint()..color = const Color(0xFF7A0044),
      );
      for (var i = 0; i < n; i++) {
        final src = Rect.fromLTWH((i % 4) * cw, (i ~/ 4) * ch, cw, ch);
        final x = (i % 4) * (2 * cw + gap), y = (i ~/ 4) * (ch + gap);
        canvas.drawImageRect(
          jsImage,
          src,
          Rect.fromLTWH(x, y, cw, ch),
          Paint(),
        );
        canvas.drawImageRect(
          dart,
          src,
          Rect.fromLTWH(x + cw, y, cw, ch),
          Paint(),
        );
      }
      final sheet = await rec.endRecording().toImage(sw.round(), sh.round());
      await writePng(sheet, 'build/skins_port/SKINS_PORT.png');
    });
    expect(File('build/skins_port/dart_1.3.png').existsSync(), isTrue);
  });
}
