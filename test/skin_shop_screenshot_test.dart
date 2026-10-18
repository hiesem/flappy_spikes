import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts;

/// Renders the skin shop to `build/menu_shots/skinshop_*.png` (1080 wide,
/// 3.375 x) for comparison with the approved mock captures
/// `design/menu_v2/skinshop_*.png` (PRD-menu-v2 §4): birds tab, a locked
/// hat tried on, the hoops tab, a locked trail (Afterimage) tried on and a
/// legendary purchase mid-celebration.
///
/// Mock state (`skin_shop.js` START_OWNED / START_NEW): 3 250 coins, 15
/// owned items, NEW tags on the update's items only.
const Map<String, Object> skinShopMockPrefs = {
  'bestScore': 12,
  'gamesPlayed': 34,
  'claimedLevels': ['1'], // no LEVEL UP popup over the captures
  'coins': 3250,
  'ownedItems': [
    'bird:sky',
    'bird:lime',
    'bird:grape',
    'bird:robin',
    'gear:shades',
    'gear:bowtie',
    'hat:cap',
    'hat:party',
    'hat:tophat',
    'hoop:sky',
    'trail:blue',
    'trail:sparkle',
  ],
};

Map<String, Object> mockPrefs([Map<String, Object> extra = const {}]) => {
  ...skinShopMockPrefs,
  'seenItems': [
    for (final item in allItems)
      if (!kNewInUpdate.contains(item.key)) item.key,
  ],
  ...extra,
};

const double shotScale = 1080 / 320;

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  void shot(
    String name, {
    Map<String, Object> prefs = const {},
    required Future<void> Function(FlappySpikesGame game) act,
  }) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(mockPrefs(prefs), 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'skin shop screenshot: $name',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        game.openSkins();
        await flushAndMount(game);
        stepGame(game, Config.uiFadeDuration + 0.1);
        await flushAndMount(game);
        expect(game.skinShop, isNotNull);
        await act(game);
        await flushAndMount(game);
        await tester.runAsync(
          () => captureShot(game, shotScale, 'skinshop_$name'),
        );
      },
    );
  }

  // Birds tab at the start: a hoop pass, the trail drawn as always.
  shot('birds', act: (game) async => stepGame(game, 1.15));

  // A locked legendary hat tried on, grid scrolled to the bottom.
  shot(
    'tryon',
    act: (game) async {
      game.selectSkinTab(SkinLayer.hat);
      stepGame(game, 0.5);
      game.tapItem(SkinLayer.hat, 'crown');
      final scroll = game.skinShop!.scroll;
      scroll.offset = scroll.maxOffset;
      stepGame(game, 1.2);
    },
  );

  // Hoops tab, crown equipped.
  shot(
    'hoops',
    prefs: {
      'ownedItems': [
        ...skinShopMockPrefs['ownedItems']! as List<String>,
        'hat:crown',
      ],
      'equippedItem.hat': 'crown',
    },
    act: (game) async {
      game.selectSkinTab(SkinLayer.hoop);
      stepGame(game, 2.4);
    },
  );

  // Trails tab with the Afterimage tried on.
  shot(
    'trails',
    prefs: {
      'ownedItems': [
        ...skinShopMockPrefs['ownedItems']! as List<String>,
        'hat:crown',
      ],
      'equippedItem.hat': 'crown',
    },
    act: (game) async {
      game.selectSkinTab(SkinLayer.trail);
      stepGame(game, 0.5);
      game.tapItem(SkinLayer.trail, 'echo');
      final scroll = game.skinShop!.scroll;
      scroll.offset = scroll.maxOffset;
      stepGame(game, 1.6);
    },
  );

  // Legendary bought: banner, rays, confetti (0.45 s in).
  shot(
    'buy',
    prefs: {'coins': 5765},
    act: (game) async {
      game.selectSkinTab(SkinLayer.hat);
      stepGame(game, 0.5);
      game.tapItem(SkinLayer.hat, 'crown');
      stepGame(game, 0.3);
      await game.buyTriedOnItem();
      await flushAndMount(game);
      stepGame(game, 0.45);
      expect(game.menu.items.look.hat, 'crown');
    },
  );

  // WP-J2: the Rubber duck tried on from its tile — the price pill became
  // the pulsing BUY pill (mid-pulse); the tile below shows a grey one.
  shot(
    'tile_buy',
    prefs: {'coins': 1000},
    act: (game) async {
      game.tapItem(SkinLayer.bird, 'duck', fromTile: true);
      game.skinShop!.scrollToItem('duck');
      stepGame(game, 0.5);
      expect(game.skinShop!.tileFor('duck').showsBuyPill, isTrue);
    },
  );

  shot(
    'tile_buy_poor',
    prefs: {'coins': 100},
    act: (game) async {
      game.tapItem(SkinLayer.bird, 'duck', fromTile: true);
      game.skinShop!.scrollToItem('duck');
      stepGame(game, 0.5);
      expect(game.skinShop!.tileFor('duck').current.affordable, isFalse);
    },
  );
}
