// PRD 2.6 F10 (853, O81): collection includes 24 skill items; PROUD PEACOCK counts the 199 sold collectibles.
import 'package:flame/components.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/skins/shop_widgets.dart';
import 'package:flappy_spikes/components/skins/skin_shop_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart' hide escape;

import 'helpers.dart';
import 'shop_flow_test.dart' show escape, openShop, shopTest;

/// Opens the skin shop from home and lets the fades finish; records every
/// requested sound into [sounds].
Future<SkinShopScreen> openSkinShop(
  FlappySpikesGame game, {
  List<Sfx>? sounds,
  SkinLayer? layer,
  String? tryOnId,
}) async {
  if (sounds != null) game.sound.onPlay = sounds.add;
  game.openSkins(layer: layer, tryOnId: tryOnId);
  await flushAndMount(game);
  stepGame(game, 0.6);
  await flushAndMount(game);
  return game.skinShop!;
}

/// Every collectible owned except the ones listed (for affordability /
/// counter tests) — plus [coins].
Map<String, Object> prefsWith({
  int coins = 0,
  List<String> owned = const [],
  List<String> seen = const [],
}) => {'coins': coins, 'ownedItems': owned, 'seenItems': seen};

/// Seen-list that silences every NEW tag.
final List<String> allSeen = [for (final item in allItems) item.key];

void main() {
  group('Skin shop layout (PRD-menu-v2 §4.1)', () {
    shopTest(
      'at 711: bar, stage, tabs and the 3 x 92 grid down to 667',
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(game);
        expect(game.menuScene, MenuScene.skins);
        expect(game.homeScreen, isNull);
        // No title on this screen.
        expect(screen.titleText.isMounted, isFalse);
        expect(screen.bar.toRect(), const Rect.fromLTWH(70, 100, 180, 18));
        expect(screen.stage.toRect(), const Rect.fromLTWH(14, 126, 292, 138));
        expect(screen.tabBar.toRect(), const Rect.fromLTWH(14, 270, 292, 52));
        expect(screen.scroll.viewport, const Rect.fromLTRB(14, 326, 306, 667));
        expect(screen.nameRow.position, Vector2(22, 133));
        final action = screen.actionButton.toRect();
        expect(action.bottomRight, const Offset(298, 256));
        expect(action.height, 30);
        expect(screen.tiles, hasLength(33));
        // PRD-2.6 F10, lines 845–853 / O88: the three skill items
        // occupy a separate final row below the section header.
        for (final (i, tile) in screen.tiles.indexed) {
          expect(
            tile.toRect(),
            Rect.fromLTWH(14.0 + (i % 3) * 100,
                332.0 + (i ~/ 3) * 100 + (i >= 30 ? 28 : 0), 92, 92),
          );
        }
        expect(screen.skillSectionHeader!.text, 'EARNED BY SKILL · NOT SOLD');
        expect(screen.skillSectionHeader!.position.y, 332 + 10 * 100 + 28 - 22);
        // 6 pt top / 30 pt bottom padding, including the skill gap.
        expect(screen.scroll.contentBottom, 332 + 10 * 100 + 28 + 92 + 30);
        expect(screen.scroll.scrollable, isTrue);
      },
    );

    for (final height in [568.0, 711.0]) {
      shopTest(
        'at ${height.toInt()}: the grid bottom follows the view height, '
        'tiles never overlap the tab bar',
        height: height,
        verify: (game, spy, ads, iap, tester) async {
          final screen = await openSkinShop(game);
          final scroll = screen.scroll;
          expect(scroll.viewport.top, 326);
          expect(scroll.viewport.bottom, height - 44);
          expect(Config.skinShopGridBottomFor(height), height - 44);
          final tabBottom = screen.tabBar.toRect().bottom;
          // PRD:834 adds CARDS; these journeys cover the five wardrobe tabs.
          for (final layer in kShopLayers.where((l) => l != SkinLayer.card)) {
            game.selectSkinTab(layer);
            stepGame(game, 0.5);
            await flushAndMount(game);
            expect(screen.tiles, hasLength(itemsFor(layer).length));
            for (final tile in screen.tiles) {
              expect(tile.toRect().top, greaterThan(tabBottom));
            }
            // Scrolled to the end, the last row sits 30 pt above the
            // viewport bottom and still below the tab bar.
            scroll.offset = scroll.maxOffset;
            final last = screen.tiles.last.toRect();
            expect(
              scroll.screenY(last.bottom),
              closeTo(scroll.viewport.bottom - 30, 1e-9),
            );
            scroll.offset = 0;
          }
        },
      );
    }
  });

  group('Skin shop flows', () {
    shopTest(
      'opens from home on the Birds tab: Classic equipped, NEW snapshot',
      prefs: prefsWith(coins: 200),
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(game);
        expect(spy.last('skins_open'), {'source': 'tile'});
        expect(screen.tab, SkinLayer.bird);
        game.update(0);
        expect(screen.nameRow.nameText, 'Classic');
        expect(screen.nameRow.chipText, 'COMMON');
        expect(screen.actionButton.shownKind, ShopActionKind.equipped);
        expect(screen.actionButton.label, 'EQUIPPED');
        final classic = screen.tileFor('classic').current;
        expect(classic.equipped, isTrue);
        expect(classic.owned, isTrue);
        expect(screen.tileFor('classic').animatesArt, isTrue); // flaps
        // Affordable + unseen, and the update's items, are NEW.
        expect(screen.tileFor('sky').current.isNew, isTrue);
        // PRD-2.3 §19.3: the 2.0 update items follow the normal rule now.
        expect(screen.tileFor('ghost').current.isNew, isFalse);
        expect(screen.tileFor('robin').current.isNew, isFalse);
        expect(screen.bar.labelText, '3 / 223'); // the free defaults
        expect(screen.tabBar.tabFor(SkinLayer.bird).countText, '1/33');
        // Static art is drawn once (cached pictures).
        expect(screen.tileFor('sky').animatesArt, isFalse);
        expect(screen.tileFor('robo').animatesArt, isTrue);
      },
    );

    shopTest(
      'tab switch: sk_tab, analytics, try-on cleared, staggered entrance',
      prefs: prefsWith(seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final sounds = <Sfx>[];
        final screen = await openSkinShop(game, sounds: sounds);
        game.tapItem(SkinLayer.bird, 'sky');
        expect(screen.tryOnId, 'sky');
        screen.scroll.offset = 100;
        sounds.clear();
        game.selectSkinTab(SkinLayer.gear);
        expect(sounds, [Sfx.skTab]);
        expect(spy.last('skin_shop_tab'), {'layer': 'gear'});
        expect(screen.tab, SkinLayer.gear);
        expect(screen.tryOnId, isNull);
        expect(screen.scroll.offset, 0);
        await flushAndMount(game);
        expect(screen.tiles.first.item.id, kNoneId);
        // Staggered: 30 ms per column, 40 ms per row, 240 ms each.
        stepGame(game, 0.01);
        expect(screen.tiles[0].enterProgress, greaterThan(0));
        expect(screen.tiles[1].enterProgress, 0);
        expect(screen.tiles[3].enterProgress, 0);
        expect(screen.tabBar.sliding, isTrue);
        stepGame(game, 0.8);
        for (final tile in screen.tiles) {
          expect(tile.enterProgress, 1);
        }
        expect(screen.tabBar.sliding, isFalse);
        expect(screen.tabBar.underlineX, closeTo(292 / 6, 1e-9));
        // "none" equipped -> NOTHING ON.
        expect(screen.actionButton.label, 'NOTHING ON');
        expect(screen.nameRow.chipText, isNull);
        // Same tab again: nothing.
        sounds.clear();
        game.selectSkinTab(SkinLayer.gear);
        expect(sounds, isEmpty);
      },
    );

    shopTest(
      'try-on: locked item on the preview, BUY (grey when short), '
      'one at a time; equipping an owned item clears it',
      prefs: prefsWith(coins: 3250, owned: ['hat:cap'], seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final sounds = <Sfx>[];
        final screen = await openSkinShop(game, sounds: sounds);
        game.selectSkinTab(SkinLayer.hat);
        await flushAndMount(game);
        sounds.clear();
        game.tapItem(SkinLayer.hat, 'crown');
        game.update(0);
        expect(screen.tryOnId, 'crown');
        expect(screen.previewLook.hat, 'crown');
        expect(game.menu.items.look.hat, kNoneId); // not equipped
        expect(sounds, [Sfx.skTap, Sfx.flap]);
        expect(screen.stage.hopVelocity, lessThan(0));
        expect(spy.last('item_try_on'), {
          'layer': 'hat',
          'id': 'crown',
          'rarity': 'LEGENDARY',
        });
        final crown = screen.tileFor('crown').current;
        expect(crown.tryingOn, isTrue);
        expect(crown.equipped, isFalse);
        expect(screen.actionButton.shownKind, ShopActionKind.buy);
        expect(screen.actionButton.poor, isTrue); // 5 000 > 3 250
        expect(screen.actionButton.pulseScale, 1); // grey: no pulse
        expect(screen.nameRow.nameText, 'Crown');
        expect(screen.nameRow.chipText, 'LEGENDARY');
        for (var i = 0; i < 20; i++) {
          stepGame(game, 0.05);
          expect(screen.stage.tryOnAlpha, inInclusiveRange(.28, .56));
        }
        // A second try-on replaces the first.
        game.tapItem(SkinLayer.hat, 'pirate');
        game.update(0);
        expect(screen.tryOnId, 'pirate');
        expect(screen.tileFor('crown').current.tryingOn, isFalse);
        expect(screen.actionButton.poor, isFalse); // 2 000 <= 3 250
        stepGame(game, 0.25);
        expect(screen.actionButton.pulseScale, greaterThan(1));
        // Equip an owned item: try-on cleared, saved at once.
        sounds.clear();
        game.tapItem(SkinLayer.hat, 'cap');
        await flushAndMount(game);
        game.update(0);
        expect(screen.tryOnId, isNull);
        expect(game.menu.items.look.hat, 'cap');
        expect(game.storage.equippedItems[SkinLayer.hat], 'cap');
        expect(sounds, [Sfx.skEquip, Sfx.flap]);
        expect(spy.last('item_equip'), {'layer': 'hat', 'id': 'cap'});
        expect(screen.actionButton.label, 'EQUIPPED');
        expect(screen.tileFor('cap').current.equipped, isTrue);
        // Tapping the equipped item again: just sk_tap.
        sounds.clear();
        final equips = spy.count('item_equip');
        game.tapItem(SkinLayer.hat, 'cap');
        expect(sounds, [Sfx.skTap]);
        expect(spy.count('item_equip'), equips);
      },
    );

    shopTest(
      'NEW tags: snapshot at open, cleared per item when tapped',
      prefs: prefsWith(coins: 0),
      verify: (game, spy, ads, iap, tester) async {
        // PRD-2.3 §19.3: the 2.3 items are NEW whatever the balance.
        var screen = await openSkinShop(game);
        game.selectSkinTab(SkinLayer.hat);
        await flushAndMount(game);
        expect(screen.tileFor('sprout').current.isNew, isTrue);
        expect(screen.tileFor('sunburst').current.isNew, isTrue);
        game.tapItem(SkinLayer.hat, 'sprout');
        await flushAndMount(game);
        game.update(0);
        expect(screen.tileFor('sprout').current.isNew, isFalse);
        expect(screen.tileFor('sunburst').current.isNew, isTrue);
        expect(game.storage.seenItems, contains('hat:sprout'));
        expect(game.menu.items.hasNewBadge, isTrue);
        game.handleBack();
        stepGame(game, 0.6);
        await flushAndMount(game);
        screen = await openSkinShop(game);
        game.selectSkinTab(SkinLayer.hat);
        await flushAndMount(game);
        expect(screen.tileFor('sprout').current.isNew, isFalse);
        expect(screen.tileFor('sunburst').current.isNew, isTrue);
      },
    );

    for (final (layer, id, rarity, sfx, confetti) in [
      (SkinLayer.bird, 'sky', Rarity.common, Sfx.skBuyCommon, 30),
      (SkinLayer.gear, 'monocle', Rarity.rare, Sfx.skBuyRare, 50),
      (SkinLayer.hoop, 'neon', Rarity.epic, Sfx.skBuyEpic, 80),
      (SkinLayer.trail, 'echo', Rarity.legendary, Sfx.skBuyLegendary, 140),
    ]) {
      shopTest(
        'buy a ${rarity.name} item: spend, own + equip, celebration, '
        'pill count-down, counters',
        prefs: prefsWith(coins: 6000, seen: allSeen),
        verify: (game, spy, ads, iap, tester) async {
          final sounds = <Sfx>[];
          final screen = await openSkinShop(game, sounds: sounds);
          game.selectSkinTab(layer);
          await flushAndMount(game);
          game.tapItem(layer, id);
          stepGame(game, 0.5);
          final item = itemById(layer, id)!;
          final counter = screen.tabBar.tabFor(layer);
          game.update(0);
          final countBefore = counter.countText;
          sounds.clear();
          await game.buyTriedOnItem();
          await flushAndMount(game);
          final after = 6000 - item.price;
          expect(game.menu.wallet.balance, after);
          expect(game.menu.items.isOwned(layer, id), isTrue);
          expect(game.menu.items.look.idFor(layer), id);
          expect(screen.tryOnId, isNull);
          expect(spy.last('item_purchase'), {
            'layer': layer.key,
            'id': id,
            'rarity': rarity.label,
            'price': item.price,
            'source': 'button',
          });
          expect(spy.last('item_equip'), {'layer': layer.key, 'id': id});
          expect(sounds.first, sfx);
          expect(sounds, contains(Sfx.flap)); // the bird hops
          expect(screen.stage.confettiCount, confetti);
          final rays = rarity == Rarity.epic || rarity == Rarity.legendary;
          expect(screen.stage.rays, rays ? greaterThan(0) : 0);
          final banner = screen.children.query<UnlockBanner>().single;
          expect(banner.nameText, item.name.toUpperCase());
          expect(banner.rarityText, rarity.label);
          final legendary = rarity == Rarity.legendary;
          expect(
            game.world.children.query<ScreenFlash>(),
            hasLength(legendary ? 1 : 0),
          );
          expect(
            game.world.children.query<ScreenShake>(),
            hasLength(legendary ? 1 : 0),
          );
          // Coin pill: counts down over 0.6 s (ease-out).
          final pill = game.coinPill;
          expect(pill.balance, after);
          expect(pill.shownBalance, 6000);
          stepGame(game, 0.3);
          expect(pill.shownBalance, lessThan(6000));
          expect(pill.shownBalance, greaterThan(after));
          // Ease-out: more than half of the way at half time.
          expect(6000 - pill.shownBalance, greaterThan(item.price / 2));
          stepGame(game, 0.35);
          expect(pill.shownBalance, after);
          // Counters went up; the bar popped after 0.5 s.
          expect(screen.bar.labelText, '4 / 223');
          expect(counter.countText, isNot(countBefore));
          expect(sounds.contains(Sfx.skProgress), !legendary);
          stepGame(game, 0.8);
          expect(sounds, contains(Sfx.skProgress));
          // The banner leaves after 1.9 s (2.6 s legendary).
          stepGame(game, legendary ? 0.6 : 0.2);
          expect(screen.children.query<UnlockBanner>(), hasLength(1));
          stepGame(game, legendary ? 0.6 : 0.3);
          await flushAndMount(game);
          expect(screen.children.query<UnlockBanner>(), isEmpty);
          expect(game.camera.viewfinder.position, Vector2.zero());
          expect(game.world.children.query<ScreenFlash>(), isEmpty);
          // The tile is owned + equipped now.
          game.update(0);
          final tile = screen.tileFor(id).current;
          expect(tile.owned && tile.equipped, isTrue);
        },
      );
    }

    shopTest(
      'collection bar pops to 112 % after 0.5 s on a purchase',
      prefs: prefsWith(coins: 500, seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(game);
        game.tapItem(SkinLayer.bird, 'sky');
        await game.buyTriedOnItem();
        await flushAndMount(game);
        game.update(0);
        expect(screen.bar.popScale, 1);
        var peak = 1.0;
        for (var i = 0; i < 60; i++) {
          stepGame(game, 1 / 60);
          if (screen.bar.popScale > peak) peak = screen.bar.popScale;
        }
        expect(peak, closeTo(1.12, 0.01));
        expect(screen.bar.popScale, 1);
        expect(screen.bar.fill, closeTo(4 / 223, 1e-9));
      },
    );

    shopTest(
      'not enough coins: sk_nocoins, dark toast 1.5 s, pill shake + gold '
      'flash, item_no_coins with the shortfall',
      prefs: prefsWith(coins: 100, seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final sounds = <Sfx>[];
        final screen = await openSkinShop(game, sounds: sounds);
        game.tapItem(SkinLayer.bird, 'sky');
        game.update(0);
        expect(screen.actionButton.poor, isTrue);
        sounds.clear();
        await game.buyTriedOnItem();
        await flushAndMount(game);
        expect(sounds, [Sfx.skNoCoins]);
        expect(game.menu.wallet.balance, 100);
        expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isFalse);
        expect(screen.tryOnId, 'sky'); // still trying on
        expect(
          screen.children.query<ShopToast>().single.message,
          'NOT ENOUGH COINS',
        );
        expect(spy.last('item_no_coins'), {
          'layer': 'bird',
          'id': 'sky',
          'shortfall': 50,
        });
        final pill = game.coinPill;
        stepGame(game, 0.05);
        expect(pill.shakeOffset, isNot(0));
        expect(pill.flashing, isTrue);
        stepGame(game, 1.0);
        expect(pill.shakeOffset, 0);
        expect(pill.flashing, isTrue); // second flash
        stepGame(game, 0.8);
        await flushAndMount(game);
        expect(pill.flashing, isFalse);
        expect(screen.children.query<ShopToast>(), isEmpty);
        // The pill's + opens the Shop; back returns to the skin shop.
        pill.onPressed();
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.shop);
        game.handleBack();
        stepGame(game, 0.6);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.skins);
      },
    );

    shopTest(
      'openSkins(layer, tryOnId): that tab, item tried on and scrolled in',
      prefs: prefsWith(seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(
          game,
          layer: SkinLayer.trail,
          tryOnId: 'echo',
        );
        expect(screen.tab, SkinLayer.trail);
        expect(screen.tryOnId, 'echo');
        expect(spy.last('item_try_on'), containsPair('id', 'echo'));
        final rect = screen.tileFor('echo').toRect();
        expect(
          screen.scroll.screenY(rect.bottom),
          lessThanOrEqualTo(screen.scroll.viewport.bottom),
        );
        // Already open: switches tab / try-on in place.
        game.openSkins(layer: SkinLayer.hat, tryOnId: 'halo');
        await flushAndMount(game);
        expect(game.skinShop, same(screen));
        expect(screen.tab, SkinLayer.hat);
        expect(screen.tryOnId, 'halo');
        // An owned item is not "tried on".
        game.handleBack();
        stepGame(game, 0.6);
        await flushAndMount(game);
        final again = await openSkinShop(
          game,
          layer: SkinLayer.hat,
          tryOnId: kNoneId,
        );
        expect(again.tryOnId, isNull);
      },
    );

    shopTest(
      'back button / Esc: home, or the Shop it came from',
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(game);
        game.tapItem(SkinLayer.bird, 'sky');
        expect(game.onKeyEvent(escape(), {}), isNotNull);
        stepGame(game, 0.6);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.skinShop, isNull);
        expect(screen.isMounted, isFalse);
        final shop = await openShop(game);
        shop.featured.onPressed();
        await flushAndMount(game);
        stepGame(game, 0.6);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.skins);
        game.skinShop!.backButton.onPressed();
        stepGame(game, 0.6);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.shop);
      },
    );
  });

  group('Skin shop live preview (§4.2)', () {
    shopTest(
      'hoops every 2.3 s at 120 pt/s; pass = pulse; the trail is drawn all '
      'the time; sk_hoop only after the hoop skin changed',
      prefs: prefsWith(owned: ['hoop:sky', 'trail:blue'], seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final sounds = <Sfx>[];
        final screen = await openSkinShop(game, sounds: sounds);
        final stage = screen.stage;
        // Opened 0.6 s ago: the first hoop appears at 0.8 s.
        expect(stage.hoops, isEmpty);
        stepGame(game, 0.25);
        expect(stage.hoops, hasLength(1));
        final hoop = stage.hoops.single;
        final x0 = hoop.x;
        stepGame(game, 0.5);
        expect(hoop.x, closeTo(x0 - 60, 0.5));
        // Pass: x crosses the bird (42 % of 292).
        while (!hoop.passed) {
          stepGame(game, 1 / 60);
        }
        expect(sounds, isNot(contains(Sfx.skHoop))); // unchanged skin
        // The trail is drawn on the Birds tab right after the pass and 1.75 s
        // later, where the old 1.7 s burn had already ended (owner bug).
        expect(stage.trail.particleCount, greaterThan(0));
        stepGame(game, 1.75);
        expect(stage.trail.particleCount, greaterThan(0));
        // A new hoop skin: sk_hoop on its first pass only.
        game.selectSkinTab(SkinLayer.hoop);
        game.tapItem(SkinLayer.hoop, 'sky');
        await flushAndMount(game);
        sounds.clear();
        stepGame(game, 4.6);
        expect(sounds.where((s) => s == Sfx.skHoop), hasLength(1));
        // TRAILS tab: sk_fire on a new trail.
        game.selectSkinTab(SkinLayer.trail);
        stepGame(game, 2.5);
        expect(stage.trail.particleCount, greaterThan(0));
        sounds.clear();
        game.tapItem(SkinLayer.trail, 'blue');
        await flushAndMount(game);
        stepGame(game, 0.1);
        expect(sounds, contains(Sfx.skFire));
        sounds.clear();
        stepGame(game, 0.5);
        expect(sounds, isNot(contains(Sfx.skFire)));
      },
    );

    shopTest(
      'hop: -150 pt/s kick, 900 pt/s² back to rest',
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(game);
        final stage = screen.stage;
        final rest = stage.birdY;
        stage.hop();
        expect(stage.hopVelocity, -150);
        stepGame(game, 1 / 6);
        expect(stage.birdY, lessThan(rest));
        stepGame(game, 0.5);
        expect(stage.birdY, rest);
        expect(stage.hopVelocity, 0);
      },
    );
  });

  group('Skin shop reduce motion', () {
    shopTest(
      'no flash, shake, rays or pulsing; confetti, hop and bob stay',
      prefs: prefsWith(coins: 6000, seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        game.reduceMotionOverride = true;
        expect(game.reduceMotion, isTrue);
        final screen = await openSkinShop(game);
        game.selectSkinTab(SkinLayer.hat);
        game.tapItem(SkinLayer.hat, 'crown');
        for (var i = 0; i < 10; i++) {
          stepGame(game, 0.07);
          expect(screen.stage.tryOnAlpha, .42);
          expect(screen.actionButton.pulseScale, 1);
        }
        await game.buyTriedOnItem();
        await flushAndMount(game);
        expect(game.menu.items.look.hat, 'crown');
        expect(game.world.children.query<ScreenFlash>(), isEmpty);
        expect(game.world.children.query<ScreenShake>(), isEmpty);
        expect(screen.stage.rays, 0);
        expect(screen.stage.confettiCount, 140);
        expect(screen.stage.hopVelocity, lessThan(0));
        expect(screen.children.query<UnlockBanner>(), hasLength(1));
        for (var i = 0; i < 60; i++) {
          stepGame(game, 1 / 60);
          expect(screen.bar.popScale, 1);
        }
        // Not enough coins: the "+" still flashes, the pill does not shake.
        game.tapItem(SkinLayer.hat, 'halo');
        await game.buyTriedOnItem();
        stepGame(game, 0.1);
        expect(game.coinPill.flashing, isTrue);
        expect(game.coinPill.shakeOffset, 0);
      },
    );
  });
}
