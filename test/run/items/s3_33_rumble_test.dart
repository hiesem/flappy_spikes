import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/rumble_router.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2b (WP-2c folded in): run events → rumble (PRD-2 §3.33): the mapping,
/// the 90 ms knock throttle, the never-skipped shake, "only the shake" in a
/// shared window, no rumble outside live play, the RUMBLE switch and its
/// analytics (§6 `setting_changed`).
void main() {
  late AnalyticsSpy spy;

  Future<void> prepare(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  Future<RunController> boot(FlappySpikesGame game) async {
    final run = await startRun(game);
    expect(game.rumble.hardware, isFalse, reason: 'tests: recorder only');
    rumbleLog(game).clear();
    return run;
  }

  /// One frame with the bird held level (no spike contact, no hoop).
  void frame(FlappySpikesGame g) {
    g.runBird!.setFlight(y: g.viewHeight / 2, vy: 0);
    g.update(1 / 60);
  }

  /// [seconds] of quiet frames (clears the 90 ms window).
  void wait(FlappySpikesGame g, double seconds) {
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      frame(g);
    }
  }

  void pickup(RunController run) =>
      run.events.emit(const PickupCollected(ElementId.heart, null));

  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy);
  }, gameSize: Vector2(320, 711));

  tester.testGameWidget(
    '§3.33 / PRD-2.2 §10 mapping: perfect pass → shake, clean off-centre '
    'pass → knock, graze pass → nothing (the touch knocked), pickup → '
    'knock; the shake never grows with the streak',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      expect(run.features.whereType<RumbleRouter>(), hasLength(1));
      final log = rumbleLog(game);
      run.debugPass(perfect: true);
      frame(game);
      expect(log, [RumbleKind.shake]);
      wait(game, .1);
      run.debugPass(perfect: false, clean: true);
      frame(game);
      expect(log, [RumbleKind.shake, RumbleKind.knock]);
      wait(game, .1);
      // PRD-2.2 §10.1 a graze pass adds nothing at the pass.
      run.debugPass(perfect: false);
      frame(game);
      expect(log, [RumbleKind.shake, RumbleKind.knock]);
      wait(game, .1);
      pickup(run);
      frame(game);
      expect(log, [RumbleKind.shake, RumbleKind.knock, RumbleKind.knock]);
      // Ten perfect passes in a row: ten identical shakes (one per frame,
      // never skipped, even inside 90 ms of each other).
      log.clear();
      for (var i = 0; i < 10; i++) {
        run.debugPass(perfect: true);
        frame(game);
      }
      expect(log, List.filled(10, RumbleKind.shake));
      expect(Rumble.shakeMs, 80); // PRD-2.2 §10.3
      expect(Rumble.shakeAmplitude, 255);
      expect(Rumble.knockMs, 15);
      expect(Rumble.knockAmplitude, 90);
    },
  );

  tester.testGameWidget(
    '§3.33 throttle: one knock per 90 ms (20 piggy coins do not buzz '
    'non-stop); a shake is never skipped',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final log = rumbleLog(game);
      // 20 pickups, one per frame (≈ 0.33 s): knocks at ≥ 90 ms spacing.
      for (var i = 0; i < 20; i++) {
        pickup(run);
        frame(game);
      }
      // 60 fps: every 6th frame clears the 90 ms window → 4 knocks.
      expect(log.where((k) => k == RumbleKind.knock).length, inInclusiveRange(3, 4));
      log.clear();
      wait(game, .1);
      // A knock right before a shake (next frame): the shake still fires.
      pickup(run);
      frame(game);
      run.debugPass(perfect: true);
      frame(game);
      expect(log, [RumbleKind.knock, RumbleKind.shake]);
      // A knock right after a shake is dropped (the shake wins its window).
      pickup(run);
      frame(game);
      expect(log, [RumbleKind.knock, RumbleKind.shake]);
    },
  );

  tester.testGameWidget(
    '§3.33 a perfect pass that also collects something in the same frame '
    'plays only the shake (whatever came first)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final log = rumbleLog(game);
      pickup(run); // the comet touched first …
      run.debugPass(perfect: true); // … then the plane
      pickup(run);
      frame(game);
      expect(log, [RumbleKind.shake]);
    },
  );

  tester.testGameWidget(
    '§3.33 no rumble while paused, dying or after the run; nothing else '
    'rumbles (death, saves)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final log = rumbleLog(game);
      run.pause();
      run.debugPass(perfect: true);
      pickup(run);
      game.update(1 / 60);
      expect(log, isEmpty, reason: 'paused');
      run.resume();
      wait(game, .2);
      // A death: no rumble for it, and none while the bird tumbles.
      killRun(game);
      pickup(run);
      run.debugPass(perfect: true);
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      expect(log, isEmpty, reason: 'death / dying / results');
    },
  );

  tester.testGameWidget(
    '§3.33 the RUMBLE switch: off → nothing fires; applies at once; '
    '§6 setting_changed (setting: rumble, value) + rumble_toggle',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final log = rumbleLog(game);
      game.setRumble(false);
      expect(game.storage.rumble, isFalse);
      run.debugPass(perfect: true);
      frame(game);
      pickup(run);
      wait(game, .2);
      expect(log, isEmpty);
      game.setRumble(true);
      log.clear(); // switching on gives its own knock (PRD-home-v3 §8)
      wait(game, .2);
      run.debugPass(perfect: true);
      frame(game);
      expect(log, [RumbleKind.shake]);
      final settings = [
        for (final e in spy.events.where((e) => e.$1 == 'setting_changed'))
          e.$2,
      ];
      expect(settings, [
        {'setting': 'rumble', 'value': 0},
        {'setting': 'rumble', 'value': 1},
      ]);
      expect(
        spy.events.where((e) => e.$1 == 'rumble_toggle').map((e) => e.$2),
        [
          {'on': 0},
          {'on': 1},
        ],
      );
    },
  );

  tester.testGameWidget(
    '§3.33 Hourglass slow motion does not change the pulses (real-time '
    'throttle)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await boot(game);
      final log = rumbleLog(game);
      run.state.timeScale = .45;
      for (var i = 0; i < 20; i++) {
        pickup(run);
        frame(game);
      }
      expect(log.length, inInclusiveRange(3, 4));
    },
  );
}
