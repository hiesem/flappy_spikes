import 'dart:ui';

import 'package:flappy_spikes/components/levels/emblem_view.dart';
import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-home-v3 §11 performance: the emblem paints from a cached picture
/// whenever it is visually static.
void main() {
  void draw(EmblemView view) {
    final recorder = PictureRecorder();
    view.render(Canvas(recorder));
    recorder.endRecording().dispose();
  }

  test('levels 1-6 outside the sweep draw the shared static picture', () {
    final view = EmblemView(level: 6, artScale: .936)..t = 3;
    expect(EmblemPainter.sweepActive(3), isFalse);
    draw(view);
    expect(view.drewCached, isTrue);
    // Inside the sweep (first 28 % of 6.4 s) it paints live.
    view.t = 1;
    draw(view);
    expect(view.drewCached, isFalse);
    // Reduce motion: no sweep -> static again.
    view
      ..shine = false
      ..t = 1.5;
    draw(view);
    expect(view.drewCached, isTrue);
  });

  test('animated levels paint live while t runs, cached when frozen', () {
    final view = EmblemView(level: 9, artScale: .936)..t = 3;
    draw(view);
    expect(view.drewCached, isFalse);
    view.t = 3.1;
    draw(view);
    expect(view.drewCached, isFalse);
    // Paused (popup / ad): the same t frame after frame.
    draw(view);
    expect(view.drewCached, isTrue);
    draw(view);
    expect(view.drewCached, isTrue);
  });

  test('pop scale 0 draws nothing', () {
    final view = EmblemView(level: 3, artScale: 1)..popScale = 0;
    draw(view);
    expect(view.drewCached, isFalse);
  });
}
