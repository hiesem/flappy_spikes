import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  late FakeInterstitialAds ads;
  FlameTester<FlappySpikesGame> tester({int runs = 0}) =>
      FlameTester<FlappySpikesGame>(() {
        ads = FakeInterstitialAds(mode: FakeAdMode.succeed);
        return createRunTestGame(
          prefs: {'gamesPlayed': runs},
          monetization: Monetization(interstitial: ads),
        );
      }, gameSize: Vector2(320, 568));

  Future<void> boot(FlappySpikesGame g, WidgetTester t) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  group('S8-09 persistence', () {
    for (final waiting in [true, false]) {
      tester().testGameWidget(
        'S8-09 §18.3 periodic save during ${waiting ? 'waiting' : 'flight'} '
        'limits crash loss to 10 seconds',
        setUp: boot,
        verify: (g, t) async {
          g.onScreenTap();
          await flushAndMount(g);
          if (!waiting) {
            g.runDebug.god = true;
            g.onPlayfieldTap();
          }
          stepGame(g, 25);
          await flushAndMount(g);
          final prefs = await SharedPreferences.getInstance();
          final saved = prefs.getInt('playtimeSeconds') ?? 0;
          expect(g.storage.playtimeSeconds, greaterThanOrEqualTo(25));
          expect(g.storage.playtimeSeconds - saved, lessThanOrEqualTo(10));
        },
      );
    }

    tester().testGameWidget(
      'S8-09 §18.3 run end persists time before NEXT',
      setUp: boot,
      verify: (g, t) async {
        g.runDebug.god = true;
        await startRun(g);
        stepGame(g, 15);
        g.runDebug.god = false;
        killRunThroughSaves(g);
        await declineRevive(g);
        await flushAndMount(g);
        expect(g.state, GameState.results);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('playtimeSeconds'), g.storage.playtimeSeconds);
      },
    );
  }, skip: 'S8-09');

  group('S8-10 preload', () {
    tester(runs: 4).testGameWidget(
      'S8-10 §18.2 preload uses finished runs, not the run just started',
      setUp: boot,
      verify: (g, t) async {
        await startRun(g);
        expect(g.storage.gamesPlayed, 4);
        expect(g.storage.playtimeSeconds, lessThan(300));
        expect(ads.preloads, 0, reason: 'the fifth run has not finished');
      },
    );
  }, skip: 'S8-10');

  tester(runs: 4).testGameWidget(
    '§18 × §10 a waiting run counts foreground time but no finished run',
    setUp: boot,
    verify: (g, t) async {
      g.onScreenTap();
      await flushAndMount(g);
      stepGame(g, 12);
      expect(g.run!.started, isFalse);
      expect(g.storage.gamesPlayed, 4);
      expect(g.storage.playtimeSeconds, greaterThanOrEqualTo(12));
      expect(ads.preloads, 0);
      expect(g.interstitialSkipReason(), InterstitialSkip.newPlayer);
    },
  );
}
