import 'package:flappy_spikes/components/fake_ad_overlay.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/noads_popup.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/shop/shop_screen.dart';
import 'package:flappy_spikes/components/skins/skin_unlock_dialog.dart';
import 'package:flappy_spikes/components/skins/skins_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;
import 'menu_e2e_test.dart' show e2e, tap, settle, capture, key, toast;

void main() {
  setUpAll(loadFonts);

  e2e('QA menu transitions finish within 170 ms', (g, r, t) async {
    // Measure game time directly, without settle's extra fade allowance.
    // Exactly 170 ms in six frames: a single update is clamped to
    // Config.maxFrameStep (one simulation clock, DECISIONS #18).
    Future<void> advance() async {
      await flushAndMount(g);
      stepGame(g, 0.17, dt: 0.17 / 6);
      await flushAndMount(g);
    }

    g.openShop();
    await advance();
    expect(g.shopScreen!.opacity, 1);
    expect(g.world.children.query<HomeScreen>(), isEmpty);
    g.closeShop();
    await advance();
    expect(g.homeScreen!.opacity, 1);
    expect(g.world.children.query<ShopScreen>(), isEmpty);
    g.openSkins();
    await advance();
    expect(g.skinsScreen!.opacity, 1);
    g.tapSkin('blue');
    await advance();
    expect(g.skinDialog!.opacity, 1);
    g.closeSkinDialog();
    await advance();
    expect(g.world.children.query<SkinUnlockDialog>(), isEmpty);
    g.closeSkins();
    await advance();
    expect(g.homeScreen!.opacity, 1);
    expect(g.world.children.query<SkinsScreen>(), isEmpty);
    g.openSettings();
    await advance();
    expect(g.world.children.query<SettingsPanel>().single.opacity, 1);
    expect(g.world.children.query<HomeScreen>(), isEmpty);
    g.closeSettings();
    await advance();
    expect(g.homeScreen!.opacity, 1);
    expect(g.world.children.query<SettingsPanel>(), isEmpty);
    g.openNoAdsPopup('home_tile');
    await advance();
    expect(g.noAdsPopup!.opacity, 1);
    g.closeNoAdsPopup();
    await advance();
    expect(g.world.children.query<NoAdsPopup>(), isEmpty);
    await g.startRun();
    await advance();
    expect(g.world.children.query<HomeScreen>(), isEmpty);
  });

  for (final placement in [AdPlacement.homeSlot, AdPlacement.shopFreeCoins]) {
    e2e('QA actual fake ad tap/countdown/input ${placement.name}', (
      g,
      r,
      t,
    ) async {
      g.monetization.showFakeAdOverlay = true;
      if (placement == AdPlacement.shopFreeCoins) {
        await tap(g, t, const Offset(49, 502));
      }
      await tap(
        g,
        t,
        placement == AdPlacement.homeSlot
            ? const Offset(189, 363)
            : const Offset(260, 228),
        fade: false,
      );
      final overlay = g.fakeAdOverlay!;
      expect(overlay.placement, placement);
      expect(overlay.secondsLeft, 3);
      expect(overlay.messageText, '3');
      expect(
        overlay.descendants().whereType<MenuText>().map((c) => c.text),
        contains('TEST AD'),
      );
      expect(g.state, GameState.start);
      await capture(g, t, 'fake_ad_${placement.name}');
      // Tap inside the card at the underlying START's PRD position.
      await tap(g, t, const Offset(189, 311), fade: false);
      g.onKeyEvent(key(LogicalKeyboardKey.space), {});
      g.openShop();
      g.openSkins();
      g.openSettings();
      g.openDebugPanel();
      expect(g.debugPanel, isNull);
      expect(
        g.menuScene,
        placement == AdPlacement.homeSlot ? MenuScene.home : MenuScene.shop,
      );
      expect(g.state, GameState.start);
      expect(g.menu.wallet.balance, 0);
      // Update in increments so countdown observations are independent
      // of the Flutter timer scheduler.
      stepGame(g, 1);
      expect(overlay.secondsLeft, 2);
      stepGame(g, 1);
      expect(overlay.secondsLeft, 1);
      stepGame(g, 1);
      expect(overlay.granted, isTrue);
      expect(overlay.messageText, 'REWARD GRANTED');
      stepGame(g, 0.9);
      await settle(g, t);
      expect(g.fakeAdOverlay, isNull);
      expect(g.menu.slot.armed.name, 'none');
      if (placement == AdPlacement.homeSlot) {
        expect(g.state, GameState.playing);
        expect(
          r.spy.params('big_hoops_used').length +
              r.spy.params('shield_armed').length,
          1,
        );
      } else {
        expect(g.menu.wallet.balance, 40);
        expect(g.menu.freeCoins.claimedToday, 1);
      }
      expect(r.spy.params('ad_rewarded_shown').single, {
        'placement': placement.analyticsName,
      });
      g.update(0.17);
      await flushAndMount(g);
      expect(g.world.children.query<FakeAdOverlay>(), isEmpty);
    });

    e2e('S1-07 visible canceled fake ad logs shown ${placement.name}', (
      g,
      r,
      t,
    ) async {
      g.monetization.showFakeAdOverlay = true;
      if (placement == AdPlacement.shopFreeCoins) {
        await tap(g, t, const Offset(49, 502));
      }
      await tap(
        g,
        t,
        placement == AdPlacement.homeSlot
            ? const Offset(189, 363)
            : const Offset(260, 228),
        fade: false,
      );
      expect(g.fakeAdOverlay, isNotNull);
      g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
      await settle(g, t, fade: true);
      expect(g.fakeAdOverlay, isNull);
      expect(g.state, GameState.start);
      expect(g.menu.wallet.balance, 0);
      expect(toast(g), 'No video available right now');
      expect(
        r.spy.params('ad_rewarded_shown'),
        contains(equals({'placement': placement.analyticsName})),
        reason:
            'PRD §6/§8 measures ads shown, including ads closed before earning the reward',
      );
    });

    e2e('QA fake ad failure and unavailable ${placement.name}', (
      g,
      r,
      t,
    ) async {
      g.monetization.showFakeAdOverlay = true;
      if (placement == AdPlacement.shopFreeCoins) {
        await tap(g, t, const Offset(49, 502));
      }
      final position = placement == AdPlacement.homeSlot
          ? const Offset(189, 363)
          : const Offset(260, 228);
      r.ads.mode = FakeAdMode.fail;
      await tap(g, t, position, fade: false);
      expect(g.fakeAdOverlay!.messageText, 'Ad failed to load');
      stepGame(g, 1.5);
      await settle(g, t);
      expect(g.fakeAdOverlay, isNull);
      expect(g.state, GameState.start);
      expect(g.menu.wallet.balance, 0);
      expect(toast(g), 'No video available right now');
      r.ads.mode = FakeAdMode.unavailable;
      await tap(g, t, position, fade: false);
      expect(g.fakeAdOverlay, isNull);
      expect(r.ads.shown, 1);
    });
  }

  e2e('S1-08 leaderboard input blocked throughout delayed rewarded ad', (
    g,
    r,
    t,
  ) async {
    r.ads.delay = const Duration(seconds: 2);
    await tap(g, t, const Offset(189, 363), fade: false);
    for (final position in [
      const Offset(189, 311),
      const Offset(49, 502),
      const Offset(123, 502),
      const Offset(197, 502),
      const Offset(271, 502),
      const Offset(287, 77),
      const Offset(33, 77),
      const Offset(49, 609),
    ]) {
      await tap(g, t, position, fade: false);
    }
    g.onKeyEvent(key(LogicalKeyboardKey.space), {});
    expect(g.state, GameState.start);
    expect(g.menuScene, MenuScene.home);
    expect(g.noAdsPopup, isNull);
    expect(r.ads.shown, 1);
    expect(r.spy.leaderboardCalls, 0);
    expect(r.spy.params('invite_tap'), isEmpty);
    await t.pump(const Duration(seconds: 2));
    await flushAndMount(g);
    expect(g.state, GameState.playing);
    expect(g.menu.slot.armed.name, 'none');
  });
}
