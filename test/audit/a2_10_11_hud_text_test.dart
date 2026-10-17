import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/hud/run_badges.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The game's fonts (the HUD text is Opificio / Fredoka / LVDC).
Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

/// A2-10 / A2-11: the HUD's text layout.
///
/// A2-10: the collectable badges built a new [HudText] (a new TextPainter
/// layout) on every frame. A2-11: [HudText.paintCentred] laid the text out a
/// second time per frame during a fade, for its width. Both changes must
/// draw exactly the same pixels, so the frames are golden images recorded
/// before the change.
void main() {
  setUpAll(_fonts);
  FlameTester<FlappySpikesGame> tester() => FlameTester(
    () => createRunTestGame(worldHeight: 568, prefs: {'firstRunHintSeen': true}),
    gameSize: Vector2(Config.worldWidth, 568),
  );

  tester().testGameWidget(
    'A2-10 the collectable badges draw the same frames',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, t) async {
      final run = await startRun(game);
      run.state.egg = EggState()..stage = EggStage.chick;
      run.state.piggy = PiggyState()
        ..placed = 12
        ..caught = 7
        ..missed = 3;
      run.state.jar = JarState()
        ..caught = 9
        ..escaped = 2;
      final badges = [EggBadge(run), PiggyBadge(run), JarBadge(run)];
      final image = await t.runAsync(() async {
        // Several frames: the egg's chick animates with its own clock.
        ui.Image? img;
        for (var frame = 0; frame < 5; frame++) {
          for (final b in badges) {
            b.update(1 / 30);
          }
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 320, 568));
          for (final b in badges) {
            b.render(canvas);
          }
          final pic = rec.endRecording();
          img?.dispose();
          img = await pic.toImage(320, 568);
          pic.dispose();
        }
        return img!;
      });
      await expectLater(image!, matchesGoldenFile('goldens/a2_10_badges.png'));
      image.dispose();
    },
  );

  tester().testGameWidget(
    'A2-11 the HUD text drawn through a fade is unchanged',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, t) async {
      final image = await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 320, 568));
        final label = HudText('VS', size: 16, color: const ui.Color(0xFFEC008C), font: HudConfig.nameFont);
        final score = HudText('1234', size: 24, color: const ui.Color(0xFFFFFFFF), spacing: .04);
        for (var i = 0; i < 8; i++) {
          final a = 1 - i / 8;
          label.paintCentred(canvas, ui.Offset(60 + i * 30.0, 120), opacity: a);
          score.paintCentred(canvas, ui.Offset(160, 200 + i * 30.0), opacity: a);
          score.paintCentred(
            canvas,
            ui.Offset(260, 200 + i * 30.0),
            opacity: a,
            colorOverride: const ui.Color(0xFF7CB518),
          );
        }
        label.paintCentred(canvas, const ui.Offset(160, 480));
        final pic = rec.endRecording();
        final img = await pic.toImage(320, 568);
        pic.dispose();
        return img;
      });
      await expectLater(image!, matchesGoldenFile('goldens/a2_11_fade.png'));
      image.dispose();
    },
  );
}
