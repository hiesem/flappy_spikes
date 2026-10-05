import 'dart:async';


import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/shop/shop_screen.dart';
import 'package:flappy_spikes/components/ui/service_message.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/skin_catalog.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// Records analytics events instead of sending them.
class EventSpy extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  List<String> get names => events.map((e) => e.$1).toList();

  Map<String, Object>? last(String name) =>
      events.lastWhere((e) => e.$1 == name).$2;

  int count(String name) => names.where((n) => n == name).length;

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }
}

/// Mutable test clock (injected into the game's storage).
class TestClock {
  DateTime now = DateTime(2026, 5, 10, 12);
  DateTime call() => now;

  /// Local day number as GameStorage computes it.
  int get today {
    final t = now;
    return DateTime.utc(t.year, t.month, t.day)
        .difference(DateTime.utc(1970))
        .inDays;
  }
}

/// Lets fire-and-forget persistence writes, the fake store's zero-length
/// "round trip" (a Future.delayed timer: fires when fake time elapses) and
/// the resulting stream events land.
late WidgetTester _tester;
Future<void> settle(FlappySpikesGame game) async {
  for (var round = 0; round < 3; round++) {
    for (var i = 0; i < 20; i++) {
      await Future<void>.value();
    }
    await _tester.binding.delayed(Duration.zero);
  }
  await flushAndMount(game);
}

/// Opens the Shop (tile) and lets the fades finish.
Future<ShopScreen> openShop(
  FlappySpikesGame game, {
  bool scrollToCoins = false,
}) async {
  game.openShop(scrollToCoins: scrollToCoins);
  await flushAndMount(game);
  stepGame(game, 0.6);
  await flushAndMount(game);
  return game.shopScreen!;
}

String? toastText(FlappySpikesGame game) {
  final toasts = game.world.children.query<ServiceMessage>();
  return toasts.isEmpty ? null : toasts.last.message;
}

KeyDownEvent escape() => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.escape,
  logicalKey: LogicalKeyboardKey.escape,
  timeStamp: Duration.zero,
);

/// Absolute rect of a component inside the Shop's scroll content, in
/// world coordinates as laid out (scroll offset 0).
Rect contentRect(PositionComponent c) =>
    Rect.fromLTWH(c.x, c.y, c.width, c.height);

void shopTest(
  String name, {
  Map<String, Object> prefs = const {},
  double height = 711,
  FakeAdMode adMode = FakeAdMode.succeed,
  FakeIapMode iapMode = FakeIapMode.succeed,
  TestClock? clock,
  bool fakeAdOverlay = false,
  bool exactSurface = false,
  required Future<void> Function(
    FlappySpikesGame game,
    EventSpy spy,
    FakeRewardedAds ads,
    FakeIapService iap,
    WidgetTester tester,
  )
  verify,
}) {
  final spy = EventSpy();
  final ads = FakeRewardedAds()..mode = adMode;
  final iap = FakeIapService()..mode = iapMode;
  final testClock = clock ?? TestClock();
  FlameTester<FlappySpikesGame>(
    () {
      SharedPreferences.setMockInitialValues(prefs);
      return FlappySpikesGame(
        worldHeight: height,
        services: spy,
        monetization: Monetization(ads: ads, iap: iap)
          ..showFakeAdOverlay = fakeAdOverlay,
        clock: testClock.call,
        soundEnabled: false,
      );
    },
    gameSize: Vector2(320, height),
    pumpWidget: exactSurface
        ? (gameWidget, tester) async {
            tester.view
              ..physicalSize = Size(320, height)
              ..devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(gameWidget);
          }
        : null,
  ).testGameWidget(
    name,
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) {
      _tester = tester;
      // onLoad ran inside FlameTester's runAsync (the real zone), so the
      // game's IAP subscription would deliver there — never while the fake
      // async test body runs. Re-subscribe from the test zone.
      game.purchases
        ..dispose()
        ..start();
      return verify(game, spy, ads, iap, tester);
    },
  );
}

void main() {
  group('Shop screen layout', () {
    shopTest(
      'S1-B rects at 711 (no scrolling)',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        const h = 711.0;
        expect(shop.banner.toRect(), const Rect.fromLTWH(14, 146, 292, 52));
        expect(shop.freeCoins.toRect(), const Rect.fromLTWH(14, 206, 292, 44));
        expect(shop.packs.map((p) => p.toRect()).toList(), const [
          Rect.fromLTWH(14, 266, 142, 150),
          Rect.fromLTWH(164, 266, 142, 150),
          Rect.fromLTWH(14, 426, 142, 150),
          Rect.fromLTWH(164, 426, 142, 150),
        ]);
        expect(shop.packs.map((p) => p.product).toList(), [
          IapProduct.coins500,
          IapProduct.coins1800,
          IapProduct.coins5000,
          IapProduct.coins12000,
        ]);
        expect(shop.packs.map((p) => p.amount.text).toList(), [
          '500',
          '1,800',
          '5,000',
          '12,000',
        ]);
        // Tags: MOST POPULAR on 1,800, BEST DEAL on 12,000, 24 tall,
        // centred on the top edge.
        expect(shop.packs[0].tagComponent, isNull);
        expect(shop.packs[2].tagComponent, isNull);
        for (final i in [1, 3]) {
          final tag = shop.packs[i].tagComponent!;
          expect(tag.height, 24);
          expect(tag.y, -12);
          expect(tag.x + tag.width / 2, closeTo(71, 1e-9));
        }
        for (final card in shop.packs) {
          expect(card.priceButton.toRect(),
              const Rect.fromLTWH(0, 112, 142, 38));
        }
        expect(
          shop.featured.toRect(),
          const Rect.fromLTWH(14, 588, 292, 56),
        );
        expect(shop.restoreLink.center.x, 160);
        expect(shop.restoreLink.y, lessThan(Config.shopRestoreTop));
        // Chrome.
        expect(shop.coinPill.toRect().topRight, const Offset(306, 58));
        expect(shop.backButton.toRect(), const Rect.fromLTWH(14, 58, 38, 38));
        expect(shop.titleText.text, 'SHOP');
        expect(shop.titleText.position, Vector2(160, 104));
        // Everything fits above the bottom spike tips at 711.
        expect(shop.scroll.viewport.bottom, h - 44);
        expect(shop.scroll.scrollable, isFalse);
        expect(Config.shopContentBottomFor(h), lessThanOrEqualTo(h - 44));
        // Placeholder store prices.
        expect(shop.banner.price, '€2.99');
        expect(shop.packs.map((p) => p.priceLabel.text).toList(), [
          '€0.99',
          '€2.99',
          '€6.99',
          '€14.99',
        ]);
      },
    );

    shopTest(
      'at 568 the content scrolls (no overlaps) and reaches the restore link',
      height: 568,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final rects = [
          contentRect(shop.banner),
          contentRect(shop.freeCoins),
          ...shop.packs.map(contentRect),
          contentRect(shop.featured),
          contentRect(shop.restoreLink),
        ];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse,
                reason: '$i overlaps $j');
          }
        }
        final scroll = shop.scroll;
        expect(scroll.viewport.top, greaterThanOrEqualTo(142));
        expect(scroll.viewport.bottom, 568 - 44);
        expect(scroll.scrollable, isTrue);
        scroll.offset = 1e6;
        expect(scroll.offset, scroll.maxOffset);
        final linkBottom = scroll.screenY(Config.shopContentBottomFor(568));
        expect(linkBottom, lessThanOrEqualTo(scroll.viewport.bottom));
        final linkTop = scroll.screenY(Config.shopRestoreTop);
        expect(linkTop, greaterThan(scroll.viewport.top));
        scroll.offset = -5;
        expect(scroll.offset, 0);
      },
    );

    shopTest(
      'drag scrolls the content at 568; taps outside the viewport miss it',
      height: 568,
      exactSurface: true,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        await tester.timedDragFrom(
          const Offset(160, 450),
          const Offset(0, -100),
          const Duration(milliseconds: 300),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(shop.scroll.offset, greaterThan(60));
        expect(game.state, GameState.start);
        expect(game.menuScene, MenuScene.shop);

        // Scroll all the way: the restore link is tappable.
        shop.scroll.offset = shop.scroll.maxOffset;
        final y = shop.scroll.screenY(Config.shopRestoreTop + 7);
        await tester.tapAt(Offset(160, y));
        await tester.pump(const Duration(milliseconds: 50));
        expect(game.purchases.restoring, isTrue);
      },
    );
  });

  group('Shop navigation', () {
    shopTest(
      'tile opens the Shop over a hidden home; back / Esc return home '
      '(not a new arrival)',
      verify: (game, spy, ads, iap, tester) async {
        expect(game.storage.slotHistory, hasLength(1));
        final shop = await openShop(game);
        expect(game.menuScene, MenuScene.shop);
        expect(game.homeScreen, isNull);
        expect(game.world.children.query<HomeScreen>(), isEmpty);
        expect(spy.last('shop_open'), {'source': 'tile'});
        expect(shop.opacity, 1);

        // Space does not start a run from the Shop.
        game.onScreenTap();
        expect(game.state, GameState.start);

        shop.backButton.onPressed();
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.shopScreen, isNull);
        expect(game.homeScreen, isNotNull);
        expect(game.storage.slotHistory, hasLength(1));
        expect(spy.count('home_slot_shown'), 1);

        await openShop(game);
        expect(game.onKeyEvent(escape(), {}), isNotNull);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.home);
        expect(game.homeScreen, isNotNull);
        stepGame(game, 0.6);
        await flushAndMount(game);
        expect(game.world.children.query<ShopScreen>(), isEmpty);
      },
    );

    shopTest(
      'pill "+" opens the Shop at the packs, and scrolls there inside it',
      height: 568,
      verify: (game, spy, ads, iap, tester) async {
        game.homeScreen!.coinPill.onPressed();
        await flushAndMount(game);
        stepGame(game, 0.6);
        await flushAndMount(game);
        final shop = game.shopScreen!;
        expect(spy.last('shop_open'), {'source': 'pill'});
        final anchor = Config.shopCoinsAnchorFor(568);
        expect(shop.scroll.offset, anchor - shop.scroll.viewport.top);
        expect(shop.scroll.screenY(anchor), shop.scroll.viewport.top);

        shop.scroll.offset = 0;
        shop.coinPill.onPressed();
        stepGame(game, 0.5);
        expect(shop.scroll.offset, anchor - shop.scroll.viewport.top);
        expect(spy.count('shop_open'), 1, reason: 'no second open');
        // The tag of the first pack row is in view.
        expect(
          shop.scroll.screenY(Config.shopPackRowTop - 12),
          greaterThanOrEqualTo(shop.scroll.viewport.top),
        );
      },
    );

    shopTest(
      'featured skin = cheapest locked skin; hidden when all are owned',
      prefs: const {
        'ownedSkins': ['pink', 'blue', 'green'],
      },
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        expect(shop.featured.skin?.id, 'purple');
        expect(shop.featured.nameText, 'GRAPE');
        await game.storage.saveOwnedSkins({for (final s in kSkins) s.id});
        game.update(0);
        await flushAndMount(game);
        expect(shop.featured.skin, isNull);
        expect(shop.featured.containsLocalPoint(Vector2(10, 10)), isFalse);
      },
    );

    shopTest(
      'featured row opens Skins at that skin (see skins_flow_test)',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        shop.featured.onPressed();
        await flushAndMount(game);
        expect(spy.last('skins_open'), {'source': 'shop_featured'});
        expect(game.menuScene, MenuScene.skins);
      },
    );
  });

  group('free coins', () {
    final clock = TestClock();
    shopTest(
      'claim -> +40, cooldown "mm:ss", 5 per day -> TOMORROW, next day resets',
      clock: clock,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        expect(shop.freeCoins.chipText, 'WATCH');
        expect(shop.freeCoins.chipDimmed, isFalse);

        await game.claimFreeCoins();
        await settle(game);
        expect(ads.placements, [AdPlacement.shopFreeCoins]);
        expect(game.menu.wallet.balance, 40);
        expect(spy.last('ad_rewarded_shown'), {
          'placement': 'shop_free_coins',
        });
        expect(spy.last('coins_earned'), {'amount': 40, 'source': 'rewarded'});
        expect(toastText(game), '+40 coins');
        expect(shop.freeCoins.chipText, '05:00');
        expect(shop.freeCoins.chipDimmed, isTrue);
        expect(shop.freeCoins.tappable, isFalse);

        // Blocked during the cooldown.
        await game.claimFreeCoins();
        expect(ads.shown, 1);
        clock.now = clock.now.add(const Duration(minutes: 3));
        game.update(0);
        expect(shop.freeCoins.chipText, '02:00');

        for (var i = 0; i < 4; i++) {
          clock.now = clock.now.add(const Duration(minutes: 5));
          game.update(0);
          await game.claimFreeCoins();
          await settle(game);
        }
        expect(ads.shown, 5);
        expect(game.menu.wallet.balance, 200);
        clock.now = clock.now.add(const Duration(minutes: 5));
        game.update(0);
        expect(shop.freeCoins.chipText, 'TOMORROW');
        await game.claimFreeCoins();
        expect(ads.shown, 5);

        clock.now = clock.now.add(const Duration(days: 1));
        game.update(0);
        expect(shop.freeCoins.chipText, 'WATCH');
      },
    );

    shopTest(
      'no ad available: chip dimmed, toast, nothing claimed',
      adMode: FakeAdMode.unavailable,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        expect(shop.freeCoins.chipText, 'WATCH');
        expect(shop.freeCoins.chipDimmed, isTrue);
        expect(shop.freeCoins.tappable, isTrue, reason: 'tap -> toast');
        await game.claimFreeCoins();
        await settle(game);
        expect(toastText(game), 'No video available right now');
        expect(game.menu.freeCoins.claimedToday, 0);
        expect(game.menu.wallet.balance, 0);
        // The toast is a chip above the bottom spikes in the Shop.
        final toast = game.world.children.query<ServiceMessage>().single;
        expect(toast.chip, isTrue);
        expect(toast.position, Config.menuScreenToastPositionFor(711));
      },
    );

    shopTest(
      'ad failed: toast, nothing claimed',
      adMode: FakeAdMode.fail,
      verify: (game, spy, ads, iap, tester) async {
        await openShop(game);
        await game.claimFreeCoins();
        await settle(game);
        expect(toastText(game), 'No video available right now');
        expect(game.menu.freeCoins.claimedToday, 0);
        expect(spy.names, isNot(contains('ad_rewarded_shown')));
      },
    );

    shopTest(
      'fake ad overlay (Linux): +40 only after the countdown; '
      'Esc closes the overlay, not the Shop',
      fakeAdOverlay: true,
      verify: (game, spy, ads, iap, tester) async {
        // 60 fps frames: one update never exceeds Config.maxFrameStep.
        void advance(double seconds) => stepGame(game, seconds);

        await openShop(game);
        final claim = game.claimFreeCoins();
        await flushAndMount(game);
        final overlay = game.fakeAdOverlay!;
        expect(overlay.placement, AdPlacement.shopFreeCoins);
        expect(game.freeCoinsBusy, isTrue);
        advance(Config.fakeAdCountdown + Config.fakeAdResultHold + 0.05);
        await claim;
        await settle(game);
        expect(game.fakeAdOverlay, isNull);
        expect(game.menu.wallet.balance, 40);
        expect(toastText(game), '+40 coins');

        // Second claim after the cooldown, closed early with Esc.
        game.storage.freeCoinsLastMs = 0;
        final again = game.claimFreeCoins();
        await flushAndMount(game);
        expect(game.fakeAdOverlay, isNotNull);
        game.onKeyEvent(escape(), {});
        await again;
        await settle(game);
        expect(game.fakeAdOverlay, isNull);
        expect(game.shopScreen, isNotNull, reason: 'Esc only closed the ad');
        expect(game.menu.wallet.balance, 40);
        expect(toastText(game), 'No video available right now');
      },
    );

    shopTest(
      'No-ads owners claim free coins without an ad (CLAIM chip)',
      prefs: const {'noAds': true},
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        game.update(0);
        expect(shop.freeCoins.chipText, 'CLAIM');
        expect(
          shop.freeCoins.chipDimmed,
          isFalse,
          reason: 'owners need no ad, so availability cannot dim the chip',
        );
        await game.claimFreeCoins();
        await settle(game);
        expect(ads.shown, 0);
        expect(game.menu.wallet.balance, 40);
        expect(spy.last('coins_earned'), {'amount': 40, 'source': 'rewarded'});
        expect(spy.names, isNot(contains('ad_rewarded_shown')));
      },
    );
  });

  group('IAP', () {
    shopTest(
      'coin pack purchase -> balance, analytics, toast',
      prefs: const {'coins': 5},
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        shop.packs[1].onPressed(); // 1,800
        await settle(game);
        expect(iap.purchases, [IapProduct.coins1800]);
        expect(game.menu.wallet.balance, 1805);
        expect(spy.last('iap_purchase'), {'product': 'coins_1800'});
        expect(spy.last('coins_earned'), {'amount': 1800, 'source': 'iap'});
        expect(toastText(game), '+1,800 coins');
        expect(game.purchases.isPending(IapProduct.coins1800), isFalse);
        expect(shop.packs[1].tappable, isTrue);
        // The pill follows the balance.
        expect(shop.coinPill.balance, 1805);
      },
    );

    shopTest(
      'pending: toast, card disabled while pending, no coins',
      iapMode: FakeIapMode.pending,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        shop.packs[0].onPressed();
        await settle(game);
        expect(toastText(game), 'Purchase pending…');
        expect(game.purchases.isPending(IapProduct.coins500), isTrue);
        game.update(0);
        expect(shop.packs[0].pending, isTrue);
        expect(shop.packs[0].tappable, isFalse);
        expect(shop.packs[0].dimmed, isTrue);
        expect(shop.packs[1].tappable, isTrue);
        // A second press is ignored while pending.
        await game.buyProduct(IapProduct.coins500);
        expect(iap.purchases, hasLength(1));
        expect(game.menu.wallet.balance, 0);
      },
    );

    shopTest(
      'failed -> "Purchase failed: <reason>"; canceled -> silent; both re-enable',
      iapMode: FakeIapMode.fail,
      verify: (game, spy, ads, iap, tester) async {
        // Opening the Shop re-queries missing store prices.
        final refreshes = iap.refreshes;
        final shop = await openShop(game);
        expect(iap.refreshes, refreshes + 1);
        // ...and so does coming back from the background.
        game.lifecycleStateChange(AppLifecycleState.resumed);
        expect(iap.refreshes, refreshes + 2);
        shop.packs[2].onPressed();
        await settle(game);
        expect(toastText(game), 'Purchase failed: Fake error');
        expect(spy.last('iap_error'), {
          'product': 'coins_5000',
          'reason': 'Fake error',
          'code': 'fake',
        });
        expect(game.purchases.isPending(IapProduct.coins5000), isFalse);
        expect(game.menu.wallet.balance, 0);

        // Let the toast expire, then cancel a purchase.
        stepGame(game, 4);
        await flushAndMount(game);
        expect(toastText(game), isNull);
        iap.mode = FakeIapMode.cancel;
        shop.packs[2].onPressed();
        await settle(game);
        // Only the store's "pending" step toasted; no failure message.
        expect(toastText(game), 'Purchase pending…');
        expect(game.purchases.isPending(IapProduct.coins5000), isFalse);
        expect(spy.names, isNot(contains('iap_purchase')));
      },
    );

    shopTest(
      'No ads purchase from the Shop banner: flag + 1,000 bonus, '
      'home tile / slot / Shop banner update',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        shop.banner.onPressed();
        await flushAndMount(game);
        // PO 2026-10-05: the banner buys straight away — no popup.
        expect(game.noAdsPopup, isNull);
        expect(spy.last('noads_purchase_tapped'), {'source': 'shop_banner'});
        expect(spy.names, isNot(contains('noads_popup_shown')));
        await settle(game);
        expect(iap.purchases, [IapProduct.noAds]);
        expect(game.menu.noAds, isTrue);
        expect(game.menu.wallet.balance, 1000);
        expect(spy.names, contains('noads_purchased'));
        expect(spy.last('coins_earned'), {
          'amount': 1000,
          'source': 'noads_bonus',
        });
        expect(spy.names, isNot(contains('noads_popup_dismissed')));
        expect(toastText(game), 'Ads removed · +1,000 coins');
        game.update(0);
        expect(shop.banner.owned, isTrue);
        expect(shop.banner.labelText, 'AD-FREE');
        expect(shop.banner.checkIcon, isNotNull, reason: 'check in icon slot');
        expect(
          shop.banner.label!.x + shop.banner.label!.width,
          lessThan(shop.banner.width),
        );
        expect(shop.banner.price, isNull);
        expect(shop.banner.tappable, isFalse);

        // Home: tile shows AD-FREE, the slot starts the run without an ad.
        shop.backButton.onPressed();
        await flushAndMount(game);
        final home = game.homeScreen!;
        expect(home.noAdsTile.owned, isTrue);
        game.update(0);
        expect(home.slotButton.labelText, isNotEmpty);
        expect(home.slotButton.showsVideo, isFalse);
        await game.tapPowerupSlot();
        expect(ads.shown, 0);
        expect(game.state, GameState.playing);
        expect(game.menu.slot.armed, Powerup.none, reason: 'consumed');

        // A store re-delivery never grants the bonus twice.
        unawaited(iap.buy(IapProduct.noAds));
        await settle(game);
        expect(game.menu.wallet.balance, 1000);
      },
    );

    shopTest(
      'pending No-ads purchase disables the home tile and Shop banner',
      iapMode: FakeIapMode.pending,
      verify: (game, spy, ads, iap, tester) async {
        game.homeScreen!.noAdsTile.onPressed();
        await settle(game);
        expect(toastText(game), 'Purchase pending…');
        game.update(0);
        final tile = game.homeScreen!.noAdsTile;
        expect(tile.dimmed, isTrue);
        expect(tile.tappable, isFalse);
        // A second tap is ignored while pending.
        tile.onPressed();
        expect(iap.purchases, hasLength(1));

        final shop = await openShop(game);
        await flushAndMount(game);
        expect(shop.banner.dimmed, isTrue);
        expect(shop.banner.tappable, isFalse);
        shop.banner.onPressed();
        expect(iap.purchases, hasLength(1));
      },
    );

    shopTest(
      'restore: owned No ads comes back without the bonus',
      verify: (game, spy, ads, iap, tester) async {
        // Bought on "another device": the fake store owns it.
        unawaited(iap.buy(IapProduct.noAds));
        await settle(game);
        await game.menu.setNoAds(false);
        final balance = game.menu.wallet.balance;
        final shop = await openShop(game);
        shop.restoreLink.onPressed();
        await settle(game);
        expect(game.menu.noAds, isTrue);
        expect(game.menu.wallet.balance, balance, reason: 'no bonus');
        expect(toastText(game), 'Purchases restored');
        stepGame(game, Config.restoreTimeout + 1);
        await flushAndMount(game);
        expect(toastText(game), isNot('Nothing to restore'));
      },
    );

    shopTest(
      'restore with nothing owned -> "Nothing to restore" after the timeout',
      verify: (game, spy, ads, iap, tester) async {
        await openShop(game);
        await game.restorePurchases();
        await settle(game);
        expect(toastText(game), isNull);
        stepGame(game, Config.restoreTimeout - 0.5);
        await flushAndMount(game);
        expect(toastText(game), isNull);
        stepGame(game, 1);
        await flushAndMount(game);
        expect(toastText(game), 'Nothing to restore');
        expect(game.menu.noAds, isFalse);
      },
    );

    shopTest(
      'Settings has a RESTORE PURCHASES link below the privacy link',
      height: 568,
      verify: (game, spy, ads, iap, tester) async {
        game.openSettings();
        await flushAndMount(game);
        final panel = game.world.children.query<SettingsPanel>().single;
        final link = panel.restoreLink!;
        expect(
          link.center,
          Config.settingsRestoreLinkPositionFor(284),
        );
        expect(link.center.y, greaterThan(Config.privacyLinkPositionFor(284).y));
        expect(link.toRect().bottom, lessThanOrEqualTo(568 - 44));
        link.button.onPressed();
        await settle(game);
        expect(game.purchases.restoring, isTrue);
        stepGame(game, Config.restoreTimeout + 0.1);
        await flushAndMount(game);
        expect(toastText(game), 'Nothing to restore');
      },
    );
  });

  group('No-ads popup', () {
    shopTest(
      'P1 card geometry at 711 and 568',
      verify: (game, spy, ads, iap, tester) async {
        game.openNoAdsPopup();
        await flushAndMount(game);
        final popup = game.noAdsPopup!;
        expect(popup.card.toRect(), const Rect.fromLTWH(20, 190, 280, 369));
        expect(popup.closeButton.toRect(),
            const Rect.fromLTWH(242, 0, 38, 38));
        expect(popup.priceButton.toRect(),
            const Rect.fromLTWH(16, 299, 248, 54));
        expect(popup.priceLabel.text, '€2.99');
        expect(popup.size, Vector2(320, 711));
        // Card on the same centred band at 568.
        final at568 = Config.noAdsCardRectFor(568);
        expect(at568.center.dy - 284, closeTo(Config.noAdsCardRectFor(711)
            .center.dy - 355.5, 1e-9));
        expect(at568.top, greaterThan(44));
        expect(at568.bottom, lessThan(568 - 44));
      },
    );

    shopTest(
      'home tile: starts the purchase straight away, no popup',
      verify: (game, spy, ads, iap, tester) async {
        game.homeScreen!.noAdsTile.onPressed();
        await flushAndMount(game);
        // PO 2026-10-05: no popup, no dismissal bookkeeping.
        expect(game.noAdsPopup, isNull);
        expect(spy.last('noads_purchase_tapped'), {'source': 'home_tile'});
        expect(spy.names, isNot(contains('noads_popup_shown')));
        await settle(game);
        expect(iap.purchases, [IapProduct.noAds]);
        expect(game.menu.noAds, isTrue);
        expect(game.menu.wallet.balance, 1000);
        expect(toastText(game), 'Ads removed · +1,000 coins');
        expect(game.storage.noAdsPopupDismissals, 0);
      },
    );

    shopTest(
      'Esc closes the popup first, then the Shop',
      verify: (game, spy, ads, iap, tester) async {
        await openShop(game);
        game.openNoAdsPopup();
        await flushAndMount(game);
        expect(game.noAdsPopup, isNotNull);
        game.onKeyEvent(escape(), {});
        await flushAndMount(game);
        expect(game.noAdsPopup, isNull);
        expect(game.menuScene, MenuScene.shop);
        game.onKeyEvent(escape(), {});
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.home);
      },
    );

    shopTest(
      'real taps: the card swallows taps, the dim dismisses',
      height: 568,
      exactSurface: true,
      verify: (game, spy, ads, iap, tester) async {
        game.openNoAdsPopup();
        await flushAndMount(game);
        stepGame(game, 0.3);
        final card = Config.noAdsCardRectFor(568);
        // Benefit text area of the card.
        await tester.tapAt(Offset(200, card.top + 200));
        await tester.pump(const Duration(milliseconds: 50));
        expect(game.noAdsPopup, isNotNull);
        expect(game.state, GameState.start);
        // The dim above the card (over the home title).
        await tester.tapAt(Offset(160, card.top - 20));
        await tester.pump(const Duration(milliseconds: 50));
        expect(game.noAdsPopup, isNull);
        expect(spy.last('noads_popup_dismissed'), {'trigger': 'launch'});
        expect(game.state, GameState.start, reason: 'no run started');
      },
    );

    shopTest(
      'owners get "Already ad-free"; never opens during a run',
      prefs: const {'noAds': true},
      verify: (game, spy, ads, iap, tester) async {
        // The owned tile is still tappable: unchanged toast, no funnel
        // event and absolutely no popup.
        game.homeScreen!.noAdsTile.onPressed();
        await flushAndMount(game);
        expect(game.noAdsPopup, isNull);
        expect(toastText(game), 'Already ad-free');
        expect(spy.names, isNot(contains('noads_purchase_tapped')));
        await game.menu.setNoAds(false);
        game.onScreenTap(); // starts a run
        game.openNoAdsPopup();
        expect(game.noAdsPopup, isNull);
        expect(spy.names, isNot(contains('noads_popup_shown')));
      },
    );

    shopTest(
      'pending purchase disables the popup price button',
      iapMode: FakeIapMode.pending,
      verify: (game, spy, ads, iap, tester) async {
        game.openNoAdsPopup();
        await flushAndMount(game);
        final popup = game.noAdsPopup!;
        popup.priceButton.onPressed();
        await settle(game);
        expect(popup.priceButton.tappable, isFalse);
        expect(popup.priceButton.dimmed, isTrue);
        expect(toastText(game), 'Purchase pending…');
        // Toasts over the popup sit below its card.
        expect(
          game.world.children.query<ServiceMessage>().last.position,
          Config.noAdsToastPositionFor(711),
        );
      },
    );
  });

  group('launch auto-trigger', () {
    final day2 = TestClock();
    shopTest(
      'day >= 2 after install: shown on launch once (trigger launch); '
      'dismissing counts',
      clock: day2,
      prefs: {'installDay': day2.today - 1},
      verify: (game, spy, ads, iap, tester) async {
        final popup = game.noAdsPopup;
        expect(popup, isNotNull);
        // START is blocked while the popup is up.
        game.onScreenTap();
        expect(game.state, GameState.start);
        expect(spy.last('noads_popup_shown'), {'trigger': 'launch'});
        await settle(game);
        expect(game.storage.noAdsPopupLastDay, day2.today);
        expect(game.menu.noAdsPopup.shouldShowOnLaunch(), isFalse,
            reason: 'max once per day');
        game.handleBack();
        await settle(game);
        expect(game.storage.noAdsPopupDismissals, 1);
        expect(spy.last('noads_popup_dismissed'), {'trigger': 'launch'});
      },
    );

    shopTest(
      'install day: not shown',
      verify: (game, spy, ads, iap, tester) async {
        expect(game.noAdsPopup, isNull);
        expect(spy.names, isNot(contains('noads_popup_shown')));
      },
    );

    final capped = TestClock();
    shopTest(
      'after three dismissals: not shown',
      clock: capped,
      prefs: {'installDay': capped.today - 5, 'noAdsPopupDismissals': 3},
      verify: (game, spy, ads, iap, tester) async {
        expect(game.noAdsPopup, isNull);
      },
    );

    final owner = TestClock();
    shopTest(
      'owners: not shown',
      clock: owner,
      prefs: {'installDay': owner.today - 5, 'noAds': true},
      verify: (game, spy, ads, iap, tester) async {
        expect(game.noAdsPopup, isNull);
      },
    );
  });

  test('formatAmount groups thousands with commas', () {
    expect(formatAmount(500), '500');
    expect(formatAmount(1800), '1,800');
    expect(formatAmount(12000), '12,000');
    expect(formatAmount(1234567), '1,234,567');
  });

  test('FreeCoinsRow.formatCooldown rounds up to whole seconds', () {
    expect(FreeCoinsRow.formatCooldown(const Duration(minutes: 5)), '05:00');
    expect(
      FreeCoinsRow.formatCooldown(const Duration(seconds: 59, milliseconds: 1)),
      '01:00',
    );
    expect(FreeCoinsRow.formatCooldown(const Duration(seconds: 1)), '00:01');
  });
}
