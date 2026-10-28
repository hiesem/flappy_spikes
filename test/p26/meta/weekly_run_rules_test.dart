import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _FailWeeklyCoinOnce extends AnalyticsSpy {
  bool failNext = true;
  bool failed = false;

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    if (failNext &&
        name == 'coins_earned' &&
        parameters?['source'] == 'weekly') {
      failNext = false;
      failed = true;
      throw StateError('simulated weekly wallet failure');
    }
    super.logEvent(name, parameters);
  }
}

void main() {
  final monday = DateTime.utc(2026, 10, 26);
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'weekly START preserves home slot, counts normally, and skips revive',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.storage.saveArmedPowerup('shield');
      final homeMode = game.homeMode;
      await game.startWeeklyCourse();
      await flushAndMount(game);
      final run = game.run!;
      expect(run.setup.weekly, isTrue);
      expect(run.setup.seed, WeeklyWeek.at(monday).seed);
      expect(run.setup.weeklyStartedAt, monday);
      expect(run.setup.opponent, isNull);
      expect(run.setup.showcase, isNull);
      expect(run.setup.starter, Powerup.none);
      expect(run.state.shield, isFalse);
      expect(game.storage.armedPowerup, 'shield');
      expect(game.homeMode, homeMode);
      expect(game.runSubmissionMode, 'weekly');
      expect(run.countsForUpload, isTrue);
      expect(run.countsForAchievements, isTrue);
      game.onPlayfieldTap();
      run.state.hoopsPassed = 30;
      killRunThroughSaves(game);
      await flushAndMount(game);
      expect(game.state, isNot(GameState.reviving));
      expect(game.reviveScreen, isNull);
      expect(run.state.revivesThisGame, 0);
      expect(game.storage.armedPowerup, 'shield');
    },
  );

  for (final mode in [HomeMode.freeFly, HomeMode.versus]) {
    final submitted = <Map<String, Object?>>[];
    final analytics = AnalyticsSpy();
    FlameTester<FlappySpikesGame>(() {
      submitted.clear();
      analytics.events.clear();
      SharedPreferences.setMockInitialValues({
        Obf.prefGamesPlayed: 6,
        Obf.prefBestHoops: 40,
      });
      return FlappySpikesGame(
        soundEnabled: false,
        worldHeight: 711,
        clock: () => monday,
        services: analytics,
        leaderboard: FakeLeaderboardService(
          onCall: (name, request) async {
            // P26-LB7 / PRD C2: Home also checks the board for owed gifts.
            // Keep this fixture focused on the weekly run submission.
            if (name == 'lbGetBoard') {
              return {
                'today': {'tab': 'today', 'rows': <Object>[]},
                'best': {'tab': 'best', 'rows': <Object>[]},
              };
            }
            submitted.add(request);
            return {
              'accepted': [
                for (final run in request['runs'] as List) (run as Map)['id'],
              ],
              'dropped': [],
            };
          },
        ),
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'weekly run submits weekly and reports weekly analytics with ${mode.name} selected',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await game.storage.saveHomeMode(mode);
      },
      verify: (game, _) async {
        await game.startWeeklyCourse();
        await flushAndMount(game);
        final run = game.run!;
        expect(run.countsForUpload, isTrue);
        game.onPlayfieldTap();
        expect(
          analytics.events.where((e) => e.$1 == 'run_start').single.$2!['mode'],
          'weekly',
        );
        await flyRun(game, untilHoops: 1, maxSeconds: 10);
        final summary = run.endRun();
        game.endRun(summary);
        await game.leaderboardQueue.flush();
        expect(submitted, hasLength(1));
        final sent = (submitted.single['runs'] as List).single as Map;
        expect(sent['mode'], 'weekly');
        expect(sent['hoops'], summary.hoopsPassed);
      },
    );
  }

  final spy = AnalyticsSpy();
  var now = monday;
  FlameTester<FlappySpikesGame>(() {
    spy.events.clear();
    now = monday;
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
      // PRD §8.3 item 19: isolate weekly payouts from the day-streak popup.
      Obf.prefStreakPaidDay: monday.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => now,
      services: spy,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'weekly run end pays tiers once, persists, excludes debug and old weeks',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      Future<void> finish(
        int hoops, {
        bool debug = false,
        bool immediateReplay = false,
      }) async {
        await game.startWeeklyCourse();
        await flushAndMount(game);
        final run = game.run!;
        expect(run.setup.weeklyStartedAt, WeeklyWeek.at(now).startsAt);
        if (debug) run.markDebugAssist();
        run.state.hoopsPassed = hoops;
        game.endRun(run.endRun());
        if (immediateReplay) {
          await flushAndMount(game);
          game.replay();
        }
        await game.weeklyWritesSettled;
      }

      Future<void> next() async {
        game.replay();
        await flushAndMount(game);
        stepGame(game, 0.5);
        await flushAndMount(game);
      }

      final before = game.storage.coins;
      await finish(30, immediateReplay: true);
      await flushAndMount(game);
      expect(game.storage.coins, before + 120);
      expect(game.storage.weeklyBest, {WeeklyWeek.at(now).key: 30});
      expect(game.storage.weeklyRewards, {15, 30});
      final loaded = GameStorage(clock: () => now);
      await loaded.load();
      expect(loaded.coins, before + 120);
      expect(loaded.weeklyBest, game.storage.weeklyBest);
      expect(loaded.weeklyRewards, {15, 30});
      expect(spy.events.where((e) => e.$1 == 'weekly_run'), hasLength(1));
      expect(
        spy.events
            .where((e) => e.$1 == 'weekly_reward')
            .map((e) => e.$2!['tier']),
        [15, 30],
      );
      expect(
        spy.events
            .where((e) => e.$1 == 'coins_earned' && e.$2?['source'] == 'weekly')
            .single
            .$2!['amount'],
        120,
      );

      stepGame(game, 0.5);
      await flushAndMount(game);
      await finish(30);
      expect(game.storage.coins, before + 120);
      expect(spy.events.where((e) => e.$1 == 'weekly_reward'), hasLength(2));
      await next();
      await finish(120, debug: true);
      expect(game.storage.coins, before + 120);
      expect(game.storage.weeklyBest, {WeeklyWeek.at(now).key: 30});
      expect(spy.events.where((e) => e.$1 == 'weekly_run'), hasLength(2));

      await next();
      await game.startWeeklyCourse();
      await flushAndMount(game);
      final old = game.run!;
      expect(old.setup.weeklyStartedAt, monday);
      now = monday.add(const Duration(days: 7));
      old.state.hoopsPassed = 120;
      game.endRun(old.endRun());
      await game.weeklyWritesSettled;
      expect(game.storage.coins, before + 120);
      expect(game.storage.weeklyBest, {WeeklyWeek.at(now).key: 0});
      expect(game.storage.weeklyRewards, isEmpty);
      final reloaded = GameStorage(clock: () => now);
      await reloaded.load();
      expect(reloaded.weeklyBest, game.storage.weeklyBest);
      expect(reloaded.weeklyRewards, isEmpty);
    },
  );

  final fault = _FailWeeklyCoinOnce();
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
      // PRD §8.3 item 19: isolate weekly payouts from the day-streak popup.
      Obf.prefStreakPaidDay: monday.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
      services: fault,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'a weekly wallet failure is logged and does not block Home or later runs',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.startWeeklyCourse();
      await flushAndMount(game);
      final first = game.run!;
      first.state.hoopsPassed = 30;
      game.endRun(first.endRun());
      await game.weeklyWritesSettled;
      expect(fault.failed, isTrue);
      expect(game.storage.weeklyRewards, {15, 30});
      expect(game.storage.coins, 120);
      await game.storage.saveMuteSound(true);
      game.sound.muted = false;
      await flushAndMount(game);
      game.replay();
      await flushAndMount(game);
      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.sound.muted, isTrue);
      expect(game.storage.weeklyRewards, {15, 30});
      await game.startWeeklyCourse();
      await flushAndMount(game);
      final second = game.run!;
      second.state.hoopsPassed = 60;
      game.endRun(second.endRun());
      await game.weeklyWritesSettled;
      expect(game.storage.weeklyRewards, {15, 30, 60});
      // PRD G1 / O28: this weekly run also completes the 40-hoop mission.
      expect(game.storage.coins, 270 + 55);
      expect(
        fault.events.where((e) => e.$1 == 'coins_earned' && e.$2?['source'] == 'mission').single.$2!['amount'],
        55,
      );
      expect(
        fault.events.where((e) => e.$1 == 'weekly_reward').single.$2!['tier'],
        60,
      );
    },
  );

  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(soundEnabled: false, worldHeight: 711);
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'weekly director opens every gate and ignores personal course history',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.startWeeklyCourse(now: monday);
      expect(game.run, isNull); // Locked installs cannot enter through the API.
      final setup = WeeklyWeek.at(monday).setup(viewHeight: 711);
      final first = RunController(setup: setup, game: game);
      expect(first.enabled, contains(ElementId.saw));
      // Squeeze is a timed feature, not a hoop/pickup registry member. Exercise
      // its actual lifetime gate rather than testing registry membership.
      game.state = GameState.playing;
      first.start();
      first.state.runClock = 1000;
      first.state.hoopIndex = 10;
      first.state.squeeze.nextAt = 0;
      first.features.whereType<SqueezeFeature>().single.update(.01, .01);
      expect(first.state.squeeze.phase, SqueezePhase.warning);
      expect(first.countsForUpload, isTrue);
      final normal = RunController(
        setup: const RunSetup(seed: 7, viewHeight: 711),
        game: game,
      );
      normal.start();
      normal.state.runClock = 1000;
      normal.state.hoopIndex = 10;
      normal.state.squeeze.nextAt = 0;
      normal.features.whereType<SqueezeFeature>().single.update(.01, .01);
      expect(normal.state.squeeze.phase, SqueezePhase.idle);
      expect(normal.enabled, isNot(contains(ElementId.saw)));
      final replay = RunController(setup: setup, game: game);
      // Simulate another player, or another attempt after lifetime flags change.
      game.storage.metElements = ElementId.values
          .map((e) => e.storageId)
          .toSet();
      game.storage.lastPortalRide = RideId.values.last.storageId;
      game.storage.lastFeatherRun = 0;
      game.storage.lastPieceRun = 0;
      final second = RunController(setup: setup, game: game);
      for (final id in [ElementId.feather, ElementId.puzzlePiece]) {
        final item = GapItemPlan(kind: id, trackX: 800, y: 300, extra: 0);
        expect(replay.spawner.spawnItem(item), isNotNull);
        expect(second.spawner.spawnItem(item), isNull);
      }
      expect(second.state.featherSpawned, isFalse);
      expect(second.state.pieceSpawned, isFalse);
      final context = DirectorContext.open(711);
      for (var i = 0; i < 220; i++) {
        final a = replay.director.nextSlot(context);
        final b = second.director.nextSlot(context);
        expect(a, b, reason: 'slot $i');
        expect(
          replay.director.nextGap(context, a),
          second.director.nextGap(context, b),
          reason: 'gap $i',
        );
      }
    },
  );
}
