import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/skins/art/bird_art.dart';
import 'package:flappy_spikes/skins/art/skill_art_v26_part2.dart';

Future<Uint8List> render(String id, double time, {bool back = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(48, 48);
  f10c2Painters[id]!(canvas, BirdShape.of('sq'), time, back);
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 120);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the seven approved items are exposed', () {
    expect(f10c2Painters.keys.toSet(), {
      'jackpot',
      'magpie',
      'prism',
      'daynight',
      'goggles',
      'hoopchain',
      'peacock',
    });
  });
  test('each item paints and responds to the game clock', () async {
    for (final id in f10c2Painters.keys) {
      final back = id == 'goggles' || id == 'peacock';
      final first = await render(id, .2, back: back);
      final second = await render(id, 1.4, back: back);
      expect(first.any((x) => x != 0), isTrue, reason: id);
      expect(first, isNot(orderedEquals(second)), reason: id);
    }
  });
  test('fan and scarf back layers paint separately', () async {
    for (final id in ['prism', 'goggles', 'peacock']) {
      expect(
        (await render(id, .5, back: true)).any((x) => x != 0),
        isTrue,
        reason: id,
      );
    }
    for (final id in ['jackpot', 'magpie', 'daynight', 'hoopchain']) {
      expect(
        (await render(id, .5, back: true)).every((x) => x == 0),
        isTrue,
        reason: id,
      );
    }
  });
}
