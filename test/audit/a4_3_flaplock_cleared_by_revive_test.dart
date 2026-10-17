// Audit A4-3 (2026-10-17): a spring flap lock running at death survived the
// revive and dropped taps for up to 0.45 s after the phoenix. The revive
// reset now clears it.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: const {'coins': 1000}, worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'A4-3 a spring flap lock running at death must not survive a revive; '
    'the run clock stands still through the offer and the phoenix',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final run = await startRun(g);
      run.state.invulnerable = 0;
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      // A spring launch 0.1 s before the death: its lock is still running.
      run.state.flapLock = 0.35;
      final clockAtDeath = run.state.runClock;
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.reviving, reason: 'offer up (>= 6 hoops)');
      final screen = g.reviveScreen!;
      screen.tapHeart();
      for (var i = 0; i < 900 && g.state == GameState.reviving; i++) {
        g.update(1 / 60);
        if (i % 10 == 9) await flushAndMount(g);
      }
      await flushAndMount(g);
      expect(g.state, GameState.playing, reason: 'phoenix finished');
      expect(
        run.state.runClock,
        closeTo(clockAtDeath, 1e-9),
        reason: 'run clock stood still through offer + phoenix',
      );
      expect(
        run.state.invulnerable,
        closeTo(2, 0.05),
        reason: 'invulnerable 2 s after the phoenix',
      );
      expect(
        run.state.flapLock,
        0,
        reason:
            'S-2: flapLock is ${run.state.flapLock.toStringAsFixed(3)} '
            'after the revive (taps ignored: ${run.flapLocked})',
      );
    },
  );
}
