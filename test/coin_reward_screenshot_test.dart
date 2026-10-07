import 'dart:math' as math;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/ui/coin_reward.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coin_reward_test.dart' show run;
import 'helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts;
import 'shop_flow_test.dart' show openShop;

/// PRD-home-v3 §5 visual check: the 10 000 pack celebration in the Shop
/// (compare with design/menu_v2/coinbuy_count.png / coinbuy_end.png),
/// written to build/menu_shots/.
void main() {
  setUpAll(loadFonts);

  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'coins': 1250}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'coin reward screenshots',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final shop = await openShop(game, scrollToCoins: true);
      final pack = shop.packs[1];
      final art = pack.stackArt;
      final p = art.absolutePosition;
      game.coinFlyRandom = math.Random(5);
      game.coinPill.hold();
      await game.menu.wallet.add(10000, CoinSource.iap);
      game.playCoinReward(
        CoinRewardAnimation.pack(
          pack.product,
          from: Rect.fromLTWH(p.x, p.y, art.width, art.height),
        ),
      );
      await flushAndMount(game);
      await run(game, .95);
      await tester.runAsync(() => captureShot(game, 1.5, 'coinbuy_flight'));
      await run(game, .5);
      await tester.runAsync(() => captureShot(game, 1.5, 'coinbuy_count'));
      await run(game, .6);
      await tester.runAsync(() => captureShot(game, 1.5, 'coinbuy_end'));
      await run(game, .45);
      await tester.runAsync(() => captureShot(game, 1.5, 'coinbuy_end2'));
    },
  );
}
