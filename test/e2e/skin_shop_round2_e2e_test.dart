import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart' show AudioPool;
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/look_component.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

// S2-01/02 already name the older PRD-1/AdMob findings. Skin-shop round 2
// starts at S2-10; those regressions are fixed (fix round 2) and pinned here.

class _Events extends GameServices {
  final events = <(String, Map<String, Object>?)>[];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));

  List<Map<String, Object>?> params(String name) => events
      .where((event) => event.$1 == name)
      .map((event) => event.$2)
      .toList();
}

class _Rig {
  final events = _Events();
  final ads = FakeRewardedAds();
  final iap = FakeIapService();
  final sounds = <Sfx>[];
}

void _journey(
  String name,
  Future<void> Function(FlappySpikesGame, _Rig, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
  double height = 711,
}) {
  final rig = _Rig();
  FlameTester<FlappySpikesGame>(
    () => createTestGame(
      prefs,
      height,
      rig.events,
      Monetization(ads: rig.ads, iap: rig.iap),
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
    name,
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.sound.onPlay = rig.sounds.add;
      game.purchases
        ..dispose()
        ..start();
      try {
        await verify(game, rig, tester);
      } finally {
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );
}

Future<void> _settle(FlappySpikesGame game, WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await flushAndMount(game);
}

Future<void> _tap(
  FlappySpikesGame game,
  WidgetTester tester,
  PositionComponent component,
) async {
  final centre = component.absolutePositionOfAnchor(Anchor.center);
  await tester.tapAt(ui.Offset(centre.x, centre.y));
  await _settle(game, tester);
}

Future<void> _fade(FlappySpikesGame game) async {
  stepGame(game, .3);
  await flushAndMount(game);
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

Future<void> _shot(
  FlappySpikesGame game,
  WidgetTester tester,
  String name,
) async {
  await tester.runAsync(() => captureShot(game, 2, 'skin_round2_$name'));
  game.onGameResize(Vector2(320, game.viewHeight));
}

const _dressed = <String, Object>{
  'ownedItems': ['bird:robin', 'gear:windup', 'hat:cowboy'],
  'equippedItem.bird': 'robin',
  'equippedItem.gear': 'windup',
  'equippedItem.hat': 'cowboy',
};

/// Plugin-free pool seam. A duration query and a start result can be
/// independently delayed/failed, just like the real asynchronous pool.
class _Pool implements AudioPool {
  final durationReady = Completer<Duration?>();
  Object? startError;
  int starts = 0;
  int stops = 0;

  @override
  Future<Duration?> getDuration() => durationReady.future;

  @override
  Future<Future<void> Function()> start({double volume = 1}) async {
    starts++;
    final error = startError;
    if (error != null) throw error;
    return () async => stops++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _microtasks() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.value();
  }
}

void main() {
  setUpAll(loadFonts);

  _journey('round 2: fresh install → locked legendary → buy → death → home', (
    game,
    rig,
    tester,
  ) async {
    expect(game.homeScreen!.bird.look, Look.defaults);
    await _tap(game, tester, game.homeScreen!.skinsTile);
    await _fade(game);
    final screen = game.skinShop!;
    expect(screen.bar.labelText, '3 / 88');
    expect(screen.tabBar.tabs.map((tab) => tab.countText), [
      '1/30',
      '0/14',
      '0/14',
      '1/15',
      '1/15',
    ]);
    // Real drag input reaches the legendary row at the end of Birds.
    for (var i = 0; i < 6; i++) {
      await tester.dragFrom(
        const ui.Offset(160, 600),
        const ui.Offset(0, -190),
      );
      await _settle(game, tester);
    }
    // The last drag carries momentum: let it settle so the tap below selects
    // Galaxy instead of just stopping the fling.
    await settleMenuScroll(screen.scroll, game, tester);
    await _tap(game, tester, screen.tileFor('galaxy'));
    expect(screen.previewLook.bird, 'galaxy');
    expect(game.menu.items.look.bird, 'classic');
    expect(screen.stage.tryOnAlpha, inInclusiveRange(.28, .56));
    expect(screen.tileFor('galaxy').current.tryingOn, isTrue);
    expect(screen.actionButton.poor, isTrue);
    await _tap(game, tester, screen.actionButton);
    expect(
      screen.children.query<ShopToast>().single.message,
      'NOT ENOUGH COINS',
    );
    expect(game.coinPill.flashing, isTrue);
    expect(rig.events.params('item_no_coins').single, {
      'layer': 'bird',
      'id': 'galaxy',
      'shortfall': 5000,
    });
    game.openDebugPanel();
    await flushAndMount(game);
    final plus1000 = game.debugPanel!.children.query<MenuButton>().first;
    for (var i = 0; i < 6; i++) {
      await _tap(game, tester, plus1000);
    }
    game.closeDebugPanel();
    await flushAndMount(game);
    await _tap(game, tester, screen.actionButton);
    expect(game.menu.wallet.balance, 1000);
    expect(screen.tryOnId, isNull);
    expect(screen.stage.confettiCount, greaterThan(100));
    expect(screen.stage.rays, greaterThan(2));
    expect(screen.children.query<UnlockBanner>().single.nameText, 'GALAXY');
    stepGame(game, .7);
    expect(game.coinPill.shownBalance, 1000);
    expect(screen.bar.labelText, '4 / 88');
    expect(rig.events.params('item_purchase').single, {
      'layer': 'bird',
      'id': 'galaxy',
      'rarity': 'LEGENDARY',
      'price': 5000,
      'source': 'button',
    });
    await _tab(game, tester, SkinLayer.gear);
    // Wind-up key is in the fourth row: scroll before tapping it.
    screen.scroll.offset = screen.scroll.maxOffset;
    await flushAndMount(game);
    await _tap(game, tester, screen.tileFor('windup'));
    await _tap(game, tester, screen.actionButton);
    await _tab(game, tester, SkinLayer.hat);
    await _tap(game, tester, screen.tileFor('cap'));
    await _tap(game, tester, screen.actionButton);
    const outfit = Look(bird: 'galaxy', gear: 'windup', hat: 'cap');
    expect(game.menu.items.look, outfit);
    expect(game.menu.wallet.balance, 0);
    expect(screen.bar.labelText, '6 / 88');
    expect(screen.tabBar.tabs.map((tab) => tab.countText), [
      '2/30',
      '1/14',
      '1/14',
      '1/15',
      '1/15',
    ]);
    final saved = GameStorage();
    await saved.load();
    expect(saved.equippedItems[SkinLayer.gear], 'windup');
    expect(saved.equippedItems[SkinLayer.hat], 'cap');
    expect(
      saved.ownedItems,
      containsAll(['bird:galaxy', 'gear:windup', 'hat:cap']),
    );
    await _tap(game, tester, screen.backButton);
    await _fade(game);
    expect(game.homeScreen!.bird.look, outfit);
    expect(game.homeScreen!.bird.lookComponent.blend, 0);
    await _tap(game, tester, game.homeScreen!.startButton);
    final bird = game.world.children.query<Bird>().single;
    expect(game.state, GameState.playing);
    expect(bird.look, outfit);
    expect(bird.body.fixtures, hasLength(1));
    expect(bird.body.fixtures.single.shape.radius, 14.75);
    // PRD-2 §3.0.1: the first colour change comes at hoop 10.
    for (var i = 0; i < 10; i++) {
      game.run!.debugPass();
    }
    stepGame(game, .55, flapBelow: game.viewHeight / 2);
    expect(bird.lookComponent.blend, closeTo(.35, 1e-6));
    // A real spike collision, then the existing results REPLAY action.
    stepGame(game, 2);
    await flushAndMount(game);
    // PRD-2 §3.14 (WP-2d): ≥ 6 hoops → the revive offer; No thanks.
    await declineRevive(game);
    expect(game.state, GameState.gameOver);
    expect(bird.lookComponent.pose, LookPose.dead);
    expect(bird.look, outfit);
    final deadClock = bird.lookComponent.time;
    stepGame(game, .2);
    expect(bird.lookComponent.time, deadClock);
    await tester.tapAt(ui.Offset(160, game.viewHeight / 2 + 25.25));
    await _settle(game, tester);
    await _fade(game);
    expect(game.state, GameState.start);
    expect(game.homeScreen!.bird.look, outfit);
    expect(game.homeScreen!.bird.lookComponent.blend, 0);
  });

  _journey(
    'round 2: equip NONE, cancel try-on, keep counters and saved look',
    prefs: _dressed,
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      final screen = game.skinShop!;
      await _tab(game, tester, SkinLayer.gear);
      await _tap(game, tester, screen.tileFor(kNoneId));
      expect(screen.actionButton.label, 'NOTHING ON');
      await _tab(game, tester, SkinLayer.hat);
      await _tap(game, tester, screen.tileFor('beanie'));
      expect(screen.previewLook.hat, 'beanie');
      await _tab(game, tester, SkinLayer.trail);
      expect(screen.tryOnId, isNull);
      expect(screen.previewLook.hat, 'cowboy');
      await _tab(game, tester, SkinLayer.hat);
      await _tap(game, tester, screen.tileFor(kNoneId));
      expect(screen.actionButton.label, 'NOTHING ON');
      expect(screen.bar.labelText, '6 / 88');
      expect(screen.tabBar.tabs.map((tab) => tab.countText), [
        '2/30',
        '1/14',
        '1/14',
        '1/15',
        '1/15',
      ]);
      await _tap(game, tester, screen.backButton);
      await _fade(game);
      expect(game.homeScreen!.bird.look, const Look(bird: 'robin'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('equippedItem.gear'), 'none');
      expect(prefs.getString('equippedItem.hat'), 'none');
      expect(
        rig.events.params('item_equip'),
        containsAll([
          {'layer': 'gear', 'id': 'none'},
          {'layer': 'hat', 'id': 'none'},
        ]),
      );
    },
  );

  for (final height in [568.0, 730.0]) {
    _journey(
      'round 2: five-tab purchase/counters/layout at ${height.toInt()}',
      height: height,
      prefs: const {'coins': 1400},
      (game, rig, tester) async {
        await _tap(game, tester, game.homeScreen!.skinsTile);
        await _fade(game);
        final screen = game.skinShop!;
        expect(screen.stage.position, Vector2(14, 126));
        expect(screen.stage.size, Vector2(292, 138));
        expect(screen.tabBar.position, Vector2(14, 270));
        expect(screen.tabBar.size, Vector2(292, 52));
        expect(
          screen.scroll.viewport,
          ui.Rect.fromLTRB(14, 326, 306, height - 44),
        );
        final ids = ['sky', 'shades', 'cap', 'sky', 'blue'];
        for (final layer in SkinLayer.values) {
          await _tab(game, tester, layer);
          await _tap(game, tester, screen.tileFor(ids[layer.index]));
          await _tap(game, tester, screen.actionButton);
          expect(game.menu.items.look.idFor(layer), ids[layer.index]);
          expect(screen.tryOnId, isNull);
          // The grid's final item remains reachable on both height bounds.
          screen.scroll.offset = screen.scroll.maxOffset;
          stepGame(game, 1);
          await flushAndMount(game);
          final last = screen.tiles.last;
          final centre = last.absolutePositionOfAnchor(Anchor.center);
          expect(centre.y, inInclusiveRange(326, height - 44));
          await _shot(game, tester, '${height.toInt()}_${layer.key}_bottom');
        }
        expect(game.menu.wallet.balance, 250);
        expect(screen.bar.labelText, '8 / 88');
        expect(screen.tabBar.tabs.map((tab) => tab.countText), [
          '2/30',
          '1/14',
          '1/14',
          '2/15',
          '2/15',
        ]);
        expect(rig.events.params('item_purchase'), hasLength(5));
        expect(screen.stage.showsTrail, isTrue);
        expect(screen.stage.trail.particleCount, greaterThan(0));
        // Hoop/trail equipment is retained when returning to Home/run,
        // with rendering confined to the bird/gear/hat stack in this phase.
        await _tap(game, tester, screen.backButton);
        await _fade(game);
        expect(game.homeScreen!.bird.look.hoop, 'sky');
        expect(game.homeScreen!.bird.look.trail, 'blue');
      },
    );
  }

  _journey(
    'round 2: reduce motion across home, Shop, and legendary purchase',
    prefs: const {'coins': 5000},
    (game, rig, tester) async {
      game.reduceMotionOverride = true;
      final home = game.homeScreen!;
      stepGame(game, 15);
      expect(home.bird.idle.lastAction, isNull);
      expect(home.bird.idle.time, greaterThan(14));
      expect(home.slotButton.pulse.k, 0);
      expect(home.slotButton.streak.progress, isNull);
      expect(home.trophyWiggle.isIdentity, isTrue);
      expect(home.skinsTile.tagWobble.isIdentity, isTrue);
      expect(game.coinPill.glintOpacity, 0);
      await _tap(game, tester, home.shopTile);
      await _fade(game);
      final shop = game.shopScreen!;
      stepGame(game, 15);
      expect(shop.freeCoins.pulse.k, 0);
      expect(shop.freeCoins.cameraNod.isIdentity, isTrue);
      expect(shop.banner.streak.progress, isNull);
      expect(shop.featured.streak.progress, isNull);
      for (final pack in shop.packs) {
        expect(pack.streak.progress, isNull);
        expect(pack.tagWiggle.isIdentity, isTrue);
      }
      await _tap(game, tester, shop.backButton);
      await _fade(game);
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      final screen = game.skinShop!;
      await _tab(game, tester, SkinLayer.hat);
      screen.scroll.offset = screen.scroll.maxOffset;
      await flushAndMount(game);
      await _tap(game, tester, screen.tileFor('crown'));
      expect(screen.stage.tryOnAlpha, .42);
      expect(screen.actionButton.pulseScale, 1);
      await _tap(game, tester, screen.actionButton);
      expect(game.menu.items.look.hat, 'crown');
      expect(screen.stage.rays, 0);
      expect(game.world.children.query<ScreenFlash>(), isEmpty);
      expect(game.world.children.query<ScreenShake>(), isEmpty);
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
        expect(screen.bar.popScale, 1);
        expect(game.camera.viewfinder.position, Vector2.zero());
      }
    },
  );

  _journey('round 2: GET → six-coin flight → +40 once after navigation', (
    game,
    rig,
    tester,
  ) async {
    await _tap(game, tester, game.homeScreen!.shopTile);
    await _fade(game);
    final shop = game.shopScreen!;
    expect(shop.freeCoins.chipText, 'GET');
    expect(shop.freeCoins.chip!.size, Vector2(112, 32));
    rig.sounds.clear();
    await _tap(game, tester, shop.freeCoins.chip!);
    expect(game.menu.wallet.balance, 40);
    expect(game.coinPill.shownBalance, 0);
    final fly = game.coinFly!;
    expect(fly.count, 6);
    expect(fly.duration, .65);
    expect(fly.stagger, .07);
    stepGame(game, .5);
    await _shot(game, tester, 'get_in_flight');
    // Returning Home during the flight must never strand the held pill.
    await _tap(game, tester, shop.backButton);
    await _fade(game);
    stepGame(game, 1.2);
    await flushAndMount(game);
    // The final landing creates a TimerComponent; let that newly mounted
    // component run its progress-sound delay as it would on live frames.
    stepGame(game, .5);
    await flushAndMount(game);
    expect(fly.landed, 6);
    expect(game.coinFly, isNull);
    expect(game.coinPill.held, isFalse);
    expect(game.coinPill.shownBalance, 40);
    expect(
      rig.sounds.where(
        (sfx) => [Sfx.bnAdBtn, Sfx.bnCoin, Sfx.skProgress].contains(sfx),
      ),
      [Sfx.bnAdBtn, Sfx.bnCoin, Sfx.skProgress],
    );
    expect(rig.ads.shown, 1);
    expect(rig.events.params('coins_earned').single, {
      'amount': 40,
      'source': 'rewarded',
    });
    await _tap(game, tester, game.homeScreen!.shopTile);
    await _fade(game);
    expect(game.shopScreen!.freeCoins.chipText, '05:00');
    await _tap(game, tester, game.shopScreen!.freeCoins.chip!);
    expect(game.menu.wallet.balance, 40);
    expect(rig.ads.shown, 1);
  });

  _journey(
    'round 2: legacy reset preserves new wardrobe, balance and progress',
    prefs: const {
      ..._dressed,
      'coins': 80,
      'ownedSkins': ['crown', 'ghost'],
      'equippedSkin': 'crown',
      'seenSkins': ['ghost'],
    },
    (game, rig, tester) async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['ownedSkins', 'equippedSkin', 'seenSkins']) {
        expect(prefs.containsKey(key), isFalse);
      }
      expect(game.menu.wallet.balance, 80, reason: 'common.md: no refund');
      expect(
        game.homeScreen!.bird.look,
        const Look(bird: 'robin', gear: 'windup', hat: 'cowboy'),
      );
      expect(game.menu.items.isOwned(SkinLayer.hat, 'crown'), isFalse);
      expect(game.menu.items.isOwned(SkinLayer.bird, 'ghost'), isFalse);
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      expect(game.skinShop!.bar.labelText, '6 / 88');
    },
  );

  _journey(
    'round 2: home art and Shop cascade freeze under popups/debug/fake ads',
    prefs: _dressed,
    (game, rig, tester) async {
      final home = game.homeScreen!;
      stepGame(game, .4);
      game.openNoAdsPopup();
      await flushAndMount(game);
      final homeT = home.clock.t;
      final artT = home.bird.lookComponent.time;
      stepGame(game, .7);
      expect(home.clock.t, homeT);
      expect(home.bird.lookComponent.time, artT);
      game.closeNoAdsPopup();
      await _fade(game);
      expect(home.bird.lookComponent.time, greaterThan(artT));
      game.openDebugPanel();
      await flushAndMount(game);
      final debugArtT = home.bird.lookComponent.time;
      stepGame(game, .7);
      expect(home.bird.lookComponent.time, debugArtT);
      game.closeDebugPanel();
      await flushAndMount(game);
      await _tap(game, tester, home.shopTile);
      await _fade(game);
      final shop = game.shopScreen!;
      // Exact staggered start times, then freeze those phases under an ad.
      expect(shop.banner.streak.delay, 0);
      expect(shop.packs.map((pack) => pack.streak.delay), [
        .7,
        1.14,
        1.58,
        2.02,
      ]);
      expect(shop.featured.streak.delay, 2.5);
      stepGame(game, 7.15 - shop.clock.t);
      expect(shop.banner.streak.progress, isNotNull);
      expect(shop.packs.first.streak.progress, isNotNull);
      expect(shop.packs.last.streak.progress, isNull);
      game.monetization.showFakeAdOverlay = true;
      await _tap(game, tester, shop.freeCoins.chip!);
      expect(game.fakeAdOverlay, isNotNull);
      final shopT = shop.clock.t;
      final featuredT = shop.featured.idle.time;
      final streak = shop.banner.streak.progress;
      stepGame(game, .7);
      expect(shop.clock.t, shopT);
      expect(shop.featured.idle.time, featuredT);
      expect(shop.banner.streak.progress, streak);
      // Cancel through the overlay's real close control; no coins granted.
      await _tap(game, tester, game.fakeAdOverlay!.closeButton);
      await _fade(game);
      expect(game.liveMotionPaused, isFalse);
      expect(game.menu.wallet.balance, 0);
      expect(shop.clock.t, greaterThan(shopT));
    },
  );

  test(
    'round 2: a ready low-latency pool plays and returns its player',
    () async {
      final pool = _Pool();
      pool.durationReady.complete(const Duration(milliseconds: 1));
      final sound = SoundService()
        ..poolFactory = (file, legacy) async =>
            file == 'flap.mp3' ? pool : null;
      sound.play(Sfx.flap); // dropped while the pool is warming
      await _microtasks();
      sound.play(Sfx.flap);
      await _microtasks();
      expect(pool.starts, 1);
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(pool.stops, 1);
    },
  );

  group('S2-10 wind-up key has no reaction to a gameplay flap', () {
    _journey(
      'gear pixels keep their phase while the wing flaps',
      prefs: _dressed,
      (game, rig, tester) async {
        await _tap(game, tester, game.homeScreen!.startButton);
        stepGame(game, .48);
        expect(game.state, GameState.playing);
        final look = game.world.children.query<Bird>().single.lookComponent;
        // Hold only the wing constant: Robin and Cowboy have static art.
        // Any instant pixel change therefore comes from the wind-up key.
        look.flapOverride = false;
        ui.Picture draw() {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder)..translate(20, 20);
          look.render(canvas);
          return recorder.endRecording();
        }

        final before = draw();
        game.onScreenTap(); // no elapsed time; only the gameplay flap
        final after = draw();
        await tester.runAsync(() async {
          final a = await before.toImage(88, 80);
          final b = await after.toImage(88, 80);
          final bytesA = (await a.toByteData())!.buffer.asUint8List();
          final bytesB = (await b.toByteData())!.buffer.asUint8List();
          a.dispose();
          b.dispose();
          before.dispose();
          after.dispose();
          expect(
            bytesB,
            orderedEquals(bytesA),
            reason:
                'PRD §5.2: wind-up key is idle-only, with no gameplay reactions',
          );
        });
      },
    );
  });

  // S2-11: a warm pool must never be published before its duration.
  test(
    'S2-11 SFX waits for duration metadata before playing a warm pool',
    () async {
      final pool = _Pool();
      final sound = SoundService()
        ..poolFactory = (file, legacy) async =>
            file == 'flap.mp3' ? pool : null;
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // starts warm-up, dropped
        await _microtasks(); // pool exists, its duration is still pending
        sound.play(Sfx.flap);
        await _microtasks();
        // Finish warm-up so this test leaves no pending metadata future.
        pool.durationReady.complete(const Duration(milliseconds: 1));
        await _microtasks();
      }, (error, stack) => uncaught.add(error));
      expect(
        uncaught,
        isEmpty,
        reason:
            'a play during warm-up must not dereference a missing stop duration',
      );
    },
  );

  test('S2-12 low-latency pool playback failure is contained', () async {
    final pool = _Pool()
      ..startError = StateError('native SoundPool start failed');
    pool.durationReady.complete(const Duration(milliseconds: 1));
    final sound = SoundService()
      ..poolFactory = (file, legacy) async => file == 'flap.mp3' ? pool : null;
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      sound.play(Sfx.flap);
      await _microtasks();
      sound.play(Sfx.flap);
      await _microtasks();
    }, (error, stack) => uncaught.add(error));
    expect(pool.starts, 1, reason: 'the failure must exercise the ready pool');
    expect(
      uncaught,
      isEmpty,
      reason: 'audio failure must never take the game down',
    );
  });
}
