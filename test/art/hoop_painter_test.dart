import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/hoop_painter.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'art_render.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 60;
  final centre = const ui.Offset(30, 30);

  test('ids match the PRD 5.4 catalogue in display order', () {
    // PRD 2.6 F10: three skill items follow the original grid.
    expect(HoopPainter.ids, [for (final i in itemsFor(SkinLayer.hoop)) i.id]);
    expect(HoopPainter.ids, hasLength(33));
    expect(HoopPainter.fallbackId, 'pink');
  });

  test('every hoop draws both halves at several t without throwing', () {
    for (final id in HoopPainter.ids) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (final t in const [0.0, .4, 1.3, 7.7]) {
        HoopPainter.paintHalf(
          canvas,
          id,
          centre,
          20,
          t,
          front: false,
          lineWidth: 7,
        );
        HoopPainter.paintHalf(
          canvas,
          id,
          centre,
          20,
          t,
          front: true,
          lineWidth: 7,
        );
        HoopPainter.paintHoopTile(canvas, id, centre, 20, t);
      }
      recorder.endRecording().dispose();
    }
  });

  test('degenerate sizes draw nothing', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    HoopPainter.paintHalf(canvas, 'pink', centre, 0, 1, front: true);
    HoopPainter.paintHalf(
      canvas,
      'pink',
      centre,
      20,
      1,
      front: true,
      lineWidth: 0,
    );
    HoopPainter.paintHoopTile(canvas, 'pink', centre, 0, 1);
    recorder.endRecording().dispose();
  });

  testWidgets('unknown hoop id falls back to the classic pink ring', (
    tester,
  ) async {
    final known = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'pink',
        centre,
        20,
        .8,
        front: true,
        lineWidth: 7,
      );
    });
    final unknown = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'not-a-hoop',
        centre,
        20,
        .8,
        front: true,
        lineWidth: 7,
      );
    });
    expect(unknown, equals(known));
    expect(hasInk(known), isTrue);
  });

  testWidgets('back half is the right side, front half the left side', (
    tester,
  ) async {
    final back = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'pink',
        centre,
        20,
        0,
        front: false,
        lineWidth: 7,
      );
    });
    final front = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'pink',
        centre,
        20,
        0,
        front: true,
        lineWidth: 7,
      );
    });

    // rx = ry * .26 = 5.2, so the ring passes x = 30 +- 5.2 at y = 30.
    expect(pixel(back, size, 34, 30)[3], greaterThan(0), reason: 'back = +x');
    expect(pixel(front, size, 34, 30)[3], 0, reason: 'front skips +x');
    expect(pixel(front, size, 26, 30)[3], greaterThan(0), reason: 'front = -x');
    expect(pixel(back, size, 26, 30)[3], 0, reason: 'back skips -x');
    // The opening stays empty in both halves.
    expect(pixel(back, size, 30, 30)[3], 0);
    expect(pixel(front, size, 30, 30)[3], 0);
  });

  testWidgets('the black hole fills the opening on the back half only', (
    tester,
  ) async {
    final back = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'blackhole',
        centre,
        20,
        .5,
        front: false,
        lineWidth: 7,
      );
    });
    final front = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'blackhole',
        centre,
        20,
        .5,
        front: true,
        lineWidth: 7,
      );
    });
    expect(pixel(back, size, 30, 30)[3], 255, reason: 'opening is filled');
    expect(
      pixel(front, size, 30, 30)[3],
      0,
      reason: 'no fill on the front half',
    );
  });

  testWidgets('plain hoops use the front/back colours of the skin', (
    tester,
  ) async {
    final sky = await capture(tester, size, size, (canvas) {
      HoopPainter.paintHalf(
        canvas,
        'sky',
        centre,
        20,
        0,
        front: true,
        lineWidth: 7,
      );
    });
    expect(pixel(sky, size, 26, 30), [41, 182, 246, 255]);
  });

  testWidgets('animated hoops change with t', (tester) async {
    for (final id in const [
      'candy',
      'lava',
      'ice',
      'rainbow',
      'galaxy',
      'neon',
    ]) {
      final a = await capture(tester, size, size, (canvas) {
        HoopPainter.paintHalf(
          canvas,
          id,
          centre,
          20,
          0,
          front: true,
          lineWidth: 7,
        );
      });
      final b = await capture(tester, size, size, (canvas) {
        HoopPainter.paintHalf(
          canvas,
          id,
          centre,
          20,
          .9,
          front: true,
          lineWidth: 7,
        );
      });
      expect(a, isNot(equals(b)), reason: '$id should animate with t');
    }
  });
}
