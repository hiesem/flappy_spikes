import 'package:flame/components.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/skins/skins_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/skin_catalog.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart' hide escape;

import 'helpers.dart';
import 'shop_flow_test.dart' show escape, openShop, settle, shopTest, toastText;

/// Opens the Skins screen (home tile) and lets the fades finish.
Future<SkinsScreen> openSkins(FlappySpikesGame game) async {
  game.openSkins();
  await flushAndMount(game);
  stepGame(game, 0.6);
  await flushAndMount(game);
  return game.skinsScreen!;
}

/// Lets a dialog / screen fade finish.
Future<void> fade(FlappySpikesGame game) async {
  await flushAndMount(game);
  stepGame(game, 0.6);
  await flushAndMount(game);
}

void main() {
  group('Skins layout', () {
    shopTest(
      'K1 grid rects at 711: 3 x 92 x 106, 8 pt gaps, all 12 fit',
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        expect(game.menuScene, MenuScene.skins);
        expect(game.homeScreen, isNull);
        expect(screen.titleText.text, 'SKINS');
        expect(
          screen.tiles.map((t) => t.skin.id).toList(),
          kSkins.map((s) => s.id).toList(),
        );
        for (final (i, tile) in screen.tiles.indexed) {
          expect(
            tile.toRect(),
            Rect.fromLTWH(
              14.0 + (i % 3) * 100,
              150.0 + (i ~/ 3) * 114,
              92,
              106,
            ),
          );
        }
        expect(screen.tiles.last.toRect().right, 306);
        expect(screen.tiles.last.toRect().bottom, 598);
        expect(screen.scroll.scrollable, isFalse);
        expect(
          screen.tiles.last.toRect().bottom,
          lessThanOrEqualTo(screen.scroll.viewport.bottom),
        );
        // Preview centred on the tile (48 x 52).
        final preview = screen.tiles.first.previewIcon;
        expect(preview.size, Vector2(48, 52));
        expect(preview.position, Vector2(46, Config.skinPreviewCenterY));
      },
    );

    shopTest(
      'at 568 the grid drag-scrolls; the last row is reachable and tappable',
      height: 568,
      exactSurface: true,
      prefs: const {'coins': 50},
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        final scroll = screen.scroll;
        expect(scroll.viewport.bottom, 568 - 44);
        expect(scroll.scrollable, isTrue);
        expect(scroll.maxOffset, 606 - 524);
        await tester.timedDragFrom(
          const Offset(160, 450),
          const Offset(0, -150),
          const Duration(milliseconds: 300),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(scroll.offset, scroll.maxOffset);
        final ghost = screen.tileFor('ghost').toRect();
        expect(
          scroll.screenY(ghost.bottom),
          lessThanOrEqualTo(scroll.viewport.bottom),
        );
        await tester.tapAt(
          Offset(ghost.center.dx, scroll.screenY(ghost.center.dy)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(game.skinDialog?.skin.id, 'ghost');
        expect(game.state, GameState.start);
      },
    );
  });

  group('Skins tile states', () {
    shopTest(
      'equipped / owned / locked / NEW flags and decorations',
      prefs: const {
        'coins': 250,
        'ownedSkins': ['pink', 'blue'],
        'equippedSkin': 'blue',
      },
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        final blue = screen.tileFor('blue');
        expect(blue.equipped, isTrue);
        expect(blue.outline.isVisible, isTrue);
        expect(blue.checkBadge.isVisible, isTrue);
        expect(blue.checkBadge.toRect(), const Rect.fromLTWH(70, 84, 22, 22));
        expect(blue.lockIcon.isVisible, isFalse);
        expect(blue.pricePill.isVisible, isFalse);
        expect(blue.previewIcon.sprite, same(blue.preview));

        final pink = screen.tileFor('pink');
        expect(pink.owned, isTrue);
        expect(pink.equipped, isFalse);
        expect(pink.outline.isVisible, isFalse);
        expect(pink.checkBadge.isVisible, isFalse);
        expect(pink.lockIcon.isVisible, isFalse);
        expect(pink.newTag, isNull);

        final green = screen.tileFor('green');
        expect(green.locked, isTrue);
        expect(green.lockIcon.isVisible, isTrue);
        expect(green.lockIcon.position, Vector2(6, 8));
        expect(green.pricePill.isVisible, isTrue);
        expect(green.priceLabel.text, '150');
        expect(green.pricePill.toRect().bottom, 106 - 6);
        expect(green.pricePill.center.x, closeTo(46, 1e-9));
        expect(green.previewIcon.sprite, same(green.previewLocked));
        expect(green.outline.isVisible, isFalse);

        // NEW = affordable and unseen when the screen opened.
        expect(
          [
            for (final t in screen.tiles)
              if (t.isNew) t.skin.id,
          ],
          ['green', 'purple'],
        );
        final tag = screen.tileFor('green').newTag!;
        expect(tag.toRect().right, 92 + 4);
        expect(tag.toRect().top, -6);
      },
    );
  });

  group('Skins actions', () {
    shopTest(
      'tap owned equips at once: outline moves, home + run bird follow',
      prefs: const {
        'ownedSkins': ['pink', 'blue'],
      },
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        screen.tileFor('blue').onPressed();
        await settle(game);
        expect(game.menu.skins.equipped, 'blue');
        expect(spy.last('skin_equip'), {'skin': 'blue'});
        expect(game.skinDialog, isNull);
        expect(screen.tileFor('blue').equipped, isTrue);
        expect(screen.tileFor('pink').equipped, isFalse);
        expect(screen.tileFor('pink').outline.isVisible, isFalse);
        expect(game.world.children.query<Bird>().single.skin.id, 'blue');

        // Re-tapping the equipped skin logs nothing new.
        screen.tileFor('blue').onPressed();
        await settle(game);
        expect(spy.count('skin_equip'), 1);

        screen.backButton.onPressed();
        await settle(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.homeScreen!.bird.sprites.skin.id, 'blue');
      },
    );

    shopTest(
      'tap locked + enough coins: dialog, purchase, equipped, toast',
      prefs: const {'coins': 1250},
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        screen.tileFor('purple').onPressed();
        await fade(game);
        final dialog = game.skinDialog!;
        expect(dialog.skin.id, 'purple');
        expect(dialog.insufficient, isFalse);
        expect(dialog.titleText.text, 'UNLOCK GRAPE?');
        expect(dialog.confirmLabel.text, '200');
        expect(dialog.messageText, isNull);
        expect(game.menu.skins.isOwned('purple'), isFalse);

        // Taps on the screen behind are blocked (the dialog is on top).
        game.tapSkin('blue');
        expect(game.skinDialog, same(dialog));

        dialog.confirmButton.onPressed();
        await settle(game);
        expect(game.skinDialog, isNull);
        expect(game.menu.skins.isOwned('purple'), isTrue);
        expect(game.menu.skins.equipped, 'purple');
        expect(game.menu.wallet.balance, 1050);
        expect(spy.last('skin_purchase'), {'skin': 'purple', 'price': 200});
        expect(toastText(game), 'Grape unlocked!');
        game.update(0);
        expect(screen.tileFor('purple').equipped, isTrue);
        expect(screen.tileFor('purple').lockIcon.isVisible, isFalse);
        expect(screen.tileFor('pink').equipped, isFalse);
        expect(game.menuScene, MenuScene.skins);
      },
    );

    shopTest(
      'not enough coins: NOT ENOUGH COINS / GET COINS -> Shop at the packs; '
      'back returns to Skins, then home',
      prefs: const {'coins': 100},
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        screen.tileFor('crown').onPressed();
        await fade(game);
        final dialog = game.skinDialog!;
        expect(dialog.insufficient, isTrue);
        expect(dialog.titleText.text, 'NOT ENOUGH COINS');
        expect(dialog.messageText!.text, 'You need 900 more');
        expect(dialog.confirmLabel.text, 'GET COINS');

        dialog.confirmButton.onPressed();
        await fade(game);
        expect(game.skinDialog, isNull);
        expect(game.skinsScreen, isNull);
        expect(game.menu.skins.isOwned('crown'), isFalse);
        expect(game.menu.wallet.balance, 100);
        final shop = game.shopScreen!;
        expect(game.menuScene, MenuScene.shop);
        expect(spy.last('shop_open'), {'source': 'skins_dialog'});
        expect(
          shop.scroll.offset,
          (Config.shopCoinsAnchorFor(711) - shop.scroll.viewport.top).clamp(
            0.0,
            shop.scroll.maxOffset,
          ),
        );

        shop.backButton.onPressed();
        await fade(game);
        expect(game.menuScene, MenuScene.skins);
        expect(game.skinsScreen, isNotNull);
        expect(game.homeScreen, isNull);
        expect(game.world.children.query<SkinsScreen>(), hasLength(1));

        game.skinsScreen!.backButton.onPressed();
        await fade(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.homeScreen, isNotNull);
        expect(game.world.children.query<SkinsScreen>(), isEmpty);
      },
    );

    shopTest(
      'the dialog follows the balance live',
      prefs: const {'coins': 100},
      verify: (game, spy, ads, iap, tester) async {
        await openSkins(game);
        game.tapSkin('purple');
        await fade(game);
        final dialog = game.skinDialog!;
        expect(dialog.insufficient, isTrue);
        expect(dialog.messageText!.text, 'You need 100 more');
        await game.storage.saveCoins(150);
        game.update(0);
        await flushAndMount(game);
        expect(dialog.messageText!.text, 'You need 50 more');
        await game.storage.saveCoins(200);
        game.update(0);
        await flushAndMount(game);
        expect(dialog.insufficient, isFalse);
        expect(dialog.confirmLabel.text, '200');
      },
    );

    shopTest(
      'Esc closes the dialog first, then the screen; CANCEL closes it too',
      prefs: const {'coins': 100},
      verify: (game, spy, ads, iap, tester) async {
        await openSkins(game);
        game.tapSkin('green');
        await fade(game);
        expect(game.skinDialog, isNotNull);
        game.onKeyEvent(escape(), {});
        await fade(game);
        expect(game.skinDialog, isNull);
        expect(game.menuScene, MenuScene.skins);

        game.tapSkin('green');
        await fade(game);
        game.skinDialog!.cancelButton.onPressed();
        await fade(game);
        expect(game.skinDialog, isNull);
        expect(game.menu.skins.isOwned('green'), isFalse);

        game.onKeyEvent(escape(), {});
        await fade(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.homeScreen, isNotNull);
        expect(game.skinsScreen, isNull);
        // Space does not start a run from Skins (now home: it does).
        expect(game.state, GameState.start);
      },
    );

    shopTest(
      'coin pill "+" in Skins opens the Shop at the packs',
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkins(game);
        game.onScreenTap();
        expect(game.state, GameState.start, reason: 'no run from Skins');
        screen.coinPill.onPressed();
        await fade(game);
        expect(game.menuScene, MenuScene.shop);
        expect(spy.last('shop_open'), {'source': 'pill'});
      },
    );
  });

  group('NEW badge lifecycle', () {
    shopTest(
      'NEW tags show on the first visit only; the home badge clears',
      prefs: const {'coins': 150},
      verify: (game, spy, ads, iap, tester) async {
        expect(game.homeScreen!.skinsTile.tag, 'NEW');
        var screen = await openSkins(game);
        expect(spy.last('skins_open'), {'source': 'tile'});
        expect(
          [
            for (final t in screen.tiles)
              if (t.isNew) t.skin.id,
          ],
          ['blue', 'green'],
        );
        await settle(game);
        expect(game.menu.skins.hasNewBadge, isFalse);
        // Tags stay for this visit.
        expect(screen.tileFor('blue').newTag, isNotNull);

        screen.backButton.onPressed();
        await fade(game);
        expect(game.homeScreen!.skinsTile.tag, isNull);

        screen = await openSkins(game);
        expect(screen.tiles.where((t) => t.isNew), isEmpty);
      },
    );
  });

  group('featured skin from the Shop', () {
    shopTest(
      'featured row opens Skins with the unlock dialog; back returns to '
      'the Shop',
      prefs: const {
        'coins': 1250,
        'ownedSkins': ['pink', 'blue', 'green'],
      },
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        expect(shop.featured.skin?.id, 'purple');
        shop.featured.onPressed();
        await fade(game);
        expect(game.shopScreen, isNull);
        expect(game.menuScene, MenuScene.skins);
        expect(spy.last('skins_open'), {'source': 'shop_featured'});
        final dialog = game.skinDialog!;
        expect(dialog.skin.id, 'purple');
        expect(dialog.insufficient, isFalse);

        game.onKeyEvent(escape(), {}); // dialog
        await fade(game);
        expect(game.skinDialog, isNull);
        expect(game.menuScene, MenuScene.skins);
        game.onKeyEvent(escape(), {}); // Skins -> Shop
        await fade(game);
        expect(game.menuScene, MenuScene.shop);
        expect(game.shopScreen, isNotNull);
        game.onKeyEvent(escape(), {}); // Shop -> home
        await fade(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.homeScreen, isNotNull);
      },
    );

    shopTest(
      'featured skin at 568 scrolls its tile into view',
      height: 568,
      prefs: const {
        'coins': 2000,
        'ownedSkins': [
          'pink',
          'blue',
          'green',
          'purple',
          'grey',
          'sand',
          'crown',
          'tophat',
          'sunglasses',
          'headband',
          'partyhat',
        ],
      },
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        expect(shop.featured.skin?.id, 'ghost');
        shop.featured.onPressed();
        await fade(game);
        final screen = game.skinsScreen!;
        expect(game.skinDialog?.skin.id, 'ghost');
        final ghost = screen.tileFor('ghost').toRect();
        expect(
          screen.scroll.screenY(ghost.bottom),
          lessThanOrEqualTo(screen.scroll.viewport.bottom),
        );
        expect(
          screen.scroll.screenY(ghost.top),
          greaterThanOrEqualTo(screen.scroll.viewport.top),
        );
      },
    );
  });
}
