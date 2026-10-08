import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/noads_popup_policy.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'home_layout_test.dart' show loadFonts;

/// PRD-menu-v4 §8 in the game: the session-start home arrival (launch /
/// back after >= 30 min), the popup queue, run bookkeeping and analytics.
class _Events extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  List<Map<String, Object>?> params(String name) => [
    for (final e in events)
      if (e.$1 == name) e.$2,
  ];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }
}

class _Clock {
  DateTime now = DateTime(2026, 10, 3, 12);
  DateTime call() => now;
  int get day => DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(1970)).inDays;
}

Future<void> _flush(FlappySpikesGame game) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.value();
  }
  await flushAndMount(game);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  /// Open window by default: installed yesterday, first session over.
  void scheduleTest(
    String name,
    Future<void> Function(
      FlappySpikesGame game,
      _Events events,
      _Clock clock,
      FakeRewardedAds ads,
    )
    verify, {
    Map<String, Object>? prefs,
  }) {
    final events = _Events();
    final clock = _Clock();
    final ads = FakeRewardedAds();
    FlameTester<FlappySpikesGame>(
      () {
        SharedPreferences.setMockInitialValues(
          prefs ?? {'installDay': clock.day - 1, 'firstSessionDone': true},
        );
        return FlappySpikesGame(
          worldHeight: 711,
          services: events,
          monetization: Monetization(ads: ads, iap: FakeIapService()),
          clock: clock.call,
          soundEnabled: false,
        );
      },
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      name,
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) => verify(game, events, clock, ads),
    );
  }

  /// Background for [away], then resumed.
  Future<void> background(
    FlappySpikesGame game,
    _Clock clock,
    Duration away,
  ) async {
    game.lifecycleStateChange(AppLifecycleState.inactive);
    game.lifecycleStateChange(AppLifecycleState.hidden);
    game.lifecycleStateChange(AppLifecycleState.paused);
    clock.now = clock.now.add(away);
    game.lifecycleStateChange(AppLifecycleState.hidden);
    game.lifecycleStateChange(AppLifecycleState.inactive);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    await _flush(game);
  }

  /// One run scoring [score], back home.
  Future<void> run(FlappySpikesGame game, int score) async {
    await game.startRun();
    expect(game.state, GameState.playing);
    game.score = score;
    killRun(game);
    await _flush(game);
    game.goHome();
    stepGame(game, 1);
    await _flush(game);
    expect(game.state, GameState.start);
  }

  scheduleTest('launch: shown with reason fallback, marks the show', (
    game,
    events,
    clock,
    ads,
  ) async {
    expect(game.noAdsPopup, isNotNull);
    expect(events.params('noads_popup_shown').single, {
      'trigger': 'launch',
      'reason': 'fallback',
    });
    await _flush(game);
    expect(game.storage.noAdsPopupLastMs, clock.now.millisecondsSinceEpoch);
    expect(game.storage.noAdsPopupShowsToday, 1);
  });

  scheduleTest(
    'first session: never (fresh install, even with day offset)',
    prefs: const {},
    (game, events, clock, ads) async {
      expect(game.noAdsPopup, isNull);
      expect(game.menu.noAdsPopup.inFirstSession, isTrue);
      game.storage.debugDayOffset = 2;
      // A short background is still the first session.
      await background(game, clock, const Duration(minutes: 29));
      expect(game.noAdsPopup, isNull);
      // >= 30 min away: a new session, now day 3 -> shown.
      await background(game, clock, Config.sessionGap);
      expect(game.menu.noAdsPopup.inFirstSession, isFalse);
      expect(game.noAdsPopup, isNotNull);
    },
  );

  scheduleTest(
    'install day: 10 finished runs open the window on the next session',
    prefs: {'installDay': _Clock().day, 'firstSessionDone': true},
    (game, events, clock, ads) async {
      expect(game.noAdsPopup, isNull);
      for (var i = 0; i < Config.noAdsPopupMinRuns - 1; i++) {
        await run(game, 8);
      }
      await background(game, clock, const Duration(hours: 1));
      expect(game.noAdsPopup, isNull, reason: '9 runs on install day');
      await run(game, 8);
      expect(game.noAdsPopup, isNull, reason: 'never between runs');
      await background(game, clock, const Duration(hours: 1));
      expect(game.noAdsPopup, isNotNull);
      expect(events.params('noads_popup_shown').single!['reason'], 'fallback');
    },
  );

  scheduleTest('30-min session gap: 29:59 no, 30:00 yes', (
    game,
    events,
    clock,
    ads,
  ) async {
    game.closeNoAdsPopup();
    await _flush(game);
    // Good moment: three rewarded videos (the powerup slot's ad).
    for (var i = 0; i < 3; i++) {
      await game.showRewardedAd(AdPlacement.homeSlot);
    }
    expect(game.storage.noAdsPopupVideos, 3);
    clock.now = clock.now.add(Config.noAdsPopupMinGap);
    await background(
      game,
      clock,
      Config.sessionGap - const Duration(seconds: 1),
    );
    expect(game.noAdsPopup, isNull, reason: 'same session');
    await background(game, clock, Config.sessionGap);
    expect(game.noAdsPopup, isNotNull);
    expect(events.params('noads_popup_shown').last!['reason'], 'videos');
    expect(game.storage.noAdsPopupVideos, 0);
  });

  scheduleTest('inactive alone (e.g. a system sheet) is no background', (
    game,
    events,
    clock,
    ads,
  ) async {
    game.closeNoAdsPopup();
    await _flush(game);
    clock.now = clock.now.add(const Duration(days: 1));
    game.lifecycleStateChange(AppLifecycleState.inactive);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    await _flush(game);
    expect(game.noAdsPopup, isNull);
  });

  scheduleTest('new best / new level of the previous run; < 6 suppresses', (
    game,
    events,
    clock,
    ads,
  ) async {
    game.closeNoAdsPopup();
    await _flush(game);
    clock.now = clock.now.add(Config.noAdsPopupMinGap);
    // A new best below 6 points: frustrating, no popup.
    await run(game, 5);
    expect(game.storage.lastRunMood, RunMood.best);
    await background(game, clock, const Duration(hours: 1));
    expect(game.noAdsPopup, isNull, reason: '< 6 points');
    // 8 points: new best (and level 1 = HATCHLING? only if it crosses).
    await run(game, 8);
    final reason = game.menu.levels.level > 0 ? 'level' : 'best';
    await background(game, clock, const Duration(hours: 1));
    expect(game.noAdsPopup, isNotNull);
    expect(events.params('noads_popup_shown').last!['reason'], reason);
    expect(game.storage.lastRunMood, RunMood.none);
  });

  scheduleTest(
    'reason level when the run reaches a new level',
    prefs: {
      'installDay': _Clock().day - 1,
      'firstSessionDone': true,
      'noAdsPopupLastMs': _Clock().now.millisecondsSinceEpoch,
      'noAdsPopupLastDay': _Clock().day,
      'noAdsPopupShowsToday': 1,
    },
    (game, events, clock, ads) async {
      expect(game.noAdsPopup, isNull, reason: '4 h gap');
      final before = game.menu.levels.level;
      await run(game, 60);
      expect(game.menu.levels.level, greaterThan(before));
      expect(game.storage.lastRunMood, RunMood.level);
      // Claim the owed LEVEL UP so nothing is queued.
      stepGame(game, 1);
      await _flush(game);
      await game.claimLevelUp();
      await _flush(game);
      clock.now = clock.now.add(Config.noAdsPopupMinGap);
      await background(game, clock, Config.sessionGap);
      expect(game.noAdsPopup, isNotNull);
      expect(events.params('noads_popup_shown').last!['reason'], 'level');
    },
  );

  scheduleTest(
    'queue: a LEVEL UP up at the session start goes first',
    prefs: {
      'installDay': _Clock().day - 1,
      'firstSessionDone': true,
      'bestScore': 15,
    },
    (game, events, clock, ads) async {
      // Launch: the upsell first, then LEVEL UP after it.
      expect(game.noAdsPopup, isNotNull);
      game.closeNoAdsPopup();
      await _flush(game);
      stepGame(game, 1);
      await _flush(game);
      expect(game.levelUpPopup, isNotNull);
      // A session start while LEVEL UP is up: the upsell waits its turn.
      clock.now = clock.now.add(Config.noAdsPopupFallback);
      await background(game, clock, Config.sessionGap);
      expect(game.noAdsPopup, isNull);
      expect(game.queuedPopups, 1);
      await game.claimLevelUp();
      await _flush(game);
      expect(game.noAdsPopup, isNotNull);
      expect(events.params('noads_popup_shown').length, 2);
    },
  );

  scheduleTest('a session start away from home shows nothing', (
    game,
    events,
    clock,
    ads,
  ) async {
    game.closeNoAdsPopup();
    await _flush(game);
    await game.startRun();
    clock.now = clock.now.add(Config.noAdsPopupFallback);
    await background(game, clock, Config.sessionGap);
    expect(game.noAdsPopup, isNull);
    expect(game.queuedPopups, 0);
    game.score = 10;
    killRun(game);
    await _flush(game);
    game.goHome();
    stepGame(game, 1);
    await _flush(game);
    expect(game.noAdsPopup, isNull, reason: 'never between runs');
  });

  scheduleTest(
    'owners never, even with every trigger',
    prefs: {
      'installDay': _Clock().day - 9,
      'firstSessionDone': true,
      'noAds': true,
      'noAdsPopupVideos': 9,
      'lastRunMood': 'level',
      'gamesPlayed': 50,
    },
    (game, events, clock, ads) async {
      expect(game.noAdsPopup, isNull);
      clock.now = clock.now.add(const Duration(days: 2));
      await background(game, clock, Config.sessionGap);
      expect(game.noAdsPopup, isNull);
      expect(events.params('noads_popup_shown'), isEmpty);
    },
  );

  scheduleTest('debug panel force bypasses the schedule', (
    game,
    events,
    clock,
    ads,
  ) async {
    game.closeNoAdsPopup();
    await _flush(game);
    expect(game.menu.noAdsPopup.evaluate(), isNull, reason: 'gap');
    game.openDebugPanel();
    await _flush(game);
    final panel = game.world.children.query<DebugPanel>().single;
    final force = panel.actions.firstWhere(
      (a) => a.label() == 'NO-ADS POPUP: force',
    );
    await force.run();
    await _flush(game);
    expect(game.noAdsPopup, isNotNull);
    expect(events.params('noads_popup_shown').last, {
      'trigger': 'launch',
      'reason': 'forced',
    });
  });
}
