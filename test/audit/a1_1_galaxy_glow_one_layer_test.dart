// Audit A1-1: the Galaxy dust trail drew its stars' violet glow as one
// mask-blur pass PER STAR (~16 per frame in the preview and again in its
// tile — each an offscreen pass on the GPU), the reason the skin-shop preview
// slowed down with Galaxy dust. The glow is now one blurred layer per frame.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts mask-blurred draws and layers; everything else is ignored.
class _Counting implements ui.Canvas {
  int maskBlurs = 0, layers = 0, blurLayers = 0, draws = 0;
  int _save = 1;
  final Float64List _m = Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;

  void _d(ui.Paint p) {
    draws++;
    if (p.maskFilter != null) maskBlurs++;
  }

  @override
  int getSaveCount() => _save;
  @override
  void save() => _save++;
  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    layers++;
    if (paint.imageFilter != null) blurLayers++;
    _save++;
  }

  @override
  void restore() => _save > 1 ? _save-- : null;
  @override
  void restoreToCount(int count) => _save = math.min(_save, count);
  @override
  Float64List getTransform() => _m;
  @override
  void drawPath(ui.Path path, ui.Paint paint) => _d(paint);
  @override
  void drawRect(ui.Rect rect, ui.Paint paint) => _d(paint);
  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) => _d(paint);
  @override
  void drawOval(ui.Rect rect, ui.Paint paint) => _d(paint);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('Galaxy dust: no per-star mask blur, one glow layer per frame', () {
    final e = TrailEmitter('galaxy', random: math.Random(3));
    var stars = 0;
    for (var frame = 0; frame < 240; frame++) {
      e.emit(ui.Offset(150, 70 + 6 * math.sin(frame / 9)), 1 / 60, k: 1.9);
      e.step(1 / 60);
      final c = _Counting();
      e.paint(c, k: 1.9);
      expect(c.maskBlurs, 0, reason: 'frame $frame');
      expect(c.blurLayers, lessThanOrEqualTo(1), reason: 'frame $frame');
      expect(c.layers, c.blurLayers, reason: 'frame $frame');
      if (frame > 60) {
        expect(c.blurLayers, 1, reason: 'stars are alive: frame $frame');
        expect(c.draws, greaterThan(20));
        stars++;
      }
    }
    expect(stars, greaterThan(0));
  });

  test('Galaxy dust still draws the violet glow around its stars', () async {
    final e = TrailEmitter('galaxy', random: math.Random(3));
    for (var frame = 0; frame < 120; frame++) {
      e.emit(const ui.Offset(150, 70), 1 / 60, k: 1.9);
      e.step(1 / 60);
    }
    final rec = ui.PictureRecorder();
    e.paint(ui.Canvas(rec), k: 1.9);
    final img = await rec.endRecording().toImage(200, 140);
    final d = (await img.toByteData())!;
    // Strongly violet pixels (#E040FB glow: red and blue well above green).
    var violet = 0;
    for (var i = 0; i < d.lengthInBytes; i += 4) {
      final r = d.getUint8(i), g = d.getUint8(i + 1), b = d.getUint8(i + 2);
      final a = d.getUint8(i + 3);
      if (a > 20 && b > g + 40 && r > g + 30) violet++;
    }
    expect(violet, greaterThan(50));
  });
}
