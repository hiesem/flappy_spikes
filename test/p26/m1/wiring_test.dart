import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/ftue_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class _PlanCall {
  const _PlanCall(this.gamesPlayed, this.seen, this.attempt, this.forced);

  final int gamesPlayed;
  final int seen;
  final int attempt;
  final bool forced;
}

final class _ShowcasePlan extends ShowcasePlan {
  final calls = <_PlanCall>[];

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) {
    calls.add(_PlanCall(gamesPlayed, seen, attempt, forced));
    return null;
  }
}

final class _ShowcaseProgress extends ShowcaseProgress {
  final highlights = <({String id, bool scripted, int hoop})>[];
  final runEnds = <({int gamesPlayed, int hoopsPassed})>[];

  @override
  void onHighlight(String id, {required bool scripted, required int hoop}) {
    highlights.add((id: id, scripted: scripted, hoop: hoop));
  }

  @override
  void onRunEnd({required int gamesPlayed, required int hoopsPassed}) {
    runEnds.add((gamesPlayed: gamesPlayed, hoopsPassed: hoopsPassed));
  }
}

final class _FtueTracker extends FtueTracker {
  final steps = <String>[];

  @override
  void step(String id, {required int gamesPlayed}) => steps.add(id);
}

final class _HomeMoments extends HomeMoments {
  final moments = <HomeMoment>[];

  @override
  void show(HomeMoment moment, void Function() open) {
    moments.add(moment);
    open();
  }
}

void main() {
  final showcasePlan = _ShowcasePlan();
  final showcaseProgress = _ShowcaseProgress();
  final ftueTracker = _FtueTracker();
  final withRun = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({'gamesPlayed': 3});
    final game = FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      showcasePlan: showcasePlan,
      showcaseProgress: showcaseProgress,
      ftueTracker: ftueTracker,
    );
    game.runSeed = 7;
    game.runDebug.ignoreGates = true;
    return game;
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

  withRun.testGameWidget(
    'the showcase, progress and FTUE seams fire',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await startRun(game);
      expect(showcasePlan.calls, hasLength(1));
      final call = showcasePlan.calls.single;
      expect(call.gamesPlayed, 3);
      expect(call.seen, 0);
      expect(call.attempt, 0);
      expect(call.forced, isFalse);
      expect(game.run!.setup.showcase, isNull);
      expect(game.run!.setup.extraStarters, isEmpty);
      expect(ftueTracker.steps, [FtueStep.run4Start, FtueStep.firstTap]);

      game.run!.events.emit(
        const HighlightStarted('portal', scripted: true, hoop: 7),
      );
      expect(showcaseProgress.highlights.single, (
        id: 'portal',
        scripted: true,
        hoop: 7,
      ));

      game.endRun(null);
      expect(showcaseProgress.runEnds.single.gamesPlayed, 4);
      expect(ftueTracker.steps, [FtueStep.run4Start, FtueStep.firstTap]);
      await flushAndMount(game);
    },
  );

  final homeMoments = _HomeMoments();
  final withHome = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      'playerLevel': 1,
      'claimedLevels': <String>[],
    });
    return FlappySpikesGame(
      worldHeight: Config.worldHeight,
      soundEnabled: false,
      homeMoments: homeMoments,
    );
  }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

  withHome.testGameWidget(
    'LEVEL UP and No-Ads route through HomeMoments',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await flushAndMount(game);
      game.openNoAdsPopup(reason: 'forced', check: 'forced');
      expect(homeMoments.moments, [HomeMoment.noAds]);
      game.closeNoAdsPopup();

      game.openLevelUpPopup();
      expect(homeMoments.moments, [HomeMoment.noAds, HomeMoment.levelUp]);
    },
  );
}
