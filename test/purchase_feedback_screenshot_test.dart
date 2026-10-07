import 'dart:math' as math;

import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_screenshot_test.dart' show captureShot, loadFonts;
import 'purchase_feedback_test.dart' show run;
import 'shop_flow_test.dart' show openShop, settle, shopTest;

/// PRD-home-v3 §5–7 visual check, written to build/menu_shots/: compare
/// with design/menu_v2/coinbuy_*.png, purchase_*.png and noads_*.png.
void main() {
  setUpAll(loadFonts);

  Future<void> shot(FlappySpikesGame game, WidgetTester tester, String name) =>
      tester.runAsync(() => captureShot(game, 2, name));

  shopTest(
    'purchase feedback screenshots: coin pack',
    prefs: const {'coins': 1250},
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      game.coinFlyRandom = math.Random(5);
      shop.packs[1].onPressed();
      await settle(game);
      await run(game, 1.3);
      await shot(game, tester, 'wpi_coinbuy_count');
      await run(game, .65);
      await shot(game, tester, 'wpi_coinbuy_end');
    },
  );

  for (final mode in [FakeIapMode.fail, FakeIapMode.cancel]) {
    shopTest(
      'purchase feedback screenshots: ${mode.name}',
      prefs: const {'coins': 3050},
      iapMode: mode,
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        shop.packs[1].onPressed();
        await settle(game);
        await run(game, .6);
        await shot(
          game,
          tester,
          mode == FakeIapMode.fail
              ? 'wpi_purchase_failed'
              : 'wpi_purchase_cancelled',
        );
      },
    );
  }

  shopTest(
    'purchase feedback screenshots: No ads',
    prefs: const {'coins': 1250},
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      game.coinFlyRandom = math.Random(7);
      shop.banner.onPressed();
      await settle(game);
      await run(game, .7);
      await shot(game, tester, 'wpi_noads_celebration');
      await run(game, 1.4);
      game.noAdsCelebration!.claimButton.onPressed();
      await run(game, 1.6);
      await shot(game, tester, 'wpi_noads_claim');
      await run(game, 1.5);
      await shot(game, tester, 'wpi_noads_owned_shop_flip');
      await run(game, 1.5);
      await shot(game, tester, 'wpi_noads_owned_shop');
      game.closeShop();
      await run(game, .6);
      await shot(game, tester, 'wpi_noads_owned_home');
    },
  );
}
