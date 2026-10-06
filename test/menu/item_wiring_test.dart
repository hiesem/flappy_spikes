import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// WP-A wiring: MenuState owns the item store, and the debug panel's
/// ALL ITEMS button grants the whole catalogue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final withGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(const {}, 711),
    gameSize: Vector2(320, 711),
  );

  withGame.testGameWidget(
    'MenuState wires ItemStore with the free defaults',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      expect(game.menu.items.look, Look.defaults);
      expect(game.menu.items.ownedCount, 3);
      expect(game.menu.items.hasNewBadge, isTrue);
    },
  );

  withGame.testGameWidget(
    'debug ALL ITEMS grants the catalogue and persists it',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.openDebugPanel();
      await flushAndMount(game);
      final panel = game.world.children.query<DebugPanel>().single;
      final action = panel.actions
          .firstWhere((a) => a.label().startsWith('ALL ITEMS'));
      await action.run();
      await flushAndMount(game);

      expect(game.menu.items.ownedCount, kCollectibleTotal);
      final storage = GameStorage();
      await storage.load();
      expect(storage.ownedItems.length, allItems.length);
    },
  );
}
