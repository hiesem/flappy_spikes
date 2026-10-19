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
/// with pause, and its seams land on hoop 20·k in a real run.
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
            // hoop 38 / 58 would make hoop 40 / 60 a ride ring)
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
      'seams 2 and 3 are centred on hoops 40 and 60 in a real run @${h.round()}',
      setUp: (g, _) async => boot(g),
      verify: (g, _) async {
        g.runDebug.god = true;
        final run = await startRun(g, startHoopIndex: 34);
        final b = RunBackdrop.of(g)!;
        expect(BackdropWorld.sceneAt(b.worldDistance), 1);
        var prev = b.worldDistance;
        var prevCam = run.state.camX;
        var maxStep = 0.0;
        final atPlane = <int, double>{};
        await flyUntil(g, (r) {
          final w = b.worldDistance;
          final step = w - prev;
          // PRD-2.4 §3.5 (WP-R): a themed portal ride re-syncs the world at
          // its launch while its scene covers the whole screen (not drawn);
          // on a ride the world moves with the ride camera (the launch
          // rushes at the flight camera's speed, the glide catches up).
          final unseen = b.rideHook?.hidden ?? false;
          final dcam = (r.state.camX - prevCam).abs();
          prevCam = r.state.camX;
          final bound = r.state.ride == null ? 10.0 : dcam * 1.2 + 12;
          if (!unseen && step.abs() > bound) {
            fail('step $step > $bound (ride ${r.state.ride?.phase})');
          }
          if (!unseen && r.state.ride == null && step.abs() > maxStep) {
            maxStep = step.abs();
          }
          prev = w;
          for (final hp in r.spawner.hoops) {
            final i = hp.plan.index;
            if ((i == 40 || i == 60) && hp.plan.kind != HoopKindId.rideRing) {
              if (!atPlane.containsKey(i) && r.state.camX + kANCH >= hp.plan.trackX) atPlane[i] = w;
            }
          }
          return atPlane.length == 2;
        }, maxSeconds: 80);
        expect(atPlane.keys, unorderedEquals([40, 60]));
        // the frame that reaches hoop 20·k's plane is within one frame's
        // move of seam k (kHoopsPerScene = 20: one scene is 20 hoops)
        for (final MapEntry(key: i, value: w) in atPlane.entries) {
          expect((w - i * kPerHoop).abs(), lessThan(6), reason: 'hoop $i: w $w');
          expect(BackdropWorld.seamAt(w).j, i ~/ kHoopsPerScene);
        }
        expect(maxStep, lessThan(10), reason: 'continuous');
        expect(run.state.hoopsPassed, greaterThan(0));
      },
    );
  }
}
