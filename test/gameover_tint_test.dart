import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/ui/fadable_text.dart';
import 'package:flappy_spikes/components/ui/sprite_button.dart';
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
    'game-over panel uses the UI accent pink on title and labels',
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
      // Let the staggered fade-in run to completion (0.5 + 2 * 0.2 = 0.9 s).
      stepGame(game, 1.0);

      final panel = game.world.children.query<GameOverPanel>().single;

      // --- title sprite: accent pink, fully faded in -------------------------
      final sprites = panel.children.whereType<SpriteComponent>().toList();
      final title = sprites.first;
      expect(
        title.paint.colorFilter,
        isNotNull,
        reason: 'gameover_title must carry the accent modulate tint',
      );
      expect(
        title.paint.colorFilter.toString(),
        ColorFilter.mode(Config.uiAccent, BlendMode.modulate).toString(),
        reason: 'gameover_title must be UI pink #FF4FB7, not the pipe tint',
      );
      expect(
        title.paint.color.a,
        closeTo(1, 1e-6),
        reason: 'fade-in must complete (opacity preserved alongside tint)',
      );

      // --- best/games labels: accent pink, fully faded in --------------------
      final labels = panel.children.whereType<FadableTextComponent>();
      final bestLabel =
          labels.firstWhere((l) => l.text.startsWith('Best Score:'));
      final gamesLabel =
          labels.firstWhere((l) => l.text.startsWith('Games Played:'));
      for (final label in [bestLabel, gamesLabel]) {
        expect(
          label.textRenderer.style.color,
          Config.uiAccent,
          reason: '"${label.text}" must render in the UI accent pink',
        );
      }

      // --- natively pink artwork must stay untinted -------------------------
      final pointsfield = sprites[1];
      expect(pointsfield.paint.colorFilter, isNull,
          reason: 'pointsfield artwork is natively colored: no tint');
      for (final button in panel.children.whereType<SpriteButton>()) {
        expect(button.paint.colorFilter, isNull,
            reason: 'replay/share buttons must stay untinted');
      }

      // The current-score label inside the pointsfield is white and nudged
      // above the field center so it clears the "POINTS" caption.
      final scoreLabel = labels.firstWhere((l) => !l.text.contains(':'));
      expect(scoreLabel.textRenderer.style.color, const Color(0xFFFFFFFF));
      expect(
        scoreLabel.position.y,
        closeTo(
          Config.pointsfieldPosition.y + Config.scoreLabelNudgeY,
          1e-9,
        ),
        reason: 'score number must sit above the field center',
      );
      expect(Config.scoreLabelNudgeY, lessThan(0));
    },
  );
}
