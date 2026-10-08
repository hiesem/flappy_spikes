import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/hoops/kinds/train.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The 1.0 `pipe_spawner_test` / `gap_variance_test` ported to hoops
/// (WP-1a): spacing, scroll-in, despawn, the opening ramp by hoop index and
/// the §3.0.2 band rule (it replaces the "both pipe stubs ≥ 20 pt" rule).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  for (final h in [568.0, 711.0]) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 11),
      gameSize: Vector2(320, h),
    );

    tester.testGameWidget(
      '§3.0.1 / §3.0.2 ($h) spawned hoops: one spacing apart, scrolled in '
      'from ≥ 60 pt past the edge, opening by hoop index, inside the band',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        final spawns = <(Hoop, SlotPlan, double)>[];
        for (final hoop in run.spawner.hoops) {
          spawns.add((hoop, hoop.plan, run.state.camX));
        }
        run.events.on<HoopSpawned>((e) {
          // WP-3c: a Ring Train's rings 2 and 3 belong to the same slot.
          if (e.plan.extra is TrainRing) return;
          spawns.add((e.hoop, e.plan, run.state.camX));
        });
        final flight = await flyRun(game, maxSeconds: 80, untilHoops: 32);
        expect(
          flight.hoops,
          greaterThanOrEqualTo(25),
          reason: flight.trace.last,
        );
        expect(spawns.length, greaterThanOrEqualTo(25));
        final bandTop = Config.spikeHeight, bandBottom = h - Config.spikeHeight;
        for (var i = 0; i < spawns.length; i++) {
          final (hoop, plan, cam) = spawns[i];
          expect(plan.index, i);
          // Never pops into view (one frame of scrolling at most).
          expect(
            plan.trackX - cam,
            greaterThanOrEqualTo(320 + 60 - 4),
            reason: 'hoop $i spawned at ${plan.trackX - cam} on screen',
          );
          if (i > 0) {
            expect(
              plan.trackX - spawns[i - 1].$2.lastRingX,
              closeTo(RunConfig.spacing, 1e-6),
            );
          }
          expect(hoop.opening, closeTo(RunConfig.openingFor(i), 1e-9));
          final m =
              hoop.opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin;
          expect(
            plan.centreY - bandTop,
            greaterThanOrEqualTo(m - 1e-6),
            reason: 'hoop $i too close to the top tooth line',
          );
          expect(
            bandBottom - plan.centreY,
            greaterThanOrEqualTo(m - 1e-6),
            reason: 'hoop $i too close to the floor tooth line',
          );
        }
        // Hoops 0–2 sit at 0.45–0.55 of the band, hoop 0 at exactly 0.5.
        expect(spawns.first.$2.centreY, closeTo(h / 2, 1e-6));
      },
    );
  }

  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  tester.testGameWidget(
    'stalled frames keep hoops one spacing apart (one clamped clock)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true; // nothing ends the run during the check
      final seen = <Hoop>{};
      for (var frame = 0; frame < 420; frame++) {
        game.update(frame % 15 == 14 ? 1.0 : 1 / 60);
        if (frame % 10 == 0) await flushAndMount(game);
        seen.addAll(run.spawner.hoops);
        final xs = run.spawner.hoops.map((h) => h.planeX).toList()..sort();
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], closeTo(RunConfig.spacing, 1e-6));
        }
        // One clamped step never moves the world more than maxFrameStep.
      }
      expect(game.state, GameState.playing);
      expect(seen.length, greaterThanOrEqualTo(3));
    },
  );

  tester.testGameWidget(
    'hoops despawn after leaving the left edge of the screen',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyRun(game, untilHoops: 6);
      await flushAndMount(game);
      for (final hoop in run.spawner.hoops) {
        expect(
          hoop.planeX - run.state.camX,
          greaterThan(-RunConfig.firstHoopOffscreen - hoop.opening - 1),
        );
      }
      expect(run.spawner.hoops.length, lessThanOrEqualTo(4));
      expect(
        run.layers.back.children.whereType<Hoop>().length,
        run.spawner.hoops.length,
      );
      expect(
        run.layers.front.children.whereType<HoopFrontLayer>().length,
        run.spawner.hoops.length,
      );
    },
  );
}
