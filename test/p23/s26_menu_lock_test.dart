import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/menu_screen_chrome.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/tuning_defaults.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.3 §26.4: the Shop and Skins lock below a best of 25.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The owner's default (the lock is on); see test/flutter_test_config.dart.
  Tuning.instance = Tuning();
  TuningValues.current = TuningValues.defaults();
  await loadFonts();

  final spy = AnalyticsSpy();
  late FakeRewardedAds rewarded;

  FlameTester<FlappySpikesGame> tester(
    Map<String, Object> prefs, {
    double height = 568,
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy.events.clear();
      rewarded = FakeRewardedAds();
      return createRunTestGame(
        prefs: prefs,
        worldHeight: height,
        services: spy,
        monetization: Monetization(ads: rewarded),
      );
    },
    gameSize: Vector2(320, height),
    pumpWidget: (widget, t) async {
      // Taps are real pointer events: the view must be the game's size.
      t.view
        ..physicalSize = ui.Size(320, height)
        ..devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(widget);
    },
  );

  /// Starts a fresh first session (no launch popup) and lets it settle.
  Future<void> boot(FlappySpikesGame g, dynamic _) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  /// Taps [component] at its centre (the test binding's real pointer).
  Future<void> tap(
    FlappySpikesGame g,
    WidgetTester t,
    PositionComponent component,
  ) async {
    final p = component.absolutePositionOfAnchor(Anchor.center);
    await t.tapAt(ui.Offset(p.x, p.y));
    await flushAndMount(g);
  }

  // Owner 2026-10-13: the overlay lives in the world (above the strips),
  // owned by its screen.
  List<String> overlayLines(MenuScreen screen) =>
      screen.lockOverlay?.lines ?? const [];

  bool hasOverlay(MenuScreen screen) {
    final o = screen.lockOverlay;
    return o != null && o.isMounted;
  }

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 best 24: Home → SHOP opens the dimmed Shop with its lock text',
    setUp: boot,
    verify: (g, t) async {
      g.openShop();
      await flushAndMount(g);
      final shop = g.shopScreen!;
      expect(shop.locked, isTrue);
      expect(hasOverlay(shop), isTrue);
      expect(overlayLines(shop), ['SCORE 25 POINTS', 'TO UNLOCK THE SHOP']);
      expect(spy.events.where((e) => e.$1 == 'menu_locked_view').single.$2, {
        'screen': 'shop',
        'best': 24,
      });
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 best 24: Home → SKINS opens the dimmed Skins with its lock text',
    setUp: boot,
    verify: (g, t) async {
      g.openSkins();
      await flushAndMount(g);
      final skins = g.skinShop!;
      expect(skins.locked, isTrue);
      expect(overlayLines(skins), ['SCORE 25 POINTS', 'TO UNLOCK SKINS']);
      expect(spy.events.where((e) => e.$1 == 'menu_locked_view').single.$2, {
        'screen': 'skins',
        'best': 24,
      });
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 blocked input: a tap on the lock (the free coins row, a pack) does '
    'nothing; the back button works',
    setUp: boot,
    verify: (g, t) async {
      g.openShop();
      await flushAndMount(g);
      final shop = g.shopScreen!;
      await tap(g, t, shop.freeCoins);
      expect(rewarded.shown, 0, reason: 'no free-coins ad');
      await tap(g, t, shop.packs.first);
      expect(g.shopScreen, same(shop), reason: 'still locked, still there');
      await tap(g, t, shop.backButton);
      expect(g.shopScreen, isNull, reason: 'back closes the Shop');
      expect(g.state, GameState.start);
      await t.pump(const Duration(milliseconds: 400));
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 blocked input: the coin pill opens the locked Shop from Skins',
    setUp: boot,
    verify: (g, t) async {
      g.openSkins();
      await flushAndMount(g);
      expect(g.skinShop, isNotNull);
      g.coinPill.onPressed();
      await flushAndMount(g);
      expect(g.shopScreen, isNotNull, reason: 'the pill works');
      expect(g.shopScreen!.locked, isTrue);
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 exemption: the revive shop opens unlocked with a best of 24',
    setUp: boot,
    verify: (g, t) async {
      await startRun(g);
      for (var i = 0; i < 8; i++) {
        g.run!.debugPass(perfect: true);
      }
      killRun(g);
      await flushAndMount(g);
      expect(g.state, GameState.reviving);
      g.openReviveShop(onClose: () {});
      await flushAndMount(g);
      expect(g.shopScreen, isNotNull);
      expect(
        g.shopScreen!.locked,
        isFalse,
        reason: 'GET COINS is never locked',
      );
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 exemption: the No-Ads popup still opens on a locked Home',
    setUp: boot,
    verify: (g, t) async {
      g.openNoAdsPopup();
      await flushAndMount(g);
      expect(g.noAdsPopup, isNotNull);
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 Home tiles: the lock badge shows and no NEW badge or dot while '
    'locked',
    setUp: boot,
    verify: (g, t) async {
      final home = g.homeScreen!;
      expect(home.shopTile.locked, isTrue);
      expect(home.skinsTile.locked, isTrue);
      expect(home.shopTile.lockBadgeComponent, isNotNull);
      expect(home.skinsTile.lockBadgeComponent, isNotNull);
      expect(home.skinsTile.tagComponent, isNull, reason: 'no NEW tag');
      expect(home.skinsTile.tag, isNull);
    },
  );

  tester({
    'bestScore': 25, 'playerLevel': 1,
    'claimedLevels': ['1'],
  }).testGameWidget(
    '§26.4 unlocked: a best of 25 opens both screens with no overlay and the '
    'NEW badge is back',
    setUp: boot,
    verify: (g, t) async {
      final home = g.homeScreen!;
      expect(home.shopTile.locked, isFalse);
      expect(home.skinsTile.tag, 'NEW', reason: 'the 2.3 items are new');
      expect(home.skinsTile.lockBadgeComponent, isNull);
      g.openShop();
      await flushAndMount(g);
      expect(g.shopScreen!.locked, isFalse);
      expect(hasOverlay(g.shopScreen!), isFalse);
      await tap(g, t, g.shopScreen!.backButton);
      g.openSkins();
      await flushAndMount(g);
      expect(g.skinShop!.locked, isFalse);
      expect(hasOverlay(g.skinShop!), isFalse);
      expect(g.queuedPopups, 0, reason: 'unlocking is silent');
      await t.pump(const Duration(milliseconds: 400));
    },
  );

  tester({'bestScore': 24}).testGameWidget(
    '§26.4 unlocking is silent: a run that reaches 25 opens both screens '
    'with no popup',
    setUp: boot,
    verify: (g, t) async {
      final run = await startRun(g);
      run.state.score = 25;
      g.showRunScore(25);
      killRunThroughSaves(g);
      await declineRevive(g);
      stepGame(g, 2);
      await flushAndMount(g);
      g.goHome();
      await flushAndMount(g);
      expect(g.menu.locked, isFalse);
      expect(g.noAdsPopup, isNull);
      g.openShop();
      await flushAndMount(g);
      expect(g.shopScreen!.locked, isFalse);
      expect(hasOverlay(g.shopScreen!), isFalse);
    },
  );

  // QA_P2 gap: the 568 pt capture next to the 711 one.
  for (final h in [568.0, 711.0]) {
    tester({
      'bestScore': 24,
      'claimedLevels': ['1'], // no LEVEL UP popup over the captures
    }, height: h).testGameWidget(
      '§26.2 look: the locked Shop and Skins at ${h.round()} pt (visual check)',
      setUp: boot,
      verify: (g, t) async {
        g.openShop();
        await flushAndMount(g);
        stepGame(g, 0.6); // the screens fade in
        await flushAndMount(g);
        await t.runAsync(
          () => captureShot(g, 1, 'p23_s26_shop_locked_${h.round()}'),
        );
        g.closeShop();
        await flushAndMount(g);
        stepGame(g, 0.6);
        g.openSkins();
        await flushAndMount(g);
        stepGame(g, 0.6);
        await flushAndMount(g);
        await t.runAsync(
          () => captureShot(g, 1, 'p23_s26_skins_locked_${h.round()}'),
        );
        await t.pump(const Duration(milliseconds: 400));
      },
    );
  }

  FlameTester<FlappySpikesGame>(() {
    // A run start hands the tuned set to the config getters (as in a tester build).
    Tuning.instance = Tuning(
      active: TuningValues.resolve({'ui_unlock_best': '10'}),
    );
    Tuning.instance.beginRun();
    return createRunTestGame(
      prefs: const {'bestScore': 9},
      worldHeight: 568,
      services: spy,
      monetization: Monetization(ads: FakeRewardedAds()),
    );
  }, gameSize: Vector2(320, 568)).testGameWidget(
    '§26.1 tuning: ui_unlock_best = 10 moves the threshold and the number in '
    'the text (best 9 is locked, the text says 10)',
    setUp: boot,
    verify: (g, t) async {
      try {
        expect(Config.menuUnlockBest, 10);
        g.openShop();
        await flushAndMount(g);
        expect(g.shopScreen!.locked, isTrue);
        expect(overlayLines(g.shopScreen!), [
          'SCORE 10 POINTS',
          'TO UNLOCK THE SHOP',
        ]);
      } finally {
        Tuning.instance = Tuning();
        TuningValues.current = TuningValues.defaults();
      }
    },
  );

  group('§26.1 tuning', () {
    setUp(() {
      Tuning.instance = Tuning(
        active: TuningValues.resolve({'ui_unlock_best': '10'}),
      );
    });
    tearDown(() {
      Tuning.instance = Tuning();
      TuningValues.current = TuningValues.defaults();
    });

    test('ui_unlock_best = 10 moves the threshold and the text', () {
      Tuning.instance.beginRun(); // a run start reads the tuned set
      expect(Config.menuUnlockBest, 10);
      expect(
        kTuningDefaults.where((d) => d.key == 'ui_unlock_best').single.value,
        25,
      );
    });
  });
}
