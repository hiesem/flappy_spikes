import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/start_panel.dart';
import 'package:flappy_spikes/components/ui/sprite_button.dart';
import 'package:flappy_spikes/components/ui/text_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  withGame.testGameWidget(
    'start scene: leaderboard button and privacy link are present and safe',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<StartPanel>().single;

      // Small pink button at 3/4 width, level with the sound toggle (2014
      // original layout). The sound toggle shares its 30x30 size, so find by
      // position instead.
      final gameCenter = panel.children.whereType<SpriteButton>().firstWhere(
            (b) => b.position.x == Config.gameCenterButtonPosition.x,
          );
      expect(gameCenter.position.y, Config.gameCenterButtonPosition.y);
      expect(gameCenter.size.x, Config.gameCenterButtonSize.x);

      final link = panel.children.whereType<TextButton>().single;
      expect(link.label.text, 'Privacy Policy');
      expect(link.position, Config.privacyLinkPosition);

      // Pressing either is a guarded no-op without configured services: no
      // crash, and the tap must not leak through and start the game.
      gameCenter.onPressed();
      link.onPressed();
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
      gameCenter.onPressed(); // guarded no-op: must not throw
    },
  );
}
