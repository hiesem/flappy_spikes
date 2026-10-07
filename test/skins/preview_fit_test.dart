import 'dart:ui' as ui;

import 'package:flappy_spikes/components/skins/preview_stage.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered vertical extent of [look] (art units, origin = art-box centre)
/// over a spread of animation frames, wing up and down.
Future<(double, double)> _rendered(Look look) async {
  const s = 2.0, half = 60.0, px = 240;
  var top = double.infinity, bottom = double.negativeInfinity;
  for (final t in const [0.0, .45, .9, 1.35, 2.3]) {
    for (final flap in const [false, true]) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..scale(s)
        ..translate(half, half);
      LookPainter.paint(canvas, look, t: t, flap: flap);
      final image = await recorder.endRecording().toImage(px, px);
      final data = (await image.toByteData())!;
      image.dispose();
      for (var y = 0; y < px; y++) {
        for (var x = 0; x < px; x++) {
          if (data.getUint8((y * px + x) * 4 + 3) > 20) {
            final wy = y / s - half;
            if (wy < top) top = wy;
            if (wy + 1 / s > bottom) bottom = wy + 1 / s;
          }
        }
      }
    }
  }
  return (top, bottom);
}

PreviewStage _stage(Look Function() look) => PreviewStage(
  rect: Config.skinShopStageRect,
  look: look,
  triedLayer: () => null,
  tab: () => SkinLayer.hat,
  background: () => const ui.Color(0xFFEEEEEE),
  play: (_) {},
  reduceMotion: () => false,
);

const _tallHats = ['wizard', 'chef', 'party', 'tophat', 'prop', 'halo'];

void main() {
  // QA S2-51: the extent table the preview places the bird by must cover
  // what the art really draws.
  test('LookPainter.extentOf covers every bird with every hat and gear', () async {
    for (final bird in BirdArt.ids) {
      final looks = [
        Look(bird: bird),
        for (final hat in HatArt.ids) Look(bird: bird, hat: hat),
        for (final gear in GearArt.ids) Look(bird: bird, gear: gear),
      ];
      for (final look in looks) {
        final (top, bottom) = await _rendered(look);
        final (predictedTop, predictedBottom) = LookPainter.extentOf(look);
        expect(top, greaterThanOrEqualTo(predictedTop - .51), reason: '$look');
        expect(
          bottom,
          lessThanOrEqualTo(predictedBottom + .51),
          reason: '$look',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('tall hats fit the preview through the bob and the celebration hop', () {
    for (final bird in BirdArt.ids) {
      for (final hat in _tallHats) {
        final look = Look(bird: bird, hat: hat);
        final stage = _stage(() => look);
        final (_, bottom) = LookPainter.extentOf(look);
        // Settle, then a celebration hop and a plain hop.
        for (var i = 0; i < 60; i++) {
          stage.update(1 / 60);
        }
        stage.celebrate(Rarity.epic);
        var lowest = double.infinity;
        for (var i = 0; i < 180; i++) {
          if (i == 90) stage.hop();
          stage.update(1 / 60);
          final top = stage.lookTopNow();
          if (top < lowest) lowest = top;
          expect(
            stage.birdY + 3 + bottom * PreviewStage.k,
            lessThanOrEqualTo(stage.height),
            reason: '$look bottom',
          );
        }
        expect(lowest, greaterThanOrEqualTo(0), reason: '$look top');
      }
    }
  });

  test('a look without a tall hat keeps resting at the stage middle', () {
    final stage = _stage(() => const Look(bird: 'classic', hat: 'cap'));
    stage.update(1 / 60);
    expect(stage.restY, stage.height / 2);
  });
}
