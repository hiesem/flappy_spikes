import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/look_component.dart';
import 'package:flappy_spikes/components/menu_screen_chrome.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/skins/item_tile.dart';
import 'package:flappy_spikes/components/skins/skin_shop_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart' show GearArt, HatArt;
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;
import '../shop_flow_test.dart' show EventSpy;

// Independent QA of WP-J1/J2. Gestures enter through GameWidget; purchases
// use real wallet/storage/game flows with plugin-free analytics/store seams.
// Open defects use group skip reasons because FlameTester's skip is bool-only.
void _journey(
  String name,
  Future<void> Function(FlappySpikesGame, EventSpy, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
  double height = 568,
  String? skip,
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
      gameSize: Vector2(320, height),
      pumpWidget: (widget, tester) async {
        tester.view
          ..physicalSize = ui.Size(320, height)
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

ui.Offset _centre(PositionComponent component) {
  final c = component.absolutePositionOfAnchor(Anchor.center);
  return ui.Offset(c.x, c.y);
}

Future<void> _tap(
  FlappySpikesGame game,
  WidgetTester tester,
  PositionComponent component, {
  ui.Offset delta = ui.Offset.zero,
}) async {
  await tester.tapAt(_centre(component) + delta);
  await tester.pump(const Duration(milliseconds: 60));
  await flushAndMount(game);
}

Future<void> _fade(FlappySpikesGame game, WidgetTester tester) async {
  stepGame(game, .4);
  await flushAndMount(game);
  await tester.pump();
}

Future<SkinShopScreen> _skins(
  FlappySpikesGame game,
  WidgetTester tester,
) async {
  await _tap(game, tester, game.homeScreen!.skinsTile);
  await _fade(game, tester);
  expect(game.menuScene, MenuScene.skins);
  return game.skinShop!;
}

Future<void> _tab(
  FlappySpikesGame game,
  WidgetTester tester,
  SkinLayer layer,
) async {
  await _tap(game, tester, game.skinShop!.tabBar.tabFor(layer));
  stepGame(game, .7);
  await flushAndMount(game);
}

Future<void> _flick(
  WidgetTester tester,
  MenuScrollArea scroll, {
  double distance = -60,
  int millis = 60,
}) async {
  await tester.pump();
  final startY = distance < 0
      ? scroll.viewport.bottom - 24
      : scroll.viewport.top + 24;
  await tester.timedDragFrom(
    ui.Offset(160, startY),
    ui.Offset(0, distance),
    Duration(milliseconds: millis),
  );
}

ItemTile _visibleLocked(SkinShopScreen screen) =>
    screen.tiles.firstWhere((tile) {
      final y = _centre(tile).dy;
      return !tile.current.owned &&
          y > screen.scroll.viewport.top + 25 &&
          y < screen.scroll.viewport.bottom - 25;
    });

Future<void> _shot(
  FlappySpikesGame game,
  WidgetTester tester,
  String name,
) async {
  await tester.runAsync(() => captureShot(game, 2, 's2_qa1_$name'));
  game.onGameResize(Vector2(320, game.viewHeight));
}

void main() {
  setUpAll(loadFonts);

  for (final height in [568.0, 730.0]) {
    _journey(
      'v2 first tap → move try-on → second tile tap → saved outfit at $height',
      height: height,
      prefs: const {'coins': 1000},
      (game, events, tester) async {
        final screen = await _skins(game, tester);
        final sky = screen.tileFor('sky'), lime = screen.tileFor('lime');
        await _tap(game, tester, sky);
        expect(sky.showsBuyPill, isTrue);
        expect(sky.buyPill.label, 'BUY 150');
        expect(events.count('item_purchase'), 0);
        var peak = 1.0;
        for (var frame = 0; frame < 60; frame++) {
          stepGame(game, 1 / 60);
          peak = math.max(peak, sky.buyPillScale);
        }
        expect(peak, closeTo(1.06, .001));
        await _shot(game, tester, 'buy_pill_${height.toInt()}');
        await _tap(game, tester, lime);
        expect(sky.showsBuyPill, isFalse);
        expect(lime.showsBuyPill, isTrue);
        await _tap(game, tester, sky);
        expect(events.count('item_purchase'), 0);
        // Anywhere on the same tile is the second tap, including its corner.
        await _tap(game, tester, sky, delta: const ui.Offset(-30, -28));
        expect(game.menu.wallet.balance, 850);
        expect(game.menu.items.look.bird, 'sky');
        expect(events.count('item_purchase'), 1);
        expect(events.last('item_purchase')!['source'], 'tile');
        expect(screen.tryOnId, isNull);
        expect(sky.showsBuyPill, isFalse);
        expect(screen.children.query<UnlockBanner>(), hasLength(1));
        final saved = GameStorage();
        await saved.load();
        expect(saved.coins, 850);
        expect(saved.equippedItems[SkinLayer.bird], 'sky');
        await _tap(game, tester, screen.backButton);
        await _fade(game, tester);
        expect(game.homeScreen!.bird.look.bird, 'sky');
      },
    );
  }

  _journey(
    'v2 unaffordable second tap → toast → tab reset → button buy',
    prefs: const {'coins': 150},
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      final robin = screen.tileFor('robin');
      screen.scrollToItem('robin');
      await _tap(game, tester, robin);
      expect(robin.showsBuyPill, isTrue);
      expect(robin.current.affordable, isFalse);
      stepGame(game, .5);
      expect(robin.buyPillScale, 1);
      await _tap(game, tester, robin);
      expect(events.count('item_no_coins'), 1);
      expect(events.count('item_purchase'), 0);
      expect(
        screen.children.query<ShopToast>().single.message,
        'NOT ENOUGH COINS',
      );
      expect(game.coinPill.flashing, isTrue);
      expect(game.menu.wallet.balance, 150);
      expect(screen.tryOnId, 'robin');
      await _shot(game, tester, 'poor_buy_pill');
      await _tab(game, tester, SkinLayer.hat);
      expect(screen.tryOnId, isNull);
      await _tab(game, tester, SkinLayer.bird);
      final sky = screen.tileFor('sky');
      expect(sky.showsBuyPill, isFalse);
      await _tap(game, tester, sky);
      expect(events.count('item_purchase'), 0);
      await _tap(game, tester, screen.actionButton);
      expect(game.menu.wallet.balance, 0);
      expect(game.menu.items.look.bird, 'sky');
      expect(events.last('item_purchase')!['source'], 'button');
    },
  );

  _journey(
    'v2 try-on → fling → stop-tap on BUY tile → real second tap',
    prefs: const {'coins': 1000},
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      await _flick(tester, screen.scroll);
      expect(screen.scroll.isGliding, isTrue);
      final tile = _visibleLocked(screen);
      await _tap(game, tester, tile); // stops only
      expect(screen.tryOnId, isNull);
      await _tap(game, tester, tile);
      expect(screen.tryOnId, tile.item.id);
      final balance = game.menu.wallet.balance;
      await _flick(tester, screen.scroll, distance: -30, millis: 80);
      expect(screen.scroll.isGliding, isTrue);
      // The tile remains visible even after this small drag.
      expect(_centre(tile).dy, inInclusiveRange(326, 524));
      await _tap(game, tester, tile);
      expect(screen.scroll.isBusy, isFalse);
      expect(game.menu.wallet.balance, balance);
      expect(events.count('item_purchase'), 0);
      expect(screen.tryOnId, tile.item.id);
      expect(tile.showsBuyPill, isTrue);
      await _tap(game, tester, tile);
      expect(game.menu.wallet.balance, balance - tile.item.price);
      expect(events.count('item_purchase'), 1);
    },
  );

  _journey(
    'v2 reduce motion keeps momentum but freezes BUY pulse',
    prefs: const {'coins': 1000},
    (game, events, tester) async {
      game.reduceMotionOverride = true;
      final screen = await _skins(game, tester);
      await _tap(game, tester, screen.tileFor('sky'));
      for (var i = 0; i < 60; i++) {
        stepGame(game, 1 / 60);
        expect(screen.tileFor('sky').buyPillScale, 1);
        expect(screen.actionButton.pulseScale, 1);
      }
      await _flick(tester, screen.scroll);
      final released = screen.scroll.offset;
      expect(screen.scroll.isGliding, isTrue);
      stepGame(game, .12);
      expect(screen.scroll.offset, greaterThan(released));
      // The fixed preview BUY (outside the list) stops the fling AND buys
      // (S1-51 decision: native list behaviour).
      await _tap(game, tester, screen.actionButton);
      expect(screen.scroll.isBusy, isFalse);
      expect(game.menu.items.look.bird, 'sky');
      expect(events.count('item_purchase'), 1);
      expect(screen.stage.rays, 0);
    },
  );

  for (final menu in ['skins', 'Shop', 'LEVELS']) {
    _journey(
      'v2 $menu fling, stop, drag, rubber-band, scrollTo and return',
      prefs: const {
        'bestScore': 640,
        'claimedLevels': ['1', '2', '3', '4', '5', '6'],
      },
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
        scroll.scrollTo(scroll.viewport.top, animate: false);
        await _flick(tester, scroll, distance: -40, millis: 120);
        expect(scroll.isGliding, isTrue);
        final released = scroll.offset, velocity = scroll.velocity;
        stepGame(game, .08);
        expect(scroll.offset, greaterThan(released));
        expect(scroll.velocity.abs(), lessThan(velocity.abs()));
        // A tap inside the moving list only stops it (presses nothing).
        await tester.tapAt(ui.Offset(160, scroll.viewport.center.dy));
        await tester.pump(const Duration(milliseconds: 60));
        await flushAndMount(game);
        expect(screen.active, isTrue);
        expect(scroll.isBusy, isFalse);
        final stopped = scroll.offset;
        stepGame(game, .2);
        expect(scroll.offset, stopped);
        await _flick(tester, scroll, distance: -40, millis: 120);
        expect(scroll.isGliding, isTrue);
        scroll.scrollTo(scroll.viewport.top + scroll.maxOffset, animate: true);
        expect(scroll.isBusy, isFalse);
        stepGame(game, 1);
        expect(scroll.offset, scroll.maxOffset);
        await _flick(tester, scroll, distance: -80, millis: 80);
        expect(scroll.isSpringing, isTrue);
        expect(scroll.offset, greaterThan(scroll.maxOffset));
        // Stop a spring, hold it, then lift and let the spring resume.
        final gesture = await tester.startGesture(
          ui.Offset(160, scroll.viewport.center.dy),
        );
        expect(scroll.isBusy, isFalse);
        final held = scroll.offset;
        stepGame(game, .15);
        expect(scroll.offset, held);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 60));
        expect(scroll.isSpringing, isTrue);
        await settleMenuScroll(scroll, game, tester);
        expect(scroll.isOverScrolled, isFalse);
        expect(scroll.offset, scroll.maxOffset);
        scroll.scrollTo(scroll.viewport.top, animate: false);
        await _flick(tester, scroll, distance: 100, millis: 80);
        expect(scroll.offset, inExclusiveRange(-100, 0));
        expect(scroll.isSpringing, isTrue);
        await settleMenuScroll(scroll, game, tester);
        expect(scroll.offset, 0);
        // A new drag can take over a spring without a selection on release.
        await _flick(tester, scroll, distance: 80, millis: 80);
        expect(scroll.isSpringing, isTrue);
        final takeover = await tester.startGesture(
          ui.Offset(160, scroll.viewport.center.dy),
        );
        expect(scroll.isBusy, isFalse);
        await takeover.moveBy(const ui.Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 20));
        final midway = scroll.offset;
        await takeover.moveBy(const ui.Offset(0, -60));
        expect(scroll.offset, greaterThan(midway));
        await takeover.up();
        await tester.pump(const Duration(milliseconds: 60));
        await settleMenuScroll(scroll, game, tester);
        expect(scroll.isOverScrolled, isFalse);
        expect(game.menu.wallet.balance, 0);
        await _tap(game, tester, screen.backButton);
        await _fade(game, tester);
        expect(game.menuScene, MenuScene.home);
        expect(events.count('item_purchase'), 0);
      },
    );
  }

  _journey(
    'v2 4 pt drag still taps; a long drag never purchases',
    prefs: const {'coins': 1000},
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      final sky = screen.tileFor('sky');
      final small = await tester.startGesture(_centre(sky));
      await small.moveBy(const ui.Offset(0, 4));
      await small.up();
      await tester.pump(const Duration(milliseconds: 60));
      await flushAndMount(game);
      expect(screen.tryOnId, 'sky');
      expect(screen.scroll.offset, 0);
      final long = await tester.startGesture(_centre(sky));
      await long.moveBy(const ui.Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      await long.moveBy(const ui.Offset(0, -30));
      await long.up();
      await tester.pump(const Duration(milliseconds: 60));
      await flushAndMount(game);
      expect(events.count('item_purchase'), 0);
      expect(game.menu.wallet.balance, 1000);
      expect(sky.pressed, isFalse);
    },
  );

  _journey('v2 release velocity uses recent drag samples and ignores a pause', (
    game,
    events,
    tester,
  ) async {
    final screen = await _skins(game, tester);
    final scroll = screen.scroll;
    // A slow opening movement must not dilute the final fast 60 ms.
    final gesture = await tester.startGesture(const ui.Offset(160, 500));
    var timestamp = const Duration(milliseconds: 100);
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const ui.Offset(0, -10), timeStamp: timestamp);
      timestamp += const Duration(milliseconds: 100);
    }
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const ui.Offset(0, -20), timeStamp: timestamp);
      timestamp += const Duration(milliseconds: 20);
    }
    await gesture.up(timeStamp: timestamp);
    expect(scroll.isGliding, isTrue);
    expect(scroll.velocity, closeTo(1000, 1));
    scroll.scrollTo(scroll.viewport.top, animate: false);
    // This time the finger stops before release. A stationary pointer
    // sample exercises Flutter's release estimate with no real-time sleeps.
    final paused = await tester.startGesture(const ui.Offset(160, 500));
    timestamp += const Duration(milliseconds: 100);
    for (var i = 0; i < 5; i++) {
      await paused.moveBy(const ui.Offset(0, -10), timeStamp: timestamp);
      timestamp += const Duration(milliseconds: 20);
    }
    timestamp += const Duration(milliseconds: 200);
    await paused.moveBy(ui.Offset.zero, timeStamp: timestamp);
    await paused.up(timeStamp: timestamp);
    expect(scroll.isBusy, isFalse, reason: 'old samples must not fling');
    final stopped = scroll.offset;
    stepGame(game, 1);
    expect(scroll.offset, stopped);
    expect(events.count('item_purchase'), 0);
  });

  _journey(
    'S1-50 a 10 pt scroll attempt must not buy the tried-on tile',
    prefs: const {'coins': 1000},
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      final sky = screen.tileFor('sky');
      await _tap(game, tester, sky);
      final gesture = await tester.startGesture(_centre(sky));
      await gesture.moveBy(const ui.Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));
      await flushAndMount(game);
      expect(
        events.count('item_purchase'),
        0,
        reason: 'WP-J1: travel beyond ~6 pt is scrolling and cancels the press',
      );
      expect(game.menu.wallet.balance, 1000);
      expect(game.menu.items.isOwned(SkinLayer.bird, 'sky'), isFalse);
    },
  );

  // S1-51 orchestrator decision (native mobile behaviour): only a tap INSIDE
  // the gliding list is swallowed; a control outside it stops the list and
  // acts.
  _journey(
    'S1-51 a tap on the coin pill during a fling stops the list and opens Shop',
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      await _flick(tester, screen.scroll);
      expect(screen.scroll.isGliding, isTrue);
      await _tap(game, tester, game.coinPill);
      expect(screen.scroll.isBusy, isFalse);
      final stopped = screen.scroll.offset;
      stepGame(game, .1);
      expect(screen.scroll.offset, stopped);
      await _fade(game, tester);
      expect(game.menuScene, MenuScene.shop);
      expect(events.count('shop_open'), 1);
    },
  );

  _journey('S2-50 the same flick travels equally at 30, 60 and 120 fps', (
    game,
    events,
    tester,
  ) async {
    final screen = await _skins(game, tester);
    Future<double> distanceAt(int fps) async {
      screen.scroll.offset = 0;
      await _flick(tester, screen.scroll);
      final start = screen.scroll.offset;
      for (var frame = 0; frame < fps; frame++) {
        game.update(1 / fps);
      }
      expect(screen.scroll.isGliding, isTrue);
      expect(screen.scroll.isOverScrolled, isFalse);
      return screen.scroll.offset - start;
    }

    final at30 = await distanceAt(30);
    final at60 = await distanceAt(60);
    final at120 = await distanceAt(120);
    expect(
      at30,
      closeTo(at120, 1),
      reason: 'same input and elapsed time: 30=$at30, 60=$at60, 120=$at120',
    );
    expect(at60, closeTo(at120, 1));
  });

  _journey(
    'v2 buy Rubber duck → equip all 14 gear and all 14 hats → saved home look',
    height: 730,
    prefs: {
      'coins': 750,
      'ownedItems': [
        for (final id in GearArt.ids) 'gear:$id',
        for (final id in HatArt.ids) 'hat:$id',
      ],
    },
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      screen.scrollToItem('duck');
      await _tap(game, tester, screen.tileFor('duck'));
      await _tap(game, tester, screen.tileFor('duck'));
      expect(game.menu.wallet.balance, 0);
      stepGame(game, 3);
      for (final layer in [SkinLayer.gear, SkinLayer.hat]) {
        await _tab(game, tester, layer);
        final ids = layer == SkinLayer.gear ? GearArt.ids : HatArt.ids;
        expect(ids, hasLength(29)); // PRD-2.3 §19: +15 per layer
        for (final id in ids) {
          screen.scrollToItem(id);
          await _tap(game, tester, screen.tileFor(id));
          expect(game.menu.items.look.bird, 'duck');
          expect(game.menu.items.look.idFor(layer), id);
          expect(screen.previewLook, game.menu.items.look);
          expect(screen.tileFor(id).current.equipped, isTrue);
          stepGame(game, .5);
          if (['windup', 'jetpack', 'carpet', 'wizard', 'halo'].contains(id)) {
            await _shot(game, tester, 'rubber_duck_${layer.key}_$id');
          }
        }
      }
      expect(events.count('item_purchase'), 1);
      expect(events.count('item_equip'), 59); // purchase auto-equips too
      final saved = GameStorage();
      await saved.load();
      expect(saved.equippedItems[SkinLayer.bird], 'duck');
      expect(saved.equippedItems[SkinLayer.gear], GearArt.ids.last);
      expect(saved.equippedItems[SkinLayer.hat], HatArt.ids.last);
      await _tap(game, tester, screen.backButton);
      await _fade(game, tester);
      expect(game.homeScreen!.bird.look, game.menu.items.look);
      expect(game.homeScreen!.bird.look.bird, 'duck');
    },
  );

  _journey(
    'v2 Rubber duck tile purchase → all layers → flap/death → home',
    height: 730,
    prefs: const {'coins': 2000},
    (game, events, tester) async {
      final screen = await _skins(game, tester);
      // Reach the rare row through real input, rather than tapItem/offset.
      for (var i = 0; i < 3; i++) {
        await _flick(tester, screen.scroll, distance: -80, millis: 200);
        await settleMenuScroll(screen.scroll, game, tester);
      }
      // Correct a possible overrun with programmatic positioning: the same
      // path used when the Shop opens a featured item in the grid.
      screen.scrollToItem('duck');
      final duck = screen.tileFor('duck');
      await _tap(game, tester, duck);
      expect(screen.activeItem.name, 'Rubber duck');
      expect(duck.buyPill.label, 'BUY 750');
      await _shot(game, tester, 'rubber_duck_try_on');
      await _tap(game, tester, duck);
      expect(game.menu.items.look.bird, 'duck');
      expect(game.menu.wallet.balance, 1250);
      await _tab(game, tester, SkinLayer.gear);
      await _tap(game, tester, screen.tileFor('shades'));
      await _tap(game, tester, screen.tileFor('shades'));
      await _tab(game, tester, SkinLayer.hat);
      await _tap(game, tester, screen.tileFor('cap'));
      await _tap(game, tester, screen.actionButton);
      const outfit = Look(bird: 'duck', gear: 'shades', hat: 'cap');
      expect(game.menu.items.look, outfit);
      expect(events.count('item_purchase'), 3);
      stepGame(game, 3);
      await flushAndMount(game);
      await _shot(game, tester, 'rubber_duck_dressed');
      await _tap(game, tester, screen.backButton);
      await _fade(game, tester);
      expect(game.homeScreen!.bird.look, outfit);
      await _tap(game, tester, game.homeScreen!.startButton);
      stepGame(game, .1);
      final bird = game.world.children.query<Bird>().single;
      expect(bird.look, outfit);
      game.onScreenTap();
      expect(bird.lookComponent.pose, LookPose.flap);
      await _shot(game, tester, 'rubber_duck_flap');
      // Falls onto the floor spikes, tumbles (PRD-2 §3.0.5), results.
      for (var i = 0; i < 400 && game.state != GameState.results; i++) {
        game.update(1 / 60);
      }
      await flushAndMount(game);
      expect(game.state, GameState.results);
      expect(bird.lookComponent.pose, LookPose.dead);
      expect(bird.look, outfit);
      await _shot(game, tester, 'rubber_duck_dead');
      game.goHome();
      await _fade(game, tester);
      expect(game.homeScreen!.bird.look, outfit);
    },
  );
}
