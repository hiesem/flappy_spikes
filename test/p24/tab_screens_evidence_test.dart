import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'support/tablet.dart';

/// WP-TAB screenshot evidence at 3:4 (and the other shapes for home and
/// a run): home, skins, a run with hoops, a portal ride, results. LOOK at
/// them (evidence/tab/screens).
void main() {
  const prefs = {
    'firstRunHintSeen': true,
    'bestScore': 25,
    'playerLevel': 1,
    'gamesPlayed': 34,
    'claimedLevels': ['1'],
  };

  for (final (name, w, h) in kShapes) {
    final size = canvasFor(w, h);
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {
          ...prefs,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
        worldHeight: worldHeightFor(w, h),
      ),
      gameSize: size,
    ).testGameWidget(
      'WP-TAB evidence: home, skins, run, results @$name',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        stepGame(g, 1);
        await flushAndMount(g);
        await shoot(tester, g, size, 'screens', '${name}_home');
        if (name == '3x4') {
          g.openSkins();
          await flushAndMount(g);
          stepGame(g, 1);
          await flushAndMount(g);
          await shoot(tester, g, size, 'screens', '${name}_skins');
          g.handleSystemBack();
          stepGame(g, 1);
          await flushAndMount(g);
        }
        g.runDebug.god = true;
        await startRun(g, startHoopIndex: 3);
        await flyUntil(g, (r) => r.state.runClock > 5);
        await shoot(tester, g, size, 'screens', '${name}_run');
        g.runDebug.god = false;
        killRunThroughSaves(g);
        await declineRevive(g);
        for (var i = 0; i < 40 && g.state != GameState.results; i++) {
          stepGame(g, .25);
          await flushAndMount(g);
          await declineRevive(g);
        }
        for (var i = 0; i < 20 && !(g.resultsScreen?.canContinue ?? false); i++) {
          await flushAndMount(g);
          stepGame(g, .25);
        }
        stepGame(g, 2);
        await flushAndMount(g);
        expect(g.resultsScreen?.canContinue, isTrue);
        await shoot(tester, g, size, 'screens', '${name}_results');
        expect(g.state, GameState.results);
      },
    );
  }

  for (final ride in RideId.values) {
    final size = canvasFor(3, 4);
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {
          ...prefs,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
        worldHeight: worldHeightFor(3, 4),
      ),
      gameSize: size,
    ).testGameWidget(
      'WP-TAB evidence: portal ride ${ride.name} @3x4',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        g.runDebug.god = true;
        await startRun(g, startHoopIndex: 3, ride: ride, force: [ElementId.portal]);
        var shots = 0;
        var t = 0.0;
        String? last;
        await flyUntil(g, (r) {
          t += 1 / 60;
          final phase = r.state.ride?.phase;
          if (phase != null && phase != last) {
            last = phase;
            return true;
          }
          return false;
        }, maxSeconds: 40);
        // One shot per ride phase, every 1.2 s while it runs.
        for (var i = 0; i < 14 && shots < 12; i++) {
          final r = g.run!;
          if (r.state.ride == null && i > 0) break;
          await shoot(tester, g, size, 'rides', '${ride.name}_${i.toString().padLeft(2, '0')}_${r.state.ride?.phase ?? 'none'}');
          shots++;
          await flyUntil(g, (_) => false, maxSeconds: 1.2);
        }
        expect(shots, greaterThan(0));
        expect(t, greaterThan(0));
      },
    );
  }

  final size34 = canvasFor(3, 4);
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: {'bestScore': 25, 'playerLevel': 1, 'claimedLevels': ['1']},
      worldHeight: worldHeightFor(3, 4),
    ),
    gameSize: size34,
  ).testGameWidget(
    'WP-TAB evidence: first-run hint, pause, revive @3x4',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      await openRun(g);
      stepGame(g, 1.5);
      await flushAndMount(g);
      await shoot(tester, g, size34, 'screens', '3x4_waiting_hint');
      g.onScreenTap();
      await flyUntil(g, (r) => r.state.hoopsPassed >= 7, maxSeconds: 40);
      g.pause();
      await flushAndMount(g);
      stepGame(g, .5);
      expect(g.state, GameState.paused);
      expect(g.pauseScreen!.position.x, g.extraWidth / 2);
      await flushAndMount(g);
      await shoot(tester, g, size34, 'screens', '3x4_pause');
      g.resume();
      stepGame(g, .2);
      killRunThroughSaves(g);
      for (var i = 0; i < 30 && g.state != GameState.reviving; i++) {
        stepGame(g, .1);
      }
      await flushAndMount(g);
      stepGame(g, 1.5);
      await flushAndMount(g);
      await shoot(tester, g, size34, 'screens', '3x4_revive');
    },
  );
}
