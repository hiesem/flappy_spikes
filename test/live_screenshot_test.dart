import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart' hide escape;

import 'helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts;
import 'shop_flow_test.dart' show openShop, shopTest;

/// Renders the live home & Shop (PRD-menu-v2 §8) to `build/menu_shots/`
/// for the side-by-side check against `design/menu_v2/live_home.png`,
/// `live_shop.png` and `live_shop_get.png`: home at the slot's pulse peak
/// and mid light streak, the Shop with the price streaks running and the
/// GET pulse, and a frame in the middle of the free-coins coin fly.
void main() {
  setUpAll(loadFonts);

  shopTest(
    'live screenshot: home',
    prefs: const {
      'coins': 1250,
      'bestScore': 12,
      'gamesPlayed': 34,
      'claimedLevels': ['1'], // no LEVEL UP popup over the captures
    },
    verify: (game, spy, ads, iap, tester) async {
      game.menu.slot.debugForce = Powerup.bigHoops;
      game.menu.slot.rollForArrival();
      final home = game.homeScreen!;
      stepGame(game, 1.6 - home.clock.t);
      await tester.runAsync(() => captureShot(game, 2, 'live_home_pulse'));
      stepGame(game, 6.4 + 0.9 - home.clock.t);
      await tester.runAsync(() => captureShot(game, 2, 'live_home_streak'));
    },
  );

  shopTest(
    'live screenshot: shop',
    prefs: const {'coins': 1250},
    verify: (game, spy, ads, iap, tester) async {
      final shop = await openShop(game);
      // Streaks on the lower packs (delays 1.58 / 2.02 s) and GET near
      // its pulse peak.
      stepGame(game, 6.4 * 2 + 2.3 - shop.clock.t);
      await tester.runAsync(() => captureShot(game, 2, 'live_shop'));
      await game.claimFreeCoins();
      await flushAndMount(game);
      stepGame(game, 0.25 + 0.07 * 3 + 0.3);
      await tester.runAsync(() => captureShot(game, 2, 'live_shop_get'));
    },
  );
}
