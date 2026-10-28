import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/run/screens/versus_intro.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../../menu_screenshot_test.dart' show loadFonts;
import '../../share/share_card_golden_test.dart' show loadCardFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadFonts();
    await loadCardFonts();
  });
  for (final level in [19, 23, 24, 999]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 568),
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      'real results rank and versus plate at level $level',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        final summary = RunSummary(
          score: 10,
          hoopsPassed: 10,
          coins: 10,
          bestBefore: 20,
          bestAfter: 20,
          runSeconds: 10,
          cause: MistakeCause.spikes,
          hoopIndex: 10,
          timeline: RunTimeline.empty(),
        );
        final page = ResultsScreen(
          summary: summary,
          model: ResultsModel(
            score: 10,
            bestBefore: 20,
            bestAfter: 20,
            reward: 10,
            levelBefore: level,
            levelAfter: level,
          ),
        );
        final intro = VersusIntro(
          myName: trackLevelDef(level)!.name,
          myLook: Look.defaults,
          myLevel: level,
        );
        game.world.addAll([page, intro]);
        await flushAndMount(game);
        intro.youPlate.emblemVisible = true;
        intro.youPlate.update(0);
        final frame = await tester.runAsync(() async {
          await intro.youPlate.emblem.imageReady;
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawColor(const ui.Color(0xFFF1F1F1), ui.BlendMode.src);
          canvas.save();
          canvas.translate(0, 20 - page.rank.y);
          page.rank.renderTree(canvas);
          canvas.restore();
          canvas.save();
          canvas.translate(
            44 - intro.youPlate.x + intro.youPlate.width / 2,
            80 - intro.youPlate.y + intro.youPlate.height / 2,
          );
          intro.youPlate.renderTree(canvas);
          canvas.restore();
          final picture = recorder.endRecording();
          final frame = await picture.toImage(320, 170);
          picture.dispose();
          return frame;
        });
        await expectLater(
          frame!,
          matchesGoldenFile('goldens/j7_real_$level.png'),
        );
        frame.dispose();
      },
    );
  }
}
