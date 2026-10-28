import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/noads_celebration.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayPurchaseDetails;

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;
import '../services/store_iap_service_test.dart' show FakeStore;

/// PRD-2.3 §22 gift codes, app side (§22.6 Flutter tests, fake store):
/// the launch / resume sync, grant once per purchase id, consume, the No
/// Ads gift's coins only once, the promo `no_ads`, the gift products kept
/// out of the Shop and the price queries, and the gift popup (menus only,
/// one per code, before the No-Ads popup, PRD §0 item 2).
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  // The game under test's fake store / analytics (FlameTester may build
  // the games of several tests before running them: read them per game).
  late FlappySpikesGame current;
  late WidgetTester currentTester;
  FakeIapService fakeStore() => current.monetization.iap as FakeIapService;
  AnalyticsSpy spyOf() => current.services as AnalyticsSpy;
  var now = DateTime(2026, 10, 13, 12);

  FlappySpikesGame make({
    Map<String, Object> prefs = const {},
    void Function(FakeIapService iap)? store,
  }) {
    final fake = FakeIapService();
    store?.call(fake);
    now = DateTime(2026, 10, 13, 12);
    return createRunTestGame(
      prefs: prefs,
      worldHeight: 711,
      services: AnalyticsSpy(),
      monetization: Monetization(iap: fake),
      clock: () => now,
    );
  }

  Future<void> boot(FlappySpikesGame g, WidgetTester tester) async {
    current = g;
    currentTester = tester;
    now = DateTime(2026, 10, 13, 12);
    await g.ready();
    await preloadImages(g);
    await g.images.loadAll(kNoAdsCelebrationImages);
    await flushAndMount(g);
  }

  /// Microtasks, zero timers (prefs, image futures) and mounting.
  Future<void> drain(FlappySpikesGame g) async {
    for (var round = 0; round < 4; round++) {
      for (var i = 0; i < 20; i++) {
        await Future<void>.value();
      }
      await TestWidgetsFlutterBinding.instance.delayed(Duration.zero);
      await flushAndMount(g);
    }
    // Popup onLoads (image futures) and some prefs writes finish on real
    // async.
    await currentTester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await flushAndMount(g);
  }

  /// Lets the launch sync's grants and popups settle (in verify).
  Future<void> launched(FlappySpikesGame g) async {
    await drain(g);
    stepGame(g, .5);
    await flushAndMount(g);
  }

  Future<void> settle(FlappySpikesGame g, [double seconds = .5]) async {
    await drain(g);
    stepGame(g, seconds);
    await drain(g);
  }

  /// CLAIM on the gift popup; lets the coins land.
  Future<void> claim(FlappySpikesGame g) async {
    await drain(g);
    g.noAdsCelebration!.claimButton.onPressed();
    await settle(g, 3);
    await settle(g, 2);
  }

  void resume(FlappySpikesGame g) {
    g.lifecycleStateChange(AppLifecycleState.inactive);
    g.lifecycleStateChange(AppLifecycleState.hidden);
    g.lifecycleStateChange(AppLifecycleState.paused);
    g.lifecycleStateChange(AppLifecycleState.hidden);
    g.lifecycleStateChange(AppLifecycleState.inactive);
    g.lifecycleStateChange(AppLifecycleState.resumed);
  }

  int gifts() => spyOf().events.where((e) => e.$1 == 'gift_redeemed').length;

  // --- grants -----------------------------------------------------------------

  FlameTester<FlappySpikesGame>(
    () => make(
      prefs: const {'coins': 100},
      store: (s) => s.redeem(IapProduct.giftCoins10000, 'GPA.gift-1'),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 a gift_coins_10000 delivered on launch credits 10,000 coins once, '
    'is consumed and shows the gift popup',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      expect(fakeStore().syncs, 1, reason: 'the launch sync');
      expect(g.menu.wallet.balance, 10100);
      expect(fakeStore().consumed, ['GPA.gift-1']);
      expect(fakeStore().held, isEmpty);
      final popup = g.noAdsCelebration!;
      expect(popup.gift!.product, IapProduct.giftCoins10000);
      expect(popup.title, NoAdsCelebration.giftTitle);
      expect(popup.title, 'A GIFT FOR YOU!');
      expect(popup.message, '10,000 coins');
      expect(popup.bonusCoins, 10000);
      expect(g.coinPill.target, 100, reason: 'the pill waits for CLAIM');
      expect(spyOf().events.where((e) => e.$1 == 'gift_redeemed').single.$2, {
        'product': 'gift_coins_10000',
        'source': 'promo',
      });
      await tester.runAsync(() => captureShot(g, 2, 'p23_s22_gift_coins'));
      await claim(g);
      expect(g.noAdsCelebration, isNull);
      expect(g.coinPill.target, 10100);
      // A later sync finds nothing (consumed).
      now = now.add(const Duration(seconds: 6));
      resume(g);
      await settle(g);
      expect(fakeStore().syncs, 2);
      expect(g.menu.wallet.balance, 10100);
      expect(gifts(), 1);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 the same purchase delivered twice credits once; a second gift '
    'purchase with a new id credits again',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      IapEvent gift(String id) => IapEvent.store(
        IapProduct.giftCoins10000,
        IapStatus.purchased,
        transactionIds: ['id:$id', 'token:t-$id'],
        acknowledged: false,
      );
      fakeStore().deliver(gift('A'));
      fakeStore().deliver(gift('A'));
      await settle(g);
      expect(g.menu.wallet.balance, 10000);
      expect(gifts(), 1);
      await claim(g);
      expect(g.noAdsCelebration, isNull, reason: 'one popup for one code');
      fakeStore().deliver(gift('B'));
      await settle(g);
      expect(g.menu.wallet.balance, 20000);
      expect(gifts(), 2);
      expect(g.noAdsCelebration, isNotNull);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(
      store: (s) => s.redeem(IapProduct.giftNoAdsCoins10000, 'GPA.noads-1'),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 gift_noads_coins_10000 turns No Ads on and credits 10,000 once; a '
    'restore afterwards brings back No Ads without coins',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      expect(g.menu.noAds, isTrue);
      expect(g.menu.wallet.balance, 10000);
      final popup = g.noAdsCelebration!;
      expect(popup.gift!.noAds, isTrue);
      expect(popup.message, 'No Ads + 10,000 coins');
      expect(g.noAdsShown, isFalse, reason: 'the owned looks wait');
      await tester.runAsync(() => captureShot(g, 2, 'p23_s22_gift_noads'));
      await claim(g);
      expect(g.noAdsShown, isTrue);
      expect(fakeStore().held.single.acknowledged, isTrue);
      expect(
        fakeStore().consumed,
        isEmpty,
        reason: 'one-time: acknowledged only',
      );

      // Settings → Restore purchases: No Ads only.
      await g.menu.setNoAds(false);
      await g.restorePurchases();
      await settle(g);
      expect(g.menu.noAds, isTrue);
      expect(g.menu.wallet.balance, 10000);
      expect(g.noAdsCelebration, isNull);
      expect(gifts(), 1);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(
      store: (s) => s.held.add(
        FakeHeldPurchase(
          IapProduct.giftNoAdsCoins10000,
          'GPA.noads-old',
          acknowledged: true,
        ),
      ),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.2 after a reinstall (granted ids gone) the acknowledged No Ads '
    'gift restores No Ads silently, never the coins',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      expect(g.menu.noAds, isTrue);
      expect(g.menu.wallet.balance, 0);
      expect(g.noAdsCelebration, isNull);
      expect(gifts(), 0);
      expect(g.queuedPopups, 0);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(store: (s) => s.redeem(IapProduct.noAds, 'GPA.promo-noads')),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 a no_ads promo purchase behaves like a bought one (No Ads + its '
    '1,000 bonus coins), with the gift popup',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      expect(g.menu.noAds, isTrue);
      expect(g.menu.wallet.balance, kNoAdsBonusCoins);
      expect(g.storage.lifetimeCoinsEarned, kNoAdsBonusCoins);
      expect(g.storage.lifetimeCoinsBought, 0);
      final popup = g.noAdsCelebration!;
      expect(popup.gift!.product, IapProduct.noAds);
      expect(popup.message, 'No Ads');
      expect(popup.bonusCoins, kNoAdsBonusCoins);
      expect(spyOf().events.where((e) => e.$1 == 'gift_redeemed').single.$2, {
        'product': 'no_ads',
        'source': 'promo',
      });
      await claim(g);
      // Re-delivered later (acknowledged now): nothing more.
      now = now.add(const Duration(seconds: 6));
      resume(g);
      await settle(g);
      expect(g.menu.wallet.balance, kNoAdsBonusCoins);
      expect(g.noAdsCelebration, isNull);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.2 an old no_ads receipt (no store acknowledgement info, or already '
    'acknowledged) still only restores ownership: no bonus, no popup',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      fakeStore().deliver(
        const IapEvent(IapProduct.noAds, IapStatus.purchased),
      );
      await settle(g);
      expect(g.menu.noAds, isTrue);
      expect(g.menu.wallet.balance, 0);
      expect(g.noAdsCelebration, isNull);
      await g.menu.setNoAds(false);
      fakeStore().deliver(
        const IapEvent.store(
          IapProduct.noAds,
          IapStatus.restored,
          transactionIds: ['id:old'],
          acknowledged: true,
        ),
      );
      await settle(g);
      expect(g.menu.noAds, isTrue);
      expect(g.menu.wallet.balance, 0);
      expect(gifts(), 0);
    },
  );

  // --- sync ---------------------------------------------------------------------

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 syncPurchases runs on launch and on resume, at most once per 5 s',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      expect(fakeStore().syncs, 1);
      resume(g);
      await settle(g);
      expect(fakeStore().syncs, 1, reason: 'within 5 s of the launch sync');
      now = now.add(const Duration(seconds: 4));
      resume(g);
      expect(fakeStore().syncs, 1);
      now = now.add(Config.iapSyncInterval);
      resume(g);
      expect(fakeStore().syncs, 2);
      // A code redeemed while away arrives on the next resume.
      fakeStore().redeem(IapProduct.giftCoins10000, 'GPA.away');
      now = now.add(const Duration(seconds: 5));
      resume(g);
      await settle(g);
      expect(fakeStore().syncs, 3);
      expect(g.menu.wallet.balance, 10000);
      expect(g.noAdsCelebration?.gift, isNotNull);
    },
  );

  // --- popup ------------------------------------------------------------------

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 the gift popup waits until a menu (never mid-run) and queues one '
    'per code',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      await startRun(g);
      stepGame(g, .3);
      fakeStore().redeem(IapProduct.giftCoins10000, 'GPA.run-1');
      fakeStore().redeem(IapProduct.giftNoAdsCoins10000, 'GPA.run-2');
      await fakeStore().syncPurchases();
      await settle(g, .3);
      // Granted at once, shown later.
      expect(g.menu.wallet.balance, 20000);
      expect(g.menu.noAds, isTrue);
      expect(g.state, GameState.playing);
      expect(g.noAdsCelebration, isNull);
      expect(g.pendingGiftPopups, 2);
      expect(g.giftThisHomeVisit, isTrue);
      killRun(g);
      await flushAndMount(g);
      expect(g.noAdsCelebration, isNull, reason: 'not on the results page');
      g.goHome();
      await settle(g, 1);
      expect(g.state, GameState.start);
      // Note: the run start cleared the visit flag, the grants set it.
      expect(g.noAdsCelebration!.gift!.product, IapProduct.giftCoins10000);
      expect(g.pendingGiftPopups, 1);
      await claim(g);
      expect(g.noAdsCelebration!.gift!.product, IapProduct.giftNoAdsCoins10000);
      await claim(g);
      expect(g.noAdsCelebration, isNull);
      expect(g.pendingGiftPopups, 0);
      expect(g.coinPill.target, 20000);
      expect(g.noAdsPopup, isNull);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => make(store: (s) => s.redeem(IapProduct.giftCoins10000, 'GPA.s')),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'PRD §0 item 2: on a Home visit with a gift the No-Ads popup is skipped '
    '(giftThisHomeVisit); the gift popup shows over Settings too',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      expect(g.giftThisHomeVisit, isTrue);
      expect(g.noAdsCelebration, isNotNull);
      await claim(g);
      expect(g.noAdsPopup, isNull, reason: 'skipped this visit');
      // A gift arriving while Settings is open shows over it.
      g.openSettings();
      await settle(g);
      fakeStore().deliver(
        const IapEvent.store(
          IapProduct.giftCoins10000,
          IapStatus.purchased,
          transactionIds: ['id:settings'],
          acknowledged: false,
        ),
      );
      await settle(g);
      expect(g.world.children.query<SettingsPanel>(), hasLength(1));
      expect(g.noAdsCelebration?.gift, isNotNull);
    },
  );

  // --- the shop never shows them ----------------------------------------------

  test('§22.6 the gift products are never in the Shop list', () {
    expect(kShopProducts.where((p) => p.isGift), isEmpty);
    expect(IapProduct.giftCoins10000.isGift, isTrue);
    expect(IapProduct.giftNoAdsCoins10000.isGift, isTrue);
    expect(IapProduct.giftCoins10000.consumable, isTrue);
    expect(IapProduct.giftNoAdsCoins10000.consumable, isFalse);
    expect(IapProduct.giftNoAdsCoins10000.grantsNoAds, isTrue);
    expect(IapProduct.giftCoins10000.coins, 10000);
    expect(IapProduct.giftNoAdsCoins10000.coins, 10000);
  });

  FlameTester<FlappySpikesGame>(
    () => make(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§22.6 the Shop shows no gift pack',

    setUp: boot,
    verify: (g, tester) async {
      await launched(g);
      g.openShop();
      await settle(g, .6);
      final shop = g.shopScreen!;
      expect(shop.packFor(IapProduct.giftCoins10000), isNull);
      expect(shop.packFor(IapProduct.giftNoAdsCoins10000), isNull);
      expect(shop.packFor(IapProduct.coins10000), isNotNull);
    },
  );

  // --- the store layer (Google Play) -------------------------------------------

  group('StoreIapService §22', () {
    GooglePlayPurchaseDetails play(
      IapProduct product, {
      String id = 'GPA.1',
      bool acknowledged = false,
      PurchaseStateWrapper state = PurchaseStateWrapper.purchased,
      PurchaseStatus status = PurchaseStatus.restored,
    }) => GooglePlayPurchaseDetails(
      purchaseID: id,
      productID: product.storeId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'token-$id',
        source: 'google_play',
      ),
      transactionDate: '0',
      billingClientPurchase: PurchaseWrapper(
        orderId: id,
        packageName: 'com.duoleads.flappyspikes',
        purchaseTime: 0,
        purchaseToken: 'token-$id',
        signature: '',
        products: [product.storeId],
        isAutoRenewing: false,
        originalJson: '{}',
        isAcknowledged: acknowledged,
        purchaseState: state,
      ),
      status: status,
    );

    Future<(StoreIapService, FakeStore, List<IapEvent>)> rig() async {
      final store = FakeStore()..goLive(IapProduct.values);
      final service = StoreIapService(store: store);
      final events = <IapEvent>[];
      service.events.listen((e) {
        events.add(e);
        final granted = e.granted;
        if (granted != null && !granted.isCompleted) granted.complete();
      });
      await service.initialize();
      return (service, store, events);
    }

    test('price queries never include the gift products', () async {
      final (service, store, _) = await rig();
      expect(store.queries.single, {for (final p in kShopProducts) p.storeId});
      expect(store.queries.single, isNot(contains('gift_coins_10000')));
      await service.refresh();
      expect(store.queries, hasLength(1), reason: 'the Shop list is complete');
    });

    test('syncPurchases re-reads owned purchases; a gift is granted, then '
        'consumed (not just acknowledged)', () async {
      final (service, store, events) = await rig();
      store.owned.add(play(IapProduct.giftCoins10000));
      await service.syncPurchases();
      await pumpEventQueue();
      expect(store.restoreCalls, 1);
      final e = events.single;
      expect(e.product, IapProduct.giftCoins10000);
      expect(e.status, IapStatus.restored);
      expect(e.acknowledged, isFalse);
      expect(e.transactionIds, ['id:GPA.1', 'token:token-GPA.1']);
      expect(store.consumed, hasLength(1));
      expect(store.completed, isEmpty);
    });

    test('off Google Play the gift is completed instead', () async {
      final (service, store, _) = await rig();
      store.consumeApplies = false;
      store.owned.add(play(IapProduct.giftCoins10000));
      await service.syncPurchases();
      await pumpEventQueue();
      expect(store.completed, hasLength(1));
    });

    test('the No Ads gift is acknowledged (never consumed); its '
        'acknowledgement reaches the event', () async {
      final (service, store, events) = await rig();
      store.owned.add(play(IapProduct.giftNoAdsCoins10000, acknowledged: true));
      await service.syncPurchases();
      await pumpEventQueue();
      expect(events.single.acknowledged, isTrue);
      expect(store.consumed, isEmpty);
    });

    test('a purchase still waiting for payment is never granted', () async {
      final (service, store, events) = await rig();
      store.owned.add(
        play(IapProduct.giftCoins10000, state: PurchaseStateWrapper.pending),
      );
      await service.syncPurchases();
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(store.consumed, isEmpty);
      expect(store.completed, isEmpty);
    });

    test('a sync asked for before initialize runs right after it', () async {
      final store = FakeStore()..goLive(IapProduct.values);
      final service = StoreIapService(store: store);
      // S8-13: the early sync's future completes once the deferred sync ran
      // (the game's first START waits for it, PRD-2.3 §24.3).
      var done = false;
      final early = service.syncPurchases().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(store.restoreCalls, 0);
      expect(done, isFalse);
      await service.initialize();
      await early;
      expect(store.restoreCalls, 1);
    });
  });
}
