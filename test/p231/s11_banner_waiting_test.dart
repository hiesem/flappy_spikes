import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §11: the gameplay banner shows the moment the waiting game screen
/// appears (the hovering bird), before the first tap. The VS intro keeps the
/// strip reserved and empty; the interstitial still starts on the first tap.
void main() {
  late FakeBannerAds banner;
  late FakeInterstitialAds interstitial;

  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    VersusService? versus,
  }) => FlameTester<FlappySpikesGame>(() {
    banner = FakeBannerAds(enabled: true, heightDp: 48, widthDp: 320);
    interstitial = FakeInterstitialAds();
    return createRunTestGame(
      prefs: prefs,
      worldHeight: 711,
      versus: versus,
      monetization: Monetization(
        ads: FakeRewardedAds(),
        banner: banner,
        interstitial: interstitial,
      ),
    );
  }, gameSize: Vector2(320, 711));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  tester(prefs: {'gamesPlayed': 5}).testGameWidget(
    'PRD-2.3.1 §11 a run waiting for its first tap shows the banner before '
    'any tap; the interstitial preload waits for the tap',
    setUp: boot,
    verify: (g, _) async {
      final run = await openRun(g);
      expect(run.waiting, isTrue);
      expect(g.bannerState.value, BannerState.showing);
      expect(g.runHasBanner, isTrue);
      expect(interstitial.preloads, 0, reason: 'the first flight starts it');
      // Still waiting a while later: the banner stays.
      await stepSeconds(g, 2);
      expect(run.waiting, isTrue);
      expect(g.bannerState.value, BannerState.showing);
      expect(interstitial.preloads, 0);
      g.onPlayfieldTap();
      expect(run.waiting, isFalse);
      expect(g.bannerState.value, BannerState.showing);
      expect(interstitial.preloads, 1);
    },
  );

  tester(prefs: {'gamesPlayed': 5, 'noAds': true}).testGameWidget(
    'PRD-2.3.1 §11 NO ADS owners get no banner on the waiting screen',
    setUp: boot,
    verify: (g, _) async {
      final run = await openRun(g);
      expect(run.waiting, isTrue);
      expect(g.bannerState.value, BannerState.off);
      expect(g.runHasBanner, isFalse);
    },
  );

  final versus = FakeVersusService(
    pool: [
      OpponentRun(
        uid: 'u1',
        name: 'BrightOwl',
        score: 3,
        best: 9,
        level: 1,
        timeline: RunTimeline()
          ..addPoint(1)
          ..addPoint(2)
          ..addPoint(3)
          ..end(4),
      ),
    ],
  );
  tester(prefs: {'gamesPlayed': 5}, versus: versus).testGameWidget(
    'PRD-2.3.1 §11 VERSUS: the strip stays reserved and empty through the VS '
    'intro; the banner shows once the waiting screen is up',
    setUp: (g, t) async {
      await boot(g, t);
      await g.versus.prefetch();
    },
    verify: (g, _) async {
      g.onScreenTap();
      await flushAndMount(g);
      expect(g.state, GameState.versusIntro);
      expect(g.bannerState.value, BannerState.reservedEmpty);
      final states = <BannerState>{};
      for (var i = 0; i < 1200 && g.state == GameState.versusIntro; i++) {
        states.add(g.bannerState.value);
        g.update(1 / 30);
        await Future<void>.value();
      }
      await flushAndMount(g);
      expect(states, {BannerState.reservedEmpty});
      expect(g.state, GameState.playing);
      final run = g.run!;
      expect(run.waiting, isTrue);
      expect(g.bannerState.value, BannerState.showing);
      expect(interstitial.preloads, 0);
      g.onPlayfieldTap();
      expect(g.bannerState.value, BannerState.showing);
      expect(interstitial.preloads, 1, reason: 'still on the first tap');
    },
  );
}
