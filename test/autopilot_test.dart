import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );
  final withTallGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(const {}, 711),
    gameSize: Vector2(1080, 2400),
  );

  void autopilotTest(FlameTester<FlappySpikesGame> tester, String name) {
    tester.testGameWidget(
      name,
      setUp: (game, tester) async {
        await game.ready();
        game.sound.enabled = false;
        await preloadImages(game);
        game.onScreenTap(); // start -> playing
        game.update(1 / 60);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final bird = game.world.children.query<Bird>().single;
        const dt = 1 / 60;
        var t = 0.0;
        var frames = 0;
        final trace = <String>[]; // ring buffer, dumped on death
        void log(String s) {
          trace.add(s);
          if (trace.length > 50) {
            trace.removeAt(0);
          }
        }

        // Bang-bang controller, one decision per frame. Targets the nearest
        // un-cleared pipe, but aims at the point INSIDE its visible gap band
        // closest to the NEXT pipe's aim point — the bird is then already
        // pre-positioned (and moving the right way) for the next gap the
        // moment it clears the current one.
        double aimBand(PipePair pipe) {
          final gapTop = pipe.gapBottomY - pipe.gap;
          // Aim slightly below the gap center, clamped to the VISIBLE gap:
          // when the gap slides under a spike strip, only the part inside
          // the playfield is flyable.
          final visibleTop =
              gapTop < Config.spikeHeight ? Config.spikeHeight : gapTop;
          final visibleBottom =
              pipe.gapBottomY > game.viewHeight - Config.spikeHeight
                  ? game.viewHeight - Config.spikeHeight
                  : pipe.gapBottomY;
          return (pipe.gapBottomY - pipe.gap / 2 + 10).clamp(
            visibleTop + Config.birdRadius + 4,
            visibleBottom - Config.birdRadius - 4,
          );
        }

        while (t < 75.0 &&
            game.state == GameState.playing &&
            game.score < 30) {
          game.update(dt);
          t += dt;
          // Flush microtasks only every 10 frames (a flush per frame makes
          // the test crawl): newly spawned pairs finish mounting within
          // 0.17 s, long before they matter to the controller.
          if (++frames % 10 == 0) {
            await Future<void>.value();
          }
          if (game.state != GameState.playing) {
            break;
          }

          final upcoming =
              game.world.children.query<PipePair>().where((pipe) {
                return pipe.isLoaded &&
                    pipe.body.position.x + Config.pipeWidth / 2 >
                        Config.birdX - Config.birdRadius;
              }).toList()
                ..sort(
                  (a, b) => a.body.position.x.compareTo(b.body.position.x),
                );

          // The flyable band [lo, hi] while crossing the current pipe (or
          // the whole sky when no pipe is near); aimY is the target altitude.
          var lo = Config.spikeHeight + Config.birdRadius + 2;
          var hi =
              game.viewHeight - Config.spikeHeight - Config.birdRadius - 2;
          var aimY = game.viewHeight / 2 + 16; // hold just below mid-screen
          var secondsToCrossing = 999.0;
          if (upcoming.isNotEmpty) {
            final first = upcoming.first;
            final gapTop = first.gapBottomY - first.gap;
            final visibleTop =
                gapTop < Config.spikeHeight ? Config.spikeHeight : gapTop;
            final visibleBottom =
                first.gapBottomY > game.viewHeight - Config.spikeHeight
                    ? game.viewHeight - Config.spikeHeight
                    : first.gapBottomY;
            lo = visibleTop + Config.birdRadius + 2;
            hi = visibleBottom - Config.birdRadius - 2;
            aimY = aimBand(first);
            if (upcoming.length > 1) {
              // Pre-position toward the next gap while staying inside the
              // current pipe's band.
              aimY = aimBand(upcoming[1]).clamp(lo, hi);
            }
            secondsToCrossing =
                (first.body.position.x -
                        Config.pipeWidth / 2 -
                        (Config.birdX + Config.birdRadius)) /
                    Config.scrollSpeed;
            if (secondsToCrossing < 0) {
              secondsToCrossing = 0;
            }
          }

          // Predicted altitude at the crossing moment if we never flap again
          // (fall speed capped at the terminal velocity, like the game does).
          final vyNow = bird.body.linearVelocity.y;
          final yNow = bird.body.position.y;
          double predictedY(double tAhead) {
            const cap = Config.maxFallSpeed;
            const g = Config.gravity;
            final tCap = vyNow >= cap ? 0.0 : (cap - vyNow) / g;
            if (tAhead <= tCap) {
              return yNow + vyNow * tAhead + 0.5 * g * tAhead * tAhead;
            }
            final yCap = yNow + vyNow * tCap + 0.5 * g * tCap * tCap;
            return yCap + cap * (tAhead - tCap);
          }

          // Flap when (a) below the aim point, or (b) on course to undershoot
          // the band at the crossing — but only if the flap's arc cannot
          // carry the bird out of the top of the band (apex guard; rise ~55
          // + margin) and we are not already rocketing upward.
          final apexIfFlap = yNow - 65;
          final mustClimb =
              yNow > aimY || predictedY(secondsToCrossing) > hi - 5;
          var action = '-';
          if (mustClimb && apexIfFlap > lo && vyNow > -50) {
            game.onScreenTap();
            action = 'FLAP';
          }
          log(
            't=${t.toStringAsFixed(2)} y=${yNow.toStringAsFixed(1)} '
            'vy=${vyNow.toStringAsFixed(0)} band=[${lo.toStringAsFixed(1)},'
            '${hi.toStringAsFixed(1)}] aim=${aimY.toStringAsFixed(1)} '
            'px=${upcoming.isEmpty ? '-' : upcoming.first.body.position.x.toStringAsFixed(0)} '
            'gap=${upcoming.isEmpty ? '-' : '[${(upcoming.first.gapBottomY - upcoming.first.gap).toStringAsFixed(0)},${upcoming.first.gapBottomY.toStringAsFixed(0)}]'} '
            '$action',
          );
        }

        // The gate: the early game (score < 12, gap >= ~125 pt, flyable band
        // >= ~90 pt) must be comfortably survivable — that was the user's
        // complaint. Reaching 30 (past the whole ramp) is the stretch goal
        // and is logged for information; late-game deaths do not fail.
        expect(
          game.score,
          greaterThanOrEqualTo(12),
          reason: 'autopilot died during the EASY phase at score '
              '${game.score} (t=${t.toStringAsFixed(1)}s, '
              'viewHeight=${game.viewHeight})\nlast frames:\n'
              '${trace.join('\n')}',
        );
        // ignore: avoid_print
        print(
          'AUTOPILOT final: score=${game.score}, state=${game.state}, '
          't=${t.toStringAsFixed(1)}s, viewHeight=${game.viewHeight}',
        );
      },
    );
  }

  autopilotTest(
    withGame,
    'AUTOPILOT (568): the easy early game is comfortably survivable',
  );
  autopilotTest(
    withTallGame,
    'AUTOPILOT (711): the easy early game is comfortably survivable',
  );
}
