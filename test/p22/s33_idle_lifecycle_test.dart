import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §33.4 item 5 / §33.7 "Lifecycle": backgrounding pauses the
/// engine and resume continues the same state; idle menus draw at
/// [Config.idleMenuFps] while their idle motion keeps its timing, and a
/// touch brings the display rate back at once.
void main() {
  const frame = Duration(microseconds: 16667);

  /// Pumps [seconds] of 60 Hz frames; returns the game frames drawn.
  Future<int> pumpFor(
    WidgetTester tester,
    FlappySpikesGame g,
    double seconds,
  ) async {
    final before = g.idleFrames.frames;
    final n = (seconds * 60).round();
    for (var i = 0; i < n; i++) {
      await tester.pump(frame);
    }
    return g.idleFrames.frames - before;
  }

  FlameTester<FlappySpikesGame> home() => FlameTester<FlappySpikesGame>(
    () => createTestGame({'claimedLevels': ['1']}, 711),
    gameSize: Vector2(320, 711),
  );

  Future<void> settle(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  group('§33.4 item 5 idle menus', () {
    test('config: 30 fps after 2 s settled', () {
      expect(Config.idleMenuFps, 30);
      expect(Config.idleMenuDelay, 2);
      expect(Config.idleMenuWakeLead, lessThan(1 / 60));
    });

    home().testGameWidget(
      'off by default: the loop runs at the display rate (tests, e2e)',
      setUp: (g, _) => settle(g),
      verify: (g, tester) async {
        expect(g.idleFrames.enabled, isFalse);
        await pumpFor(tester, g, 3);
        final frames = await pumpFor(tester, g, 1);
        expect(frames, inInclusiveRange(58, 61));
        expect(g.idleFrames.idleFrames, 0);
      },
    );

    home().testGameWidget(
      'settled Home draws ~30 frames/s, its idle clock keeps real time, '
      'a touch returns to 60 at once',
      setUp: (g, _) => settle(g),
      verify: (g, tester) async {
        g.idleFrames
          ..enabled = true
          ..attach();
        addTearDown(g.idleFrames.detach);
        expect(g.state, GameState.start);
        expect(g.menuScene, MenuScene.home);

        // Before the idle delay: the display rate.
        final early = await pumpFor(tester, g, 1);
        expect(early, inInclusiveRange(58, 61));
        expect(g.idleFrames.idleFrames, 0);

        await pumpFor(tester, g, 2);
        final clock = g.homeScreen!.clock;
        final t0 = clock.t;
        final idle = await pumpFor(tester, g, 2);
        expect(idle, inInclusiveRange(27 * 2, 33 * 2), reason: '~30 fps');
        expect(g.idleFrames.idleFrames, greaterThan(50));
        // The idle motion (bob, pulse, streak) keeps its speed: the clock
        // advanced by the real 2 s, not by 1 s of half the frames.
        expect(clock.t - t0, closeTo(2, 0.1));

        // A touch anywhere: the very next vsync draws, then 60 fps.
        await tester.pump(frame);
        final atTouch = g.idleFrames.frames;
        final gesture = await tester.startGesture(const Offset(5, 300));
        await tester.pump(frame);
        expect(g.idleFrames.frames, atTouch + 1);
        final awake = await pumpFor(tester, g, 1);
        expect(awake, inInclusiveRange(58, 61));
        await gesture.up();
        await pumpFor(tester, g, 0.5);
      },
    );

    home().testGameWidget(
      'a popup over Home (or any non-menu state) is never limited',
      setUp: (g, _) => settle(g),
      verify: (g, tester) async {
        g.idleFrames.enabled = true;
        g.openSettings();
        await flushAndMount(g);
        await pumpFor(tester, g, 3);
        final frames = await pumpFor(tester, g, 1);
        expect(frames, inInclusiveRange(58, 61));
        expect(g.idleFrames.sleeping, isFalse);
      },
    );
  });

  group('§33.7 lifecycle', () {
    home().testGameWidget(
      'backgrounding pauses the engine; resume continues the same Home',
      setUp: (g, _) => settle(g),
      verify: (g, tester) async {
        g.idleFrames.enabled = true;
        await pumpFor(tester, g, 0.5);
        final home = g.homeScreen;
        expect(g.paused, isFalse);
        g.lifecycleStateChange(AppLifecycleState.inactive);
        g.lifecycleStateChange(AppLifecycleState.hidden);
        g.lifecycleStateChange(AppLifecycleState.paused);
        expect(g.paused, isTrue);
        expect(g.isPausedOnBackground, isTrue);
        final frames = await pumpFor(tester, g, 1);
        expect(frames, 0, reason: 'no update, no frames in the background');
        g.lifecycleStateChange(AppLifecycleState.hidden);
        g.lifecycleStateChange(AppLifecycleState.inactive);
        g.lifecycleStateChange(AppLifecycleState.resumed);
        expect(g.paused, isFalse);
        expect(await pumpFor(tester, g, 0.5), greaterThan(10));
        expect(g.state, GameState.start);
        expect(identical(g.homeScreen, home), isTrue);
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      'backgrounding a run pauses it and the engine; resume keeps the run '
      'paused where it was',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
        await flushAndMount(g);
      },
      verify: (g, tester) async {
        final run = await startRun(g);
        stepGame(g, 1, flapBelow: 300);
        final hoops = run.state.hoopsPassed;
        final score = run.state.score;
        g.lifecycleStateChange(AppLifecycleState.inactive);
        g.lifecycleStateChange(AppLifecycleState.hidden);
        g.lifecycleStateChange(AppLifecycleState.paused);
        expect(g.paused, isTrue);
        expect(g.state, GameState.paused);
        g.lifecycleStateChange(AppLifecycleState.resumed);
        expect(g.paused, isFalse);
        expect(g.state, GameState.paused, reason: 'the pause screen waits');
        expect(run.state.hoopsPassed, hoops);
        expect(run.state.score, score);
      },
    );
  });
}
