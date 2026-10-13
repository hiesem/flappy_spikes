import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/components/look_component.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/components/ui/service_message.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/purchases.dart' show PurchaseProblem;
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/skins/look.dart';
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
    expect(g.menu.items.look.idFor(SkinLayer.bird), 'classic');
    expect(g.menu.slot.offered, isIn([Powerup.bigHoops, Powerup.shield]));
    expect(g.noAdsPopup, isNull);
    final offered = g.menu.slot.offered;
    await tap(g, t, const Offset(300, 220));
    expect(g.state, GameState.start);
    await tap(g, t, const Offset(49, 608));
    expect(g.menuScene, MenuScene.shop);
    expect(r.spy.params('shop_open').single, {'source': 'tile'});
    await tap(g, t, const Offset(33, 77));
    expect(g.menuScene, MenuScene.home);
    expect(g.menu.slot.offered, offered);
    await tap(g, t, const Offset(287, 77));
    expect(g.menuScene, MenuScene.shop);
    expect(r.spy.params('shop_open').last, {'source': 'pill'});
    await tap(g, t, const Offset(33, 77));
    var invites = 0;
    g.onInvite = (_) => invites++;
    await tap(g, t, const Offset(197, 608));
    expect(invites, 1);
    expect(g.menu.wallet.balance, 0);
    expect(r.spy.params('invite_tap').length, 1);
    await tap(g, t, const Offset(79, 77));
    expect(r.spy.leaderboardCalls, 1);
    await tap(g, t, const Offset(189, 423.5), fade: false);
    expect(g.state, GameState.playing);
    g.onPlayfieldTap(); // PRD-2.3 §10.1 the first tap flaps
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

  e2e('QA play score is credited once, YOUR REWARD, NEXT rolls home', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(189, 423.5), fade: false);
    // PRD-2 §3.2: a coin per hoop, credited at the moment of the pass (a
    // pass with a rim touch: 1 coin, source `hoop`), kept at game over.
    await flushAndMount(g);
    expect(hoopsOf(g), isNotEmpty);
    g.run!.debugPass();
    expect(g.score, 1);
    expect(g.menu.wallet.balance, 1);
    killRun(g);
    killRun(g);
    await settle(g, t, fade: true);
    expect(g.menu.wallet.balance, 1);
    expect(g.storage.gamesPlayed, 1);
    expect(g.world.children.query<ResultsScreen>().single.model.reward, 1);
    expect(r.spy.params('coins_earned').single, {
      'amount': 1,
      'source': 'hoop',
      'egg_x2': 0,
    });
    await capture(g, t, 'gameover_1coin');
    // The results page's NEXT (PRD-2 §5.10).
    final next = g.resultsScreen!.nextButton.absoluteCenter;
    await tap(g, t, Offset(next.x, next.y));
    expect(g.state, GameState.start);
    expect(g.menuScene, MenuScene.home);
    expect(r.spy.params('home_slot_shown').length, 2);
    expect(g.foregroundColor, kPalettes[0]!.foreground);
    final rolls = <Powerup>[];
    for (var i = 0; i < 30; i++) {
      rolls.add(g.menu.slot.offered);
      await g.startRun();
      killRun(g);
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
        await tap(g, t, const Offset(189, 476.5));
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
          await tap(g, t, const Offset(189, 423.5), fade: false);
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
    await tap(g, t, const Offset(189, 476.5));
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
        await tap(g, t, const Offset(49, 608));
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
          // PRD-home-v3 §5: the coin-fly celebration replaces the toast.
          expect(g.coinReward, isNotNull);
          expect(toast(g), isNot(contains('coins')));
          expect(g.purchaseResultPopup, isNull);
        } else if (mode == FakeIapMode.fail) {
          // §6: the FAILED popup replaces the failure toast.
          expect(g.purchaseResultPopup!.problem, PurchaseProblem.failed);
          expect(r.spy.params('iap_error').single!['code'], 'fake');
        } else if (mode == FakeIapMode.cancel) {
          expect(g.purchaseResultPopup!.problem, PurchaseProblem.cancelled);
        } else if (mode == FakeIapMode.pending) {
          expect(g.purchaseResultPopup, isNull);
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
    await tap(g, t, const Offset(49, 608));
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

  e2e('S1-01 (PRD-2.2 §7.7) no-ads owners watch the Shop free-coins ad '
      'like everyone', (g, r, t) async {
    await tap(g, t, const Offset(49, 608));
    await tap(g, t, const Offset(260, 228));
    expect(
      r.ads.shown,
      1,
      reason: 'PRD-2.2 §7.7: the 40 free coins need a watched ad for everyone',
    );
  }, prefs: {'noAds': true});

  e2e('QA no-ads purchase, owner UI, bonus once and restore paths', (
    g,
    r,
    t,
  ) async {
    // PO 2026-10-05: the home tile buys straight away — no popup.
    await tap(g, t, const Offset(271, 608));
    expect(g.noAdsPopup, isNull);
    expect(r.spy.params('noads_popup_shown'), isEmpty);
    expect(r.spy.params('noads_purchase_tapped').single, {
      'source': 'home_tile',
    });
    expect(g.menu.noAds, isTrue);
    expect(g.menu.wallet.balance, 1000);
    expect(r.spy.params('noads_purchased').length, 1);
    expect(r.spy.params('coins_earned').single, {
      'amount': 1000,
      'source': 'noads_bonus',
    });
    // PRD-home-v3 §7: the celebration comes first; the tile keeps its old
    // face until CLAIM's count-up is done, then flips.
    final celebration = g.noAdsCelebration!;
    expect(r.spy.params('noads_celebration_shown').single, {'source': 'tile'});
    expect(g.homeScreen!.noAdsTile.owned, isFalse);
    expect(g.coinPill.shownBalance, 0, reason: 'bonus not shown yet');
    await tap(g, t, celebration.claimRect.center);
    expect(g.noAdsCelebration, isNull);
    expect(r.spy.params('noads_bonus_claimed').length, 1);
    for (var i = 0; i < 80; i++) {
      stepGame(g, .05);
      await flushAndMount(g);
    }
    expect(g.coinPill.shownBalance, 1000);
    expect(g.homeScreen!.noAdsTile.owned, isTrue);
    await tap(g, t, const Offset(49, 608));
    expect(g.shopScreen!.banner.owned, isTrue);
    expect(g.menu.wallet.balance, 1000);
    await g.menu.setNoAds(false);
    await g.restorePurchases();
    await settle(g, t);
    expect(g.menu.noAds, isTrue);
    expect(g.menu.wallet.balance, 1000);
    await tap(g, t, const Offset(33, 77));
    await tap(g, t, const Offset(33, 77));
    final settings = g.world.children.query<SettingsPanel>().single;
    expect(settings.restoreRow, isNotNull);
    // PRD-2.3 §20.2: GAME → Restore purchases (row 388..425 at 711).
    await tap(g, t, const Offset(160, 406));
    expect(toast(g), 'Purchases restored');
  });

  e2e('S1-02 no-ads IAP also records iap_purchase product=no_ads', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(271, 608));
    expect(r.spy.params('noads_purchase_tapped').single, {
      'source': 'home_tile',
    });
    expect(g.menu.noAds, isTrue);
    expect(
      r.spy.params('iap_purchase'),
      contains(equals({'product': 'no_ads'})),
    );
  });

  e2e('QA empty restore times out with feedback', (g, r, t) async {
    g.openSettings();
    await settle(g, t, fade: true);
    await tap(g, t, const Offset(160, 406)); // PRD-2.3 §20.2 Restore row
    stepGame(g, 12);
    await flushAndMount(g);
    expect(toast(g), 'Nothing to restore');
  });

  // Skin shop grid at scroll 0 (PRD-menu-v2 §4.1): tile i centred at
  // (60 + 100 * col, 378 + 100 * row); tab i at (43.2 + 58.4 * i, 296).
  e2e(
    'QA skin shop try-on/buy/equip/NEW and shop featured/back stack real taps',
    (g, r, t) async {
      expect(g.menu.items.hasNewBadge, isTrue);
      await tap(g, t, const Offset(123, 608));
      final shop = g.skinShop!;
      expect(shop.tileFor('classic').current.equipped, isTrue);
      expect(shop.tileFor('sky').current.owned, isFalse);
      expect(shop.tileFor('sky').current.isNew, isTrue);
      await tap(g, t, const Offset(160, 378));
      expect(shop.tryOnId, 'sky');
      expect(shop.tileFor('sky').current.isNew, isFalse);
      expect(r.spy.params('item_try_on').single, {
        'layer': 'bird',
        'id': 'sky',
        'rarity': 'COMMON',
      });
      await tap(g, t, shop.actionButton.absoluteCenter.toOffset());
      expect(g.menu.wallet.balance, 1050);
      expect(g.menu.items.look.bird, 'sky');
      expect(shop.tryOnId, isNull);
      expect(r.spy.params('item_purchase').single, {
        'layer': 'bird',
        'id': 'sky',
        'rarity': 'COMMON',
        'price': 150,
        'source': 'button',
      });
      await tap(g, t, const Offset(60, 378));
      expect(g.menu.items.look.bird, 'classic');
      expect(r.spy.params('item_equip').last, {
        'layer': 'bird',
        'id': 'classic',
      });
      await tap(g, t, const Offset(160, 296));
      expect(shop.tab, SkinLayer.hat);
      expect(r.spy.params('skin_shop_tab').single, {'layer': 'hat'});
      await tap(g, t, const Offset(33, 77));
      expect(g.menuScene, MenuScene.home);
      // Untapped affordable items keep their NEW badge.
      expect(g.homeScreen!.skinsTile.tag, 'NEW');
      await tap(g, t, const Offset(49, 608));
      await tap(g, t, const Offset(160, 616));
      expect(g.menuScene, MenuScene.skins);
      expect(g.skinShop!.tryOnId, 'sunburst'); // PRD-2.3 §19.3 featured
      g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
      await settle(g, t, fade: true);
      expect(g.menuScene, MenuScene.shop);
      g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
      await settle(g, t, fade: true);
      expect(g.menuScene, MenuScene.home);
    },
    prefs: {'coins': 1200},
  );

  e2e('S1-03 item purchase auto-equip records item_equip', (g, r, t) async {
    await tap(g, t, const Offset(123, 608));
    await tap(g, t, const Offset(160, 378));
    await tap(g, t, g.skinShop!.actionButton.absoluteCenter.toOffset());
    expect(g.menu.items.look.bird, 'sky');
    expect(
      r.spy.params('item_equip'),
      contains(equals({'layer': 'bird', 'id': 'sky'})),
    );
  }, prefs: {'coins': 150});

  e2e('QA not enough coins: toast, pill nudge, + opens the Shop, back', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(123, 608));
    await tap(g, t, const Offset(160, 378));
    await tap(
      g,
      t,
      g.skinShop!.actionButton.absoluteCenter.toOffset(),
      fade: false,
    );
    expect(g.menu.wallet.balance, 100);
    expect(
      g.skinShop!.children.query<ShopToast>().single.message,
      'NOT ENOUGH COINS',
    );
    expect(g.coinPill.flashing, isTrue);
    expect(r.spy.params('item_no_coins').single, {
      'layer': 'bird',
      'id': 'sky',
      'shortfall': 50,
    });
    await tap(g, t, center(g.coinPill));
    expect(g.menuScene, MenuScene.shop);
    g.handleBack();
    await settle(g, t, fade: true);
    expect(g.menuScene, MenuScene.skins);
    expect(g.skinShop!.tryOnId, isNull);
  }, prefs: {'coins': 100});

  e2e('QA keyboard, settings taps/slider, debug actions, persistence', (
    g,
    r,
    t,
  ) async {
    await tap(g, t, const Offset(33, 77));
    // PRD-2.3 §20.2 at 711: the SOUND tile (14..106 x 135..235), then the
    // 2nd volume bar (bars from x 26, 268 wide; y 276..306) = 2 / 8.
    await tap(g, t, const Offset(60, 185));
    await tap(g, t, const Offset(80, 300));
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
    await g.menu.items.purchase(SkinLayer.bird, 'sky');
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
    expect(restart.menu.wallet.balance, 850);
    expect(restart.menu.items.look.idFor(SkinLayer.bird), 'sky');
    expect(restart.menu.items.isOwned(SkinLayer.bird, 'sky'), isTrue);
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
    expect(
      restart.world.children.query<Bird>().single.look.idFor(SkinLayer.bird),
      'sky',
    );
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
    e2e('QA shop banner no-ads purchase ${mode.name}', (g, r, t) async {
      await tap(g, t, const Offset(49, 608));
      await tap(g, t, const Offset(160, 172));
      // PO 2026-10-05: the banner buys straight away — no popup.
      expect(g.noAdsPopup, isNull);
      expect(r.spy.params('noads_popup_shown'), isEmpty);
      expect(r.spy.params('noads_purchase_tapped').single, {
        'source': 'shop_banner',
      });
      expect(r.iap.purchases, [IapProduct.noAds]);
      expect(g.menu.noAds, isFalse);
      expect(g.menu.wallet.balance, 0);
      expect(
        g.purchases.isPending(IapProduct.noAds),
        mode == FakeIapMode.pending,
      );
      if (mode != FakeIapMode.pending) {
        // PRD-home-v3 §6: FAILED / CANCELLED popup; Esc closes it first.
        expect(
          g.purchaseResultPopup!.problem,
          mode == FakeIapMode.fail
              ? PurchaseProblem.failed
              : PurchaseProblem.cancelled,
        );
        g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
        await settle(g, t, fade: true);
        expect(g.purchaseResultPopup, isNull);
        expect(g.menuScene, MenuScene.shop);
      }
      if (mode == FakeIapMode.pending) {
        expect(g.shopScreen!.banner.tappable, isFalse);
        expect(g.shopScreen!.banner.dimmed, isTrue);
        expect(toast(g), 'Purchase pending…');
      }
      g.onKeyEvent(key(LogicalKeyboardKey.space), {});
      expect(g.state, GameState.start);
      // Nothing opened over the Shop; Esc leaves it.
      g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
      await settle(g, t, fade: true);
      expect(g.menuScene, MenuScene.home);
    }, configure: (r) => r.iap.mode = mode);
  }

  e2e('QA popup launch schedule across actual game restarts and days', (
    initial,
    r,
    t,
  ) async {
    // PRD-2.3 §24 (replaces the PRD-menu-v4 §8 numbers). Day 1, first
    // session: never.
    expect(initial.noAdsPopup, isNull);
    // Day 1, second session, 0 runs: still too early.
    var g = await restartWithSamePrefs(r, t);
    expect(g.noAdsPopup, isNull, reason: 'install day, < 10 runs');
    // Day 2 12:00: fallback (never shown before).
    r.clock.now = r.clock.now.add(const Duration(days: 1));
    g = await restartWithSamePrefs(r, t);
    expect(r.spy.params('noads_popup_shown').last, {
      'trigger': 'launch',
      'reason': 'fallback',
      'check': 'session',
    });
    expect(g.storage.noAdsPopupLastDay, r.clock.day);
    await tap(g, t, const Offset(281, 209));
    expect(g.noAdsPopup, isNull);
    expect(g.storage.noAdsPopupDismissals, 1);
    g = await restartWithSamePrefs(r, t);
    expect(g.noAdsPopup, isNull, reason: '1 h gap from the show');
    // 12:30: the gap still runs (closing did not restart it, it is the show).
    r.clock.now = r.clock.now.add(const Duration(minutes: 30));
    g = await restartWithSamePrefs(r, t);
    expect(g.noAdsPopup, isNull, reason: '30 min after the show');
    // 13:00: the gap is over, but no trigger and < 3 h since the show.
    r.clock.now = r.clock.now.add(const Duration(minutes: 30));
    g = await restartWithSamePrefs(r, t);
    expect(g.noAdsPopup, isNull, reason: 'no good moment, < 3 h');
    for (var i = 0; i < 3; i++) {
      await g.menu.noAdsPopup.recordRewardedVideo();
    }
    g = await restartWithSamePrefs(r, t);
    expect(r.spy.params('noads_popup_shown').last!['reason'], 'videos');
    g.handleBack();
    await settle(g, t);
    // 14:00, 15:00 and 16:00: three more shows (the cap is 5 a local day).
    for (var show = 3; show <= 5; show++) {
      r.clock.now = r.clock.now.add(const Duration(hours: 1));
      for (var i = 0; i < 3; i++) {
        await g.menu.noAdsPopup.recordRewardedVideo();
      }
      g = await restartWithSamePrefs(r, t);
      expect(g.noAdsPopup, isNotNull, reason: 'show $show of the day');
      g.handleBack();
      await settle(g, t);
    }
    // 17:00 with three more videos: the day's five shows are used up.
    r.clock.now = r.clock.now.add(const Duration(hours: 1));
    for (var i = 0; i < 3; i++) {
      await g.menu.noAdsPopup.recordRewardedVideo();
    }
    g = await restartWithSamePrefs(r, t);
    expect(g.noAdsPopup, isNull, reason: 'max 5 per day');
    // Day 3 00:30: the videos still count.
    r.clock.now = r.clock.now.add(const Duration(hours: 7, minutes: 30));
    g = await restartWithSamePrefs(r, t);
    expect(g.noAdsPopup, isNotNull);
    expect(r.spy.params('noads_popup_shown').last!['reason'], 'videos');
    expect(r.spy.params('noads_popup_shown').length, 6);
  });

  e2e('S1-04 dismissals never stop the launch upsell (PRD-menu-v4 §8)', (
    g,
    r,
    t,
  ) async {
    for (var i = 0; i < 5; i++) {
      r.clock.now = r.clock.now.add(const Duration(days: 1));
      final day = await restartWithSamePrefs(r, t);
      expect(day.noAdsPopup, isNotNull, reason: 'launch upsell, day ${i + 2}');
      day.handleBack();
      await settle(day, t);
    }
    expect(r.spy.params('noads_popup_dismissed').length, 5);
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
    await tap(g, t, const Offset(189, 423.5), fade: false);
    killRun(g);
    await settle(g, t, fade: true);
    stepGame(g, 1.5);
    await flushAndMount(g);
    expect(g.world.children.query<ResultsScreen>().single.canContinue, isTrue);
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
    'QA equipped look follows equip through home, run, death',
    (g, r, t) async {
      await g.menu.items.equip(SkinLayer.bird, 'toucan');
      await g.menu.items.equip(SkinLayer.hat, 'tophat');
      await settle(g, t);
      expect(g.homeScreen!.bird.look.bird, 'toucan');
      expect(g.homeScreen!.bird.look.hat, 'tophat');
      await tap(g, t, const Offset(189, 423.5), fade: false);
      final bird = g.world.children.query<Bird>().single;
      expect(bird.look.bird, 'toucan');
      expect(bird.look.hat, 'tophat');
      killRun(g);
      expect(bird.dead, isTrue);
      // The look stays on; the dead pose is frozen (hat/gear tumble along).
      expect(bird.look.bird, 'toucan');
      expect(bird.lookComponent.pose, LookPose.dead);
      await settle(g, t, fade: true);
      await capture(g, t, 'gameover_look');
    },
    prefs: {
      'ownedItems': ['bird:toucan', 'hat:tophat'],
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
      expect(g.menu.items.look.idFor(SkinLayer.bird), 'classic');
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
      'ownedItems': ['bird:sky'],
      'equippedItem.bird': 'sky',
    },
  );

  for (final height in [568.0, 640.0, 711.0, 730.0]) {
    e2e('QA layout and real short-screen scroll $height', (g, r, t) async {
      final home = g.homeScreen!;
      expect(home.coinPill.y, 58);
      expect(home.coinPill.x + home.coinPill.width, 306);
      expect(home.gearButton.y, 58);
      expect(home.gearButton.x, 14);
      expect(home.shopTile.x, 14);
      // PRD-home-v3 §3.1: trophy in the top row, BEST / LAST on the
      // margins, START / slot / emblem on the centre line.
      expect(home.trophyButton.x, 60);
      expect(home.trophyButton.y, 58);
      expect(home.bestStat.x, 14);
      expect(home.lastStat.x + home.lastStat.width, 306);
      expect(home.startButton.x + home.startButton.width / 2, 160);
      expect(home.bird.x + home.bird.width / 2, closeTo(160, 1e-9));
      expect(
        home.slotButton.y + home.slotButton.height,
        lessThan(home.shopTile.y),
      );
      expect(
        home.subtitle.y + home.subtitle.height,
        lessThan(
          Config.homePlateCentreFor(height).dy -
              90 * Config.homeEmblemScaleFor(height),
        ),
      );
      expect(Config.homeEmblemBottomFor(height), lessThan(home.startButton.y));
      for (final c in [
        home.coinPill,
        home.gearButton,
        home.trophyButton,
        home.startButton,
        home.bird,
        home.bestStat,
        home.lastStat,
        home.slotButton,
        ...home.tiles,
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
      await tap(g, t, const Offset(287, 77));
      if (height < 711) expect(scroll.offset, greaterThan(0));
      await t.dragFrom(const Offset(160, 400), const Offset(0, -450));
      await settle(g, t, fade: true);
      expect(scroll.offset, closeTo(scroll.maxOffset, 0.1));
      expect(
        scroll.screenY(
          g.shopScreen!.featured.y + g.shopScreen!.featured.height,
        ),
        lessThan(height - 44),
      );
      await capture(g, t, 'shop_${height.toInt()}_end');
      g.closeShop();
      await settle(g, t, fade: true);
      g.openSkins();
      await settle(g, t, fade: true);
      final skins = g.skinShop!;
      for (var i = 0; i < 4; i++) {
        await t.dragFrom(const Offset(160, 500), const Offset(0, -400));
        await settle(g, t);
      }
      await settle(g, t, fade: true);
      expect(skins.scroll.offset, closeTo(skins.scroll.maxOffset, 0.1));
      final last = skins.tileFor('phoenix');
      final bottom = skins.scroll.screenY(last.y + last.height / 2);
      expect(bottom, lessThanOrEqualTo(height - 44));
      await capture(g, t, 'skins_${height.toInt()}_end');
      await tap(g, t, Offset(last.x, bottom - 30));
      expect(skins.tryOnId, 'phoenix');
    }, height: height);
  }
}
