import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/ad_grace.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// PRD-2.3 §18.5: the new-player ad grace (5 runs or 5 minutes of playtime),
/// the playtime counter and the `first_interstitial` event.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdGrace (§18.2)', () {
    test('ends after 5 finished runs or 300 s of playtime, whichever first', () {
      expect(Config.adsGraceRuns, 5);
      expect(Config.adsGraceSeconds, 300);
      expect(AdGrace.active(runs: 0, playtimeSeconds: 0), isTrue);
      expect(AdGrace.active(runs: 4, playtimeSeconds: 0), isTrue);
      expect(AdGrace.active(runs: 5, playtimeSeconds: 0), isFalse);
      expect(AdGrace.active(runs: 1, playtimeSeconds: 299), isTrue);
      expect(AdGrace.active(runs: 1, playtimeSeconds: 300), isFalse);
    });
  });

  final spy = AnalyticsSpy();
  late FakeInterstitialAds interstitial;
  late FakeRewardedAds rewarded;
  var now = DateTime(2026, 10, 13, 12);

  FlameTester<FlappySpikesGame> tester(Map<String, Object> prefs) =>
      FlameTester<FlappySpikesGame>(() {
        spy.events.clear();
        now = DateTime(2026, 10, 13, 12);
        interstitial = FakeInterstitialAds(mode: FakeAdMode.succeed);
        rewarded = FakeRewardedAds();
        return createRunTestGame(
          prefs: prefs,
          services: spy,
          clock: () => now,
          monetization: Monetization(ads: rewarded, interstitial: interstitial),
        );
      }, gameSize: Vector2(320, 568));

  /// Starts a run, dies (no revive: no hoops passed), and stops on results.
  Future<void> toResults(FlappySpikesGame g) async {
    await startRun(g);
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
    expect(g.state, GameState.results);
    stepGame(g, 1);
  }

  /// NEXT, then the interstitial decision: the skip reason, or null when
  /// the video ad played.
  Future<String?> next(FlappySpikesGame g) async {
    spy.events.clear();
    g.goHome();
    await flushAndMount(g);
    expect(g.state, GameState.start);
    final skipped = spy.events.where((e) => e.$1 == 'ad_interstitial_skipped');
    if (spy.events.any((e) => e.$1 == 'ad_interstitial_shown')) {
      expect(skipped, isEmpty);
      return null;
    }
    return skipped.single.$2!['reason'] as String;
  }

  /// Lets the fire-and-forget prefs writes land.
  Future<void> settle(FlappySpikesGame g) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.value();
    }
    await flushAndMount(g);
  }

  tester({'gamesPlayed': 3}).testGameWidget(
    '§18.5 grace by runs: with 4 finished runs and no playtime, NEXT goes '
    'Home without an ad (reason new_player)',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      await toResults(g);
      expect(g.storage.gamesPlayed, 4);
      expect(g.interstitialSkipReason(), InterstitialSkip.newPlayer);
      expect(await next(g), 'new_player');
      expect(interstitial.shown, 0);
    },
  );

  tester({'gamesPlayed': 4}).testGameWidget(
    '§18.5 grace by runs ends with the 5th run: the 2.2 rules apply',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      await toResults(g);
      expect(g.storage.gamesPlayed, 5);
      expect(await next(g), isNull);
      expect(interstitial.shown, 1);
    },
  );

  tester({'gamesPlayed': 1, 'playtimeSeconds': 300}).testGameWidget(
    '§18.5 grace by time: 300 s of playtime ends it at run 2',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      await toResults(g);
      expect(g.storage.gamesPlayed, 2);
      expect(await next(g), isNull);
      expect(interstitial.shown, 1);
    },
  );

  tester({'gamesPlayed': 2}).testGameWidget(
    '§18.5 preload: the runs of the grace load nothing; run 5 loads the '
    'interstitial',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      Future<void> finishRun() async {
        killRunThroughSaves(g);
        await declineRevive(g);
        await flushAndMount(g);
        stepGame(g, 1);
      }

      await startRun(g); // run 3
      expect(interstitial.preloads, 0, reason: 'run 3 is in the grace');
      await finishRun();
      expect(await next(g), 'new_player');
      await startRun(g); // run 4
      expect(interstitial.preloads, 0, reason: 'run 4 is in the grace');
      await finishRun();
      expect(await next(g), 'new_player');
      await startRun(g); // run 5
      expect(interstitial.preloads, 0, reason: 'run 5 has not finished');
      await finishRun();
      expect(interstitial.preloads, 1, reason: '5 finished runs end it');
      await next(g);
      await startRun(g); // run 6
      expect(interstitial.preloads, 2, reason: 'run 6 is past the grace');
    },
  );

  // S8-10: the preload uses the finished-run predicate of the show.
  tester({'gamesPlayed': 4}).testGameWidget(
    '§18.5 preload: the run that becomes run 5 loads at its end',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      await startRun(g);
      expect(interstitial.preloads, 0);
      killRunThroughSaves(g);
      await declineRevive(g);
      await flushAndMount(g);
      expect(interstitial.preloads, 1);
    },
  );

  // --- playtime counter ---------------------------------------------------

  tester({}).testGameWidget(
    '§18.5 counter: counts only while resumed',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      stepGame(g, 2.5);
      final before = g.storage.playtimeSeconds;
      expect(before, greaterThanOrEqualTo(2));
      g.lifecycleStateChange(AppLifecycleState.inactive);
      g.lifecycleStateChange(AppLifecycleState.paused);
      stepGame(g, 10);
      expect(g.storage.playtimeSeconds, before, reason: 'paused: no count');
      g.lifecycleStateChange(AppLifecycleState.resumed);
      stepGame(g, 5.5);
      expect(g.storage.playtimeSeconds, greaterThanOrEqualTo(before + 5));
    },
  );

  tester({'gamesPlayed': 5}).testGameWidget(
    '§18.5 counter: no longer counted once the grace has ended',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      stepGame(g, 12);
      expect(g.storage.playtimeSeconds, 0);
      await settle(g);
      final reader = GameStorage(clock: () => now);
      await reader.load();
      expect(reader.playtimeSeconds, 0);
    },
  );

  tester({}).testGameWidget(
    '§18.5 counter: saved every 10 s and on going to the background; '
    'survives an app restart',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      stepGame(g, 10.5);
      await settle(g);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('playtimeSeconds');
      expect(saved, isNotNull, reason: 'written every 10 s');
      expect(saved, greaterThanOrEqualTo(10));
      stepGame(g, 3);
      g.lifecycleStateChange(AppLifecycleState.paused);
      await settle(g);
      expect(prefs.getInt('playtimeSeconds'), g.storage.playtimeSeconds);
      final reader = GameStorage(clock: () => now);
      await reader.load();
      expect(reader.playtimeSeconds, g.storage.playtimeSeconds);
    },
  );

  tester({}).testGameWidget(
    '§18.5 counter: Delete my data keeps it (like gamesPlayed)',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      stepGame(g, 4.5);
      final before = g.storage.playtimeSeconds;
      expect(before, greaterThan(0));
      g.lifecycleStateChange(AppLifecycleState.paused);
      g.lifecycleStateChange(AppLifecycleState.resumed);
      await g.storage.resetVersusData();
      expect(g.storage.playtimeSeconds, before);
      await settle(g);
      final reader = GameStorage(clock: () => now);
      await reader.load();
      expect(reader.playtimeSeconds, before);
    },
  );

  // --- analytics ----------------------------------------------------------

  tester({'gamesPlayed': 4}).testGameWidget(
    '§18.4 first_interstitial fires once, with runs and playtime_s',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      await toResults(g);
      expect(await next(g), isNull);
      final first = spy.events.where((e) => e.$1 == 'first_interstitial');
      expect(first.length, 1);
      expect(first.single.$2!['runs'], 5);
      expect(first.single.$2!['playtime_s'], isA<int>());
      expect(g.storage.firstInterstitialShown, isTrue);
      now = now.add(const Duration(seconds: 61));
      await toResults(g);
      expect(await next(g), isNull);
      expect(interstitial.shown, 2);
      expect(
        spy.events.where((e) => e.$1 == 'first_interstitial'),
        isEmpty,
        reason: 'the second interstitial does not send it',
      );
    },
  );

  tester({'gamesPlayed': 4}).testGameWidget(
    '§18.4 first_interstitial carries runs and playtime_s',
    setUp: (g, _) async => g.ready(),
    verify: (g, _) async {
      await toResults(g);
      spy.events.clear();
      g.goHome();
      await flushAndMount(g);
      final first = spy.events.where((e) => e.$1 == 'first_interstitial');
      expect(first.single.$2, {
        'runs': 5,
        'playtime_s': g.storage.playtimeSeconds,
      });
    },
  );
}
