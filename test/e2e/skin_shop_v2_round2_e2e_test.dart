import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/menu_screen_chrome.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/skins/skin_shop_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;
import '../shop_flow_test.dart' show EventSpy;

// Real GameWidget pointer events, game flows, wallet and persistence;
// analytics and the platform store stay plugin-free. A group carries string
// skip reasons because FlameTester's skip parameter only accepts bool.
void _journey(
  String name,
  Future<void> Function(FlappySpikesGame, EventSpy, WidgetTester) verify, {
  double scale = 1,
  double height = 568,
  String? skip,
  Map<String, Object> prefs = const {'coins': 30000},
}) {
  group(name, skip: skip, () {
    final events = EventSpy();
    FlameTester<FlappySpikesGame>(
      () => createTestGame(
        prefs,
        height,
        events,
        Monetization(ads: FakeRewardedAds(), iap: FakeIapService()),
      ),
      gameSize: Vector2(320 * scale, height * scale),
      pumpWidget: (widget, tester) async {
        tester.view
          ..physicalSize = ui.Size(320 * scale, height * scale)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(widget);
      },
    ).testGameWidget(
      'user journey',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        try {
          await verify(game, events, tester);
        } finally {
          await tester.pump(const Duration(milliseconds: 60));
        }
      },
    );
  });
}

ui.Offset _centre(PositionComponent c, [double scale = 1]) {
  final p = c.absolutePositionOfAnchor(Anchor.center);
  return ui.Offset(p.x * scale, p.y * scale);
}

Future<void> _tap(
  FlappySpikesGame game,
  WidgetTester tester,
  PositionComponent c, {
  double scale = 1,
}) async {
  await tester.tapAt(_centre(c, scale));
  await tester.pump(const Duration(milliseconds: 60));
  await flushAndMount(game);
}

Future<void> _fade(FlappySpikesGame game, WidgetTester tester) async {
  stepGame(game, .6);
  await flushAndMount(game);
  await tester.pump();
}

Future<SkinShopScreen> _skins(
  FlappySpikesGame game,
  WidgetTester tester, {
  double scale = 1,
}) async {
  await _tap(game, tester, game.homeScreen!.skinsTile, scale: scale);
  await _fade(game, tester);
  expect(game.menuScene, MenuScene.skins);
  return game.skinShop!;
}

Future<void> _flick(WidgetTester tester, MenuScrollArea scroll) async {
  await tester.timedDragFrom(
    ui.Offset(160, scroll.viewport.bottom - 24),
    const ui.Offset(0, -60),
    const Duration(milliseconds: 60),
  );
}

Future<void> _shot(
  FlappySpikesGame game,
  WidgetTester tester,
  String name,
) async {
  await tester.runAsync(() => captureShot(game, 2, 's2_qa2_$name'));
  game.onGameResize(Vector2(320, game.viewHeight));
}

void main() {
  setUpAll(loadFonts);

  for (final scale in [1.0, 2.0, 3.0]) {
    _journey('round 2 drag slop at ${scale}x camera scale', scale: scale, (
      game,
      events,
      tester,
    ) async {
      final screen = await _skins(game, tester, scale: scale);
      final sky = screen.tileFor('sky');
      final small = await tester.startGesture(_centre(sky, scale));
      await small.moveBy(ui.Offset(0, 4 * scale));
      await small.up();
      await tester.pump(const Duration(milliseconds: 60));
      await flushAndMount(game);
      expect(screen.tryOnId, 'sky');
      expect(sky.showsBuyPill, isTrue);
      final scroll = await tester.startGesture(_centre(sky, scale));
      await scroll.moveBy(ui.Offset(0, -10 * scale));
      await tester.pump(const Duration(milliseconds: 80));
      await scroll.up();
      await tester.pump(const Duration(milliseconds: 60));
      await flushAndMount(game);
      expect(events.count('item_purchase'), 0);
      expect(game.menu.wallet.balance, 30000);
      expect(screen.scroll.offset, greaterThan(0));
      expect(sky.pressed, isFalse);
    });
  }

  _journey('round 2 pause without a stationary move prevents a stale fling', (
    game,
    events,
    tester,
  ) async {
    final screen = await _skins(game, tester);
    final gesture = await tester.startGesture(const ui.Offset(160, 500));
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(
        const ui.Offset(0, -12),
        timeStamp: Duration(milliseconds: i * 20),
      );
    }
    final held = screen.scroll.offset;
    // VelocityTracker uses a sampling-clock stopwatch to detect a finger
    // stopped without receiving any more PointerMove events.
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.up(timeStamp: const Duration(milliseconds: 280));
    expect(screen.scroll.isBusy, isFalse);
    stepGame(game, 1);
    expect(screen.scroll.offset, held);
    expect(screen.tryOnId, isNull);
    expect(events.count('item_purchase'), 0);
  });

  // S1-52 (fixed in R2), Medium: menu_screen_chrome.dart fell back to the host's
  // pixel/s velocity without converting to world pt/s or applying the cap.
  // This identical sparse world-point flick yields 3145 / 6290 / 9435 pt/s
  // at 1x / 2x / 3x; the latter two exceed the configured 4000 pt/s ceiling.
  _journey(
    'S1-52 sparse flicks keep the same velocity at every camera scale',
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      Future<double> sparseFlick(double scale) async {
        tester.view.physicalSize = ui.Size(320 * scale, 568 * scale);
        await tester.pump(const Duration(milliseconds: 60));
        screen.scroll.offset = 0;
        final gesture = await tester.startGesture(
          ui.Offset(160 * scale, 500 * scale),
        );
        // Three sub-slop events give the host a velocity estimate; only the
        // last move reaches the scroll component (one drag sample).
        for (var i = 1; i <= 3; i++) {
          await gesture.moveBy(
            ui.Offset(0, -scale),
            timeStamp: Duration(milliseconds: i * 10),
          );
        }
        await gesture.moveBy(
          ui.Offset(0, -30 * scale),
          timeStamp: const Duration(milliseconds: 40),
        );
        await gesture.up(timeStamp: const Duration(milliseconds: 41));
        expect(screen.scroll.isGliding, isTrue);
        return screen.scroll.velocity;
      }

      final at1 = await sparseFlick(1);
      final at2 = await sparseFlick(2);
      final at3 = await sparseFlick(3);
      expect(at2, closeTo(at1, 1), reason: '1x=$at1, 2x=$at2, 3x=$at3');
      expect(at3, closeTo(at1, 1));
      expect(at3.abs(), lessThanOrEqualTo(Config.menuScrollMaxFlingVelocity));
      expect(events.count('item_purchase'), 0);
    },
  );

  // S2-52 (fixed in R2), Low: menu_screen_chrome.dart advanced a whole fling
  // frame before starting the spring, losing the edge-crossing time within
  // that frame. At t=.1s, 30/60 fps overshoots exceed 120 fps by 3.83 pt in
  // Skins, 4.49 pt in Shop and 4.21 pt in LEVELS (about 20% of the bounce).
  // All settle in range, but the handover trajectory is not dt-independent.
  for (final menu in ['skins', 'Shop', 'LEVELS']) {
    _journey(
      'S2-52 $menu edge bounce trajectory is independent of fps',
      (game, events, tester) async {
        final MenuScreen screen;
        if (menu == 'skins') {
          screen = await _skins(game, tester);
        } else {
          await _tap(
            game,
            tester,
            menu == 'Shop' ? game.homeScreen!.shopTile : game.homeScreen!.bird,
          );
          await _fade(game, tester);
          screen = menu == 'Shop' ? game.shopScreen! : game.levelsScreen!;
        }
        final scroll = screen.scroll;
        Future<List<double>> trajectory(int fps) async {
          scroll.offset = scroll.maxOffset - 80;
          await _flick(tester, scroll);
          expect(scroll.isGliding, isTrue);
          final points = <double>[];
          for (var tenth = 0; tenth < 6; tenth++) {
            for (var frame = 0; frame < fps ~/ 10; frame++) {
              game.update(1 / fps);
            }
            points.add(scroll.offset);
          }
          await settleMenuScroll(scroll, game, tester);
          expect(scroll.offset, scroll.maxOffset);
          return points;
        }

        final at30 = await trajectory(30);
        final at60 = await trajectory(60);
        final at120 = await trajectory(120);
        // Matching elapsed times include the handover from fling to spring,
        // rather than only the in-bounds portion covered by round 1.
        for (var i = 0; i < at30.length; i++) {
          expect(
            at30[i],
            closeTo(at120[i], 1),
            reason:
                '$menu at ${(i + 1) / 10}s: '
                '30=$at30, 60=$at60, 120=$at120',
          );
          expect(at60[i], closeTo(at120[i], 1));
        }
        expect(events.count('item_purchase'), 0);
      },
    );
  }

  _journey('round 2 direction reversal uses the latest movement', (
    game,
    events,
    tester,
  ) async {
    final screen = await _skins(game, tester);
    screen.scroll.offset = 200;
    final gesture = await tester.startGesture(const ui.Offset(160, 400));
    for (var i = 1; i <= 4; i++) {
      await gesture.moveBy(
        const ui.Offset(0, -10),
        timeStamp: Duration(milliseconds: i * 60),
      );
    }
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(
        const ui.Offset(0, 10),
        timeStamp: Duration(milliseconds: 240 + i * 20),
      );
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 341));
    expect(screen.scroll.velocity, closeTo(-500, 1));
    final released = screen.scroll.offset;
    stepGame(game, .1);
    expect(screen.scroll.offset, lessThan(released));
    await settleMenuScroll(screen.scroll, game, tester);
    expect(screen.scroll.isOverScrolled, isFalse);
    expect(events.count('item_purchase'), 0);
  });

  for (final reduced in [false, true]) {
    _journey(
      'round 2 all five layers: move try-on, stop-tap, tile buy, saved look '
      '(reduce motion $reduced)',
      height: 730,
      (game, events, tester) async {
        game.reduceMotionOverride = reduced;
        final screen = await _skins(game, tester);
        var balance = game.menu.wallet.balance;
        var purchases = 0;
        // PRD:834 adds CARDS; these journeys cover the five wardrobe tabs.
        for (final layer in kShopLayers.where((l) => l != SkinLayer.card)) {
          await _tap(game, tester, screen.tabBar.tabFor(layer));
          stepGame(game, .8);
          await flushAndMount(game);
          expect(screen.tryOnId, isNull);
          final first = screen.tiles[1], second = screen.tiles[2];
          await _tap(game, tester, first);
          expect(first.showsBuyPill, isTrue);
          expect(first.buyPill.label, 'BUY ${first.item.price}');
          var peak = 1.0;
          for (var frame = 0; frame < 60; frame++) {
            game.update(1 / 60);
            peak = math.max(peak, first.buyPillScale);
          }
          expect(peak, closeTo(reduced ? 1 : 1.06, .001));
          await _tap(game, tester, second);
          expect(first.showsBuyPill, isFalse);
          expect(second.showsBuyPill, isTrue);
          await _tap(game, tester, first);
          expect(events.count('item_purchase'), purchases);
          await tester.timedDragFrom(
            ui.Offset(160, screen.scroll.viewport.bottom - 24),
            const ui.Offset(0, -20),
            const Duration(milliseconds: 60),
          );
          expect(screen.scroll.isGliding, isTrue);
          expect(_centre(first).dy, greaterThan(screen.scroll.viewport.top));
          await _tap(game, tester, first); // This stops; it must never buy.
          expect(screen.scroll.isBusy, isFalse);
          expect(screen.tryOnId, first.item.id);
          expect(game.menu.wallet.balance, balance);
          expect(events.count('item_purchase'), purchases);
          await _tap(game, tester, first);
          balance -= first.item.price;
          purchases++;
          expect(game.menu.wallet.balance, balance);
          expect(events.count('item_purchase'), purchases);
          expect(events.last('item_purchase')!['source'], 'tile');
          expect(game.menu.items.look.idFor(layer), first.item.id);
          expect(first.showsBuyPill, isFalse);
          expect(first.current.equipped, isTrue);
          expect(screen.tryOnId, isNull);
          // Equipping the owned item again never spends more coins.
          await _tap(game, tester, first);
          expect(game.menu.wallet.balance, balance);
          final saved = GameStorage();
          await saved.load();
          expect(saved.coins, balance);
          expect(saved.equippedItems[layer], first.item.id);
          await _shot(game, tester, '${layer.key}_bought_reduced_$reduced');
        }
        await _tap(game, tester, screen.backButton);
        await _fade(game, tester);
        expect(game.menuScene, MenuScene.home);
        final look = game.menu.items.look;
        expect(game.homeScreen!.bird.look.bird, look.bird);
        expect(game.homeScreen!.bird.look.gear, look.gear);
        expect(game.homeScreen!.bird.look.hat, look.hat);
      },
    );
  }

  _journey(
    'round 2 unaffordable tile and fixed BUY in every layer',
    prefs: const {'coins': 0},
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      var rejected = 0;
      // PRD:834 adds CARDS; these journeys cover the five wardrobe tabs.
      for (final layer in kShopLayers.where((l) => l != SkinLayer.card)) {
        await _tap(game, tester, screen.tabBar.tabFor(layer));
        stepGame(game, .8);
        await flushAndMount(game);
        final tile = screen.tiles[1];
        expect(tile.showsBuyPill, isFalse);
        await _tap(game, tester, tile);
        expect(tile.current.affordable, isFalse);
        expect(tile.showsBuyPill, isTrue);
        stepGame(game, .5);
        expect(tile.buyPillScale, 1);
        await _tap(game, tester, tile);
        expect(events.count('item_no_coins'), ++rejected);
        expect(screen.tryOnId, tile.item.id);
        expect(
          screen.children.query<ShopToast>().single.message,
          'NOT ENOUGH COINS',
        );
        await _tap(game, tester, screen.actionButton);
        expect(events.count('item_no_coins'), ++rejected);
        expect(game.menu.wallet.balance, 0);
        expect(events.count('item_purchase'), 0);
        expect(game.menu.items.isOwned(layer, tile.item.id), isFalse);
      }
      // Returning to Birds clears the last try-on and starts at a price pill.
      await _tap(game, tester, screen.tabBar.tabFor(SkinLayer.bird));
      stepGame(game, .8);
      await flushAndMount(game);
      expect(screen.tryOnId, isNull);
      expect(screen.tileFor('sky').showsBuyPill, isFalse);
      await _tap(game, tester, screen.tileFor('sky'));
      expect(events.count('item_no_coins'), rejected);
    },
  );

  _journey('round 2 settled duck → Wizard try-on → purchase fits the preview', (
    game,
    events,
    tester,
  ) async {
    final screen = await _skins(game, tester);
    screen.scrollToItem('duck');
    await _tap(game, tester, screen.tileFor('duck'));
    await _tap(game, tester, screen.tileFor('duck'));
    expect(game.menu.items.look.bird, 'duck');
    stepGame(game, 3);
    await flushAndMount(game);
    await _tap(game, tester, screen.tabBar.tabFor(SkinLayer.hat));
    stepGame(game, 1);
    await flushAndMount(game);
    screen.scrollToItem('wizard');
    await _tap(game, tester, screen.tileFor('wizard'));
    expect(screen.tryOnId, 'wizard');
    var lowest = double.infinity;
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
      lowest = math.min(lowest, screen.stage.lookTopNow());
      if (i == 0) await _shot(game, tester, 'duck_wizard_transition');
    }
    expect(
      lowest,
      greaterThanOrEqualTo(0),
      reason: 'new tall hat must fit while its resting position eases',
    );
    await _tap(game, tester, screen.tileFor('wizard'));
    stepGame(game, 2);
    await _shot(game, tester, 'duck_wizard_settled');
    expect(screen.stage.lookTopNow(), greaterThanOrEqualTo(0));
  });
}
