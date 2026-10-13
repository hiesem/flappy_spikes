import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/rating_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A store sheet that only records its requests (PRD-2.3 §23).
class _RatingSheet implements RatingBackend {
  int requests = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> requestReview() async => requests++;
}

int _dayOf(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(1970)).inDays;

/// PRD-2.3 §24.5: the No-Ads popup schedule (after-run check, 1 h gap, 5 a
/// day, 3 h fallback), its collisions and the owners' rules (§24.3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final spy = AnalyticsSpy();
  late FakeBannerAds banner;
  late FakeInterstitialAds interstitial;
  late _RatingSheet sheet;
  var now = DateTime(2026, 10, 13, 12);

  /// The popup window: installed yesterday, the first session over. The
  /// last show was [lastShowMinutesAgo] before 12:00 (default: long ago).
  Map<String, Object> window({
    int lastShowMinutesAgo = 100000,
    int shows = 0,
    Map<String, Object> extra = const {},
  }) {
    final base = DateTime(2026, 10, 13, 12);
    final today = _dayOf(base);
    final lastMs = lastShowMinutesAgo >= 100000
        ? 0
        : base
              .subtract(Duration(minutes: lastShowMinutesAgo))
              .millisecondsSinceEpoch;
    return {
      'installDay': today - 1,
      'firstSessionDone': true,
      'gamesPlayed': 12,
      'noAdsPopupLastMs': lastMs,
      'noAdsPopupLastDay': today,
      'noAdsPopupShowsToday': shows,
      'bestScore': 100,
      ...extra,
    };
  }

  FlameTester<FlappySpikesGame> tester(
    Map<String, Object> prefs, {
    bool interstitialSucceeds = false,
    bool rating = false,
  }) => FlameTester<FlappySpikesGame>(() {
    spy.events.clear();
    now = DateTime(2026, 10, 13, 12);
    banner = FakeBannerAds(enabled: true, heightDp: 48, widthDp: 320);
    interstitial = FakeInterstitialAds(
      mode: interstitialSucceeds ? FakeAdMode.succeed : FakeAdMode.unavailable,
    );
    sheet = _RatingSheet();
    return createRunTestGame(
      prefs: prefs,
      services: spy,
      clock: () => now,
      rating: rating ? RatingPrompt(backend: sheet) : null,
      monetization: Monetization(
        ads: FakeRewardedAds(),
        banner: banner,
        interstitial: interstitial,
      ),
    );
  }, gameSize: Vector2(320, 711));

  late WidgetTester currentTester;

  Future<void> boot(FlappySpikesGame g, WidgetTester tester) async {
    currentTester = tester;
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  List<Map<String, Object>?> shownParams() => [
    for (final e in spy.events)
      if (e.$1 == 'noads_popup_shown') e.$2,
  ];

  Future<void> saveVideos(FlappySpikesGame g, int videos) async {
    await g.storage.saveNoAdsPopupVideos(videos);
  }

  /// Lets the popup close the way the player does (×).
  Future<void> dismiss(FlappySpikesGame g) async {
    g.closeNoAdsPopup();
    await flushAndMount(g);
  }

  /// Lets the arrival's fire-and-forget storage reload (`GameStorage.load`)
  /// finish before any popup can open on that arrival: the test binding only
  /// delivers platform replies between real turns.
  Future<void> ioSettle() async {
    for (var round = 0; round < 4; round++) {
      for (var i = 0; i < 20; i++) {
        await Future<void>.value();
      }
      await currentTester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  /// One run that ends with [score] (on the results page, NEXT pressed).
  /// The Home arrival's storage reload is fire-and-forget: real time lets
  /// the preference writes of the arrival land first.
  Future<void> run(FlappySpikesGame g, int score) async {
    final r = await startRun(g);
    r.state.score = score;
    g.showRunScore(score);
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
    stepGame(g, 1);
    g.goHome();
    await ioSettle();
    await flushAndMount(g);
    expect(g.state, GameState.start);
  }

  // --- the after-run check ----------------------------------------------------

  tester(window(lastShowMinutesAgo: 30)).testGameWidget(
    '§24.5 after-run check: with the window open and a good moment, the '
    'popup shows on the Home arrival after a run, not only at session start',
    setUp: boot,
    verify: (g, _) async {
      expect(g.noAdsPopup, isNull, reason: 'launch: the 1 h gap is not over');
      now = now.add(const Duration(minutes: 40));
      await saveVideos(g, 3);
      await run(g, 8);
      expect(g.noAdsPopup, isNotNull);
      expect(shownParams().single, {
        'trigger': 'launch',
        'reason': 'videos',
        'check': 'after_run',
      });
    },
  );

  tester(window(lastShowMinutesAgo: 30)).testGameWidget(
    '§24.5 after-run check: a new best of the run is the good moment',
    setUp: boot,
    verify: (g, _) async {
      expect(g.noAdsPopup, isNull, reason: 'no good moment at launch');
      now = now.add(const Duration(minutes: 40));
      await run(g, 120); // a new best (the saved best is 100)
      expect(g.noAdsPopup, isNotNull);
      expect(shownParams().single!['reason'], 'best');
      expect(shownParams().single!['check'], 'after_run');
    },
  );

  // --- the gap ------------------------------------------------------------------

  tester(window(lastShowMinutesAgo: 30)).testGameWidget(
    '§24.5 gap: not within 1 h of the last show, even when it was closed; '
    'at 1 h it can',
    setUp: boot,
    verify: (g, _) async {
      // The last show was 30 min before the test starts (11:30): 70 min later
      // the gap is over.
      now = now.add(const Duration(minutes: 40));
      await saveVideos(g, 3);
      await run(g, 8);
      expect(g.noAdsPopup, isNotNull, reason: '70 min after the last show');
      await dismiss(g);
      expect(g.storage.noAdsPopupClosedMs, isNot(0));
      now = now.add(const Duration(minutes: 30));
      await saveVideos(g, 3);
      await run(g, 8);
      expect(g.noAdsPopup, isNull, reason: '30 min after the show');
      now = now.add(const Duration(minutes: 31));
      await run(g, 8);
      expect(g.noAdsPopup, isNotNull, reason: '61 min after the show');
    },
  );

  // --- the daily cap ------------------------------------------------------------

  tester(window(lastShowMinutesAgo: 120)).testGameWidget(
    '§24.5 cap: 5 shows a local day (1 h apart), the 6th does not happen, '
    'and the next day it can',
    setUp: boot,
    verify: (g, _) async {
      for (var i = 1; i <= 5; i++) {
        now = now.add(const Duration(hours: 1));
        await saveVideos(g, 3);
        await run(g, 8);
        expect(g.noAdsPopup, isNotNull, reason: 'show $i of the day');
        await dismiss(g);
      }
      expect(g.menu.noAdsPopup.showsToday, 5);
      now = now.add(const Duration(hours: 1));
      await saveVideos(g, 3);
      await run(g, 8);
      expect(g.noAdsPopup, isNull, reason: 'the 6th of the day');
      // The next local day (the debug day offset would do the same).
      now = DateTime(2026, 10, 14, 0, 30);
      await run(g, 8);
      expect(g.noAdsPopup, isNotNull, reason: 'the cap is per day');
      expect(g.menu.noAdsPopup.showsToday, 1);
    },
  );

  // --- the fallback -------------------------------------------------------------

  tester(window(lastShowMinutesAgo: 150)).testGameWidget(
    '§24.5 fallback: with no good moment it shows 3 h after the last show, '
    'not earlier',
    setUp: boot,
    verify: (g, _) async {
      await run(g, 8); // 2 h 30 min after the show: no good moment
      expect(g.noAdsPopup, isNull);
      now = now.add(const Duration(minutes: 29)); // 2 h 59 min
      await run(g, 8);
      expect(g.noAdsPopup, isNull, reason: 'not before 3 h');
      now = now.add(const Duration(minutes: 1)); // 3 h
      await run(g, 8);
      expect(g.noAdsPopup, isNotNull);
      expect(shownParams().single!['reason'], 'fallback');
      expect(shownParams().single!['check'], 'after_run');
    },
  );

  // --- unchanged rules ----------------------------------------------------------

  tester({'gamesPlayed': 12}).testGameWidget(
    '§24.5 unchanged: never in the first session, even after runs with good '
    'moments',
    setUp: boot,
    verify: (g, _) async {
      expect(g.menu.noAdsPopup.inFirstSession, isTrue);
      await saveVideos(g, 3);
      await run(g, 8);
      await run(g, 9);
      expect(g.noAdsPopup, isNull);
      expect(shownParams(), isEmpty);
    },
  );

  tester(window(lastShowMinutesAgo: 120)).testGameWidget(
    '§24.5 unchanged: never right after a run below 6 points',
    setUp: boot,
    verify: (g, _) async {
      await saveVideos(g, 3);
      await run(g, 5);
      expect(g.noAdsPopup, isNull, reason: 'the run scored 5');
      await run(g, 8);
      expect(g.noAdsPopup, isNotNull);
    },
  );

  // --- collisions ---------------------------------------------------------------

  tester(
    window(lastShowMinutesAgo: 30, extra: {'gamesPlayed': 4}),
    rating: true,
  ).testGameWidget(
    '§24.5 collisions: never on the arrival of a run that requested the '
    'rating sheet (run 5)',
    setUp: boot,
    verify: (g, _) async {
      await saveVideos(g, 3);
      now = now.add(const Duration(minutes: 40));
      await g.rating.prepare();
      await startRunAndSettle(g, 8); // run 5: the sheet is requested
      expect(sheet.requests, 1);
      g.goHome();
      await flushAndMount(g);
      expect(g.noAdsPopup, isNull, reason: 'the rating run has no popup');
      expect(shownParams(), isEmpty);
      now = now.add(const Duration(hours: 2));
      await saveVideos(g, 3);
      await run(g, 8); // run 6: the popup may show again
      expect(g.noAdsPopup, isNotNull);
      expect(shownParams().single!['check'], 'after_run');
    },
  );

  tester(
    window(lastShowMinutesAgo: 30),
    interstitialSucceeds: true,
  ).testGameWidget(
    '§24.5 collisions: the popup may show right after an interstitial, at '
    'most one per arrival',
    setUp: boot,
    verify: (g, _) async {
      now = now.add(const Duration(minutes: 40));
      await saveVideos(g, 3);
      await startRunAndSettle(g, 8);
      g.goHome(); // the interstitial plays between NEXT and Home
      await flushAndMount(g);
      expect(spy.events.where((e) => e.$1 == 'ad_interstitial_shown').length, 1);
      expect(g.state, GameState.start);
      expect(g.noAdsPopup, isNotNull, reason: 'on that same arrival');
      expect(shownParams().length, 1);
      await flushAndMount(g);
      expect(shownParams().length, 1, reason: 'one offer per arrival');
    },
  );

  tester(window(lastShowMinutesAgo: 30)).testGameWidget(
    '§24.5 collisions: a popup on the arrival of a run and no LEVEL UP or '
    'second offer on that arrival',
    setUp: boot,
    verify: (g, _) async {
      now = now.add(const Duration(minutes: 40));
      await saveVideos(g, 3);
      await run(g, 8);
      expect(shownParams().length, 1);
      expect(g.queuedPopups, 0);
    },
  );

  // --- owners (24.3) --------------------------------------------------------------

  tester(window(extra: {'noAds': true, 'noAdsPopupVideos': 9})).testGameWidget(
    '§24.5 owners: no banner, no banner load on Home, no interstitial, no '
    'popup, and the tile is in its owned state',
    setUp: boot,
    verify: (g, _) async {
      expect(g.noAdsShown, isTrue);
      expect(g.bannerWanted, isFalse);
      expect(banner.preloads, 0);
      expect(g.noAdsPopup, isNull);
      await run(g, 9);
      expect(g.noAdsPopup, isNull);
      expect(spy.events.where((e) => e.$1 == 'noads_popup_shown'), isEmpty);
      expect(g.interstitialSkipReason(), InterstitialSkip.noAds);
      expect(interstitial.shown, 0);
      expect(banner.preloads, 0);
    },
  );

  tester(window(extra: {'noAds': true})).testGameWidget(
    '§24.5 owners: a restore at launch means the first run has no banner',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      expect(r, isNotNull);
      expect(g.bannerState.value, BannerState.off);
      expect(g.runHasBanner, isFalse);
      expect(banner.preloads, 0);
    },
  );

  tester(window(lastShowMinutesAgo: 30)).testGameWidget(
    '§24.5 owners: a purchase mid-run keeps this run\'s banner; the next run '
    'has none',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      expect(g.bannerState.value, BannerState.showing);
      await g.storage.saveNoAds(true); // the purchase lands during the run
      stepGame(g, 1);
      expect(g.bannerState.value, BannerState.showing, reason: 'this run');
      killRunThroughSaves(g);
      await declineRevive(g);
      stepGame(g, 2); // the death tumble, then the results page
      await flushAndMount(g);
      expect(g.state, GameState.results);
      await ioSettle(); // the results page finishes loading
      g.goHome();
      await ioSettle();
      await flushAndMount(g);
      expect(g.bannerState.value, BannerState.off, reason: 'on Home');
      await startRun(g);
      expect(g.bannerState.value, BannerState.off);
      expect(g.runHasBanner, isFalse);
    },
  );
}

/// Starts a run and plays it out to the settled results page, then steps
/// 1.6 s (the rating sheet's count) on it; a level-up CLAIM is taken.
Future<void> startRunAndSettle(FlappySpikesGame g, int score) async {
  final r = await startRun(g);
  r.state.score = score;
  g.showRunScore(score);
  killRunThroughSaves(g);
  await declineRevive(g);
  await flushAndMount(g);
  for (var i = 0; i < 900 && !g.resultsScreen!.settled; i++) {
    final page = g.resultsScreen!;
    if (page.claimShowing) page.claimButton.onPressed();
    g.update(1 / 60);
  }
  await flushAndMount(g);
  stepGame(g, 1.6);
  await flushAndMount(g);
}
