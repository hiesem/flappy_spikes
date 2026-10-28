import 'package:flame/components.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/rating_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A store sheet that records its requests (the platform calls of
/// [RatingPrompt], faked).
class FakeRatingBackend implements RatingBackend {
  bool available = true;
  bool throwsOnRequest = false;
  int requests = 0;
  int availabilityChecks = 0;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<void> requestReview() async {
    requests++;
    if (throwsOnRequest) throw StateError('store refused');
  }
}

/// PRD-2.3 §23.5: the rating prompt (trigger, cooldown, timing, overlays,
/// the interstitial skip, the wrapper and analytics).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final spy = AnalyticsSpy();
  late FakeRatingBackend backend;
  late RatingPrompt rating;
  late FakeInterstitialAds interstitial;
  var now = DateTime(2026, 10, 13, 12);

  FlameTester<FlappySpikesGame> tester(
    Map<String, Object> prefs, {
    bool available = true,
    // region P26-C3R
    int? showcaseDoneAt = 3,
    // endregion
  }) => FlameTester<FlappySpikesGame>(() {
    spy.events.clear();
    now = DateTime(2026, 10, 13, 12);
    backend = FakeRatingBackend()..available = available;
    rating = RatingPrompt(backend: backend);
    interstitial = FakeInterstitialAds(mode: FakeAdMode.succeed);
    return createRunTestGame(
      // region P26-C3R
      prefs: {
        'showcaseDoneAt': ?showcaseDoneAt,
        ...prefs,
      },
      // endregion
      services: spy,
      clock: () => now,
      rating: rating,
      monetization: Monetization(
        ads: FakeRewardedAds(),
        interstitial: interstitial,
      ),
    );
  }, gameSize: Vector2(320, 568));

  /// Boots the game with the platform answer in place (the app does it at
  /// start-up).
  Future<void> boot(FlappySpikesGame g) async {
    await rating.prepare();
    await g.ready();
  }

  /// A run that ends with [score] on the results page.
  Future<void> play(FlappySpikesGame g, int score) async {
    final run = await startRun(g);
    // The run's own score (the summary) and the HUD's (the game's).
    run.state.score = score;
    g.showRunScore(score);
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
    expect(g.state, GameState.results);
  }

  /// Steps the results page until its sequence has played out. A level-up
  /// CLAIM is taken at once (its own test covers the wait).
  Future<void> untilSettled(FlappySpikesGame g) async {
    for (var i = 0; i < 900 && !g.resultsScreen!.settled; i++) {
      final page = g.resultsScreen!;
      if (page.claimShowing) page.claimButton.onPressed();
      g.update(1 / 60);
    }
    await flushAndMount(g);
    expect(g.resultsScreen!.settled, isTrue);
  }

  /// NEXT and the Home arrival.
  Future<void> home(FlappySpikesGame g) async {
    g.goHome();
    await flushAndMount(g);
    expect(g.state, GameState.start);
  }

  int requestsOf(String trigger) => spy.events
      .where((e) => e.$1 == 'rate_requested' && e.$2!['trigger'] == trigger)
      .length;

  // --- trigger --------------------------------------------------------------

  tester({'gamesPlayed': 4}).testGameWidget(
    '§23.5 trigger: with gamesPlayed reaching 5, the request happens 1.5 s '
    'after the results page settles',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 8); // run 5, a new best
      expect(g.storage.gamesPlayed, 5);
      await untilSettled(g);
      stepGame(g, 1.4);
      expect(backend.requests, 0, reason: 'not yet 1.5 s');
      stepGame(g, 0.2);
      await flushAndMount(g);
      expect(backend.requests, 1);
      expect(g.storage.lastRatingRequestAt, greaterThan(0));
      expect(
        spy.events.where((e) => e.$1 == 'rate_requested').single.$2,
        {'trigger': 'run5', 'runs': 5, 'best': 8},
      );
    },
  );

  tester({'gamesPlayed': 2}).testGameWidget(
    '§23.5 trigger: runs 1-4 make no request, even with a new best',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 8); // run 3, a new best
      await untilSettled(g);
      stepGame(g, 3);
      await home(g);
      await play(g, 12); // run 4, another new best
      await untilSettled(g);
      stepGame(g, 3);
      expect(g.storage.gamesPlayed, 4);
      expect(backend.requests, 0);
      expect(g.storage.lastRatingRequestAt, 0);
    },
  );

  tester({'gamesPlayed': 5, 'bestScore': 10}).testGameWidget(
    '§23.5 trigger: after run 5 only a new best triggers it',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 5); // run 6, no new best
      await untilSettled(g);
      stepGame(g, 3);
      expect(backend.requests, 0);
      await home(g);
      await play(g, 12); // run 7, a new best
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
      expect(requestsOf('new_best'), 1);
    },
  );

  // region P26-C3R
  tester({'gamesPlayed': 4}, showcaseDoneAt: null).testGameWidget(
    'PRD-2.6 C3: unfinished showcase suppresses runs 5 and 6, allows run 7',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      // C3R editor call: PRD silent; this follows the C3 intent.
      for (final score in [8, 12]) {
        await play(g, score);
        await untilSettled(g);
        stepGame(g, 2);
        expect(backend.requests, 0);
        expect(g.storage.lastRatingRequestAt, 0);
        await home(g);
      }
      // Null at run 7 is a harness/legacy state: the inert showcase here
      // never finishes. Production completes at the run-6 cap, then waits
      // until run 8, as covered by the late-finish test below (PRD-2.6 C3).
      expect(g.storage.showcaseDoneAt, isNull);
      await play(g, 16);
      expect(g.storage.gamesPlayed, 7);
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
    },
  );

  tester({'gamesPlayed': 6}, showcaseDoneAt: 6).testGameWidget(
    'PRD-2.6 C3: a late showcase finish waits two runs',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 8);
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 0);
      await home(g);
      await play(g, 12);
      expect(g.storage.gamesPlayed, 8);
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
    },
  );

  tester({'gamesPlayed': 8, 'bestScore': 100}).testGameWidget(
    'PRD-2.6 C3: tuned minimum triggers at run 10 without a new best',
    setUp: (g, _) async {
      final previous = TuningValues.current;
      addTearDown(() => TuningValues.current = previous);
      TuningValues.current = TuningValues.resolve({'rate_min_runs': '10'});
      await boot(g);
    },
    verify: (g, _) async {
      await play(g, 8);
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 0);
      await home(g);
      await play(g, 8);
      expect(g.storage.gamesPlayed, 10);
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
    },
  );
  // endregion

  // --- cooldown -------------------------------------------------------------

  tester({'gamesPlayed': 4}).testGameWidget(
    '§23.5 cooldown: a second qualifying run within 30 days makes no request; '
    'after 30 days (faked clock) it does',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 8); // run 5
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
      await home(g);
      now = now.add(const Duration(days: 29));
      await play(g, 20); // run 6, a new best, 29 days later
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1, reason: 'within the cooldown');
      await home(g);
      now = now.add(const Duration(days: 2));
      await play(g, 30); // run 7, 31 days after the request
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 2);
      expect(requestsOf('new_best'), 1);
    },
  );

  // --- NEXT before the 1.5 s, and overlays ----------------------------------

  tester({'gamesPlayed': 4}).testGameWidget(
    '§23.5 NEXT within 1.5 s: no request and no cooldown; the next '
    'qualifying run asks',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 8); // run 5
      await untilSettled(g);
      stepGame(g, 0.5);
      await home(g);
      stepGame(g, 3);
      expect(backend.requests, 0);
      expect(g.storage.lastRatingRequestAt, 0, reason: 'no cooldown used');
      expect(requestsOf('run5'), 0);
      await play(g, 20); // run 6, a new best: asks now
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
      expect(requestsOf('new_best'), 1);
    },
  );

  tester({'gamesPlayed': 4}).testGameWidget(
    'PRD-2.6 J7a/J4 rating waits for pending reveal payout',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      // PRD-2.6 J7a/J4: rating waits for the reveal reward to be paid.
      g.runDebug.ignoreGates = false;
      await play(g, 25); // run 5 reaches level 1
      for (var i = 0; i < 900 && !g.resultsScreen!.revealReady; i++) {
        g.update(1 / 60);
      }
      await flushAndMount(g);
      expect(g.resultsScreen!.revealReady, isTrue);
      expect(g.storage.lvlPending, isNotEmpty);
      stepGame(g, 4);
      expect(backend.requests, 0, reason: 'the reveal reward is pending');
      expect(g.resultsScreen!.settled, isFalse);
      expect(await claimLevelRewards(g, 'tap'), 50);
      expect(g.storage.lvlPending, isEmpty);
      await untilSettled(g);
      stepGame(g, 1.4);
      expect(backend.requests, 0);
      stepGame(g, 0.2);
      await flushAndMount(g);
      expect(backend.requests, 1);
    },
  );

  // --- interstitial ----------------------------------------------------------

  tester({'gamesPlayed': 4}).testGameWidget(
    '§23.5 ads: a run with a request skips the interstitial (reason rating); '
    'the next qualifying run follows the normal ad rules',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      await play(g, 8); // run 5: the interstitial is skipped
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
      expect(g.interstitialSkipReason(), InterstitialSkip.rating);
      spy.events.clear();
      await home(g);
      expect(interstitial.shown, 0);
      expect(
        spy.events
            .where((e) => e.$1 == 'ad_interstitial_skipped')
            .single
            .$2!['reason'],
        'rating',
      );
      // Run 6 is not a new best (no request): the ad plays as usual.
      await play(g, 5);
      await untilSettled(g);
      expect(g.interstitialSkipReason(), isNull);
      await home(g);
      expect(interstitial.shown, 1);
    },
  );

  // --- wrapper ----------------------------------------------------------------

  tester({'gamesPlayed': 4}, available: false).testGameWidget(
    '§23.5 wrapper: when the platform says no, no request, no cooldown, and '
    'the interstitial rules apply as usual',
    setUp: (g, _) => boot(g),
    verify: (g, _) async {
      expect(rating.available, isFalse);
      await play(g, 8); // run 5
      await untilSettled(g);
      stepGame(g, 3);
      expect(backend.requests, 0);
      expect(g.storage.lastRatingRequestAt, 0);
      expect(spy.events.where((e) => e.$1 == 'rate_requested'), isEmpty);
      expect(g.interstitialSkipReason(), isNull);
      await home(g);
      expect(interstitial.shown, 1);
    },
  );

  tester({'gamesPlayed': 4}).testGameWidget(
    '§23.5 wrapper: a refused request is swallowed; the game goes on',
    setUp: (g, _) async {
      backend.throwsOnRequest = true;
      await boot(g);
    },
    verify: (g, _) async {
      await play(g, 8);
      await untilSettled(g);
      stepGame(g, 2);
      expect(backend.requests, 1);
      await home(g);
      expect(g.state, GameState.start);
    },
  );

  tester({}).testGameWidget(
    '§23.5 settings: no Rate row (PRD-2.3 §20.5 and §23.1)',
    setUp: (g, _) async {
      await boot(g);
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, _) async {
      g.openSettings();
      await flushAndMount(g);
      stepGame(g, .6);
      await flushAndMount(g);
      final panel = g.world.children.query<SettingsPanel>().single;
      final labels = [for (final r in panel.rows) r.label.toUpperCase()];
      expect(labels, isNotEmpty);
      expect(labels.where((l) => l.contains('RATE')), isEmpty);
    },
  );

  // --- the wrapper itself -----------------------------------------------------

  test('§23.4 RatingPrompt: no backend is never available; every call is '
      'try/caught', () async {
    final none = RatingPrompt();
    expect(await none.prepare(), isFalse);
    expect(none.available, isFalse);
    expect(await none.request(), isFalse);
    final failing = RatingPrompt(backend: _ThrowingBackend());
    expect(await failing.prepare(), isFalse);
    expect(await failing.request(), isFalse);
  });

  test('§23.4 RatingRules: triggers and the 30-day cooldown', () {
    expect(Config.ratingMinRuns, 5);
    expect(Config.ratingCooldown, const Duration(days: 30));
    expect(Config.ratingDelaySeconds, 1.5);
    expect(RatingRules.trigger(runs: 4, newBest: true, minRuns: 5), isNull);
    expect(RatingRules.trigger(runs: 5, newBest: false, minRuns: 5), 'run5');
    expect(RatingRules.trigger(runs: 6, newBest: false, minRuns: 5), isNull);
    expect(
      RatingRules.trigger(runs: 6, newBest: true, minRuns: 5),
      'new_best',
    );
    final day = DateTime(2026, 10, 13);
    expect(
      RatingRules.cooldownOver(
        lastRequestAt: 0,
        now: day,
        cooldown: Config.ratingCooldown,
      ),
      isTrue,
    );
    final last = day.millisecondsSinceEpoch ~/ 1000;
    expect(
      RatingRules.cooldownOver(
        lastRequestAt: last,
        now: day.add(const Duration(days: 30)).subtract(
          const Duration(seconds: 1),
        ),
        cooldown: Config.ratingCooldown,
      ),
      isFalse,
    );
    expect(
      RatingRules.cooldownOver(
        lastRequestAt: last,
        now: day.add(const Duration(days: 30)),
        cooldown: Config.ratingCooldown,
      ),
      isTrue,
    );
  });
}

class _ThrowingBackend implements RatingBackend {
  @override
  Future<bool> isAvailable() async => throw StateError('no store');

  @override
  Future<void> requestReview() async => throw StateError('no store');
}
