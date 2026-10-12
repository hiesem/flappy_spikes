import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2d PRD-2 §5.7: the run HUD row (heart indicator, versus bar, pause
/// button) in the viewport and in real time; pause / resume (no 3-2-1),
/// Esc and backgrounding pause; settings from the pause card.
void main() {
  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  void step(FlappySpikesGame g, double seconds) {
    for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
      g.update(1 / 60);
    }
  }

  void hold(FlappySpikesGame g, double seconds) {
    for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
      if (g.state == GameState.playing) {
        g.runBird!.setFlight(y: g.viewHeight / 2, vy: 0);
      }
      g.update(1 / 60);
    }
  }

  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.7 ($h) solo HUD: in the viewport, heart indicator (empty → ⅓ → '
      '⅔ → full + pulse), pause button at right edge 306, no versus bar, '
      'no coin total; the banner band lives in the run banner layer (PRD-2.2 §12)',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        hold(game, .5);
        final hud = game.runHud!;
        expect(hud.parent, game.camera.viewport);
        expect(hud.rowOpacity, 1);
        expect(hud.versus, isNull);
        expect(hud.heart.position, Vector2(14, 52));
        expect(hud.heart.size, Vector2.all(38));
        expect(hud.pauseButton.position.x + hud.pauseButton.size.x, 306);
        expect(hud.pauseButton.position.y, 52);
        expect(hud.heart.fill, 0);
        run.state.hearts = 1;
        expect(hud.heart.fill, closeTo(1 / 3, 1e-9));
        run.state.hearts = 2;
        expect(hud.heart.fill, closeTo(2 / 3, 1e-9));
        run.state
          ..hearts = 0
          ..extraLife = true;
        expect(hud.heart.fill, 1);
        var maxPulse = 1.0;
        for (var i = 0; i < 60; i++) {
          hold(game, 1 / 60);
          if (hud.heart.pulse > maxPulse) maxPulse = hud.heart.pulse;
        }
        expect(maxPulse, closeTo(1.14, .01));
        // PRD-2.2 §12: the streak's banner host lives in the run's banner
        // layer in the world (behind the gameplay), not in the HUD.
        expect(hud.banners.parent, hud.bannerLayer);
        expect(hud.bannerLayer.parent, game.world);
        expect(game.world.descendants().whereType<BannerHost>().single,
            same(hud.banners));
        expect(hud.descendants().whereType<BannerHost>(), isEmpty);
        // Fades out on a death.
        run.state.extraLife = false;
        killRun(game);
        step(game, .3);
        expect(hud.rowOpacity, 0);
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      versus: FakeVersusService(
        pool: [
          OpponentRun(
            uid: 'u1',
            name: 'Molly',
            score: 2,
            best: 31,
            level: 3,
            timeline: RunTimeline()
              ..addPoint(.5)
              ..addPoint(1)
              ..end(30),
          ),
        ],
      ),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.7 versus bar (placeholder for WP-5b): you / opponent boxes, the '
    "opponent's score replays their timeline on runClock, gold outline "
    'flash when they score',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      await startRun(game);
      await flushAndMount(game);
      final bar = game.runHud!.versus!;
      expect(bar.them.left, 170);
      expect(bar.you.left, 60);
      expect(bar.theirScore, 0);
      hold(game, .6);
      expect(bar.theirScore, 1);
      expect(bar.flash, greaterThan(0));
      hold(game, .6);
      expect(bar.theirScore, 2);
      hold(game, .6);
      expect(bar.flash, 0);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§5.7 / ARCH §0 the HUD runs in real time: an Hourglass time scale '
    'slows the world, not the HUD banners; SAVED! shows in the HUD band',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      hold(game, .3);
      final hud = game.runHud!;
      run.state.timeScale = .45;
      final b = hud.banners.show(ElementBanner('TEST'));
      await flushAndMount(game);
      final clock0 = run.state.runClock;
      hold(game, .5);
      expect(b.time, closeTo(.5, 1e-6));
      expect(run.state.runClock - clock0, closeTo(.5 * .45, 1e-6));
      run.state.timeScale = 1;
      // An extra-life save: "SAVED!" in the HUD band.
      run.state.extraLife = true;
      hold(game, .2);
      run.mistake(const Mistake(MistakeCause.spikes));
      await flushAndMount(game);
      final cur = hud.banners.current;
      expect(cur, isA<ElementBanner>());
      expect((cur! as ElementBanner).text, 'SAVED!');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.7 pause: the pause button freezes the run (runClock, world, bird), '
    'taps do not flap; RESUME is straight back in (no 3-2-1); no pause '
    'during the tumble',
    setUp: (g, _) => boot(g),
    verify: (game, tester) async {
      final run = await startRun(game);
      hold(game, .5);
      // A real tap on the pause button (viewport hit test).
      // The widget letterboxes the 320-wide game: map game → widget.
      final vp = game.camera.viewport;
      final k = vp.size.y / game.viewHeight;
      await tester.tapAt(
        Offset(vp.position.x + 287 * k, vp.position.y + 71 * k),
      );
      // Lets the gesture arena's timers run out (the run is paused).
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.state, GameState.paused);
      await flushAndMount(game);
      final screen = game.pauseScreen!;
      expect(screen.parent, game.camera.viewport);
      final clock = run.state.runClock;
      final camX = run.state.camX;
      final bird = game.runBird!;
      final y = bird.body.position.y;
      game.onScreenTap();
      step(game, 1);
      expect(run.state.runClock, clock);
      expect(run.state.camX, camX);
      expect(bird.body.position.y, y);
      expect(run.isScrolling, isFalse);
      // RESUME: playing on the very next frame.
      game.resume();
      expect(game.state, GameState.playing);
      expect(game.pauseScreen, isNull);
      game.update(1 / 60);
      expect(run.state.runClock, greaterThan(clock));
      expect(run.state.camX, greaterThan(camX));
      // Not while dying.
      killRun(game);
      game.pause();
      expect(game.state, isNot(GameState.paused));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§5.7 / ARCH §2.3 Esc and backgrounding pause a running run; Esc on the '
    'pause screen resumes; settings open over the pause card and come back',
    setUp: (g, _) => boot(g),
    verify: (game, tester) async {
      await startRun(game);
      hold(game, .3);
      const esc = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      );
      game.onKeyEvent(esc, const {});
      expect(game.state, GameState.paused);
      game.onKeyEvent(esc, const {});
      expect(game.state, GameState.playing);
      hold(game, .2);
      game.lifecycleStateChange(AppLifecycleState.paused);
      expect(game.state, GameState.paused);
      await flushAndMount(game);
      // Settings over the pause card.
      game.openRunSettings();
      await flushAndMount(game);
      expect(game.runSettingsOpen, isTrue);
      expect(game.pauseScreen!.hidden, isTrue);
      expect(game.runHud!.hidden, isTrue, reason: 'settings own the screen');
      expect(game.state, GameState.paused);
      game.resume();
      expect(game.state, GameState.paused, reason: 'no resume under settings');
      game.onKeyEvent(esc, const {});
      expect(game.runSettingsOpen, isFalse);
      expect(game.pauseScreen!.hidden, isFalse);
      step(game, .5);
      game.pauseScreen!.tapAt(game.pauseScreen!.resumeRect.center);
      expect(game.state, GameState.playing);
    },
  );
}
