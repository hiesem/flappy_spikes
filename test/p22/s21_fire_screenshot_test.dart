import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §21 visual check against `design/menu_v2/screen_fire_choice2.html`
/// (right phone): the bird on fire at ×3, ×5, ×7 with the 2× Classic flame
/// trail, and ×7 with Blue flame. Writes `build/shots/p22/s21_fire_*.png`
/// (never committed); nothing is asserted beyond "rendered".
void main() {
  for (final (streak, trail) in [
    (3, 'flame'),
    (5, 'flame'),
    (7, 'flame'),
    (7, 'blue'),
  ]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: 4),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§21 shot: on fire at ×$streak ($trail)',
      setUp: (g, _) async {
        await g.ready();
        g.sound.enabled = false;
        await preloadImages(g);
      },
      verify: (game, tester) async {
        if (trail != 'flame') {
          await game.storage.saveOwnedItems({
            ...game.storage.ownedItems,
            'trail:$trail',
          });
          await game.menu.items.equip(SkinLayer.trail, trail);
        }
        final run = await startRun(game);
        await flyUntil(game, (_) => false, maxSeconds: 1);
        for (var i = 0; i < streak; i++) {
          run.debugPass(perfect: true);
        }
        await flyUntil(game, (_) => false, maxSeconds: .7);
        await flushAndMount(game);
        const scale = 2.0;
        final size = Vector2(320 * scale, 711 * scale);
        game.onGameResize(size);
        final rec = ui.PictureRecorder();
        final c = ui.Canvas(rec);
        c.drawRect(
          ui.Rect.fromLTWH(0, 0, size.x, size.y),
          ui.Paint()..color = game.backgroundColor(),
        );
        game.render(c);
        await tester.runAsync(() async {
          final img = await rec.endRecording().toImage(
            size.x.toInt(),
            size.y.toInt(),
          );
          final bytes = (await img.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          img.dispose();
          final file = File('build/shots/p22/s21_fire_x${streak}_$trail.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
          expect(bytes.length, greaterThan(10000));
        });
      },
    );
  }
}
