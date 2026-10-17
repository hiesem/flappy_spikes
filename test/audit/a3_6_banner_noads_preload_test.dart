import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Audit A3-6: the banner service preloads on its own (end of initialize,
/// on a consent change, on its load-retry timer), so No-Ads owners still
/// requested and retried banners. The game now tells the service whether a
/// banner is wanted at all ([BannerAds.preloadWanted]).
void main() {
  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  FakeBannerAds banner() => FakeBannerAds(enabled: true);

  late FakeBannerAds noAdsBanner;
  FlameTester<FlappySpikesGame>(() {
    noAdsBanner = banner();
    return createRunTestGame(
      worldHeight: 711,
      monetization: Monetization(banner: noAdsBanner),
      prefs: {'noAds': true},
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'A3-6 a No-Ads owner: the service\'s own preloads (consent, retry) '
    'request no banner',
    setUp: boot,
    verify: (g, _) async {
      expect(g.menu.noAds, isTrue);
      expect(noAdsBanner.preloads, 0, reason: 'the game never asks');
      // What the service does by itself at the end of initialize, on a
      // consent change and from its retry timer:
      noAdsBanner.preload();
      expect(noAdsBanner.preloads, 0);
    },
  );

  late FakeBannerAds adsBanner;
  FlameTester<FlappySpikesGame>(() {
    adsBanner = banner();
    return createRunTestGame(
      worldHeight: 711,
      monetization: Monetization(banner: adsBanner),
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'A3-6 a player with ads: the banner still preloads on Home',
    setUp: boot,
    verify: (g, _) async {
      expect(g.menu.noAds, isFalse);
      expect(adsBanner.preloads, 1);
      expect(adsBanner.loaded.value, isTrue);
    },
  );
}
