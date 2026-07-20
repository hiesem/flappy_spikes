import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/start_panel.dart';
import 'package:flappy_spikes/components/ui/sprite_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final withTallGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(const {}, 711),
    gameSize: Vector2(1080, 2400),
  );

  testWidgets('viewHeight is clamped to [568, 730]', (tester) async {
    expect(createTestGame().viewHeight, 568, reason: 'default design height');
    expect(createTestGame(const {}, 711).viewHeight, 711);
    expect(createTestGame(const {}, 2000).viewHeight, 730);
    expect(createTestGame(const {}, 400).viewHeight, 568);
  });

  withTallGame.testGameWidget(
    'tall layout: strips pinned to the true edges, layout stays centered',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      expect(game.viewHeight, 711);

      // Spike strips are pinned to the true top/bottom of the playfield.
      final strips = game.world.children.query<SpikeStrip>();
      final ceiling = strips.firstWhere((s) => s.isCeiling);
      final ground = strips.firstWhere((s) => !s.isCeiling);
      expect(ceiling.body.position.y, closeTo(Config.spikeHeight / 2, 1e-6));
      expect(
        ground.body.position.y,
        closeTo(711 - Config.spikeHeight / 2, 1e-6),
      );

      // The backdrop covers the whole playfield height.
      final backdrop = game.world.children
          .whereType<RectangleComponent>()
          .firstWhere((c) => c.priority == -1000);
      expect(backdrop.size.y, 711);

      // The bird spawns at the playfield center.
      final bird = game.world.children.query<Bird>().single;
      expect(bird.body.position.y, closeTo(711 / 2, 1e-6));

      // The score HUD sits at center + 35.
      final hud = game.world.children.query<ScoreHud>().single;
      expect(hud.position.y, closeTo(711 / 2 + 35, 1e-9));

      // The gap band scales with the playfield height; the 568 default is
      // unchanged.
      expect(
        Config.gapBottomMaxFor(Config.pipeGap, 711),
        711 - Config.spikeHeight - Config.pipeGap - 40,
      );
      expect(
        Config.gapBottomMaxFor(Config.pipeGap),
        Config.gapBottomMax,
      );

      // Start panel layout follows the playfield center.
      final panel = game.world.children.query<StartPanel>().single;
      final title = panel.children
          .whereType<SpriteComponent>()
          .firstWhere((c) => c is! SpriteButton);
      expect(
        title.position.y,
        closeTo(711 / 2 - Config.titleSize.y / 2 - 35, 1e-6),
        reason: 'title keeps its offset above the playfield center',
      );
    },
  );
}
