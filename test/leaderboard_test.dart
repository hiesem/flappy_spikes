import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/ui/service_message.dart';
import 'package:flappy_spikes/components/ui/sprite_button.dart';
import 'package:flappy_spikes/components/ui/text_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Records [submitBestScore] / [showLeaderboards] calls instead of touching
/// plugins.
class SpyGameServices extends GameServices {
  int submitCalls = 0;
  int? lastSubmitted;
  int showCalls = 0;
  ShowLeaderboardResult nextShowResult = ShowLeaderboardResult.unavailable;

  @override
  Future<void> submitBestScore(int value) async {
    submitCalls++;
    lastSubmitted = value;
  }

  @override
  Future<ShowLeaderboardResult> showLeaderboards() async {
    showCalls++;
    return nextShowResult;
  }
}

/// Boots a game in the playing state with a spy services instance and the
/// given persisted prefs, then runs [verify].
void testGameWidgetWithSpy(
  String name, {
  required Map<String, Object> prefs,
  required Future<void> Function(
    FlappySpikesGame game,
    SpyGameServices spy,
    WidgetTester tester,
  )
  verify,
}) {
  final spy = SpyGameServices();
  final spyGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(prefs, null, spy),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );
  spyGame.testGameWidget(
    name,
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();
    },
    verify: (game, tester) => verify(game, spy, tester),
  );
}

void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  withGame.testGameWidget(
    'start scene: leaderboard button is present and safe, no privacy link',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final home = game.world.children.query<HomeScreen>().single;

      // PRD-home-v3 §3.1: the trophy box sits in the top row next to the
      // gear (x 60, y 58, 38 x 38) and opens the leaderboard.
      final row = home.trophyButton;
      final expected = Config.homeTrophyRectFor(game.viewHeight);
      expect(row.position.x, expected.left);
      expect(row.position.y, expected.top);
      expect(row.size.x, expected.width);
      expect(row.size.y, expected.height);
      expect(expected, const Rect.fromLTWH(60, 58, 38, 38));

      // The privacy-policy link lives on the settings screen (2026-07-22):
      // no text buttons on the home screen.
      expect(home.children.whereType<TextButton>(), isEmpty);

      // Pressing it is a guarded no-op without configured services: no
      // crash, and the tap must not leak through and start the game.
      row.onPressed();
      expect(game.state, GameState.start);
    },
  );

  withGame.testGameWidget(
    'game-over scene: leaderboard button sits at the right of the pointsfield',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      game.onScreenTap(); // start -> playing
      game.update(1 / 60);
      await game.ready();
    },
    verify: (game, tester) async {
      game.onBirdHit();
      await flushAndMount(game); // mount the game-over panel

      final panel = game.world.children.query<GameOverPanel>().single;
      final buttons = panel.children.whereType<SpriteButton>().toList();
      expect(buttons, hasLength(3), reason: 'replay + share + leaderboard');
      final gameCenter = buttons.firstWhere(
        (b) => b.size.x == Config.gameCenterGameoverButtonSize.x,
      );
      expect(gameCenter.position.x, Config.gameCenterGameoverButtonPosition.x);
      expect(gameCenter.position.y, Config.gameCenterGameoverButtonPosition.y);
      // The button is fade-gated while invisible (Fix E): step past its
      // fade-in so the press exercises the real path.
      stepGame(game, 0.3);
      gameCenter.onPressed(); // guarded no-op: must not throw
    },
  );

  group('score submission', () {
    testGameWidgetWithSpy(
      'submits the stored best on game over even without a new best',
      prefs: {
        'bestScore': 25,
        'claimedLevels': ['1'], // no LEVEL UP popup
      },
      verify: (game, spy, tester) async {
        game.score = 5; // below the stored best
        game.onBirdHit();
        expect(spy.submitCalls, 1);
        expect(spy.lastSubmitted, 25, reason: 'PGS keeps the max server-side');
      },
    );

    testGameWidgetWithSpy(
      'submits the new best when the score beats it',
      prefs: {
        'bestScore': 25,
        'claimedLevels': ['1'], // no LEVEL UP popup
      },
      verify: (game, spy, tester) async {
        game.score = 30;
        game.onBirdHit();
        expect(spy.submitCalls, 1);
        expect(spy.lastSubmitted, 30);
      },
    );
  });

  group('game-over leaderboard button fade gate (Fix E)', () {
    testGameWidgetWithSpy(
      'is untappable while invisible, tappable after the fade-in',
      prefs: const {},
      verify: (game, spy, tester) async {
        game.onBirdHit();
        await flushAndMount(game); // mount the game-over panel (opacity 0)

        final panel = game.world.children.query<GameOverPanel>().single;
        final gameCenter = panel.children
            .whereType<SpriteButton>()
            .firstWhere(
              (b) => b.size.x == Config.gameCenterGameoverButtonSize.x,
            );

        gameCenter.onPressed();
        expect(
          spy.showCalls,
          0,
          reason: 'Flame hit-testing ignores opacity: the tap must be gated '
              'on the fade-in completing',
        );

        stepGame(game, 0.3); // stagger(0) reaches opacity 1
        gameCenter.onPressed();
        expect(spy.showCalls, 1);
      },
    );
  });

  group('service failure message (Fix B)', () {
    testGameWidgetWithSpy(
      'shows a transient accent message when sign-in fails, then removes it',
      prefs: const {},
      verify: (game, spy, tester) async {
        spy.nextShowResult = ShowLeaderboardResult.signInFailed;
        await game.showLeaderboard();
        await flushAndMount(game);

        var messages = game.world.children.query<ServiceMessage>();
        expect(messages, hasLength(1));
        expect(messages.single.message, 'Play Games sign-in unavailable');
        expect(messages.single.position.x, Config.serviceMessagePosition.x);
        expect(messages.single.position.y, Config.serviceMessagePosition.y);

        stepGame(game, Config.uiFadeDuration + 0.1); // fade-in complete
        messages = game.world.children.query<ServiceMessage>();
        expect(
          messages.single.textComponent.textRenderer.style.color,
          Config.uiAccent,
          reason: 'service messages use the fixed UI pink, not the stage tint',
        );

        // Gone after fade-in + hold + fade-out.
        stepGame(
          game,
          2 * Config.uiFadeDuration + Config.serviceMessageHoldDuration,
        );
        await flushAndMount(game);
        expect(game.world.children.query<ServiceMessage>(), isEmpty);
      },
    );

    testGameWidgetWithSpy(
      'shows the leaderboard copy when the native UI fails',
      prefs: const {},
      verify: (game, spy, tester) async {
        spy.nextShowResult = ShowLeaderboardResult.leaderboardFailed;
        await game.showLeaderboard();
        await flushAndMount(game);

        final messages = game.world.children.query<ServiceMessage>();
        expect(messages.single.message, 'Leaderboard unavailable — try again');
      },
    );

    testGameWidgetWithSpy(
      'no message when services are unavailable (tests/unconfigured builds)',
      prefs: const {},
      verify: (game, spy, tester) async {
        await game.showLeaderboard(); // default spy result: unavailable
        await flushAndMount(game);
        expect(game.world.children.query<ServiceMessage>(), isEmpty);
      },
    );
  });
}
