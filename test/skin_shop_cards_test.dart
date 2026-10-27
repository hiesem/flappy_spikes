import 'dart:ui';

import 'package:flappy_spikes/components/skins/shop_widgets.dart';
import 'package:flappy_spikes/components/skins/item_tile.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'shop_flow_test.dart' show shopTest;
import 'skin_shop_flow_test.dart' show openSkinShop;

Future<List<int>> tilePixels(ItemTile tile) async {
  final recorder = PictureRecorder();
  tile.render(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(92, 92);
  final bytes = await image.toByteData();
  final result = bytes!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  for (final height in [568.0, 711.0]) {
    shopTest(
      'F9e six fixed tabs and three card kinds at $height',
      height: height,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openSkinShop(game, layer: SkinLayer.card);
        expect(shop.tabBar.tabs, hasLength(6)); // PRD:834
        expect(shop.tabBar.tabFor(SkinLayer.card).countText, '0/60');
        expect(shop.bar.total, 208);
        final fixed = [
          shop.bar.position.clone(),
          shop.stage.position.clone(),
          shop.tabBar.position.clone(),
        ];
        for (final kind in CardKind.values) {
          shop.selectCardKind(kind);
          await flushAndMount(game);
          stepGame(game, .5);
          expect(shop.cardCounter(kind), '0/20');
          expect(shop.tiles, hasLength(21)); // free none + 17 sold + 3 skill
          expect(shop.tiles.first.item.id, '');
          expect(shop.tiles.skip(18).every((t) => t.item.isSkillOnly), isTrue);
          expect(shop.scroll.viewport.top, 360);
          expect(shop.scroll.viewport.bottom, height - 44);
          shop.scroll.offset = shop.scroll.maxOffset;
          expect(
            shop.scroll.screenY(shop.tiles.last.toRect().bottom),
            height - 74,
          );
          expect(shop.bar.position, fixed[0]);
          expect(shop.stage.position, fixed[1]);
          expect(shop.tabBar.position, fixed[2]);
          final count = shop.cardArt.pictureCount;
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          for (var i = 0; i < 4; i++) {
            game.update(.1);
            shop.renderTree(canvas);
          }
          recorder.endRecording().dispose();
          expect(
            shop.cardArt.pictureCount,
            count,
            reason: 'rendering must replay cached card animation pictures',
          );
          shop.selectTab(SkinLayer.bird);
          await flushAndMount(game);
          expect(shop.scroll.viewport.top, 326);
          expect(shop.tiles, hasLength(30));
          shop.selectTab(SkinLayer.card);
          await flushAndMount(game);
        }
      },
    );
  }

  shopTest(
    'F9e try, buy, equip, clear preserve the other card slots',
    prefs: const {'coins': 12000},
    verify: (game, spy, ads, iap, tester) async {
      final sounds = <Sfx>[];
      final shop = await openSkinShop(
        game,
        layer: SkinLayer.card,
        sounds: sounds,
      );
      for (final kind in CardKind.values) {
        shop.selectCardKind(kind);
        await flushAndMount(game);
        final item = cardItemsFor(kind).first;
        game.tapItem(SkinLayer.card, item.id);
        game.update(0);
        expect(shop.tryOnItem, item);
        expect(shop.previewLook.cardIdFor(kind), item.id);
        expect(shop.actionButton.shownKind, ShopActionKind.buy);
        await game.buyTriedOnItem();
        game.update(0);
        expect(game.menu.items.look.cardIdFor(kind), item.id);
        expect(sounds, contains(Sfx.skBuyCommon));
        expect(shop.actionButton.shownKind, ShopActionKind.equipped);
      }
      expect(game.menu.wallet.balance, 11250);
      expect(game.menu.items.look.card, 'f_bubblegum|n_tangerine|s_gg');
      shop.selectCardKind(CardKind.name);
      await flushAndMount(game);
      shop.tiles.first.onPressed();
      await flushAndMount(game);
      game.update(0);
      expect(game.menu.items.look.card, 'f_bubblegum||s_gg');
      expect(shop.actionButton.shownKind, ShopActionKind.nothingOn);
      game.tapItem(SkinLayer.card, 'n_tangerine');
      await flushAndMount(game);
      expect(sounds, contains(Sfx.skEquip));
      expect(game.menu.items.look.card, 'f_bubblegum|n_tangerine|s_gg');
      expect(shop.cardCounter(CardKind.name), '1/20');
      expect(shop.tabBar.tabFor(SkinLayer.card).countText, '3/60');
    },
  );

  shopTest(
    'F9e gold skill tiles cannot offer or spend coins',
    prefs: const {'coins': 10000},
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openSkinShop(game, layer: SkinLayer.card);
      for (final kind in CardKind.values) {
        shop.selectCardKind(kind);
        await flushAndMount(game);
        final tile = shop.tiles.last;
        tile.onPressed();
        game.update(0);
        expect(shop.tryOnId, tile.item.id);
        expect(tile.showsBuyPill, isFalse);
        expect(shop.actionButton.shownKind, ShopActionKind.skillOnly);
        await game.buyTriedOnItem();
        expect(game.menu.wallet.balance, 10000);
        expect(game.menu.items.isOwned(SkinLayer.card, tile.item.id), isFalse);
      }
    },
  );
  shopTest(
    'F9e reduced motion paints card names at the static frame',
    verify: (game, spy, ads, iap, tester) async {
      game.reduceMotionOverride = true;
      final shop = await openSkinShop(game, layer: SkinLayer.card);
      shop.selectCardKind(CardKind.name);
      await flushAndMount(game);
      final tile = shop.tileFor('n_fire');
      final first = await tester.runAsync(() => tilePixels(tile));
      stepGame(game, 1.3);
      expect(await tester.runAsync(() => tilePixels(tile)), first);
      final count = shop.cardArt.pictureCount;
      shop.scroll.offset = shop.scroll.maxOffset;
      stepGame(game, 1.3);
      expect(await tester.runAsync(() => tilePixels(tile)), first);
      expect(shop.cardArt.pictureCount, count);
    },
  );
}
