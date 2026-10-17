// Audit A4-6 (2026-10-17): a death in the comet's landing tail left up to 8
// speed streaks frozen on screen through the tumble and the revive offer.
// CometFeature.onDeath now clears them.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'A4-6 a death in the comet landing tail clears the speed streaks',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: ElementId.comet.firstPossible!,
        force: [ElementId.comet],
      );
      final comet = run.features.whereType<CometFeature>().single;
      expect(await flyUntil(game, (r) => comet.active), isTrue);
      expect(
        await flyUntil(game, (r) => !comet.active, maxSeconds: 20),
        isTrue,
      );
      final tail = comet.ride!;
      expect(tail.done, isTrue);
      expect(tail.finished, isFalse, reason: 'still in the landing tail');
      expect(tail.lines.count, greaterThan(0), reason: 'streaks on screen');
      run.mistake(const Mistake(MistakeCause.spikes));
      expect(run.dying, isTrue);
      for (var i = 0; i < 60; i++) {
        expect(tail.lines.count, 0, reason: 'no streak frozen on screen');
        game.update(1 / 60);
      }
    },
  );
}
