import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/purchases.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu_screenshot_test.dart' show loadFonts;
import '../purchase_feedback_test.dart' show run;
import 'menu_v4_qa_helpers.dart';

Map<String, Object> _recent(V4Rig rig) => {
  ...rig.eligible,
  'noAdsPopupLastMs': rig.clock.now.millisecondsSinceEpoch,
  'noAdsPopupLastDay': rig.clock.day,
  'noAdsPopupShowsToday': 1,
};

void main() {
  setUpAll(loadFonts);

  for (final close in ['cross', 'dim', 'back', 'Esc']) {
    v4Journey(
      'v4 R2: $close close keeps the show\'s 1 h gap across restart (PRD-2.3 §24.2)',
      eligible: true,
      (game, rig, tester) async {
        await run(game, .3);
        final shown = game.storage.noAdsPopupLastMs;
        rig.clock.now = rig.clock.now.add(const Duration(minutes: 30));
        final closed = rig.clock.now.millisecondsSinceEpoch;
        switch (close) {
          case 'cross':
            await v4Tap(game.noAdsPopup!.closeButton, game, tester);
          case 'dim':
            await tester.tapAt(const Offset(10, 80));
          case 'back':
            game.handleBack();
          case 'Esc':
            v4Escape(game);
        }
        await v4Settle(game, tester);
        await v4Videos(game, tester, 3);
        var next = await v4Restart(game, rig, tester);
        expect(next.storage.noAdsPopupLastMs, shown);
        expect(next.storage.noAdsPopupClosedMs, closed);
        expect(next.storage.noAdsPopupDismissals, 1);
        expect(next.noAdsPopup, isNull, reason: '30 min after the show');
        rig.clock.now = rig.clock.now.add(
          const Duration(minutes: 29, seconds: 59),
        );
        next = await v4Restart(next, rig, tester);
        expect(next.noAdsPopup, isNull, reason: '59:59 after the show');
        rig.clock.now = rig.clock.now.add(const Duration(seconds: 1));
        next = await v4Restart(next, rig, tester);
        expect(next.noAdsPopup, isNotNull, reason: '1:00:00 after the show');
        expect(next.storage.noAdsPopupShowsToday, 2);
        expect(rig.events.last('noads_popup_shown')!['reason'], 'videos');
      },
    );
  }

  v4Journey(
    'v4 R2: last-show fallback (3 h) stays anchored to the show after a later close',
    eligible: true,
    (game, rig, tester) async {
      // The launch show is at 08:00; the close at 10:00 must not move it.
      rig.clock.now = rig.clock.now.add(const Duration(hours: 2));
      game.handleBack();
      await v4Settle(game, tester);
      rig.clock.now = DateTime(2026, 10, 7, 10, 59, 59);
      var next = await v4Restart(game, rig, tester);
      expect(next.noAdsPopup, isNull);
      rig.clock.now = rig.clock.now.add(const Duration(seconds: 1));
      next = await v4Restart(next, rig, tester);
      expect(next.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'fallback');
    },
  );

  v4Journey(
    'v4 R2: two short background intervals do not add into one new session',
    prefs: _recent,
    (game, rig, tester) async {
      await v4Videos(game, tester, 3);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupMinGap);
      await v4Background(game, rig, tester, const Duration(minutes: 20));
      await v4Background(game, rig, tester, const Duration(minutes: 20));
      expect(game.noAdsPopup, isNull);
      await v4Background(game, rig, tester, const Duration(minutes: 30));
      expect(game.noAdsPopup, isNotNull);
      expect(game.storage.noAdsPopupVideos, 0);
    },
  );

  v4Journey(
    'v4 R2: repeated paused/hidden events retain the first background time',
    prefs: _recent,
    (game, rig, tester) async {
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      game.lifecycleStateChange(AppLifecycleState.hidden);
      rig.clock.now = rig.clock.now.add(const Duration(minutes: 20));
      game.lifecycleStateChange(AppLifecycleState.paused);
      rig.clock.now = rig.clock.now.add(const Duration(minutes: 10));
      game.lifecycleStateChange(AppLifecycleState.resumed);
      await v4Settle(game, tester);
      expect(game.noAdsPopup, isNotNull);
      game.handleBack();
      await v4Settle(game, tester);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      game.lifecycleStateChange(AppLifecycleState.resumed);
      await v4Settle(game, tester);
      expect(game.noAdsPopup, isNull, reason: 'duplicate resume is no arrival');
    },
  );

  v4Journey(
    'v4 R2: eligible request updates fallback to videos behind purchase result',
    prefs: _recent,
    (game, rig, tester) async {
      game.openPurchaseResultPopup(
        IapProduct.coins17000,
        PurchaseProblem.failed,
        null,
      );
      await v4Settle(game, tester);
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, Config.sessionGap);
      expect(game.queuedPopups, 1);
      await v4Videos(game, tester, 3);
      game.handleBack();
      await v4Settle(game, tester);
      expect(v4ModalCount(game), 1);
      expect(game.noAdsPopup, isNotNull);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'videos');
      expect(game.storage.noAdsPopupVideos, 0);
    },
  );

  v4Journey(
    'v4 R2: pending offer is dropped on leaving home and does not return',
    prefs: _recent,
    (game, rig, tester) async {
      // The debug overlay leaves home up but blocks the waiting request.
      game.openDebugPanel();
      rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
      await v4Background(game, rig, tester, Config.sessionGap);
      expect(game.queuedPopups, 1);
      game.closeDebugPanel();
      game.openShop();
      await v4Settle(game, tester);
      expect(game.menuScene, MenuScene.shop);
      expect(game.queuedPopups, 0);
      expect(game.noAdsPopup, isNull);
      game.closeShop();
      await run(game, .5);
      expect(game.noAdsPopup, isNull);
      await v4Background(game, rig, tester, Config.sessionGap);
      expect(game.noAdsPopup, isNotNull);
    },
  );

  for (final videos in [0, 3]) {
    v4Journey(
      'v4 R2: low score defeats $videos videos and expired fallback after restart',
      prefs: _recent,
      (game, rig, tester) async {
        await v4FinishRun(game, tester, 5);
        await v4Videos(game, tester, videos);
        rig.clock.now = rig.clock.now.add(Config.noAdsPopupFallback);
        final next = await v4Restart(game, rig, tester);
        expect(next.noAdsPopup, isNull, reason: 'the last run scored 5');
        expect(next.storage.lastScore, 5);
        // PRD-2.3 §24.2: the next run's Home arrival checks the popup.
        await v4FinishRun(next, tester, 6);
        expect(next.noAdsPopup, isNotNull);
        expect(rig.events.last('noads_popup_shown')!['check'], 'after_run');
        expect(
          rig.events.last('noads_popup_shown')!['reason'],
          videos == 3 ? 'videos' : 'best',
        );
      },
    );
  }

  v4Journey(
    'v4 R2: first session stays suppressed through ten runs; cold launch qualifies',
    // PRD-2.6 J3: isolate the schedule; ten low-score runs cannot level here.
    prefs: (rig) => {'lvlIndex': 31},
    (game, rig, tester) async {
      for (var i = 0; i < 10; i++) {
        await v4FinishRun(game, tester, 6);
      }
      expect(game.storage.gamesPlayed, 10);
      expect(game.noAdsPopup, isNull);
      await v4Background(game, rig, tester, const Duration(minutes: 29));
      expect(game.noAdsPopup, isNull);
      expect(game.menu.noAdsPopup.inFirstSession, isTrue);
      final next = await v4Restart(game, rig, tester);
      expect(next.noAdsPopup, isNotNull);
      expect(next.storage.gamesPlayed, 10);
      expect(rig.events.last('noads_popup_shown')!['reason'], 'fallback');
    },
  );

  v4Journey(
    'v4 R2: many historical dismissals impose no cap (5 shows a local day)',
    prefs: (rig) => {...rig.eligible, 'noAdsPopupDismissals': 999},
    (game, rig, tester) async {
      for (var i = 0; i < 4; i++) {
        expect(game.noAdsPopup, isNotNull);
        game.handleBack();
        await v4Settle(game, tester);
        expect(game.storage.noAdsPopupDismissals, 1000 + i);
        await v4Background(game, rig, tester, Config.noAdsPopupFallback);
        expect(game.storage.noAdsPopupShowsToday, i + 2);
      }
      expect(rig.events.count('noads_popup_shown'), 5);
    },
  );

  v4Journey(
    'v4 R2: day offset cannot erase a persisted closing gap on restart',
    eligible: true,
    (game, rig, tester) async {
      await game.storage.saveDebugDayOffset(2);
      game.handleBack();
      await v4Settle(game, tester);
      final closed = game.storage.noAdsPopupClosedMs;
      await v4Videos(game, tester, 3);
      await game.storage.saveDebugDayOffset(0);
      final next = await v4Restart(game, rig, tester);
      expect(next.storage.noAdsPopupClosedMs, closed);
      expect(next.noAdsPopup, isNull);
      await v4Background(next, rig, tester, const Duration(days: 2, hours: 4));
      expect(next.noAdsPopup, isNotNull);
    },
  );
}
