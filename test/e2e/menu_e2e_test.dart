import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/gameover_panel.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/ui/service_message.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;

// QA input coordinates below are from PRD §4/5, independent of Config.
class RecordingServices extends GameServices {
  final events = <(String, Map<String, Object>?)>[];
  int leaderboardCalls = 0;
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }

  @override
  Future<ShowLeaderboardResult> showLeaderboards() async {
    leaderboardCalls++;
    return ShowLeaderboardResult.opened;
  }

  List<Map<String, Object>?> params(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$2).toList();
}

class Clock {
  DateTime now = DateTime(2026, 10, 3, 12);
  DateTime call() => now;
  int get day => DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(1970)).inDays;
}

class Rig {
  final spy = RecordingServices();
  final ads = FakeRewardedAds();
  final iap = FakeIapService();
  final clock = Clock();
}

Future<void> settle(
  FlappySpikesGame g,
  WidgetTester t, {
  bool fade = false,
}) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 15));
    await flushAndMount(g);
  }
  if (fade) {
    stepGame(g, 0.6);
    await flushAndMount(g);
  }
}

Future<void> tap(
  FlappySpikesGame g,
  WidgetTester t,
  Offset p, {
  bool fade = true,
}) async {
  await t.tapAt(p);
  await settle(g, t, fade: fade);
}

String? toast(FlappySpikesGame g) {
  final all = g.world.children.query<ServiceMessage>();
  return all.isEmpty ? null : all.last.message;
}

Offset center(PositionComponent c) =>
    c.absolutePosition.toOffset() + Offset(c.width / 2, c.height / 2);

Future<void> capture(FlappySpikesGame g, WidgetTester t, String name) async {
  await t.runAsync(() async {
    final size = Vector2(480, (g.viewHeight * 1.5).roundToDouble());
    g.onGameResize(size);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.x, size.y),
      ui.Paint()..color = g.backgroundColor(),
    );
    g.render(canvas);
    final image = await recorder.endRecording().toImage(480, size.y.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('build/menu_shots/qa_$name@1.5x.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    // Restore the input coordinate system after capture.
    g.onGameResize(Vector2(320, g.viewHeight));
  });
}

void e2e(
  String name,
  Future<void> Function(FlappySpikesGame, Rig, WidgetTester) verify, {
  double height = 711,
  Map<String, Object> prefs = const {},
  void Function(Rig)? configure,
}) {
  final r = Rig();
  configure?.call(r);
  FlameTester<FlappySpikesGame>(
    () {
      SharedPreferences.setMockInitialValues(prefs);
      return FlappySpikesGame(
        worldHeight: height,
        soundEnabled: false,
        services: r.spy,
        monetization: Monetization(ads: r.ads, iap: r.iap),
        clock: r.clock.call,
      );
    },
    gameSize: Vector2(320, height),
    pumpWidget: (widget, t) async {
      t.view
        ..physicalSize = Size(320, height)
        ..devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(widget);
    },
  ).testGameWidget(
    name,
    setUp: (g, t) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, t) async {
      // FlameTester loads in runAsync; subscribe in the widget test zone so
      // fake store timers and purchase events share the same scheduler.
      g.purchases
        ..dispose()
        ..start();
      try {
        await verify(g, r, t);
      } finally {
        await t.pump(const Duration(milliseconds: 50));
      }
    },
  );
}

KeyDownEvent key(LogicalKeyboardKey k) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: k,
  timeStamp: Duration.zero,
);

Future<FlappySpikesGame> restartWithSamePrefs(Rig r, WidgetTester t) async {
  final g = FlappySpikesGame(
    worldHeight: 711,
    soundEnabled: false,
    services: r.spy,
    clock: r.clock.call,
    monetization: Monetization(ads: r.ads, iap: r.iap),
  );
  await t.runAsync(() async {
    await t.pumpWidget(GameWidget(game: g));
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  });
  g.purchases
    ..dispose()
    ..start();
  await settle(g, t, fade: true);
  return g;
}

void main() {
  setUpAll(loadFonts);

  e2e('QA fresh install and PRD-position home taps', (g, r, t) async {
    expect(g.menu.wallet.balance, 0);
    expect(g.menu.skins.equipped, 'pink');
    expect(g.menu.slot.offered, isIn([Powerup.bigHoops, Powerup.shield]));
    expect(g.noAdsPopup, isNull);
    final offered = g.menu.slot.offered;
    await tap(g, t, const Offset(300, 220));
    expect(g.state, GameState.start);
    await tap(g, t, const Offset(49, 502));
    expect(g.menuScene, MenuScene.shop);
    expect(r.spy.params('shop_open').single, {'source': 'tile'});
    await tap(g, t, const Offset(287, 77));
    expect(g.menuScene, MenuScene.home);
    expect(g.menu.slot.offered, offered);
    await tap(g, t, const Offset(33, 77));
    expect(g.menuScene, MenuScene.shop);
    expect(r.spy.params('shop_open').last, {'source': 'pill'});
    await tap(g, t, const Offset(287, 77));
    var invites = 0;
    g.onInvite = () => invites++;
    await tap(g, t, const Offset(197, 502));
    expect(invites, 1);
    expect(g.menu.wallet.balance, 0);
    expect(r.spy.params('invite_tap').length, 1);
    await tap(g, t, const Offset(49, 609));
    expect(r.spy.leaderboardCalls, 1);
    await tap(g, t, const Offset(189, 311), fade: false);
    expect(g.state, GameState.playing);
    expect(
      g.world.children.query<Bird>().single.body.linearVelocity.y,
      lessThan(-200),
    );
    await tap(g, t, const Offset(300, 220), fade: false);
    expect(
      g.world.children.query<Bird>().single.body.linearVelocity.y,
      lessThan(-200),
    );
  });

  e2e('QA play score is credited once, +N panel, replay rolls home', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(189, 311), fade: false);
    // Exercise the public score-contact path with an actual spawned pair.
    await flushAndMount(g);
    final pairs = g.world.children.where(
      (c) => c.runtimeType.toString() == 'PipePair',
    );
    expect(pairs, isNotEmpty);
    g.onScoreSensor(pairs.first);
    g.onScoreSensor(pairs.first);
    expect(g.score, 1);
    expect(g.menu.wallet.balance, 0);
    g.onBirdHit();
    g.onBirdHit();
    await settle(g, t, fade: true);
    expect(g.menu.wallet.balance, 1);
    expect(g.storage.gamesPlayed, 1);
    expect(g.world.children.query<GameOverPanel>().single.coinsEarned, 1);
    expect(r.spy.params('coins_earned').single, {
      'amount': 1,
      'source': 'play',
    });
    await capture(g, t, 'gameover_1coin');
    // Existing 1.0 replay button centre = centreY + 25.25.
    await tap(g, t, const Offset(160, 380.75));
    expect(g.state, GameState.start);
    expect(g.menuScene, MenuScene.home);
    expect(r.spy.params('home_slot_shown').length, 2);
    expect(g.foregroundColor, kPalettes[0]!.foreground);
    final rolls = <Powerup>[];
    for (var i = 0; i < 30; i++) {
      rolls.add(g.menu.slot.offered);
      await g.startRun();
      g.onBirdHit();
      await settle(g, t, fade: true);
      g.goHome();
      await settle(g, t, fade: true);
    }
    for (var i = 3; i < rolls.length; i++) {
      expect(rolls.sublist(i - 3, i + 1).toSet().length, greaterThan(1));
    }
  });

  for (final mode in FakeAdMode.values) {
    for (final p in [Powerup.bigHoops, Powerup.shield]) {
      e2e('QA slot ${p.name}: ${mode.name}', (g, r, t) async {
        g.menu.slot.debugForce = p;
        g.menu.slot.rollForArrival();
        await settle(g, t);
        expect(g.homeScreen!.slotButton.showsVideo, isTrue);
        expect(g.homeScreen!.slotButton.labelText, isNot(contains('✓')));
        await tap(g, t, const Offset(189, 363));
        if (mode == FakeAdMode.succeed) {
          expect(g.state, GameState.playing);
          expect(g.homeScreen, isNull);
          expect(g.menu.slot.armed, Powerup.none);
          expect(r.spy.params('ad_rewarded_shown').single, {
            'placement': 'home_slot',
          });
        } else {
          expect(g.state, GameState.start);
          expect(g.menu.slot.armed, Powerup.none);
          expect(toast(g), 'No video available right now');
          if (mode == FakeAdMode.unavailable) {
            expect(g.homeScreen!.slotButton.dimmed, isTrue);
            expect(r.ads.shown, 0);
          }
        }
        if (mode != FakeAdMode.succeed) {
          await tap(g, t, const Offset(189, 311), fade: false);
        }
        expect(g.state, GameState.playing);
        expect(g.menu.slot.armed, Powerup.none);
        if (mode == FakeAdMode.succeed) {
          expect(
            r.spy
                .params(
                  p == Powerup.bigHoops ? 'big_hoops_used' : 'shield_armed',
                )
                .length,
            1,
          );
        }
      }, configure: (r) => r.ads.mode = mode);
    }
  }

  e2e('QA no-ads owner slot starts immediately without an ad', (g, r, t) async {
    final offered = g.menu.slot.offered;
    expect(g.homeScreen!.slotButton.showsVideo, isFalse);
    await tap(g, t, const Offset(189, 363));
    expect(g.state, GameState.playing);
    expect(g.menu.slot.armed, Powerup.none);
    expect(r.ads.shown, 0);
    expect(r.spy.params('ad_rewarded_shown'), isEmpty);
    expect(
      r.spy
          .params(
            offered == Powerup.bigHoops ? 'big_hoops_used' : 'shield_armed',
          )
          .length,
      1,
    );
  }, prefs: {'noAds': true});

  for (final mode in FakeIapMode.values) {
    for (final (i, p) in IapProduct.values.take(4).indexed) {
      e2e('QA actual pack tap ${p.name}: ${mode.name}', (g, r, t) async {
        await tap(g, t, const Offset(49, 502));
        await tap(
          g,
          t,
          Offset(i.isEven ? 85 : 235, i < 2 ? 397 : 557),
          fade: false,
        );
        expect(r.iap.purchases, [p]);
        expect(
          g.menu.wallet.balance,
          mode == FakeIapMode.succeed ? p.coins : 0,
        );
        expect(g.purchases.isPending(p), mode == FakeIapMode.pending);
        if (mode == FakeIapMode.succeed) {
          expect(r.spy.params('iap_purchase').single, {'product': p.storeId});
          expect(r.spy.params('coins_earned').single, {
            'amount': p.coins,
            'source': 'iap',
          });
          expect(toast(g), contains('coins'));
        } else if (mode == FakeIapMode.fail) {
          expect(toast(g), 'Purchase failed');
        } else if (mode == FakeIapMode.pending) {
          expect(toast(g), 'Purchase pending…');
          await tap(
            g,
            t,
            Offset(i.isEven ? 85 : 235, i < 2 ? 397 : 557),
            fade: false,
          );
          expect(r.iap.purchases.length, 1);
        }
      }, configure: (r) => r.iap.mode = mode);
    }
  }

  e2e('QA free coins cooldown, daily cap, next-day reset and failed ads', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(49, 502));
    for (var i = 1; i <= 5; i++) {
      await tap(g, t, const Offset(260, 228));
      expect(g.menu.wallet.balance, i * 40);
      expect(g.shopScreen!.freeCoins.chipText, i == 5 ? 'TOMORROW' : '05:00');
      await tap(g, t, const Offset(260, 228));
      expect(r.ads.shown, i);
      r.clock.now = r.clock.now.add(const Duration(minutes: 5));
      await settle(g, t);
    }
    await tap(g, t, const Offset(260, 228));
    expect(r.ads.shown, 5);
    r.clock.now = r.clock.now.add(const Duration(days: 1));
    r.ads.mode = FakeAdMode.fail;
    await settle(g, t);
    await tap(g, t, const Offset(260, 228));
    expect(g.menu.wallet.balance, 200);
    expect(g.menu.freeCoins.claimedToday, 0);
    expect(toast(g), 'No video available right now');
    r.ads.mode = FakeAdMode.unavailable;
    await settle(g, t);
    await tap(g, t, const Offset(260, 228));
    expect(g.shopScreen!.freeCoins.chipDimmed, isTrue);
    r.ads.mode = FakeAdMode.succeed;
    await settle(g, t);
    await tap(g, t, const Offset(260, 228));
    expect(g.menu.wallet.balance, 240);
    expect(g.menu.freeCoins.claimedToday, 1);
    expect(r.spy.params('coins_earned').last, {
      'amount': 40,
      'source': 'rewarded',
    });
    expect(r.spy.params('ad_rewarded_shown').last, {
      'placement': 'shop_free_coins',
    });
  });

  e2e('S1-01 no-ads owners never receive rewarded ads in Shop', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(49, 502));
    await tap(g, t, const Offset(260, 228));
    expect(
      r.ads.shown,
      0,
      reason: 'PRD §3.5 removes all ads; §9 never show ads to buyers',
    );
  }, prefs: {'noAds': true});

  e2e('QA no-ads purchase, owner UI, bonus once and restore paths', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(271, 502));
    expect(g.noAdsPopup!.trigger, 'home_tile');
    expect(r.spy.params('noads_popup_shown').single, {'trigger': 'home_tile'});
    await tap(g, t, const Offset(160, 516));
    expect(g.menu.noAds, isTrue);
    expect(g.menu.wallet.balance, 1000);
    expect(g.noAdsPopup, isNull);
    expect(r.spy.params('noads_purchased').length, 1);
    expect(r.spy.params('coins_earned').single, {
      'amount': 1000,
      'source': 'noads_bonus',
    });
    expect(g.homeScreen!.noAdsTile.owned, isTrue);
    await tap(g, t, const Offset(49, 502));
    expect(g.shopScreen!.banner.owned, isTrue);
    await tap(g, t, const Offset(160, 658));
    expect(toast(g), 'Purchases restored');
    expect(g.menu.wallet.balance, 1000);
    await g.menu.setNoAds(false);
    await g.restorePurchases();
    await settle(g, t);
    expect(g.menu.noAds, isTrue);
    expect(g.menu.wallet.balance, 1000);
    await tap(g, t, const Offset(287, 77));
    await tap(g, t, const Offset(287, 77));
    final settings = g.world.children.query<SettingsPanel>().single;
    expect(settings.restoreLink, isNotNull);
    await tap(g, t, const Offset(160, 653));
    expect(toast(g), 'Purchases restored');
  });

  e2e('S1-02 no-ads IAP also records iap_purchase product=no_ads', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(271, 502));
    await tap(g, t, const Offset(160, 516));
    expect(g.menu.noAds, isTrue);
    expect(
      r.spy.params('iap_purchase'),
      contains(equals({'product': 'no_ads'})),
    );
  });

  e2e('QA empty restore times out with feedback', (g, r, t) async {
    g.openSettings();
    await settle(g, t, fade: true);
    await tap(g, t, const Offset(160, 653));
    stepGame(g, 12);
    await flushAndMount(g);
    expect(toast(g), 'Nothing to restore');
  });

  e2e('QA skins buy/equip/NEW and shop featured/back stack real taps', (
    g,
    r,
    t,
  ) async {
    expect(g.menu.skins.hasNewBadge, isTrue);
    await tap(g, t, const Offset(123, 502));
    expect(g.skinsScreen!.tileFor('pink').equipped, isTrue);
    expect(g.skinsScreen!.tileFor('blue').locked, isTrue);
    expect(g.menu.skins.hasNewBadge, isFalse);
    await tap(g, t, const Offset(160, 203));
    expect(g.skinDialog!.skin.id, 'blue');
    await tap(g, t, center(g.skinDialog!.confirmButton));
    expect(g.menu.wallet.balance, 1100);
    expect(g.menu.skins.equipped, 'blue');
    expect(r.spy.params('skin_purchase').single, {
      'skin': 'blue',
      'price': 100,
    });
    await tap(g, t, const Offset(60, 203));
    expect(g.menu.skins.equipped, 'pink');
    expect(r.spy.params('skin_equip').last, {'skin': 'pink'});
    await tap(g, t, const Offset(287, 77));
    expect(g.homeScreen!.bird.sprites.skin.id, 'pink');
    expect(g.homeScreen!.skinsTile.tag, isNull);
    await tap(g, t, const Offset(49, 502));
    await tap(g, t, const Offset(160, 616));
    expect(g.menuScene, MenuScene.skins);
    expect(g.skinDialog, isNotNull);
    g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
    await settle(g, t, fade: true);
    expect(g.skinDialog, isNull);
    expect(g.menuScene, MenuScene.skins);
    g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
    await settle(g, t, fade: true);
    expect(g.menuScene, MenuScene.shop);
    g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
    await settle(g, t, fade: true);
    expect(g.menuScene, MenuScene.home);
  }, prefs: {'coins': 1200});

  e2e('S1-03 skin purchase auto-equip records skin_equip', (g, r, t) async {
    await tap(g, t, const Offset(123, 502));
    await tap(g, t, const Offset(160, 203));
    await tap(g, t, center(g.skinDialog!.confirmButton));
    expect(g.menu.skins.equipped, 'blue');
    expect(r.spy.params('skin_equip'), contains(equals({'skin': 'blue'})));
  }, prefs: {'coins': 100});

  e2e('QA insufficient coins GET COINS, shop pill scroll and Esc', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(123, 502));
    await tap(g, t, const Offset(160, 203));
    expect(g.skinDialog!.insufficient, isTrue);
    expect(g.skinDialog!.confirmLabel.text, 'GET COINS');
    await tap(g, t, center(g.skinDialog!.confirmButton));
    expect(g.menuScene, MenuScene.shop);
    expect(r.spy.params('shop_open').single, {'source': 'skins_dialog'});
    g.handleBack();
    await settle(g, t, fade: true);
    expect(g.menuScene, MenuScene.skins);
    expect(g.skinDialog, isNull);
  });

  e2e('QA keyboard, settings taps/slider, debug actions, persistence', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(287, 77));
    await tap(g, t, const Offset(85, 310.5));
    await tap(g, t, const Offset(150, 370.5));
    expect(g.storage.muteSound, isTrue);
    expect(g.storage.musicVolume, closeTo(0.25, 0.01));
    g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
    await settle(g, t, fade: true);
    g.onKeyEvent(key(LogicalKeyboardKey.keyD), {});
    await settle(g, t);
    expect(g.debugPanel, isNotNull);
    await g.debugPanel!.actions[0].run();
    await g.debugPanel!.actions[2].run();
    await g.debugPanel!.actions[4].run();
    r.ads.mode = FakeAdMode.unavailable;
    g.closeDebugPanel();
    await settle(g, t);
    expect(g.menu.wallet.balance, 1000);
    expect(g.menu.slot.offered, Powerup.shield);
    await g.menu.skins.purchase('blue');
    await g.menu.setNoAds(true);
    await g.tapPowerupSlot();
    await g.menu.freeCoins.recordClaim();
    await g.menu.noAdsPopup.markShown();
    await g.menu.noAdsPopup.markDismissed();
    await settle(g, t);
    // Restart with the same SharedPreferences backend; no re-seeding.
    final restart = FlappySpikesGame(
      worldHeight: 711,
      soundEnabled: false,
      clock: r.clock.call,
    );
    await t.runAsync(() async {
      await t.pumpWidget(GameWidget(game: restart));
      await restart.ready();
      await preloadImages(restart);
      await flushAndMount(restart);
    });
    expect(restart.menu.wallet.balance, 900);
    expect(restart.menu.skins.equipped, 'blue');
    expect(restart.menu.skins.isOwned('blue'), isTrue);
    expect(restart.menu.noAds, isTrue);
    expect(restart.menu.slot.armed, Powerup.none);
    expect(restart.menu.freeCoins.claimedToday, 1);
    expect(restart.menu.freeCoins.canClaim, isFalse);
    expect(restart.storage.noAdsPopupDismissals, 1);
    expect(restart.storage.noAdsPopupLastDay, restart.storage.today);
    expect(restart.storage.muteSound, isTrue);
    expect(restart.storage.musicVolume, closeTo(0.25, 0.01));
    expect(restart.storage.slotHistory.length, 3);
    restart.purchases.dispose();
    restart.onKeyEvent(key(LogicalKeyboardKey.space), {});
    expect(restart.state, GameState.playing);
    expect(restart.menu.slot.armed, Powerup.none);
    expect(restart.world.children.query<Bird>().single.skin.id, 'blue');
    restart.onKeyEvent(key(LogicalKeyboardKey.space), {});
    expect(
      restart.world.children.query<Bird>().single.body.linearVelocity.y,
      lessThan(-200),
    );
  });

  for (final mode in [
    FakeIapMode.fail,
    FakeIapMode.pending,
    FakeIapMode.cancel,
  ]) {
    e2e('QA shop banner no-ads popup ${mode.name}', (g, r, t) async {
      await tap(g, t, const Offset(49, 502));
      await tap(g, t, const Offset(160, 172));
      expect(g.noAdsPopup!.trigger, 'shop_banner');
      expect(r.spy.params('noads_popup_shown').single, {
        'trigger': 'shop_banner',
      });
      await tap(g, t, const Offset(160, 516));
      expect(r.iap.purchases, [IapProduct.noAds]);
      expect(g.menu.noAds, isFalse);
      expect(g.menu.wallet.balance, 0);
      expect(
        g.purchases.isPending(IapProduct.noAds),
        mode == FakeIapMode.pending,
      );
      if (mode == FakeIapMode.fail) expect(toast(g), 'Purchase failed');
      if (mode == FakeIapMode.pending) {
        expect(g.noAdsPopup!.priceButton.tappable, isFalse);
        expect(toast(g), 'Purchase pending…');
      }
      g.onKeyEvent(key(LogicalKeyboardKey.space), {});
      expect(g.state, GameState.start);
      await tap(g, t, const Offset(281, 209));
      expect(g.noAdsPopup, isNull);
      expect(g.menuScene, MenuScene.shop);
      expect(r.spy.params('noads_popup_dismissed').single, {
        'trigger': 'shop_banner',
      });
    }, configure: (r) => r.iap.mode = mode);
  }

  e2e('QA popup launch policy across actual game restarts and days', (
    initial,
    r,
    t,
  ) async {
    expect(initial.noAdsPopup, isNull);
    for (var day = 2; day <= 5; day++) {
      r.clock.now = r.clock.now.add(const Duration(days: 1));
      var g = await restartWithSamePrefs(r, t);
      if (day <= 4) {
        expect(g.noAdsPopup!.trigger, 'launch');
        expect(g.storage.noAdsPopupLastDay, r.clock.day);
        await tap(g, t, const Offset(281, 209));
        expect(g.storage.noAdsPopupDismissals, day - 1);
        g = await restartWithSamePrefs(r, t);
        expect(g.noAdsPopup, isNull, reason: 'once per day');
      } else {
        expect(g.noAdsPopup, isNull, reason: 'three dismissals');
      }
    }
    expect(r.spy.params('noads_popup_shown').length, 3);
    expect(r.spy.params('noads_popup_dismissed').length, 3);
  });

  e2e('S1-04 three manual popup dismissals also stop automatic upsells', (
    g,
    r,
    t,
  ) async {
    for (var i = 0; i < 3; i++) {
      await tap(g, t, const Offset(271, 502));
      await tap(g, t, const Offset(281, 209));
    }
    expect(r.spy.params('noads_popup_dismissed').length, 3);
    r.clock.now = r.clock.now.add(const Duration(days: 1));
    final restarted = await restartWithSamePrefs(r, t);
    expect(
      restarted.noAdsPopup,
      isNull,
      reason: 'BRIEF: automatic popup stops after three dismissals',
    );
  });

  e2e(
    'QA stale persisted armed powerup is discarded on launch',
    (g, r, t) async {
      expect(g.menu.slot.armed, Powerup.none);
      expect(g.homeScreen!.slotButton.shown, Powerup.bigHoops);
      expect(r.spy.params('home_slot_shown').single, {'item': 'big_hoops'});
      await g.startRun();
      expect(r.spy.params('shield_armed'), isEmpty);
      expect(r.spy.params('big_hoops_used'), isEmpty);
    },
    prefs: {
      'armedPowerup': 'shield',
      'slotHistory': ['shield', 'shield', 'shield'],
    },
  );

  e2e('S1-06 Esc returns from game over to a new home arrival', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(189, 311), fade: false);
    g.onBirdHit();
    await settle(g, t, fade: true);
    stepGame(g, 1.5);
    await flushAndMount(g);
    expect(g.world.children.query<GameOverPanel>().single.canContinue, isTrue);
    g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
    await settle(g, t, fade: true);
    expect(
      g.state,
      GameState.start,
      reason: 'PRD §3.6: NEXT / back from game over is a home arrival',
    );
    expect(r.spy.params('home_slot_shown').length, 2);
  });

  e2e(
    'QA owned skin sprites follow equip through home, run, death',
    (g, r, t) async {
      await tap(g, t, const Offset(123, 502));
      // Row 3 centre tile is TOPHAT.
      await tap(g, t, const Offset(160, 431));
      expect(g.menu.skins.equipped, 'tophat');
      await tap(g, t, const Offset(287, 77));
      expect(g.homeScreen!.bird.sprites.skin.id, 'tophat');
      await tap(g, t, const Offset(189, 311), fade: false);
      final bird = g.world.children.query<Bird>().single;
      expect(bird.skin.id, 'tophat');
      g.onBirdHit();
      expect(bird.dead, isTrue);
      expect(bird.skin.id, 'tophat');
      await settle(g, t, fade: true);
      await capture(g, t, 'gameover_tophat');
    },
    prefs: {
      'ownedSkins': ['pink', 'tophat'],
    },
  );

  e2e(
    'QA debug reset preserves progression and changes all fake modes',
    (g, r, t) async {
      g.openDebugPanel();
      await settle(g, t);
      final actions = g.debugPanel!.actions;
      for (final action in actions) {
        if (action.label().startsWith('Ads:') ||
            action.label().startsWith('IAP:')) {
          await action.run();
        }
      }
      expect(r.ads.mode, FakeAdMode.fail);
      expect(r.iap.mode, FakeIapMode.fail);
      await actions.firstWhere((a) => a.label() == 'Reset menu state').run();
      expect(g.menu.wallet.balance, 0);
      expect(g.menu.skins.equipped, 'pink');
      expect(g.menu.noAds, isFalse);
      expect(g.menu.slot.armed, Powerup.none);
      expect(g.storage.bestScore, 12);
      expect(g.storage.gamesPlayed, 34);
      g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
      expect(g.debugPanel, isNull);
    },
    prefs: {
      'coins': 999,
      'bestScore': 12,
      'gamesPlayed': 34,
      'noAds': true,
      'armedPowerup': 'shield',
      'ownedSkins': ['pink', 'blue'],
      'equippedSkin': 'blue',
    },
  );

  for (final height in [568.0, 640.0, 711.0, 730.0]) {
    e2e('QA layout and real short-screen scroll $height', (g, r, t) async {
      final home = g.homeScreen!;
      expect(home.coinPill.y, 58);
      expect(home.gearButton.y, 58);
      expect(home.gearButton.x + home.gearButton.width, 306);
      expect(home.shopTile.x, 14);
      expect(home.leaderboard.x, 14);
      expect(
        home.bird.y + home.bird.height / 2,
        closeTo(home.startButton.y + home.startButton.height / 2, 0.001),
      );
      expect(
        (home.bird.x + home.startButton.x + home.startButton.width) / 2,
        160,
      );
      expect(
        home.slotButton.y + home.slotButton.height,
        lessThan(home.shopTile.y),
      );
      expect(
        home.subtitle.last.y + home.subtitle.last.height,
        lessThan(home.startButton.y),
      );
      expect(
        home.leaderboard.y + home.leaderboard.height,
        lessThan(height - 44),
      );
      for (final c in [
        home.coinPill,
        home.gearButton,
        home.startButton,
        home.bird,
        home.slotButton,
        ...home.tiles,
        home.leaderboard,
      ]) {
        expect(c.x, greaterThanOrEqualTo(0));
        expect(c.x + c.width, lessThanOrEqualTo(320));
        expect(c.y, greaterThanOrEqualTo(44));
        expect(c.y + c.height, lessThanOrEqualTo(height - 44));
      }
      await capture(g, t, 'home_${height.toInt()}');
      g.openShop();
      await settle(g, t, fade: true);
      final scroll = g.shopScreen!.scroll;
      await tap(g, t, const Offset(33, 77));
      if (height < 711) expect(scroll.offset, greaterThan(0));
      await t.dragFrom(const Offset(160, 400), const Offset(0, -450));
      await settle(g, t, fade: true);
      expect(scroll.offset, closeTo(scroll.maxOffset, 0.1));
      expect(
        scroll.screenY(g.shopScreen!.restoreLink.y),
        lessThan(height - 44),
      );
      await capture(g, t, 'shop_${height.toInt()}_end');
      g.closeShop();
      await settle(g, t, fade: true);
      g.openSkins();
      await settle(g, t, fade: true);
      final skins = g.skinsScreen!;
      await t.dragFrom(const Offset(160, 400), const Offset(0, -450));
      await settle(g, t, fade: true);
      expect(skins.scroll.offset, closeTo(skins.scroll.maxOffset, 0.1));
      final ghost = skins.tileFor('ghost');
      final bottom = skins.scroll.screenY(ghost.y + ghost.height);
      expect(bottom, lessThanOrEqualTo(height - 44));
      await capture(g, t, 'skins_${height.toInt()}_end');
      await tap(g, t, Offset(260, bottom - 40));
      expect(g.skinDialog!.skin.id, 'ghost');
    }, height: height);
  }
}
