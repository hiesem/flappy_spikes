import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;
import 'menu_e2e_test.dart';

void main() {
  setUpAll(loadFonts);

  e2e('R2 owner CLAIM ignores unavailable ads, persists cap and cooldown', (
    initial,
    r,
    t,
  ) async {
    var g = initial;
    g.monetization.showFakeAdOverlay = true;
    r.ads.mode = FakeAdMode.unavailable;
    for (var i = 1; i <= 5; i++) {
      if (g.menuScene == MenuScene.home) {
        await tap(g, t, const Offset(49, 608));
      }
      final row = g.shopScreen!.freeCoins;
      expect(row.chipText, 'CLAIM');
      expect(row.chipDimmed, isFalse);
      expect(
        row.descendants().whereType<MenuIcon>().where(
          (c) => identical(c.sprite!.image, row.video.image),
        ),
        isEmpty,
      );
      await tap(g, t, const Offset(260, 228));
      expect(g.fakeAdOverlay, isNull);
      expect(g.menu.wallet.balance, 40 * i);
      expect(g.menu.freeCoins.claimedToday, i);
      expect(toast(g), '+40 coins');
      await tap(g, t, const Offset(260, 228));
      expect(g.menu.wallet.balance, 40 * i);
      if (i == 1) {
        g = await restartWithSamePrefs(r, t);
        g.monetization.showFakeAdOverlay = true;
        await tap(g, t, const Offset(49, 608));
        expect(g.shopScreen!.freeCoins.chipText, '05:00');
        expect(g.menu.freeCoins.claimedToday, 1);
        expect(g.menu.wallet.balance, 40);
      }
      r.clock.now = r.clock.now.add(const Duration(minutes: 5));
      await settle(g, t);
    }
    expect(g.shopScreen!.freeCoins.chipText, 'TOMORROW');
    await tap(g, t, const Offset(260, 228));
    expect(g.menu.wallet.balance, 200);
    r.clock.now = r.clock.now.add(const Duration(days: 1));
    g = await restartWithSamePrefs(r, t);
    await tap(g, t, const Offset(49, 608));
    expect(g.noAdsPopup, isNull);
    expect(g.shopScreen!.freeCoins.chipText, 'CLAIM');
    await tap(g, t, const Offset(260, 228));
    expect(g.menu.wallet.balance, 240);
    expect(g.menu.freeCoins.claimedToday, 1);
    expect(r.ads.shown, 0);
    expect(r.spy.params('ad_rewarded_shown'), isEmpty);
    expect(r.spy.params('ad_reward_earned'), isEmpty);
    expect(
      r.spy.params('coins_earned'),
      List.filled(6, {'amount': 40, 'source': 'rewarded'}),
    );
    await capture(g, t, 'round2_owner_claim_cooldown');
  }, prefs: {'noAds': true});

  for (final placement in [AdPlacement.homeSlot, AdPlacement.shopFreeCoins]) {
    for (final outcome in ['complete', 'cancel', 'fail', 'unavailable']) {
      e2e('R2 overlay analytics ${placement.name} $outcome', (g, r, t) async {
        g.monetization.showFakeAdOverlay = true;
        if (placement == AdPlacement.shopFreeCoins) {
          await tap(g, t, const Offset(49, 608));
        }
        r.ads.mode = switch (outcome) {
          'fail' => FakeAdMode.fail,
          'unavailable' => FakeAdMode.unavailable,
          _ => FakeAdMode.succeed,
        };
        await tap(
          g,
          t,
          placement == AdPlacement.homeSlot
              ? const Offset(189, 476.5)
              : const Offset(260, 228),
          fade: false,
        );
        expect(
          r.spy.params('ad_rewarded_shown').length,
          outcome == 'complete' || outcome == 'cancel' ? 1 : 0,
        );
        expect(r.spy.params('ad_reward_earned'), isEmpty);
        if (outcome == 'cancel') {
          g.onKeyEvent(key(LogicalKeyboardKey.escape), {});
        } else if (outcome != 'unavailable') {
          stepGame(g, 4);
        }
        await settle(g, t);
        expect(
          r.spy.params('ad_reward_earned'),
          outcome == 'complete'
              ? [
                  {'placement': placement.analyticsName},
                ]
              : isEmpty,
        );
        expect(
          r.spy.params('ad_rewarded_shown').length,
          outcome == 'complete' || outcome == 'cancel' ? 1 : 0,
        );
        expect(
          g.menu.wallet.balance,
          outcome == 'complete' && placement == AdPlacement.shopFreeCoins
              ? 40
              : 0,
        );
      });
    }
  }

  e2e('R2 long frame clamps bird and hoop translation to 1/30 second', (
    g,
    r,
    t,
  ) async {
    await g.startRun();
    await flushAndMount(g);
    g.update(1 / 60);
    final b = g.world.children.query<Bird>().single;
    final run = g.run!;
    final hoop = hoopsOf(g).single;
    final y = b.body.position.y;
    final x = hoop.planeX - run.state.camX;
    final speed = run.state.forwardSpeed;
    g.update(1);
    expect((b.body.position.y - y).abs(), lessThan(17));
    expect(x - (hoop.planeX - run.state.camX), closeTo(speed / 30, 0.05));
    expect(g.state, GameState.playing);
  });

  e2e('S2-01 stalled frame keeps spawning on the same clock as physics', (
    g,
    r,
    t,
  ) async {
    await g.startRun();
    await flushAndMount(g);
    g.update(1 / 60);
    expect(hoopsOf(g).length, 1);
    // One frame lasting a whole hoop interval, e.g. app resume / a debugger
    // stall. The world advances only 1/30 s, so no new hoop is due yet.
    g.update(2.1);
    await flushAndMount(g);
    final hoops = hoopsOf(g).toList();
    stepGame(g, 0.75, flapBelow: 355);
    await capture(g, t, 'round2_stalled_frame_hoops');
    expect(
      hoops.length,
      1,
      reason: 'Only ~0.05 s of simulation elapsed; PRD-2 §3.0.1 requires '
          '${RunConfig.spacing} pt hoop spacing.',
    );
  });
}
