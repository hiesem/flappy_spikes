import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class _ShowcasePlan extends ShowcasePlan {
  const _ShowcasePlan();

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => const ShowcaseRunPlan(highlightId: 'portal', step: 0, attempt: 1);
}

Future<void> _fonts() async {
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await opificio.load();
}

Future<ui.Image> _frame(FlappySpikesGame game) async {
  final size = Vector2(320, game.viewHeight.roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  return recorder.endRecording().toImage(size.x.toInt(), size.y.toInt());
}

void main() {
  setUpAll(_fonts);
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues(const {});
      final game = FlappySpikesGame(
        worldHeight: height,
        soundEnabled: false,
        showcasePlan: const _ShowcasePlan(),
      );
      game.runSeed = 7;
      return game;
    }, gameSize: Vector2(320, height)).testGameWidget(
      'WP-B2 FREE revive heart at ${height.round()}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        run.debugPass(perfect: true);
        killRun(game);
        await flushAndMount(game);
        final screen = game.reviveScreen!;
        for (var i = 0; i < 30 && screen.ui < 1; i++) {
          game.update(1 / 60);
        }
        final image = await tester.runAsync(() => _frame(game));
        await expectLater(
          image!,
          matchesGoldenFile('goldens/free_revive_${height.round()}.png'),
        );
        image.dispose();
      },
    );
  }
}
