import 'dart:ui';

import 'package:flappy_spikes/components/skins/shop_widgets.dart';
import 'package:flappy_spikes/components/skins/item_tile.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/components/skins/preview_stage.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'shop_flow_test.dart' show shopTest;
import 'skin_shop_flow_test.dart' show openSkinShop;

Future<List<int>> paintPixels(
  void Function(Canvas) paint,
  int width,
  int height,
) async {
  final recorder = PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData();
  final result = bytes!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return result;
}

Future<List<int>> tilePixels(ItemTile tile) => paintPixels(tile.render, 92, 92);

void main() {
  test(
    'F9e animated sticker classification includes common and rare motion',
    () {
      for (final id in [
        's_heart',
        's_kaching',
        's_spiked',
        's_nailed',
        's_bye',
      ]) {
        expect(ShopCardArt.animated(cardItemById(id)!), isTrue, reason: id);
      }
      for (final id in ['s_gg', 's_thumbs', 's_wow', 's_pow']) {
        expect(ShopCardArt.animated(cardItemById(id)!), isFalse, reason: id);
      }
    },
  );

  for (final height in [568.0, 711.0]) {
    shopTest(
      'F9e six fixed tabs and three card kinds at $height',
      height: height,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openSkinShop(game, layer: SkinLayer.card);
        expect(shop.tabBar.tabs, hasLength(6)); // PRD:834
        expect(shop.tabBar.tabFor(SkinLayer.card).countText, '0/60');
        expect(shop.bar.total, 208);
        expect(
          shop.cardArt.pictureCount,
          lessThanOrEqualTo(23),
          reason: 'one static picture per item, never an eager animation atlas',
        );
        final fixed = [
          shop.bar.position.clone(),
          shop.stage.position.clone(),
          shop.tabBar.position.clone(),
        ];
        for (final kind in CardKind.values) {
          final beforeSwitch = shop.cardArt.pictureCount;
          shop.selectCardKind(kind);
          await flushAndMount(game);
          expect(
            shop.cardArt.pictureCount - beforeSwitch,
            lessThanOrEqualTo(20),
          );
          expect(shop.cardArt.pictureCount, lessThanOrEqualTo(63));
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
            reason: 'animation sampling must not grow the static/t=0 cache',
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
      expect(spy.last('item_equip'), {'layer': 'card', 'id': ''});
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
  for (final (id, rarity) in [
    ('f_tape', Rarity.common),
    ('f_neon', Rarity.epic),
  ]) {
    shopTest(
      'F9e $rarity purchase visibly celebrates on CARDS',
      prefs: const {'coins': 10000},
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openSkinShop(game, layer: SkinLayer.card);
        expect(shop.cardArt.paintRays, isNotNull);
        final before = (await tester.runAsync(
          () => paintPixels(shop.stage.render, 292, 138),
        ))!;
        game.tapItem(SkinLayer.card, id);
        await game.buyTriedOnItem();
        // Freeze card art so outside-card differences are purchase effects.
        game.reduceMotionOverride = true;
        stepGame(game, .3);
        expect(shop.stage.rays, rarity == Rarity.epic ? greaterThan(0) : 0);
        final after = (await tester.runAsync(
          () => paintPixels(shop.stage.render, 292, 138),
        ))!;
        var changed = 0;
        for (var y = 0; y < 138; y++) {
          for (var x = 0; x < 292; x++) {
            if (x >= 20 && x < 272 && y >= 30 && y < 105) continue;
            final i = (y * 292 + x) * 4;
            if (before[i] != after[i] ||
                before[i + 1] != after[i + 1] ||
                before[i + 2] != after[i + 2]) {
              changed++;
            }
          }
        }
        expect(
          changed,
          greaterThan(20),
          reason:
              'purchase confetti / R4 rays must be visible outside the card',
        );
      },
    );
  }

  shopTest(
    'F9e sticker rays use the R4 adapter at unmodified game time',
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openSkinShop(game, layer: SkinLayer.card);
      final times = <double>[];
      final art = ShopCardArt(
        coin: shop.cardArt.coin,
        look: shop.cardArt.look,
        paintRays: (canvas, centre, radius, t) {
          times.add(t);
          PreviewStage.paintRays(canvas, centre, radius, t);
        },
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      for (final id in ['s_champ', 's_flawless', 's_topflock']) {
        final item = cardItemById(id)!;
        art.prepare(item);
        times.clear();
        art.paint(canvas, item, .125);
        art.paint(canvas, item, 6.125);
        expect(
          times,
          [.125, 6.125],
          reason:
              'animation time must not wrap at six seconds or quantize to 12 fps',
        );
      }
      expect(art.pictureCount, 3);
      recorder.endRecording().dispose();
      art.dispose();
    },
  );
  shopTest(
    'F9e NAMES grid records at 30 Hz and releases off-screen samples',
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openSkinShop(game, layer: SkinLayer.card);
      shop.selectCardKind(CardKind.name);
      await flushAndMount(game);
      stepGame(game, .6);
      shop.scroll.offset = shop.scroll.maxOffset;
      game.update(0);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      shop.renderTree(canvas);
      final art = shop.cardArt;
      expect(
        art.animationPictureCount,
        9,
        reason: 'the last three rows expose all nine animated name styles',
      );
      final warm = art.animationRecordings;
      for (var i = 0; i < 3; i++) {
        game.update(1 / 120);
        shop.renderTree(canvas);
        expect(
          art.animationRecordings,
          warm,
          reason: 'sub-frame renders must replay pictures without text layouts',
        );
      }
      game.update(1 / 120);
      shop.renderTree(canvas);
      expect(art.animationRecordings - warm, 9);
      final begin = art.animationRecordings;
      for (var i = 0; i < 120; i++) {
        game.update(1 / 120);
        shop.renderTree(canvas);
      }
      expect(
        art.animationRecordings - begin,
        9 * 30,
        reason: '120 frames must not rebuild each name layout 120 times',
      );
      expect(
        art.animationPictureCount,
        9,
        reason: 'only the latest sample is retained, never an atlas',
      );
      // Frozen game time never incurs another layout.
      final frozen = art.animationRecordings;
      shop.renderTree(canvas);
      shop.renderTree(canvas);
      expect(art.animationRecordings, frozen);
      shop.scroll.offset = 0;
      game.update(0);
      expect(art.animationPictureCount, 0);
      shop.scroll.offset = shop.scroll.maxOffset;
      game.update(0);
      shop.renderTree(canvas);
      expect(art.animationPictureCount, 9);
      game.reduceMotionOverride = true;
      game.update(0);
      shop.renderTree(canvas);
      expect(art.animationPictureCount, 0);
      game.reduceMotionOverride = false;
      game.update(.1);
      shop.renderTree(canvas);
      shop.selectCardKind(CardKind.frame);
      await flushAndMount(game);
      expect(
        art.animationPictureCount,
        0,
        reason: 'removed tiles must release their current animation pictures',
      );
      recorder.endRecording().dispose();
    },
  );

  shopTest(
    'F9e preview and tile text samples do not evict each other',
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openSkinShop(game, layer: SkinLayer.card);
      final art = ShopCardArt(
        coin: shop.cardArt.coin,
        look: shop.cardArt.look,
        paintRays: PreviewStage.paintRays,
      );
      final tile = Object(), preview = Object();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      // Names and every animated sticker containing a label use this cache.
      for (final id in ['n_fire', 's_kaching', 's_champ', 's_topflock']) {
        final item = cardItemById(id)!;
        art.prepare(item);
        final before = art.animationRecordings;
        art.paint(canvas, item, 1, owner: tile);
        art.paint(canvas, item, 3, owner: preview);
        art.paint(canvas, item, 1.01, owner: tile);
        art.paint(canvas, item, 3.01, owner: preview);
        expect(art.animationRecordings - before, 2);
        expect(art.animationPictureCount, 2);
        art.releaseAnimation(tile);
        expect(art.animationPictureCount, 1);
        art.releaseAnimation(preview);
        expect(art.animationPictureCount, 0);
      }
      recorder.endRecording().dispose();
      art.dispose();
    },
  );

  shopTest(
    'F9e CARDS rays stay centred on the card during a hop',
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openSkinShop(game, layer: SkinLayer.card);
      final centre = Config.skinShopCardPreviewRect.center;
      expect(shop.stage.celebrationCentre, centre);
      shop.stage.celebrate(Rarity.epic);
      stepGame(game, .12);
      expect(shop.stage.rays, greaterThan(0));
      expect(shop.stage.celebrationCentre, centre);
      stepGame(game, .12);
      expect(shop.stage.celebrationCentre, centre);
      shop.selectTab(SkinLayer.bird);
      await flushAndMount(game);
      expect(
        shop.stage.celebrationCentre.dx,
        shop.stage.birdX,
        reason: 'wardrobe previews retain the original bird-centred R4 rays',
      );
    },
  );
}
