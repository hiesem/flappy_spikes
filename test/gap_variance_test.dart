import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('gap variance math', () {
    test('gapVarianceForScore tapers 50 -> 20 on the ramp schedule', () {
      expect(Config.gapVarianceForScore(0), 50);
      expect(Config.gapVarianceForScore(Config.difficultyRampScore), 20);
      expect(
        Config.gapVarianceForScore(50),
        20,
        reason: 'variance stays at the end value past the ramp',
      );
      // Same linear schedule as gapForScore between the endpoints.
      expect(Config.gapVarianceForScore(5), closeTo(44, 1e-9));
      expect(Config.gapVarianceForScore(12), closeTo(35.6, 1e-9));
    });

    test('gapForPipe stays within [curve, curve + variance]', () {
      for (final score in [0, 5, 12, 25, 50]) {
        final curve = Config.gapForScore(score);
        final variance = Config.gapVarianceForScore(score);
        for (final rng in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          final gap = Config.gapForPipe(score, rng);
          expect(
            gap,
            greaterThanOrEqualTo(curve),
            reason: 'below the curve at score $score, rng $rng',
          );
          expect(
            gap,
            lessThanOrEqualTo(curve + variance + 1e-9),
            reason: 'above curve + variance at score $score, rng $rng',
          );
        }
        // Endpoints are exact: rng 0 draws the curve itself (the MINIMUM
        // gap), rng 1 draws curve + full variance — except at score 0,
        // where 145 + 50 = 195 exceeds the 568 cap and clamps to 192.
        expect(Config.gapForPipe(score, 0.0), closeTo(curve, 1e-9));
        if (score == 0) {
          expect(
            Config.gapForPipe(0, 1.0),
            closeTo(Config.maxGapFor(568), 1e-9),
            reason: 'the 568 visibility cap binds at the largest start draw',
          );
        } else {
          expect(Config.gapForPipe(score, 1.0), closeTo(curve + variance, 1e-9));
        }
      }
    });

    test('gapForPipe clamps rng01 and caps at maxGapFor', () {
      expect(Config.gapForPipe(0, -0.5), closeTo(Config.gapForScore(0), 1e-9));
      expect(
        Config.gapForPipe(0, 1.5),
        closeTo(Config.maxGapFor(568), 1e-9),
        reason:
            'rng > 1 clamps to 1.0, then 145 + 50 = 195 caps at the 568 '
            'visibility limit',
      );
      // On a tiny playfield the cap binds below curve + variance.
      expect(
        Config.gapForPipe(0, 1.0, 400),
        closeTo(Config.maxGapFor(400), 1e-9),
        reason: '195 would leave no room for both 20 pt stubs at height 400',
      );
    });

    test('maxGapFor is the largest gap with both stubs >= minPipeStub', () {
      expect(Config.maxGapFor(568), 192);
      expect(Config.maxGapFor(730), 273);
      expect(
        Config.maxGapFor(711),
        (711 - 2 * (Config.spikeHeight + Config.minPipeStub)) / 2,
      );
    });

    test('gapBottomMinFor keeps the top pipe stub >= minPipeStub', () {
      expect(
        Config.gapBottomMinFor(105),
        Config.gapBottomMin,
        reason: 'below gap 110 the flat 202 floor rules (105 + 92 = 197)',
      );
      expect(
        Config.gapBottomMinFor(110),
        Config.gapBottomMin,
        reason: 'crossover: 110 + 72 + 20 == 202',
      );
      expect(
        Config.gapBottomMinFor(120),
        120 + Config.spikeHeight + Config.minPipeStub,
        reason:
            '212: the stub rule exceeds the 202 floor past gap 110 '
            '(formula max(gapBottomMin, gap + 92))',
      );
      expect(
        Config.gapBottomMinFor(145),
        237,
        reason: 'the 145 start gap forces gapBottomY >= 237',
      );
      // The invariant itself, across the whole gap range.
      for (final gap in [50.0, 90.0, 105.0, 145.0, 172.0, 192.0]) {
        expect(
          Config.gapBottomMinFor(gap) - gap - Config.spikeHeight,
          greaterThanOrEqualTo(Config.minPipeStub),
          reason: 'top stub below ${Config.minPipeStub} pt at gap $gap',
        );
      }
    });
  });

  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );
  final withTallGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(const {}, 711),
    gameSize: Vector2(1080, 2400),
  );

  void spawnInvariantTest(FlameTester<FlappySpikesGame> tester, String name) {
    tester.testGameWidget(
      name,
      setUp: (game, tester) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
        game.onScreenTap(); // start -> playing; first pair spawns on frame 1
        game.update(1 / 60);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        // Record (gap, gapBottomY, score at spawn) for every pair the
        // spawner produces over ~30 s. Pairs are removed right after they
        // are recorded (same pattern as the other spawner tests) so the
        // simple flap bot survives the whole run.
        final seen = <PipePair>{};
        final records = <({double gap, double gapBottomY, int score})>[];

        // Forces lifecycle processing (flushAndMount's zero-dt updates do
        // not advance game time) so every pair spawned by the preceding
        // stepping is registered in the children query, then records +
        // removes all.
        Future<void> collectAndClear() async {
          await flushAndMount(game);
          for (final pipe in game.world.children.query<PipePair>()) {
            if (seen.add(pipe)) {
              records.add((
                gap: pipe.gap,
                gapBottomY: pipe.gapBottomY,
                score: game.score,
              ));
            }
            pipe.removeFromParent();
          }
        }

        // The score is swept through the ramp in 6 s phases with a CLEAN
        // BARRIER between them: a pair discovered one step late must still
        // be tagged with the score it was actually spawned at, so the next
        // phase's score is only applied after the barrier pass has found
        // every pair of the current phase.
        const phaseScores = [0, 5, 12, 25, 50];
        for (final phaseScore in phaseScores) {
          game.score = phaseScore;
          var t = 0.0;
          while (t < 6.0) {
            // flapBelow = the autopilot's cruising altitude (autopilot_test:
            // "hold just below mid-screen").
            stepGame(game, 0.1, flapBelow: game.viewHeight / 2 + 16);
            t += 0.1;
            await collectAndClear();
          }
          await collectAndClear(); // phase barrier
        }

        expect(
          records.length,
          greaterThanOrEqualTo(15),
          reason: '~20 spawns expected over 30 s, got ${records.length}',
        );
        expect(
          game.state,
          GameState.playing,
          reason: 'the flap bot must survive with pipes removed',
        );
        for (final record in records) {
          final curve = Config.gapForScore(record.score);
          expect(
            record.gap,
            greaterThanOrEqualTo(curve - 1e-9),
            reason:
                'gap ${record.gap} below curve $curve at score '
                '${record.score}',
          );
          expect(
            record.gap,
            lessThanOrEqualTo(
              curve + Config.gapVarianceForScore(record.score) + 1e-9,
            ),
            reason:
                'gap ${record.gap} above curve + variance at score '
                '${record.score}',
          );
          expect(
            record.gapBottomY - record.gap - Config.spikeHeight,
            greaterThanOrEqualTo(Config.minPipeStub - 1e-9),
            reason:
                'top stub < ${Config.minPipeStub} pt (gap ${record.gap} at y '
                '${record.gapBottomY}, viewHeight ${game.viewHeight})',
          );
          expect(
            game.viewHeight - Config.spikeHeight - record.gapBottomY,
            greaterThanOrEqualTo(Config.minPipeStub - 1e-9),
            reason:
                'bottom stub < ${Config.minPipeStub} pt (gap ${record.gap} at y '
                '${record.gapBottomY}, viewHeight ${game.viewHeight})',
          );
        }
      },
    );
  }

  spawnInvariantTest(
    withGame,
    'spawned pipes (568): gap in the variance band, both stubs >= minPipeStub',
  );
  spawnInvariantTest(
    withTallGame,
    'spawned pipes (711): gap in the variance band, both stubs >= minPipeStub',
  );
}
