import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/skill_art_v26_part1.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> render(
  String id,
  double time, {
  bool front = true,
  double? rx,
  double lineWidth = 7,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final isHoop = ['spikes', 'phoenixring', 'legend'].contains(id);
  f10c1Painters[id]!(
    canvas,
    const ui.Offset(100, 100),
    isHoop ? 35 : 1,
    time,
    front: front,
    rx: rx,
    lineWidth: lineWidth,
  );
  final image = await recorder.endRecording().toImage(200, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the first eight skill items paint and animate', () async {
    expect(f10c1Painters.keys.toList(), [
      'spikes',
      'phoenixring',
      'legend',
      'thread',
      'constellation',
      'fireflies',
      'skycrown',
      'nest',
    ]);
    for (final id in f10c1Painters.keys) {
      final first = await render(id, .05);
      final later = await render(id, .7);
      expect(first.any((byte) => byte != 0), isTrue, reason: id);
      expect(later, isNot(orderedEquals(first)), reason: '$id must animate');
    }
  });
  test('hoop halves occupy opposite sides', () async {
    for (final id in ['spikes', 'phoenixring', 'legend']) {
      final front = await render(id, .05);
      final back = await render(id, .05, front: false);
      expect(front, isNot(orderedEquals(back)), reason: id);
      int pixels(Uint8List image, int fromX, int toX) {
        var count = 0;
        for (var y = 55; y < 145; y++) {
          for (var x = fromX; x < toX; x++) {
            if (image[(y * 200 + x) * 4 + 3] != 0) count++;
          }
        }
        return count;
      }

      expect(
        pixels(front, 60, 95),
        greaterThan(pixels(front, 105, 140)),
        reason: '$id front',
      );
      expect(
        pixels(back, 105, 140),
        greaterThan(pixels(back, 60, 95)),
        reason: '$id back',
      );
    }
  });
  test('hoop radius and stroke follow the caller geometry', () async {
    for (final id in ['spikes', 'phoenixring', 'legend']) {
      final narrow = await render(id, 0, front: false, rx: 5, lineWidth: 4);
      final wide = await render(id, 0, front: false, rx: 22, lineWidth: 4);
      int alpha(Uint8List bytes, int x, int y) => bytes[(y * 200 + x) * 4 + 3];
      expect(
        alpha(wide, 122, 100),
        greaterThan(alpha(narrow, 122, 100)),
        reason: id,
      );
      final thick = await render(id, 0, front: false, rx: 22, lineWidth: 12);
      int bandPixels(Uint8List bytes) {
        var count = 0;
        for (var y = 80; y < 120; y++) {
          for (var x = 110; x < 132; x++) {
            final i = (y * 200 + x) * 4;
            final matches = switch (id) {
              'spikes' =>
                bytes[i] < 100 && bytes[i + 1] < 110 && bytes[i + 2] < 115,
              'phoenixring' =>
                bytes[i] > 150 && bytes[i + 1] < 70 && bytes[i + 2] < 30,
              _ => bytes[i] > 150 && bytes[i + 1] > 90 && bytes[i + 2] < 35,
            };
            if (bytes[i + 3] > 200 && matches) count++;
          }
        }
        return count;
      }

      expect(
        bandPixels(thick),
        greaterThan(bandPixels(wide)),
        reason: '$id stroke',
      );
    }
  });
  test('fixed frames retain characteristic colours and parts', () async {
    bool hasColor(
      Uint8List image,
      int rgb,
      int left,
      int top,
      int right,
      int bottom,
    ) {
      final red = (rgb >> 16) & 255, green = (rgb >> 8) & 255, blue = rgb & 255;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final i = (y * 200 + x) * 4;
          if (image[i + 3] > 180 &&
              (image[i] - red).abs() < 25 &&
              (image[i + 1] - green).abs() < 25 &&
              (image[i + 2] - blue).abs() < 25) {
            return true;
          }
        }
      }
      return false;
    }

    final probes = <(String, double, int, int, int, int, int)>[
      ('spikes', 0, 0xb9c3c9, 80, 65, 101, 136),
      ('phoenixring', 0, 0xff5722, 80, 65, 101, 136),
      ('legend', 0, 0xe53935, 85, 115, 100, 130),
      ('legend', 0, 0x1e88e5, 85, 95, 95, 105),
      ('legend', 0, 0x43a047, 85, 70, 100, 85),
      ('thread', 0, 0xffb529, 35, 90, 100, 110),
      ('constellation', .7, 0xffffff, 60, 80, 100, 110),
      ('fireflies', .7, 0xfffde7, 30, 80, 100, 115),
      ('skycrown', 0, 0xec008c, 95, 75, 105, 88),
      ('skycrown', 0, 0xffb529, 88, 94, 112, 100),
      ('nest', 0, 0xfff8e1, 96, 90, 104, 96),
      ('nest', .7, 0xffd54f, 95, 80, 105, 90),
    ];
    for (final (id, time, color, left, top, right, bottom) in probes) {
      expect(
        hasColor(await render(id, time), color, left, top, right, bottom),
        isTrue,
        reason: '$id ${color.toRadixString(16)}',
      );
    }
  });
}
