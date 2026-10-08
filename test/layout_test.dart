import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
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

      // §3.0.2 the hoop band scales with the playfield height: 623 pt
      // between the 44 pt strips' tooth lines at 711 (480 at 568).
      expect(711 - 2 * Config.spikeHeight, 623);
      expect(Config.worldHeight - 2 * Config.spikeHeight, 480);

      // Home screen layout follows the playfield height (PRD-home-v3 §3.1):
      // the title is pinned to the top, START sits at its 711 spot.
      await flushAndMount(game);
      final home = game.world.children.query<HomeScreen>().single;
      expect(home.title.position, Config.homeTitlePositionFor(711));
      expect(home.title.anchor, Anchor.topCenter);
      expect(home.startButton.position.y, 390);
      expect(home.startButton.position.y, Config.homeStartTopFor(711));
    },
  );
}
