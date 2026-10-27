import '../../levels/progression_fixture.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/items/big_hoops.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/rating_prompt.dart';
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
  _ShowcasePlan([this.result]);

  final ShowcaseRunPlan? result;
  final calls = <_PlanCall>[];

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) {
    calls.add(_PlanCall(gamesPlayed, seen, attempt, forced));
    return result;
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
  void onRunEnd({
    required int gamesPlayed,
    required int hoopsPassed,
    int score = 0,
    String cause = 'missed_hoop',
    bool shieldUsed = false,
    bool reviveUsed = false,
  }) {
    runEnds.add((gamesPlayed: gamesPlayed, hoopsPassed: hoopsPassed));
  }
}

final class _FtueTracker extends FtueTracker {
  final steps = <String>[];
  final calls = <({String id, int gamesPlayed})>[];

  @override
  void step(String id, {required int gamesPlayed}) {
    steps.add(id);
    calls.add((id: id, gamesPlayed: gamesPlayed));
  }
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
      // PRD-2.6 WP-A: Home defaults to VERSUS, so its first end also emits
      // `versus_first_end`; PersistedFtueTracker deduplicates it per install.
      expect(ftueTracker.steps, [
        FtueStep.run4Start,
        FtueStep.firstTap,
        FtueStep.versusFirstEnd,
      ]);
      await flushAndMount(game);
    },
  );

  for (final starter in [Powerup.none, Powerup.shield, Powerup.bigHoops]) {
    const plan = ShowcaseRunPlan(
      highlightId: 'portal',
      step: 0,
      attempt: 1,
      extraStarters: [Powerup.bigHoops, Powerup.shield],
    );
    final planner = _ShowcasePlan(plan);
    final withExtras = FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        worldHeight: Config.worldHeight,
        soundEnabled: false,
        showcasePlan: planner,
      )..runSeed = 7;
    }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

    withExtras.testGameWidget(
      'showcase arms both extras before hoop 0 with Home starter $starter',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        final run = await startRun(game, starter: starter);
        expect(run.setup.showcase, same(plan));
        expect(run.setup.starter, starter);
        expect(run.setup.extraStarters, plan.extraStarters);
        expect(run.state.shield, isTrue);
        expect(run.state.bigHoops, isNotNull);
        expect(run.state.bigHoops!.mult(0), 1.5);
        // PRD-2.6 B2 / B3 step 1: Big Hoops lasts 60 s in the portal
        // showcase (the normal 30–40 s roll is for steps 2–3 only).
        expect(run.state.bigHoops!.duration, 60);
        expect(run.spawner.hoops, isNotEmpty);
        expect(run.spawner.hoops.every(BigHoopsFeature.isGold), isTrue);
      },
    );
  }

  for (final milestone in {
    1: FtueStep.run1End,
    2: FtueStep.run2End,
    3: FtueStep.run3End,
    20: FtueStep.run20End,
  }.entries) {
    final tracker = _FtueTracker();
    final progress = _ShowcaseProgress();
    final withMilestone = FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({
        'gamesPlayed': milestone.key - 1,
      });
      return FlappySpikesGame(
        worldHeight: Config.worldHeight,
        soundEnabled: false,
        ftueTracker: tracker,
        showcaseProgress: progress,
      )..runSeed = 7;
    }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

    withMilestone.testGameWidget(
      'run ${milestone.key} end forwards FTUE and progress arguments',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        final run = await startRun(game);
        run.state.hoopsPassed = 2;
        game.endRun(null);
        // PRD-2.6 WP-A: the first VERSUS run ends with `versus_first_end`
        // as well (the Home mode defaults to VERSUS).
        expect(tracker.calls, [
          (id: FtueStep.firstTap, gamesPlayed: milestone.key - 1),
          (id: milestone.value, gamesPlayed: milestone.key),
          (id: FtueStep.versusFirstEnd, gamesPlayed: milestone.key),
        ]);
        expect(progress.runEnds, [
          (gamesPlayed: milestone.key, hoopsPassed: 2),
        ]);
        // A second end signal must not count or report the same run again.
        game.endRun(null);
        expect(tracker.calls, hasLength(3));
        expect(progress.runEnds, hasLength(1));
        await flushAndMount(game);
      },
    );
  }

  for (final finishedRuns in [5, 6]) {
    final moments = _HomeMoments();
    final backend = _RatingBackend();
    final prompt = RatingPrompt(backend: backend);
    final withRating = FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({
        'gamesPlayed': finishedRuns - 1,
        'showcaseDoneAt': 4,
      });
      return FlappySpikesGame(
        worldHeight: Config.worldHeight,
        soundEnabled: false,
        homeMoments: moments,
        rating: prompt,
      )..runSeed = 7;
    }, gameSize: Vector2(Config.worldWidth, Config.worldHeight));

    withRating.testGameWidget(
      'rating routes through HomeMoments at showcase-adjusted run $finishedRuns',
      setUp: (game, _) async {
        await prompt.prepare();
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        await startRun(game);
        game.endRun(null);
        await flushAndMount(game);
        for (
          var frame = 0;
          frame < 900 && !game.resultsScreen!.settled;
          frame++
        ) {
          game.update(1 / 60);
        }
        expect(game.resultsScreen!.settled, isTrue);
        stepGame(game, Config.ratingDelaySeconds + .1);
        await flushAndMount(game);
        expect(
          moments.moments,
          finishedRuns == 6 ? [HomeMoment.rating] : isEmpty,
        );
        expect(backend.requests, finishedRuns == 6 ? 1 : 0);
      },
    );
  }

  final homeMoments = _HomeMoments();
  final withHome = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues(trackPrefs({
      'playerLevel': 1,
      'claimedLevels': <String>[],
    }));
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

final class _RatingBackend implements RatingBackend {
  int requests = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> requestReview() async {
    requests++;
  }
}
