import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

List<(SlotPlan, GapPlan)> _plans(RunDirector director, double height) {
  double? previous;
  return List.generate(400, (i) {
    final ctx = DirectorContext.open(height, prevCentreY: previous);
    final slot = director.nextSlot(ctx);
    previous = slot.centreY;
    return (slot, director.nextGap(ctx, slot));
  });
}

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'R2 same seed has the same rules across ordinary player setups',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      game.runDebug.ignoreGates = false;
      game.storage.metElements = {
        for (final element in ElementId.values) element.storageId,
      };
      // WP-H is not wired yet: the shipped arm is the baked arm 0.
      // No arm input exists on RunSetup or RunDirector. Exercise every
      // currently selectable arm here when that input is introduced.
      for (final seed in [7, 21, 1234]) {
        List<(SlotPlan, GapPlan)>? baseline;
        for (final games in [6, 500]) {
          for (final best in [0, 32500000]) {
            for (final level in [0, 31, 36]) {
              for (final mode in HomeMode.values) {
                for (final noAds in [false, true]) {
                  game.storage
                    ..gamesPlayed = games
                    ..bestScore = best
                    ..playerLevel = level
                    ..noAds = noAds;
                  await game.storage.saveHomeMode(mode);
                  final setup = RunSetup(
                    seed: seed,
                    viewHeight: 711,
                    opponent: mode == HomeMode.versus
                        ? OpponentRun(
                            uid: 'rival',
                            name: 'Rival',
                            score: 50,
                            best: 500,
                            level: 31,
                            timeline: RunTimeline()..end(100),
                            runId: 'rival-run',
                          )
                        : null,
                  );
                  final run = RunController(setup: setup, game: game);
                  expect(run.setup.showcase, isNull);
                  expect(run.setup.ignoreGates, isFalse);
                  expect(run.countsForUpload, isTrue);
                  final plans = _plans(run.director, 711);
                  baseline ??= plans;
                  expect(
                    plans,
                    baseline,
                    reason:
                        'seed=$seed games=$games best=$best level=$level '
                        'mode=$mode noAds=$noAds arm=0',
                  );
                }
              }
            }
          }
        }
      }
    },
  );

  test('R2 delta y in points is identical at 711 and 730', () {
    for (var seed = 0; seed < 200; seed++) {
      RunDirector director() => RunDirector(
        seed: seed,
        enabled: ElementId.values.toSet(),
        met: ElementId.values.toSet(),
      );
      final a = _plans(director(), 711);
      final b = _plans(director(), 730);
      for (var i = 1; i < 400; i++) {
        expect(
          a[i].$1.centreY - a[i - 1].$1.centreY,
          closeTo(b[i].$1.centreY - b[i - 1].$1.centreY, 1e-8),
          reason: 'seed=$seed hoop=$i',
        );
      }
    }
  });
}
