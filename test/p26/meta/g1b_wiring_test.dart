import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/debug/run_stats.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import '../../helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/progression/missions.dart';
import 'package:flappy_spikes/run/run_end_bookkeeping.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('journal survives kills before and after wallet credit, exactly once', () async {
    for (final afterCredit in [false, true]) {
      SharedPreferences.setMockInitialValues({});
      final first = GameStorage();
      await first.load();
      await first.saveCoins(100);
      final board = Missions(day: 20, missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 3, paid: true),
        MissionProgress(template: MissionTemplate.m03, target: 15, progress: 15, paid: true),
        MissionProgress(template: MissionTemplate.m11, target: 10, progress: 10, paid: true),
      ]);
      await first.saveMissionJournal({
        'day': 20, 'tier': 0, 'rerollDay': -1, 'missions': board.toRecords(),
        'balance': 210, 'earned': 110,
      });
      if (afterCredit) await first.saveCoins(210);
      final recovered = GameStorage();
      await recovered.load();
      expect(recovered.coins, 210);
      expect(recovered.lifetimeCoinsEarned, 110);
      expect(RunEndBookkeeping.currentMissions(recovered).chestPending, isTrue);
      expect(RunEndBookkeeping.currentMissions(recovered).claimCoins().coins, 0);
      final again = GameStorage();
      await again.load();
      expect(again.coins, 210);
      expect(again.lifetimeCoinsEarned, 110);
      expect(again.missionJournal, isEmpty);
    }
  });

  test('unapplied payout adds to an intervening coin credit on recovery', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    await storage.saveCoins(100);
    await storage.saveMissionJournal({
      'day': 20, 'tier': 0, 'rerollDay': -1, 'missions': <Object>[],
      'balanceBefore': 100, 'earnedBefore': 0, 'amount': 20, 'applied': false,
    });
    await storage.saveCoins(110); // A separate win bonus landed first.
    await storage.saveLifetimeCoinsEarned(10);
    final recovered = GameStorage();
    await recovered.load();
    expect(recovered.coins, 130);
    expect(recovered.lifetimeCoinsEarned, 30);
    final again = GameStorage();
    await again.load();
    expect(again.coins, 130);
    expect(again.lifetimeCoinsEarned, 30);
  });

  test('applied journal repairs partial writes and preserves later credits', () async {
    for (final savedCoins in [100, 120, 130]) {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      await storage.saveCoins(savedCoins);
      await storage.saveLifetimeCoinsEarned(savedCoins == 130 ? 30 : 0);
      await storage.saveMissionJournal({
        'day': 20, 'tier': 0, 'rerollDay': -1, 'missions': <Object>[],
        'balanceBefore': 100, 'earnedBefore': 0, 'amount': 20, 'applied': true,
      });
      final recovered = GameStorage();
      await recovered.load();
      expect(recovered.coins, savedCoins == 130 ? 130 : 120);
      expect(recovered.lifetimeCoinsEarned, savedCoins == 130 ? 30 : 20);
      final again = GameStorage();
      await again.load();
      expect(again.coins, recovered.coins);
      expect(again.lifetimeCoinsEarned, recovered.lifetimeCoinsEarned);
    }
  });

  test('spending while a payout journal is pending survives recovery', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    await storage.saveCoins(120);
    await storage.saveLifetimeCoinsEarned(20);
    await storage.saveMissionJournal({
      'day': 20, 'tier': 0, 'rerollDay': -1, 'missions': <Object>[],
      'balanceBefore': 100, 'earnedBefore': 0, 'amount': 20, 'applied': true,
    });
    await storage.saveCoins(110);
    final recovered = GameStorage();
    await recovered.load();
    expect(recovered.coins, 110);
    expect(recovered.lifetimeCoinsEarned, 20);
  });

  test('rival flag persists and delete resets it', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    await storage.saveLastVersusHadRival(true);
    final next = GameStorage();
    await next.load();
    expect(next.lastVersusHadRival, isTrue);
    await next.resetVersusData();
    final reset = GameStorage();
    await reset.load();
    expect(reset.lastVersusHadRival, isFalse);
  });
  test('run events retain mission totals across revive and exclude win coins', () {
    final game = createRunTestGame();
    game.runDebug.ignoreGates = false;
    final run = RunController(game: game, setup: const RunSetup(seed: 7, viewHeight: 711));
    final stats = RunStats(run);
    run.events.emit(const HoopPassed(null, perfect: true));
    run.events.emit(const HoopPassed(null, perfect: true));
    run.events.emit(const HoopPassed(null, rimTouched: true));
    run.events.emit(const HoopPassed(null, perfect: true));
    run.events.emit(const Revived(ReviveKind.ad, 0));
    run.events.emit(const HoopPassed(null, perfect: true));
    run.events.emit(const HoopPassed(null, perfect: true));
    run.events.emit(const CoinsEarned(8, CoinSource.hoop));
    run.events.emit(const CoinsEarned(10, CoinSource.winBonus));
    run.events.emit(const PickupCollected(ElementId.feather, null));
    run.events.emit(const RideStarted(RideKind.portal));
    run.events.emit(const SqueezePhaseChanged(SqueezePhase.idle, 1));
    run.state.taken['hourglass'] = 2;
    final counts = stats.missionCounts(3);
    expect(counts.maxNoRimChain, 3);
    expect(counts.maxPerfectStreak, 3);
    expect(counts.inRunCoins, 8);
    expect(counts.feathers, 1);
    expect(counts.portalRides, 1);
    expect(counts.squeezesSurvived, 1);
    expect(counts.hourglasses, 2);
  });

  final spy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(services: spy, prefs: {'homeMode': 'free_fly'}),
    gameSize: Vector2(320, 711),
  ).testGameWidget('game four pays at run end; debug run pays nothing',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.storage.homeMode = HomeMode.freeFly;
      game.storage.gamesPlayed = 3;
      await tester.runAsync(() => RunEndBookkeeping.prepareMissions(game));
      final assigned = RunEndBookkeeping.currentMissions(game.storage);
      final assignmentEvents = spy.events.where((e) => e.$1 == 'mission_assigned').toList();
      expect(assignmentEvents, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(assignmentEvents[i].$2, {'mission': assigned.missions[i].template.id, 'tier': assigned.tier});
      }
      final board = Missions(day: game.storage.today, missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 2),
        MissionProgress(template: MissionTemplate.m03, target: 15, progress: 14),
        MissionProgress(template: MissionTemplate.m11, target: 10),
      ]);
      await game.storage.saveMissionTier(0);
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissions(board.toRecords());
      game.runDebug.ignoreGates = false;
      final run = await startRun(game);
      expect(run.countsForUpload, isTrue);
      run.state.hoopsPassed = 10;
      run.state.perfectPasses = 1;
      final balance = game.storage.coins;
      await tester.runAsync(() async {
        game.endRun(run.endRun());
        expect(game.storage.coins, balance + 110);
        expect(RunEndBookkeeping.currentMissions(game.storage).chestPending, isTrue);
        expect(game.storage.missionJournal['amount'], 110);
        await game.missionSettlement;
      });
      expect(game.storage.coins, balance + 110);
      final state = RunEndBookkeeping.currentMissions(game.storage);
      expect(state.missions.first.paid, isTrue);
      expect(state.missions.last.paid, isTrue);
      expect(state.chestPending, isTrue);
      expect(spy.events.where((e) => e.$1 == 'mission_complete').map((e) => e.$2).toList(), [
        {'mission': 'M01'}, {'mission': 'M03'}, {'mission': 'M11'},
      ]);
      expect(spy.events.where((e) => e.$1 == 'missions_all_done').toList(), [
        ('missions_all_done', null),
      ]);
      await tester.runAsync(() => RunEndBookkeeping.recordMissions(game));
      expect(game.storage.coins, balance + 110);
      run.markDebugAssist();
      final snapshot = game.storage.missions.toString();
      await tester.runAsync(() => RunEndBookkeeping.recordMissions(game));
      expect(game.storage.missions.toString(), snapshot);
      expect(game.storage.coins, balance + 110);
      await tester.runAsync(() async {
        await game.storage.saveStreakPaidDay(game.storage.today);
        game.missionsChestOpenerRegistered = true;
        game.goHome();
        for (var i = 0; i < 50; i++) { await Future<void>.delayed(const Duration(milliseconds: 2)); }
      });
      expect((game.homeMoments as HomeMomentBudget).selectedMoment, HomeMoment.missionsChest);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(), gameSize: Vector2(320, 711),
  ).testGameWidget('fresh debug run changes no unfinished mission, coins or streak',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.storage.gamesPlayed = 3;
      game.storage.homeMode = HomeMode.freeFly;
      final board = Missions(day: game.storage.today, missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 2),
        MissionProgress(template: MissionTemplate.m03, target: 15, progress: 14),
        MissionProgress(template: MissionTemplate.m11, target: 10, progress: 9),
      ]);
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissions(board.toRecords());
      game.runDebug.ignoreGates = false;
      final run = await startRun(game);
      run.state.hoopsPassed = 10;
      run.state.perfectPasses = 1;
      run.markDebugAssist();
      final before = game.storage.missions.toString();
      final coins = game.storage.coins;
      final streak = game.storage.streakDays;
      game.endRun(run.endRun());
      await tester.pump();
      expect(game.storage.missions.toString(), before);
      expect(game.storage.coins, coins);
      expect(game.storage.streakDays, streak);
      final completed = Missions(day: board.day, missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 3, paid: true),
        MissionProgress(template: MissionTemplate.m03, target: 15, progress: 15, paid: true),
        MissionProgress(template: MissionTemplate.m11, target: 10, progress: 10, paid: true),
      ]);
      await game.storage.saveMissions(completed.toRecords());
      await tester.runAsync(() async {
        game.goHome();
        for (var i = 0; i < 50; i++) { await Future<void>.delayed(const Duration(milliseconds: 2)); }
      });
      expect(RunEndBookkeeping.currentMissions(game.storage).chestPending, isTrue);
      // region P26-G1d
      // PRD G1: the production chest opener is now registered at launch.
      expect((game.homeMoments as HomeMomentBudget).selectedMoment, HomeMoment.missionsChest);
      // endregion
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: {'gamesPlayed': 6, 'bestHoops': 40},
      clock: () => DateTime.utc(2026, 10, 26, 12),
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget('weekly and mission payouts survive an immediate Home reload',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.runDebug.ignoreGates = false;
      await game.storage.saveLastVersusHadRival(true);
      final board = Missions(day: game.storage.today, missions: const [
        MissionProgress(template: MissionTemplate.m01, target: 3, progress: 2),
        MissionProgress(template: MissionTemplate.m03, target: 15),
        MissionProgress(template: MissionTemplate.m11, target: 10),
      ]);
      await game.storage.saveMissionTier(0);
      await game.storage.saveMissionDay(board.day);
      await game.storage.saveMissions(board.toRecords());
      await game.startWeeklyCourse();
      final run = game.run!;
      expect(run.setup.weekly, isTrue);
      expect(game.homeMode, HomeMode.versus);
      run.state.hoopsPassed = 30;
      final before = game.storage.coins;
      game.endRun(run.endRun());
      await flushAndMount(game);
      game.replay();
      await Future.wait([game.missionSettlement, game.weeklyWritesSettled]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      final loaded = GameStorage(clock: () => DateTime.utc(2026, 10, 26, 12));
      await loaded.load();
      expect(loaded.coins, before + 75 + 120);
      expect(loaded.weeklyBest, {WeeklyWeek.at(loaded.now()).key: 30});
      expect(loaded.weeklyRewards, {15, 30});
      expect(RunEndBookkeeping.currentMissions(loaded).missions.first.paid, isTrue);
      expect(RunEndBookkeeping.currentMissions(loaded).missions.last.paid, isTrue);
      expect(loaded.lastVersusHadRival, isTrue);
      expect(game.storage.coins, loaded.coins);
    },
  );

}
