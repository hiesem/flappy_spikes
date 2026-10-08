import 'dart:async';

import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/menu/noads_popup_policy.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart' show killRun;
import '../menu_screenshot_test.dart' show loadFonts;
import '../purchase_feedback_test.dart' show run;
import '../shop_flow_test.dart' show openShop;
import 'menu_v4_qa_helpers.dart';

Map<String, Object> _recent(V4Rig rig) => {
  ...rig.eligible,
  'noAdsPopupLastMs': rig.clock.now.millisecondsSinceEpoch,
  'noAdsPopupLastDay': rig.clock.day,
  'noAdsPopupShowsToday': 1,
};

class _OutcomeAds extends FakeRewardedAds {
  _OutcomeAds(this.result);
  final AdResult result;

  @override
  Future<AdResult> show(
    AdPlacement placement, {
    void Function()? onShown,
  }) async {
    if (result == AdResult.dismissed) onShown?.call();
    return result;
  }
}

void main() {
  setUpAll(loadFonts);

  v4Journey(
    'v4: first session stays blocked; day-2 cold start offers fallback',
    (game, rig, tester) async {
      expect(game.menu.noAdsPopup.inFirstSession, isTrue);
      expect(game.noAdsPopup, isNull);
      await v4Background(
        game,
        rig,
        tester,
        const Duration(minutes: 29, seconds: 59),
      );
      expect(game.noAdsPopup, isNull);
      expect(game.menu.noAdsPopup.inFirstSession, isTrue);
      rig.clock.now = rig.clock.now.add(const Duration(days: 1));
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.menu.noAdsPopup.inFirstSession, isFalse);
      expect(restarted.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'fallback');
      expect(
        restarted.storage.noAdsPopupLastMs,
        rig.clock.now.millisecondsSinceEpoch,
      );
      expect(restarted.storage.noAdsPopupShowsToday, 1);
    },
  );

  v4Journey(
    'v4: day 1 needs 10 finished runs, then a new session; never between runs',
    prefs: (rig) => {'installDay': rig.clock.day, 'firstSessionDone': true},
    (game, rig, tester) async {
      for (var i = 0; i < 9; i++) {
        await v4FinishRun(game, tester, 6);
        expect(game.noAdsPopup, isNull);
      }
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull);
      await v4FinishRun(game, tester, 6);
      expect(game.storage.gamesPlayed, 10);
      expect(game.noAdsPopup, isNull);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'fallback');
    },
  );

  v4Journey(
    'v4: day 2 with zero runs and 100 prior dismissals is eligible',
    prefs: (rig) => {...rig.eligible, 'noAdsPopupDismissals': 100},
    (game, rig, tester) async {
      expect(game.storage.gamesPlayed, 0);
      expect(game.noAdsPopup, isNotNull);
      game.handleBack();
      await v4Settle(game, tester);
      expect(game.storage.noAdsPopupDismissals, 101);
    },
  );

  v4Journey('v4: 10 runs in the first session still need a later session', (
    game,
    rig,
    tester,
  ) async {
    for (var i = 0; i < 10; i++) {
      await v4FinishRun(game, tester, 6);
    }
    expect(game.storage.gamesPlayed, 10);
    expect(game.menu.noAdsPopup.inFirstSession, isTrue);
    expect(game.noAdsPopup, isNull);
    expect(game.menu.noAdsPopup.evaluate(), isNull);
    await v4Background(game, rig, tester, v4SessionGap);
    expect(game.noAdsPopup, isNotNull);
  });

  v4Journey(
    'v4: two videos persist through restart; the third enables the next arrival',
    prefs: _recent,
    (game, rig, tester) async {
      await v4Videos(game, tester, 2);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.storage.noAdsPopupVideos, 2);
      expect(restarted.noAdsPopup, isNull);
      await v4Videos(restarted, tester, 1);
      expect(
        restarted.noAdsPopup,
        isNull,
        reason: 'video completion is no arrival',
      );
      await v4Background(restarted, rig, tester, v4SessionGap);
      expect(restarted.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'videos');
    },
  );

  v4Journey(
    'v4: persisted owners with every trigger never receive scheduled offers',
    prefs: (rig) => {
      ...rig.eligible,
      'noAds': true,
      'noAdsPopupVideos': 100,
      'lastRunMood': RunMood.level,
      'lastScore': 60,
      'gamesPlayed': 20,
    },
    (game, rig, tester) async {
      expect(game.noAdsPopup, isNull);
      await v4Background(game, rig, tester, const Duration(days: 2));
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.noAdsPopup, isNull);
      expect(rig.events.count('noads_popup_shown'), 0);
    },
  );

  v4Journey(
    'v4: inactive is no session; 29:59 background is no session; 30:00 is',
    eligible: true,
    (game, rig, tester) async {
      game.handleBack();
      await v4Settle(game, tester);
      await v4Videos(game, tester, 3);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
      game.lifecycleStateChange(AppLifecycleState.inactive);
      game.lifecycleStateChange(AppLifecycleState.resumed);
      await v4Settle(game, tester);
      expect(game.noAdsPopup, isNull);
      await v4Background(
        game,
        rig,
        tester,
        const Duration(minutes: 29, seconds: 59),
      );
      expect(game.noAdsPopup, isNull);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'videos');
      expect(game.storage.noAdsPopupVideos, 0);
      expect(rig.events.count('noads_popup_shown'), 2);
    },
  );

  v4Journey(
    'v4: 4-hour boundary is exact across real resume events',
    eligible: true,
    (game, rig, tester) async {
      game.handleBack();
      await v4Settle(game, tester);
      await v4Videos(game, tester, 3);
      rig.clock.now = DateTime(2026, 10, 7, 11, 29, 59);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull, reason: '3:59:59 since shown');
      rig.clock.now = DateTime(2026, 10, 7, 11, 30);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNotNull, reason: 'exactly 4 hours');
    },
  );

  v4Journey(
    'v4: two per day, restart retains the cap, local midnight resets it',
    eligible: true,
    (game, rig, tester) async {
      game.handleBack();
      await v4Settle(game, tester);
      await v4Videos(game, tester, 3);
      rig.clock.now = DateTime(2026, 10, 7, 11, 30);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.storage.noAdsPopupShowsToday, 2);
      game.handleBack();
      await v4Settle(game, tester);
      await v4Videos(game, tester, 3);
      rig.clock.now = DateTime(2026, 10, 7, 16);
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.noAdsPopup, isNull);
      expect(restarted.storage.noAdsPopupShowsToday, 2);
      expect(restarted.storage.noAdsPopupVideos, 3);
      rig.clock.now = DateTime(2026, 10, 7, 23, 30);
      await v4Background(restarted, rig, tester, v4SessionGap);
      expect(restarted.noAdsPopup, isNotNull);
      expect(restarted.storage.noAdsPopupShowsToday, 1);
      expect(restarted.storage.noAdsPopupLastDay, rig.clock.day);
      expect(rig.events.count('noads_popup_shown'), 3);
    },
  );

  v4Journey(
    'v4: midnight does not bypass 4 hours; fallback is exact at 24 hours',
    prefs: (rig) => {
      ...rig.eligible,
      'noAdsPopupLastMs': DateTime(2026, 10, 6, 23).millisecondsSinceEpoch,
      'noAdsPopupLastDay': rig.clock.day - 1,
      'noAdsPopupShowsToday': 2,
    },
    (game, rig, tester) async {
      // At 08:00 the gap is open, but there is no trigger and not yet 24 h.
      expect(game.noAdsPopup, isNull);
      rig.clock.now = DateTime(2026, 10, 7, 22, 59, 59);
      var restarted = await v4Restart(game, rig, tester);
      expect(restarted.noAdsPopup, isNull);
      rig.clock.now = DateTime(2026, 10, 7, 23);
      restarted = await v4Restart(restarted, rig, tester);
      expect(restarted.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'fallback');
      restarted.handleBack();
      await v4Settle(restarted, tester);
      await v4Videos(restarted, tester, 3);
      rig.clock.now = DateTime(2026, 10, 8, 2, 29, 59);
      await v4Background(restarted, rig, tester, v4SessionGap);
      expect(restarted.noAdsPopup, isNull);
      rig.clock.now = DateTime(2026, 10, 8, 2, 30);
      await v4Background(restarted, rig, tester, v4SessionGap);
      expect(restarted.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'videos');
    },
  );

  for (final score in [5, 6, 10]) {
    v4Journey(
      'v4: finished run $score -> persisted mood -> session arrival',
      prefs: _recent,
      (game, rig, tester) async {
        await v4FinishRun(game, tester, score);
        expect(game.storage.lastScore, score);
        expect(game.storage.gamesPlayed, 1);
        expect(
          game.storage.lastRunMood,
          score >= 10 ? RunMood.level : RunMood.best,
        );
        expect(game.noAdsPopup, isNull);
        if (score >= 10) {
          await run(game, .5);
          expect(game.levelUpPopup, isNotNull);
          await game.claimLevelUp();
          await v4Settle(game, tester);
        }
        rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
        final restarted = await v4Restart(game, rig, tester);
        expect(restarted.storage.lastScore, score);
        expect(restarted.storage.gamesPlayed, 1);
        if (score < 6) {
          expect(restarted.noAdsPopup, isNull);
          expect(rig.events.count('noads_popup_shown'), 0);
          await v4FinishRun(restarted, tester, 6);
          await v4Background(restarted, rig, tester, v4SessionGap);
          expect(restarted.noAdsPopup, isNotNull);
          expect(rig.events.last('noads_popup_shown')!['reason'], 'best');
        } else {
          expect(restarted.noAdsPopup, isNotNull);
          expect(
            rig.events.last('noads_popup_shown')!['reason'],
            score >= 10 ? 'level' : 'best',
          );
          expect(restarted.storage.lastRunMood, RunMood.none);
        }
      },
    );
  }

  v4Journey(
    'v4: only the latest run supplies the best/level trigger',
    prefs: _recent,
    (game, rig, tester) async {
      await v4FinishRun(game, tester, 8);
      expect(game.storage.lastRunMood, RunMood.best);
      await v4FinishRun(game, tester, 6);
      expect(game.storage.lastRunMood, RunMood.none);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull);
    },
  );

  v4Journey(
    'v4: completed free-coins and slot videos count; the slot starts a run',
    prefs: _recent,
    (game, rig, tester) async {
      await openShop(game);
      for (var i = 0; i < 2; i++) {
        await game.claimFreeCoins();
        await v4Settle(game, tester);
        rig.clock.now = rig.clock.now.add(const Duration(minutes: 6));
      }
      expect(game.storage.noAdsPopupVideos, 2);
      expect(game.menu.wallet.balance, 80);
      game.closeShop();
      await run(game, .5);
      await game.tapPowerupSlot();
      await v4Settle(game, tester);
      expect(game.state, GameState.playing);
      expect(game.storage.noAdsPopupVideos, 3);
      expect(game.noAdsPopup, isNull, reason: 'never after START');
      game.score = 6;
      killRun(game);
      await v4Settle(game, tester);
      game.goHome();
      await run(game, .3);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'videos');
    },
  );

  for (final outcome in [
    AdResult.dismissed,
    AdResult.failed,
    AdResult.unavailable,
  ]) {
    v4Journey(
      'v4: $outcome videos do not feed the three-video trigger',
      prefs: _recent,
      ads: _OutcomeAds(outcome),
      (game, rig, tester) async {
        await v4Videos(game, tester, 3);
        expect(game.storage.noAdsPopupVideos, 0);
        rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
        await v4Background(game, rig, tester, v4SessionGap);
        expect(game.noAdsPopup, isNull);
      },
    );
  }

  v4Journey(
    'v4: LEVEL UP -> queued upsell -> purchase failure is serialized',
    prefs: (rig) => {..._recent(rig), 'bestScore': 10, 'lastScore': 10},
    (game, rig, tester) async {
      await run(game, .5);
      expect(game.levelUpPopup, isNotNull);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull);
      expect(game.queuedPopups, 1);
      game.openPurchaseResultPopup(
        IapProduct.coins1000,
        PurchaseProblem.failed,
        'network',
      );
      expect(game.queuedPopups, 2);
      expect(v4ModalCount(game), 1);
      await game.claimLevelUp();
      await v4Settle(game, tester);
      expect(game.noAdsPopup, isNotNull);
      expect(game.purchaseResultPopup, isNull);
      expect(v4ModalCount(game), 1);
      game.handleBack();
      await v4Settle(game, tester);
      expect(game.purchaseResultPopup!.problem, PurchaseProblem.failed);
      expect(v4ModalCount(game), 1);
      game.handleBack();
      await run(game, .5);
      expect(v4ModalCount(game), 0);
    },
  );

  v4Journey(
    'v4: cancelled purchase goes first, then the queued session upsell',
    prefs: _recent,
    (game, rig, tester) async {
      (rig.iap as FakeIapService).mode = FakeIapMode.cancel;
      unawaited(game.buyNoAds('home_tile'));
      await v4Settle(game, tester);
      expect(game.purchaseResultPopup!.problem, PurchaseProblem.cancelled);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull);
      expect(game.queuedPopups, 1);
      game.handleBack();
      await v4Settle(game, tester);
      expect(game.noAdsPopup, isNotNull);
      expect(v4ModalCount(game), 1);
    },
  );

  v4Journey(
    'v4: a buyer celebration suppresses every later scheduled offer',
    prefs: _recent,
    (game, rig, tester) async {
      unawaited(game.buyNoAds('home_tile'));
      await v4Settle(game, tester);
      expect(game.noAdsCelebration, isNotNull);
      expect(game.menu.noAds, isTrue);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.queuedPopups, 0);
      expect(game.noAdsPopup, isNull);
      game.handleBack();
      await run(game, 6);
      expect(game.menu.wallet.balance, 1000);
      await v4Background(game, rig, tester, const Duration(days: 2));
      expect(game.noAdsPopup, isNull);
      expect(rig.events.count('noads_popup_shown'), 0);
    },
  );

  v4Journey(
    'v4: a queued offer is discarded if ownership arrives before display',
    prefs: _recent,
    (game, rig, tester) async {
      game.openPurchaseResultPopup(
        IapProduct.coins1000,
        PurchaseProblem.failed,
        null,
      );
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.queuedPopups, 1);
      // FakeIapService emits a receipt with no Purchases.buy: restore-like
      // delivery, which must recover ownership without a bonus/celebration.
      unawaited(rig.iap.buy(IapProduct.noAds));
      await v4Settle(game, tester);
      expect(game.menu.noAds, isTrue);
      game.handleBack();
      await v4Settle(game, tester);
      expect(game.queuedPopups, 0);
      expect(game.noAdsPopup, isNull);
      expect(game.menu.wallet.balance, 0);
      expect(rig.events.count('noads_popup_shown'), 0);
    },
  );

  for (final close in ['cross', 'dim', 'back', 'Esc']) {
    v4Journey(
      'v4: $close dismisses without START or a lifetime cap',
      eligible: true,
      (game, rig, tester) async {
        await run(game, .3);
        final popup = game.noAdsPopup!;
        final lastMs = game.storage.noAdsPopupLastMs;
        switch (close) {
          case 'cross':
            await v4Tap(popup.closeButton, game, tester);
          case 'dim':
            await tester.tapAt(const Offset(10, 80));
          case 'back':
            expect(game.handleBack(), isTrue);
          case 'Esc':
            v4Escape(game);
        }
        await v4Settle(game, tester);
        expect(game.noAdsPopup, isNull);
        expect(game.state, GameState.start);
        expect(game.storage.noAdsPopupDismissals, 1);
        expect(game.storage.noAdsPopupLastMs, lastMs);
        expect(rig.events.count('noads_popup_dismissed'), 1);
      },
    );
  }

  v4Journey(
    'v4: session resumes in Shop and during a run never offer between runs',
    prefs: _recent,
    (game, rig, tester) async {
      await openShop(game);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, v4SessionGap);
      game.closeShop();
      await run(game, .3);
      expect(game.noAdsPopup, isNull);
      await game.startRun();
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull);
      game.score = 6;
      killRun(game);
      await v4Settle(game, tester);
      game.goHome();
      await run(game, .3);
      expect(game.noAdsPopup, isNull);
      expect(game.queuedPopups, 0);
      expect(rig.events.count('noads_popup_shown'), 0);
    },
  );

  v4Journey(
    'v4: queued arrival during delayed START is discarded after START',
    prefs: _recent,
    (game, rig, tester) async {
      final gate = Completer<void>();
      game.beforeRunStart = () => gate.future;
      final starting = game.startRun();
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.queuedPopups, 1);
      gate.complete();
      await starting;
      await v4Settle(game, tester);
      expect(game.state, GameState.playing);
      expect(game.queuedPopups, 0);
      game.score = 6;
      killRun(game);
      await v4Settle(game, tester);
      game.goHome();
      await run(game, .3);
      expect(game.noAdsPopup, isNull);
    },
  );

  v4Journey(
    'v4: backward wall clock blocks offers; day offset shifts persisted gaps',
    eligible: true,
    (game, rig, tester) async {
      game.handleBack();
      await v4Settle(game, tester);
      await v4Videos(game, tester, 3);
      rig.clock.now = rig.clock.now.subtract(const Duration(hours: 1));
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNull);
      await game.storage.saveDebugDayOffset(1);
      await v4Background(game, rig, tester, v4SessionGap);
      expect(game.noAdsPopup, isNotNull);
      expect(game.storage.noAdsPopupLastMs, v4EffectiveMs(rig, game));
      expect(game.storage.noAdsPopupLastDay, game.storage.today);
      game.handleBack();
      await v4Settle(game, tester);
      final restarted = await v4Restart(game, rig, tester);
      expect(restarted.storage.debugDayOffset, 1);
      expect(restarted.noAdsPopup, isNull);
      await restarted.storage.saveDebugDayOffset(0);
      await v4Background(restarted, rig, tester, v4SessionGap);
      expect(
        restarted.noAdsPopup,
        isNull,
        reason: 'last show is now in the future',
      );
    },
  );

  group('S1-70', () {
    v4Journey(
      'queued session arrivals must coalesce and recheck the show window',
      prefs: (rig) => {..._recent(rig), 'bestScore': 10, 'lastScore': 10},
      (game, rig, tester) async {
        await run(game, .5);
        expect(game.levelUpPopup, isNotNull);
        rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
        for (var i = 0; i < 3; i++) {
          await v4Background(game, rig, tester, v4SessionGap);
        }
        await game.claimLevelUp();
        await v4Settle(game, tester);
        expect(game.noAdsPopup, isNotNull);
        for (var i = 0; i < 3; i++) {
          game.handleBack();
          await v4Settle(game, tester);
        }
        expect(
          game.storage.noAdsPopupShowsToday,
          1,
          reason:
              'the three queued arrivals must not become three same-day shows',
        );
        expect(
          game.noAdsPopup,
          isNull,
          reason:
              'one dismissal must not reveal another offer at the same instant',
        );
        expect(rig.events.count('noads_popup_shown'), 1);
      },
    );

    v4Journey(
      'a queued offer rechecks its four-hour window after a clock correction',
      prefs: (rig) => {..._recent(rig), 'bestScore': 10, 'lastScore': 10},
      (game, rig, tester) async {
        await run(game, .5);
        expect(game.levelUpPopup, isNotNull);
        rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
        await v4Background(game, rig, tester, v4SessionGap);
        expect(game.queuedPopups, 1);
        rig.clock.now = rig.clock.now.subtract(Config.noAdsPopupFallback);
        await game.claimLevelUp();
        await v4Settle(game, tester);
        expect(
          game.noAdsPopup,
          isNull,
          reason:
              'after clock correction only 30 minutes passed since the prior show',
        );
        expect(rig.events.count('noads_popup_shown'), 0);
      },
    );

    v4Journey(
      'returning with an old offer open must not queue a duplicate offer',
      eligible: true,
      (game, rig, tester) async {
        final popup = game.noAdsPopup!;
        await v4Background(game, rig, tester, Config.noAdsPopupFallback);
        expect(identical(game.noAdsPopup, popup), isTrue);
        game.handleBack();
        await v4Settle(game, tester);
        expect(
          game.noAdsPopup,
          isNull,
          reason: 'closing the displayed offer should actually close it',
        );
        expect(rig.events.count('noads_popup_shown'), 1);
      },
    );
  });

  group('S2-70', () {
    v4Journey(
      'closing a long-open offer starts the four-hour gap (PRD §8.5)',
      eligible: true,
      (game, rig, tester) async {
        // Keep the card open in the foreground: no new session/queued copy.
        rig.clock.now = rig.clock.now.add(const Duration(hours: 1));
        game.handleBack();
        await v4Settle(game, tester);
        await v4Videos(game, tester, 3);
        rig.clock.now = rig.clock.now.add(const Duration(hours: 3));
        await v4Background(game, rig, tester, v4SessionGap);
        expect(
          game.noAdsPopup,
          isNull,
          reason:
              'only 3 h 30 min since dismissal; four-hour closing gap still active',
        );
      },
    );
  });
}
