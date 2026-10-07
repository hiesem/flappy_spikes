import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/skins/shop_widgets.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart' hide escape;

import 'helpers.dart';
import 'menu_screenshot_test.dart' show loadFonts;
import 'shop_flow_test.dart' show EventSpy, shopTest;
import 'skin_shop_flow_test.dart' show allSeen, openSkinShop, prefsWith;

/// WP-J2: tap-twice buy on skin-shop tiles. The first real tap on a locked
/// tile tries it on and turns its price pill into a pulsing "BUY [coin]
/// price" pill; a second real tap on the same tile buys it through the
/// preview BUY's path (`buyTriedOnItem`).

Future<void> _tapAt(
  FlappySpikesGame game,
  WidgetTester tester,
  PositionComponent component, {
  Offset offset = Offset.zero,
}) async {
  final c = component.absolutePositionOfAnchor(Anchor.center);
  await tester.tapAt(ui.Offset(c.x + offset.dx, c.y + offset.dy));
  await tester.pump(const Duration(milliseconds: 16));
  await flushAndMount(game);
  game.update(0);
}

void _tileTest(
  String name, {
  Map<String, Object> prefs = const {},
  required Future<void> Function(
    FlappySpikesGame game,
    EventSpy spy,
    WidgetTester tester,
  )
  verify,
}) => shopTest(
  name,
  prefs: prefs,
  exactSurface: true,
  verify: (game, spy, ads, iap, tester) async {
    // Real fonts: the pill width check needs the shipped glyph metrics.
    await tester.runAsync(loadFonts);
    try {
      await verify(game, spy, tester);
    } finally {
      await tester.pump(const Duration(milliseconds: 50));
    }
  },
);

void main() {
  group('Tap-twice buy on tiles (WP-J2)', () {
    _tileTest(
      '1st tap: try-on + pulsing BUY pill; 2nd tap anywhere on the tile buys',
      prefs: prefsWith(coins: 1000, seen: allSeen),
      verify: (game, spy, tester) async {
        final sounds = <Sfx>[];
        final screen = await openSkinShop(game, sounds: sounds);
        final sky = screen.tileFor('sky');
        expect(sky.showsBuyPill, isFalse);
        await _tapAt(game, tester, sky);
        expect(screen.tryOnId, 'sky');
        expect(sky.current.tryingOn, isTrue);
        expect(sky.showsBuyPill, isTrue);
        expect(sky.current.affordable, isTrue);
        expect(sky.buyPill.label, 'BUY 150');
        expect(
          sky.buyPillRect.width,
          lessThanOrEqualTo(Config.skinShopTile / Config.skinShopActionPulse),
        );
        expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isFalse);
        expect(spy.count('item_purchase'), 0);
        // Pulses like the preview's BUY: up to 1.06 within the 1 s loop.
        var peak = 1.0;
        for (var i = 0; i < 10; i++) {
          stepGame(game, .1);
          peak = peak > sky.buyPillScale ? peak : sky.buyPillScale;
        }
        expect(peak, closeTo(Config.skinShopActionPulse, .01));
        // 2nd tap off-centre, still on the tile (top-left corner area).
        sounds.clear();
        await _tapAt(game, tester, sky, offset: const Offset(-38, -36));
        await flushAndMount(game);
        expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isTrue);
        expect(game.menu.items.look.bird, 'sky');
        expect(game.menu.wallet.balance, 850);
        expect(screen.tryOnId, isNull);
        expect(sky.showsBuyPill, isFalse);
        expect(sounds.first, Sfx.skBuyCommon);
        expect(screen.children.query<UnlockBanner>(), hasLength(1));
        expect(spy.last('item_purchase'), {
          'layer': 'bird',
          'id': 'sky',
          'rarity': 'COMMON',
          'price': 150,
          'source': 'tile',
        });
        expect(spy.last('item_equip'), {'layer': 'bird', 'id': 'sky'});
      },
    );

    _tileTest(
      'unaffordable: grey still BUY pill; 2nd tap = not-enough-coins',
      prefs: prefsWith(coins: 100, seen: allSeen),
      verify: (game, spy, tester) async {
        final sounds = <Sfx>[];
        final screen = await openSkinShop(game, sounds: sounds);
        final galaxy = screen.tileFor('galaxy');
        screen.scrollToItem('galaxy');
        game.update(0);
        await _tapAt(game, tester, galaxy);
        expect(galaxy.showsBuyPill, isTrue);
        expect(galaxy.current.affordable, isFalse);
        expect(galaxy.buyPill.label, 'BUY 5 000');
        expect(
          galaxy.buyPillRect.width,
          lessThanOrEqualTo(Config.skinShopTile / Config.skinShopActionPulse),
        );
        stepGame(game, .5);
        expect(galaxy.buyPillScale, 1); // grey and still
        sounds.clear();
        await _tapAt(game, tester, galaxy);
        expect(sounds, contains(Sfx.skNoCoins));
        expect(screen.children.query<ShopToast>(), hasLength(1));
        expect(spy.count('item_no_coins'), 1);
        expect(game.menu.items.isOwned(SkinLayer.bird, 'galaxy'), isFalse);
        expect(game.menu.wallet.balance, 100);
        // Still tried on: the pill stays and is still tappable.
        expect(screen.tryOnId, 'galaxy');
        expect(galaxy.showsBuyPill, isTrue);
      },
    );

    _tileTest(
      'another tile moves the try-on and the BUY pill; no purchase',
      prefs: prefsWith(coins: 5000, seen: allSeen),
      verify: (game, spy, tester) async {
        final screen = await openSkinShop(game);
        final sky = screen.tileFor('sky'), lime = screen.tileFor('lime');
        await _tapAt(game, tester, sky);
        await _tapAt(game, tester, lime);
        expect(screen.tryOnId, 'lime');
        expect(sky.showsBuyPill, isFalse);
        expect(lime.showsBuyPill, isTrue);
        expect(spy.count('item_purchase'), 0);
        // Back on sky is a first tap again (try-on, not a purchase).
        await _tapAt(game, tester, sky);
        expect(screen.tryOnId, 'sky');
        expect(spy.count('item_purchase'), 0);
        expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isFalse);
      },
    );

    _tileTest(
      'switching tabs clears the try-on and the BUY pill',
      prefs: prefsWith(coins: 5000, seen: allSeen),
      verify: (game, spy, tester) async {
        final screen = await openSkinShop(game);
        final sky = screen.tileFor('sky');
        await _tapAt(game, tester, sky);
        expect(sky.showsBuyPill, isTrue);
        await _tapAt(game, tester, screen.tabBar.tabFor(SkinLayer.hat));
        stepGame(game, .7);
        await flushAndMount(game);
        expect(screen.tryOnId, isNull);
        expect(screen.tiles.any((t) => t.showsBuyPill), isFalse);
        await _tapAt(game, tester, screen.tabBar.tabFor(SkinLayer.bird));
        stepGame(game, .7);
        await flushAndMount(game);
        final again = screen.tileFor('sky');
        expect(again.showsBuyPill, isFalse);
        // First tap after the switch only tries it on.
        await _tapAt(game, tester, again);
        expect(spy.count('item_purchase'), 0);
        expect(again.showsBuyPill, isTrue);
      },
    );

    _tileTest(
      'the top-right BUY still buys (source button)',
      prefs: prefsWith(coins: 1000, seen: allSeen),
      verify: (game, spy, tester) async {
        final screen = await openSkinShop(game);
        await _tapAt(game, tester, screen.tileFor('sky'));
        expect(screen.actionButton.shownKind, ShopActionKind.buy);
        await _tapAt(game, tester, screen.actionButton);
        await flushAndMount(game);
        expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isTrue);
        expect(spy.last('item_purchase')!['source'], 'button');
      },
    );

    shopTest(
      'reduce motion: the tile BUY pill does not pulse',
      prefs: prefsWith(coins: 1000, seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        game.reduceMotionOverride = true;
        final screen = await openSkinShop(game);
        game.tapItem(SkinLayer.bird, 'sky', fromTile: true);
        game.update(0);
        final sky = screen.tileFor('sky');
        expect(sky.showsBuyPill, isTrue);
        for (var i = 0; i < 10; i++) {
          stepGame(game, .1);
          expect(sky.buyPillScale, 1);
        }
      },
    );

    shopTest(
      'tapItem without fromTile (featured row / API) never buys',
      prefs: prefsWith(coins: 1000, seen: allSeen),
      verify: (game, spy, ads, iap, tester) async {
        final screen = await openSkinShop(game);
        game.tapItem(SkinLayer.bird, 'sky');
        game.tapItem(SkinLayer.bird, 'sky');
        await flushAndMount(game);
        expect(screen.tryOnId, 'sky');
        expect(spy.count('item_purchase'), 0);
        expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isFalse);
      },
    );
  });
}
