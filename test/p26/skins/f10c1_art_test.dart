import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/skill_art_v26_part1.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> render(String id, double time, {bool front = true}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final isHoop = ['spikes', 'phoenixring', 'legend'].contains(id);
  f10c1Painters[id]!(
    canvas,
    const ui.Offset(100, 100),
    isHoop ? 35 : 1,
    time,
    front: front,
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
      final back = await render(id, .3, front: false);
      expect(front, isNot(orderedEquals(back)), reason: id);
    }
  });
}
