import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/art_render.dart';

/// Unit tests for the emblem painter (the pixel-level companion of
/// `test/levels/emblem_generator_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // px: 260 x 260 art units — room for the wings (they reach ±113) with the
  // plate centre in the middle.
  const size = 520;
  const scale = 2.0; // px per emblem art unit

  Future<Uint8List> render(
    WidgetTester tester,
    int level, {
    double t = 2,
    bool shine = true,
    bool grey = false,
  }) => capture(tester, size, size, (canvas) {
    canvas.translate(size / 2, size / 2);
    canvas.scale(scale);
    EmblemPainter.paint(canvas, level, t: t, shine: shine, grey: grey);
  });

  int diffPixels(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] ||
          a[i + 1] != b[i + 1] ||
          a[i + 2] != b[i + 2] ||
          a[i + 3] != b[i + 3]) {
        count++;
      }
    }
    return count;
  }

  test('animates() is true for the pennant levels only', () {
    for (var level = 0; level <= 6; level++) {
      expect(EmblemPainter.animates(level), isFalse, reason: 'level $level');
    }
    for (var level = 7; level <= 10; level++) {
      expect(EmblemPainter.animates(level), isTrue, reason: 'level $level');
    }
    // Unknown levels clamp first.
    expect(EmblemPainter.animates(-3), isFalse);
    expect(EmblemPainter.animates(99), isTrue);
  });

  test('every level paints without throwing at several t', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (var level = 0; level <= 11; level++) {
      for (final t in const [0.0, .4, 1.3, 6.5, 12.9]) {
        for (final grey in const [false, true]) {
          canvas.save();
          canvas.translate(size / 2, size / 2);
          EmblemPainter.paint(canvas, level, t: t, grey: grey);
          canvas.restore();
        }
      }
    }
    recorder.endRecording().dispose();
  });

  testWidgets('every level 0..10 renders ink inside the art box', (
    tester,
  ) async {
    for (var level = 0; level <= 10; level++) {
      final rgba = await render(tester, level);
      expect(hasInk(rgba), isTrue, reason: 'level $level');
      // The art (wings ±113, crown −105, ribbon +72) never reaches the
      // canvas edge, so the outermost ring of pixels stays empty.
      for (var i = 0; i < size; i++) {
        for (final p in [
          pixel(rgba, size, i, 0),
          pixel(rgba, size, i, size - 1),
          pixel(rgba, size, 0, i),
          pixel(rgba, size, size - 1, i),
        ]) {
          expect(p[3], 0, reason: 'level $level edge at $i');
        }
      }
    }
  });

  testWidgets('unknown levels clamp to the frame and to LEGEND', (
    tester,
  ) async {
    expect(
      diffPixels(
        await render(tester, -7),
        await render(tester, 0),
      ),
      0,
    );
    expect(
      diffPixels(
        await render(tester, 11),
        await render(tester, 10),
      ),
      0,
      reason: 'level 11 paints the level-10 emblem unchanged',
    );
  });

  testWidgets('grey renders desaturated at 38 % alpha', (tester) async {
    const level = 5; // GLIDER: plate #EBD3F5, no animation at t = 2
    final colour = await render(tester, level);
    final grey = await render(tester, level, grey: true);

    expect(diffPixels(colour, grey), greaterThan(0));
    expect(
      inkPixels(grey),
      closeTo(inkPixels(colour), inkPixels(colour) * .01),
    );

    // A pixel on the plate (2 px above the plate centre, art (0, -1)).
    final x = size ~/ 2, y = size ~/ 2 - 2;
    final c = pixel(colour, size, x, y);
    final g = pixel(grey, size, x, y);
    expect(c[0], 0xEB);
    expect(c[1], 0xD3);
    expect(c[2], 0xF5);
    expect(c[3], 255);
    expect(g[0], g[1]);
    expect(g[1], g[2]);
    expect(g[3], closeTo(255 * .38, 2));
  });

  testWidgets('t moves the pennant levels and nothing else', (tester) async {
    for (var level = 0; level <= 10; level++) {
      final a = await render(tester, level, t: 2, shine: false);
      final b = await render(tester, level, t: 2.5, shine: false);
      final moved = diffPixels(a, b);
      if (EmblemPainter.animates(level)) {
        expect(moved, greaterThan(20), reason: 'level $level animates');
      } else {
        expect(moved, 0, reason: 'level $level is static besides the sweep');
      }
    }
  });

  testWidgets('the sweep runs once per 6.4 s and can be disabled', (
    tester,
  ) async {
    const level = 4;
    // t = .9: half way through the 1.792 s sweep window, so the band is on
    // the plate. At t = 0 it is still off to the left (x -110) and clipped.
    final sweeping = await render(tester, level, t: .9, shine: true);
    final noShine = await render(tester, level, t: .9, shine: false);
    expect(diffPixels(sweeping, noShine), greaterThan(20));

    // Late in the cycle the sweep is gone: shine is a no-op again.
    final late = await render(tester, level, t: 5.5, shine: true);
    final lateOff = await render(tester, level, t: 5.5, shine: false);
    expect(diffPixels(late, lateOff), 0);

    // The sweep is periodic: 6.4 s later it is at the same place.
    final nextCycle = await render(tester, level, t: .9 + 6.4, shine: true);
    expect(diffPixels(sweeping, nextCycle), 0);
  });
}
