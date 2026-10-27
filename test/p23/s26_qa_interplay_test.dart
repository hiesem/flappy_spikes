import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/noads_celebration.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

const _evidence =
    '/home/killerhis/Projects/flappyspikes/.worktrees/'
    'briefs8/evidence/qa2';

class _DelayedLaunchStore extends FakeIapService {
  final syncReply = Completer<void>();
  @override
  Future<void> syncPurchases() async {
    await syncReply.future;
    await super.syncPurchases();
  }
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  setUp(() {
    // Override the global flutter_test_config.dart unlock bypass.
    TuningValues.current = TuningValues.defaults();
  });

  FlameTester<FlappySpikesGame> tester(
    double h, {
    Map<String, Object> extraPrefs = const {},
  }) => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: h,
      prefs: {
        'bestScore': 24,
        'claimedLevels': ['1'],
        ...extraPrefs,
      },
      monetization: Monetization(iap: FakeIapService()),
    ),
    gameSize: Vector2(320, h),
    pumpWidget: (widget, t) async {
      t.view
        ..physicalSize = ui.Size(320, h)
        ..devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(widget);
    },
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester t) async {
    await g.ready();
    await preloadImages(g);
    await g.images.loadAll(kNoAdsCelebrationImages);
    await flushAndMount(g);
  }

  Future<void> drain(FlappySpikesGame g, WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await flushAndMount(g);
  }

  Future<List<int>> shotPixel(
    FlappySpikesGame g,
    WidgetTester t,
    String name,
    int x,
    int y,
  ) async {
    List<int>? pixel;
    await t.runAsync(() async {
      await captureShot(g, 1, name);
      final file = File('build/menu_shots/$name.png');
      // Evidence only (no such folder on CI).
      try {
        await Directory(_evidence).create(recursive: true);
        await file.copy('$_evidence/$name.png');
      } on FileSystemException catch (_) {}
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      final bytes = (await frame.image.toByteData())!;
      final offset = (y * frame.image.width + x) * 4;
      pixel = [for (var i = 0; i < 4; i++) bytes.getUint8(offset + i)];
      frame.image.dispose();
      codec.dispose();
    });
    return pixel!;
  }

  group('S8-12 back artwork', () {
    for (final h in [568.0, 711.0]) {
      tester(h).testGameWidget(
        'S8-12 §26.2 locked Shop back chrome stays fully bright at $h pt',
        setUp: boot,
        verify: (g, t) async {
          g.openShop();
          await flushAndMount(g);
          stepGame(g, 1);
          final rect = Config.menuScreenBackRectFor(h);
          final x = rect.left.toInt() + 3, y = rect.top.toInt() + 3;
          final locked = await shotPixel(
            g,
            t,
            'qa2_lock_shop_${h.round()}',
            x,
            y,
          );
          g.closeShop();
          await flushAndMount(g);
          stepGame(g, 1);
          await g.storage.saveBestScore(25);
          await g.storage.saveLvlIndex(1); // PRD-2.6 J5 explicit new rank.
          g.openShop();
          await flushAndMount(g);
          stepGame(g, 1);
          final open = await shotPixel(
            g,
            t,
            'qa2_open_shop_${h.round()}',
            x,
            y,
          );
          expect(locked, open, reason: 'only content is dimmed, not back');
        },
      );
    }
  });

  tester(711).testGameWidget(
    '§26 locked Skins blocks pointer tabs, try-on and dragging; '
    'coin pill and system back preserve the menu stack',
    setUp: boot,
    verify: (g, t) async {
      g.openSkins();
      await flushAndMount(g);
      stepGame(g, 1);
      final screen = g.skinShop!;
      expect(screen.locked, isTrue);
      final tab = Config.skinShopTabBarRect;
      await t.tapAt(ui.Offset(tab.left + tab.width * .5, tab.center.dy));
      final grid = screen.scroll.viewport;
      await t.tapAt(ui.Offset(50, grid.top + 40));
      await t.dragFrom(ui.Offset(160, grid.top + 90), const ui.Offset(0, -180));
      await flushAndMount(g);
      expect(screen.tab, SkinLayer.bird);
      expect(screen.tryOnId, isNull);
      expect(screen.scroll.offset, 0);
      expect(g.menu.wallet.balance, 0);
      final pill = g.coinPill.absolutePositionOfAnchor(Anchor.center);
      await t.tapAt(ui.Offset(pill.x, pill.y));
      await flushAndMount(g);
      stepGame(g, 1);
      expect(g.shopScreen!.locked, isTrue);
      expect(g.handleSystemBack(), isTrue);
      await flushAndMount(g);
      stepGame(g, 1);
      expect(g.skinShop!.locked, isTrue);
      expect(g.handleSystemBack(), isTrue);
      await flushAndMount(g);
      expect(g.menuScene, MenuScene.home);
      await t.pump(const Duration(milliseconds: 400));
    },
  );

  tester(568).testGameWidget(
    '§26 × §22 gift and Restore remain available below the unlock best',
    setUp: boot,
    verify: (g, t) async {
      expect(g.menu.locked, isTrue);
      final store = g.monetization.iap as FakeIapService;
      store.redeem(IapProduct.giftNoAdsCoins10000, 'GPA.qa2-gift');
      await store.syncPurchases();
      await drain(g, t);
      stepGame(g, 1);
      await drain(g, t);
      expect(g.storage.noAds, isTrue);
      expect(g.menu.wallet.balance, 10000);
      expect(g.noAdsCelebration!.gift, isNotNull);
      expect(g.menu.locked, isTrue, reason: 'coins do not unlock the menus');
      g.noAdsCelebration!.claimButton.onPressed();
      stepGame(g, 5);
      await drain(g, t);
      await g.storage.saveNoAds(false);
      await g.restorePurchases();
      await drain(g, t);
      expect(g.storage.noAds, isTrue);
      expect(g.menu.wallet.balance, 10000, reason: 'Restore adds no coins');
    },
  );

  tester(
    711,
    extraPrefs: const {
      'gamesPlayed': 12,
      'firstSessionDone': true,
      'lastScore': 5, // blocks the launch offer; score 8 opens its window
    },
  ).testGameWidget(
    '§0 item 2 gift then an owed level reward; eligible No-Ads offer '
    'stays skipped for the whole Home visit',
    setUp: boot,
    verify: (g, t) async {
      expect(g.noAdsPopup, isNull);
      final run = await startRun(g);
      final store = g.monetization.iap as FakeIapService;
      store.redeem(IapProduct.giftCoins10000, 'GPA.qa2-order');
      await store.syncPurchases();
      await drain(g, t);
      run.state.score = 8;
      g.showRunScore(8);
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      // A catch-up level becomes owed concurrently with the pending gift.
      // This puts both Home popups in contention without claiming the
      // level on results, where it would no longer be owed on arrival.
      await g.storage.saveBestScore(50);
      await g.menu.levels.debugForceLevelUp(); // J4 queues a durable roll.
      expect(g.menu.levels.pendingLevelUp, isNotNull);
      g.goHome();
      await drain(g, t);
      stepGame(g, 1);
      await drain(g, t);
      expect(g.noAdsCelebration?.gift, isNotNull);
      expect(g.levelUpPopup, isNull, reason: 'gift goes first');
      expect(g.noAdsPopup, isNull);
      expect(
        g.menu.noAdsPopup.evaluate(),
        isNotNull,
        reason: 'the offer would qualify without the gift visit guard',
      );
      g.noAdsCelebration!.claimButton.onPressed();
      stepGame(g, 5);
      await drain(g, t);
      stepGame(g, 1);
      await drain(g, t);
      expect(g.levelUpPopup, isNotNull, reason: 'then the owed level reward');
      expect(g.noAdsPopup, isNull);
      g.levelUpPopup!.claimButton.onPressed();
      stepGame(g, 5);
      await drain(g, t);
      expect(g.modalPopupOpen, isFalse);
      expect(g.noAdsPopup, isNull, reason: 'still skipped after both claims');
    },
  );

  group('S8-13 launch ownership', () {
    late _DelayedLaunchStore launchStore;
    FlameTester<FlappySpikesGame>(() {
      launchStore = _DelayedLaunchStore()
        ..redeem(IapProduct.giftNoAdsCoins10000, 'GPA.qa2-launch-owner');
      return createRunTestGame(
        worldHeight: 711,
        monetization: Monetization(
          iap: launchStore,
          banner: FakeBannerAds(enabled: true, heightDp: 48, widthDp: 320),
        ),
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'S8-13 §24.3 a No-Ads launch grant reaches the first run before '
      'banner reservation',
      setUp: boot,
      verify: (g, t) async {
        // A Play query is still pending while Home already accepts START.
        g.onScreenTap();
        await flushAndMount(g);
        launchStore.syncReply.complete();
        await drain(g, t);
        expect(g.storage.noAds, isTrue);
        g.onPlayfieldTap();
        await flushAndMount(g);
        expect(g.run, isNotNull);
        expect(g.runHasBanner, isFalse, reason: 'launch ownership, first run');
      },
    );
  });
}
