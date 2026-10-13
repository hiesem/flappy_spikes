import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A store whose launch sync never answers (offline / stuck Play).
class _SilentStore extends FakeIapService {
  @override
  Future<void> syncPurchases() => Completer<void>().future;
}

/// PRD-2.3 §24.3 (QA S8-13): the first START waits for the launch purchase
/// sync, but only for [Config.launchOwnershipStartWait].
void main() {
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: 711,
      monetization: Monetization(
        iap: _SilentStore(),
        banner: FakeBannerAds(enabled: true, heightDp: 48, widthDp: 320),
      ),
    ),
    gameSize: Vector2(320, 711),
  );

  tester().testGameWidget(
    '§24.3 a launch sync that never answers delays the first START by at '
    'most the bounded wait; the run then keeps its banner',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      g.onScreenTap();
      await flushAndMount(g);
      expect(g.run, isNull, reason: 'waiting for the launch sync');
      stepGame(g, Config.launchOwnershipStartWait - .2);
      await flushAndMount(g);
      expect(g.run, isNull);
      stepGame(g, .4);
      await flushAndMount(g);
      expect(g.run, isNotNull, reason: 'the wait is bounded');
      expect(g.runHasBanner, isTrue, reason: 'not an owner');
    },
  );
}
