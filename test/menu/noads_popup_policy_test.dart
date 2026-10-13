import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/noads_popup_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-menu-v4 §8: the No-ads popup schedule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  final start = DateTime(2026, 5, 10, 12);

  int dayOf(DateTime t) =>
      DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(1970)).inDays;

  /// A loaded storage + a policy whose session has started. [prefs] seed
  /// SharedPreferences; by default an install from yesterday whose first
  /// session is over (the popup window is open).
  Future<(GameStorage, NoAdsPopupPolicy)> build({
    Map<String, Object>? prefs,
    bool session = true,
  }) async {
    now = start;
    SharedPreferences.setMockInitialValues(
      prefs ?? {'installDay': dayOf(start) - 1, 'firstSessionDone': true},
    );
    final storage = GameStorage(clock: () => now);
    await storage.load();
    final policy = NoAdsPopupPolicy(storage);
    if (session) await policy.startSession();
    return (storage, policy);
  }

  group('window', () {
    test('open window, never shown: fallback', () async {
      final (_, policy) = await build();
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('no evaluation before a session started', () async {
      final (_, policy) = await build(session: false);
      expect(policy.evaluate(), isNull);
    });

    test('first session never, even on day 2 with 10 runs', () async {
      final (storage, policy) = await build(prefs: {});
      expect(policy.inFirstSession, isTrue);
      expect(storage.firstSessionDone, isTrue, reason: 'persisted for later');
      storage.debugDayOffset = 3;
      storage.gamesPlayed = 20;
      expect(policy.evaluate(), isNull);
      // The next session (back after the session gap) is not first.
      await policy.startSession();
      expect(policy.inFirstSession, isFalse);
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('a relaunch after the first session is not first', () async {
      final (storage, _) = await build(prefs: {});
      final relaunch = NoAdsPopupPolicy(storage);
      await relaunch.startSession();
      expect(relaunch.inFirstSession, isFalse);
    });

    test('installs from before the flag are past their first session',
        () async {
      final (_, policy) = await build(prefs: {'installDay': dayOf(start) - 3});
      expect(policy.inFirstSession, isFalse);
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('install day: closed until 10 finished runs', () async {
      final (storage, policy) = await build(
        prefs: {'installDay': dayOf(start), 'firstSessionDone': true},
      );
      storage.gamesPlayed = Config.noAdsPopupMinRuns - 1;
      expect(policy.pastWarmUp, isFalse);
      expect(policy.evaluate(), isNull);
      storage.gamesPlayed = Config.noAdsPopupMinRuns;
      expect(policy.pastWarmUp, isTrue);
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('install day 2 opens it with 0 runs', () async {
      final (storage, policy) = await build(
        prefs: {'installDay': dayOf(start), 'firstSessionDone': true},
      );
      expect(policy.evaluate(), isNull);
      now = DateTime(2026, 5, 11, 0, 1);
      expect(storage.gamesPlayed, 0);
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('never for owners', () async {
      final (storage, policy) = await build();
      await storage.saveNoAds(true);
      await storage.saveNoAdsPopupVideos(9);
      await storage.saveLastRunMood(RunMood.best);
      expect(policy.evaluate(), isNull);
    });
  });

  group('gap and daily cap', () {
    test('1 h gap (PRD-2.3 §24.2): blocked just before, open at exactly 1 h', () async {
      final (storage, policy) = await build();
      expect(Config.noAdsPopupMinGap, const Duration(hours: 1));
      await policy.markShown();
      await storage.saveNoAdsPopupVideos(Config.noAdsPopupVideos);
      now = start.add(Config.noAdsPopupMinGap - const Duration(seconds: 1));
      expect(policy.evaluate(), isNull);
      now = start.add(Config.noAdsPopupMinGap);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
    });

    test('closing does not restart the gap: it runs from the last show', () async {
      final (storage, policy) = await build();
      await storage.saveNoAdsPopupVideos(3);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
      await policy.markShown();
      await policy.markDismissed();
      now = start.add(const Duration(minutes: 59));
      await storage.saveNoAdsPopupVideos(3);
      expect(policy.evaluate(), isNull, reason: 'closed, but 59 min since the show');
      now = start.add(Config.noAdsPopupMinGap);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
    });

    test('max 5 per local day (PRD-2.3 §24.2); the count resets at the rollover', () async {
      final (storage, policy) = await build();
      expect(Config.noAdsPopupMaxPerDay, 5);
      // Five shows on 10 May, an hour apart (each with a good moment).
      for (var h = 8; h < 13; h++) {
        now = DateTime(2026, 5, 10, h);
        await storage.saveNoAdsPopupVideos(3);
        expect(policy.evaluate(), NoAdsPopupReason.videos, reason: 'show ${h - 7}');
        await policy.markShown();
      }
      expect(policy.showsToday, 5);
      now = DateTime(2026, 5, 10, 20);
      await storage.saveNoAdsPopupVideos(5);
      expect(policy.evaluate(), isNull, reason: 'five today');
      now = DateTime(2026, 5, 11, 0, 30);
      expect(policy.showsToday, 0);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
    });

    test('day rollover alone does not bypass the 1 h gap', () async {
      final (storage, policy) = await build();
      now = DateTime(2026, 5, 10, 23, 30);
      await policy.markShown();
      await storage.saveNoAdsPopupVideos(3);
      now = DateTime(2026, 5, 11, 0, 29);
      expect(policy.evaluate(), isNull);
      now = DateTime(2026, 5, 11, 0, 30);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
    });

    test('the debug day offset moves the wall clock on too', () async {
      final (storage, policy) = await build();
      await policy.markShown();
      expect(policy.evaluate(), isNull);
      storage.debugDayOffset = 1;
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });
  });

  group('triggers', () {
    test('videos: 3 since the last show, reset by the show', () async {
      final (storage, policy) = await build();
      await policy.markShown();
      now = start.add(const Duration(hours: 2));
      await policy.recordRewardedVideo();
      await policy.recordRewardedVideo();
      expect(policy.evaluate(), isNull, reason: 'two videos, < 3 h');
      await policy.recordRewardedVideo();
      expect(storage.noAdsPopupVideos, 3);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
      await policy.markShown();
      expect(storage.noAdsPopupVideos, 0);
    });

    test('best and level from the previous run; level wins', () async {
      final (storage, policy) = await build();
      await policy.markShown();
      now = start.add(const Duration(hours: 2));
      await policy.recordRun(newBest: true, newLevel: false);
      expect(policy.evaluate(), NoAdsPopupReason.best);
      await policy.recordRun(newBest: true, newLevel: true);
      expect(policy.evaluate(), NoAdsPopupReason.level);
      await policy.recordRun(newBest: false, newLevel: false);
      expect(policy.evaluate(), isNull, reason: 'only the previous run');
      await policy.recordRun(newBest: true, newLevel: false);
      await policy.markShown();
      expect(storage.lastRunMood, RunMood.none, reason: 'used up');
    });

    test('videos win over a good run', () async {
      final (storage, policy) = await build();
      await storage.saveNoAdsPopupVideos(3);
      await policy.recordRun(newBest: true, newLevel: true);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
    });

    test('3 h fallback (PRD-2.3 §24.2): not at 2:59, yes at exactly 3 h', () async {
      final (_, policy) = await build();
      expect(Config.noAdsPopupFallback, const Duration(hours: 3));
      await policy.markShown();
      now = start.add(const Duration(hours: 2, minutes: 59));
      expect(policy.evaluate(), isNull);
      now = start.add(Config.noAdsPopupFallback);
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('never right after a run below 6 points', () async {
      final (storage, policy) = await build();
      await storage.saveNoAdsPopupVideos(9);
      await storage.saveLastScore(Config.noAdsPopupMinScore - 1);
      expect(policy.evaluate(), isNull);
      await storage.saveLastScore(Config.noAdsPopupMinScore);
      expect(policy.evaluate(), NoAdsPopupReason.videos);
    });
  });

  group('closing', () {
    test('dismissals only count; no limit, no back-off', () async {
      final (storage, policy) = await build();
      for (var i = 0; i < 4; i++) {
        expect(policy.evaluate(), isNotNull, reason: 'show $i');
        await policy.markShown();
        await policy.markDismissed();
        now = now.add(Config.noAdsPopupFallback);
      }
      expect(storage.noAdsPopupDismissals, 4);
      // The 3 h fallback is due again, on the next day (the cap is per day).
      expect(policy.evaluate(), NoAdsPopupReason.fallback);
    });

    test('markShown / markDismissed persist', () async {
      final (storage, policy) = await build();
      await storage.saveNoAdsPopupVideos(4);
      await policy.markShown();
      await policy.markDismissed();
      final reader = GameStorage(clock: () => now);
      await reader.load();
      expect(reader.noAdsPopupLastDay, dayOf(start));
      expect(reader.noAdsPopupLastMs, start.millisecondsSinceEpoch);
      expect(reader.noAdsPopupShowsToday, 1);
      expect(reader.noAdsPopupVideos, 0);
      expect(reader.noAdsPopupDismissals, 1);
      expect(reader.firstSessionDone, isTrue);
    });
  });
}
