import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/rating_prompt.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

class _NativeSheet implements RatingBackend {
  final closed = Completer<void>();
  int requests = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> requestReview() {
    requests++;
    return closed.future;
  }
}

void main() {
  for (final noAds in [false, true]) {
    late _NativeSheet sheet;
    late FakeInterstitialAds interstitial;
    FlameTester<FlappySpikesGame>(() {
      sheet = _NativeSheet();
      interstitial = FakeInterstitialAds(mode: FakeAdMode.succeed);
      return createRunTestGame(
        // region P26-C3R
        // PRD-2.6 C3: run 5 is eligible once showcase finished at run 3.
        prefs: {'gamesPlayed': 4, 'showcaseDoneAt': 3, 'noAds': noAds},
        // endregion
        rating: RatingPrompt(backend: sheet),
        monetization: Monetization(interstitial: interstitial),
      );
    }, gameSize: Vector2(320, 568)).testGameWidget(
      '§23 native rating sheet lifecycle/back preserves results '
      '(No Ads $noAds)',
      setUp: (g, t) async {
        await g.ready();
        await g.rating.prepare();
        await preloadImages(g);
      },
      verify: (g, t) async {
        await startRun(g);
        killRunThroughSaves(g);
        await declineRevive(g);
        await flushAndMount(g);
        for (var i = 0; i < 900 && !g.resultsScreen!.settled; i++) {
          g.update(1 / 60);
        }
        expect(g.resultsScreen!.settled, isTrue);
        stepGame(g, 1.6);
        expect(sheet.requests, 1);
        final page = g.resultsScreen;
        final lastRequest = g.storage.lastRatingRequestAt;
        g.lifecycleStateChange(AppLifecycleState.inactive);
        expect(g.handleSystemBack(), isFalse);
        expect(g.state, GameState.results);
        expect(g.resultsScreen, same(page));
        // The native OS sheet consumes its own back/dismiss gesture; the
        // platform future completes, then the app resumes below it.
        sheet.closed.complete();
        g.lifecycleStateChange(AppLifecycleState.resumed);
        await flushAndMount(g);
        stepGame(g, 2);
        expect(sheet.requests, 1);
        expect(g.storage.lastRatingRequestAt, lastRequest);
        expect(
          g.interstitialSkipReason(),
          noAds ? InterstitialSkip.noAds : InterstitialSkip.rating,
        );
        g.goHome();
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(interstitial.shown, 0);
      },
    );
  }
}
