import 'dart:ui';

import 'package:flappy_spikes/components/shop/pack_art.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shop pack art (PRD-menu-v4 §2.1)', () {
    test('every tier paints through a full twinkle loop and at rest', () {
      for (var tier = 0; tier < 4; tier++) {
        for (var t = 0.0; t < PackArtPainter.twinkleLoop * 2; t += 0.1) {
          final recorder = PictureRecorder();
          PackArtPainter.paint(Canvas(recorder), tier, t);
          recorder.endRecording().dispose();
        }
        final recorder = PictureRecorder();
        PackArtPainter.paint(Canvas(recorder), tier, 0, still: true);
        recorder.endRecording().dispose();
      }
    });

    test('the burst source lies inside the art box', () {
      final box = Offset.zero & PackArtPainter.size;
      for (var tier = 0; tier < 4; tier++) {
        final heap = PackArtPainter.heapBox(tier);
        expect(box.contains(heap.topCenter), isTrue, reason: 'tier $tier');
      }
    });
  });
}
