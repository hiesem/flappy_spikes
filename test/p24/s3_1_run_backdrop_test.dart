import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/backdrop/run_backdrop.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/run_layers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.4 §3.1 / §3.3: the run background shows only in the run (not on
/// home, results or bonus pages), sits at the bottom of the world, freezes
/// with pause, and its seams land on hoop 40·k in a real run.
void main() {
  const prefs = {'firstRunHintSeen': true};

  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  FlameTester<FlappySpikesGame> tester({double h = 568, bool met = false}) => FlameTester(
        () => createRunTestGame(
          prefs: {
            ...prefs,
            // every element met: no first-meet force (a forced portal at
            // hoop 38 would make hoop 40 a ride ring)
            if (met) 'metElements': [for (final e in ElementId.values) e.storageId],
          },
          worldHeight: h,
        ),
        gameSize: Vector2(320, h),
      );

  tester().testGameWidget(
    'absent on home; in the run under everything; gone after the results',
    setUp: (g, _) async => boot(g),
    verify: (g, _) async {
      expect(g.state, GameState.start);
      expect(RunBackdrop.of(g), isNull);
      expect(g.world.children.whereType<RunBackdrop>(), isEmpty);

      final run = await startRun(g);
      await stepSeconds(g, .5);
      final b = RunBackdrop.of(g)!;
      expect(identical(b.run, run), isTrue);
      expect(b.opacity, 1);
      expect(b.priority, RunLayer.runBackdrop);
      final others = g.world.children.where((c) => c is! RunBackdrop && c.priority != RunLayer.backdrop);
      for (final c in others) {
        expect(c.priority, greaterThan(RunLayer.runBackdrop), reason: '$c');
      }

      killRunThroughSaves(g);
      await declineRevive(g);
      await stepSeconds(g, 3);
      expect(g.postRunPageUp, isTrue);
      expect(b.opacity, 0, reason: 'faded out under the post-run page');

      g.replay();
      await stepSeconds(g, 1);
      expect(g.world.children.whereType<RunBackdrop>(), isEmpty);
    },
  );

  tester().testGameWidget(
    'frozen while paused, moving again after resume',
    setUp: (g, _) async => boot(g),
    verify: (g, _) async {
      await startRun(g);
      await flyUntil(g, (r) => r.state.runClock > 2);
      final b = RunBackdrop.of(g)!;
      final w0 = b.worldDistance, t0 = g.run!.state.runClock;
      g.pause();
      await stepSeconds(g, 1);
      expect(b.worldDistance, w0);
      expect(g.run!.state.runClock, t0);
      g.resume();
      await flyUntil(g, (r) => r.state.runClock > t0 + .5);
      expect(b.worldDistance, greaterThan(w0));
    },
  );

  for (final h in [568.0, 730.0]) {
    tester(h: h, met: true).testGameWidget(
      'seam 1 is centred on hoop 40 in a real run @${h.round()}',
      setUp: (g, _) async => boot(g),
      verify: (g, _) async {
        g.runDebug.god = true;
        final run = await startRun(g, startHoopIndex: 34);
        final b = RunBackdrop.of(g)!;
        expect(BackdropWorld.sceneAt(b.worldDistance), 0);
        var prev = b.worldDistance;
        var maxStep = 0.0;
        double? atPlane;
        await flyUntil(g, (r) {
          final w = b.worldDistance;
          final step = w - prev;
          if (step.abs() > maxStep) maxStep = step.abs();
          prev = w;
          for (final hp in r.spawner.hoops) {
            if (hp.plan.index == 40 && hp.plan.kind != HoopKindId.rideRing) {
              if (atPlane == null && r.state.camX + kANCH >= hp.plan.trackX) atPlane = w;
            }
          }
          return atPlane != null;
        }, maxSeconds: 40);
        expect(atPlane, isNotNull);
        // the frame that reaches hoop 40's plane is within one frame's move
        expect((atPlane! - 40 * kPerHoop).abs(), lessThan(6), reason: 'w $atPlane');
        expect(maxStep, lessThan(10), reason: 'continuous');
        expect(run.state.hoopsPassed, greaterThan(0));
      },
    );
  }
}
