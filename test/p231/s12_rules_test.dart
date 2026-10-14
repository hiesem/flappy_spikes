// PRD-2.3.1 §12.2 / §12.9 one test per achievement rule (createRunTestGame;
// the harness's runs are debug starts, so the rule tests opt in with
// `AchievementTracker.countDebugRuns`), plus the exclusions (§12.2 "which
// runs count"): a forced, startHoopIndex or debugPass run unlocks nothing,
// and neither does `grantAll()`.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/achievements/achievements_feature.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/capsule.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
  }) => FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(prefs: prefs, services: spy);
  }, gameSize: Vector2(320, 568));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
    g.achievements.countDebugRuns = true;
  }

  Set<String> unlocked(FlappySpikesGame g) => g.storage.achUnlocked;

  /// Ends the running run (death → revive offer declined → results).
  Future<void> finish(FlappySpikesGame g) async {
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
  }

  RunSummary summary({DuelResult? duel}) => RunSummary(
    score: 0,
    hoopsPassed: 0,
    coins: 0,
    bestBefore: 0,
    bestAfter: 0,
    runSeconds: 1,
    cause: MistakeCause.missedHoop,
    hoopIndex: 0,
    timeline: RunTimeline.empty(),
    duel: duel,
  );

  final t = tester();

  // --- ranks -----------------------------------------------------------------

  for (final (i, lv) in kLevels.indexed) {
    t.testGameWidget(
      '§12.2 rank ${lv.name}: a run scoring exactly ${lv.threshold} unlocks '
      'it and every lower rank, no higher one',
      setUp: boot,
      verify: (g, _) async {
        final run = await startRun(g);
        run.ctx.addScore(lv.threshold);
        await finish(g);
        for (final (j, id) in kRankAchievements.indexed) {
          expect(unlocked(g).contains(id.key), j <= i, reason: id.key);
        }
        expect(
          spy.events.where(
            (e) =>
                e.$1 == 'achievement_unlocked' &&
                e.$2!['id'] == kRankAchievements[i].key,
          ),
          hasLength(1),
        );
      },
    );
  }

  t.testGameWidget(
    '§12.2 ranks: a 2,000-point run unlocks 9 ranks at once (all toasted)',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.ctx.addScore(2000);
      await finish(g);
      expect(unlocked(g).where((k) => k.startsWith('rank_')), hasLength(9));
      expect(unlocked(g).contains('rank_legend'), isFalse);
      expect(
        g.achievements.toastQueue
                .where((a) => a.group == AchievementGroup.rank)
                .length +
            (g.achievementToast == null ? 0 : 1),
        greaterThanOrEqualTo(9),
      );
    },
  );

  tester(prefs: {'bestScore': 5000}).testGameWidget(
    '§12.2 ranks: a high stored best and a low run unlock nothing (start '
    'fresh: the run score counts, never the best)',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.ctx.addScore(5);
      await finish(g);
      expect(unlocked(g).where((k) => k.startsWith('rank_')), isEmpty);
    },
  );

  // --- rides -------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 each of the 6 portal rides on RideEnded, then FREQUENT FLYER; a '
    'comet ride and an unfinished ride count nothing',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events
        ..emit(const RideEnded(RideKind.comet))
        ..emit(const RideStarted(RideKind.portal, RideId.storm));
      expect(unlocked(g), isEmpty);
      for (final (i, r) in RideId.values.indexed) {
        run.events.emit(RideEnded(RideKind.portal, r));
        expect(unlocked(g).contains('ride_${r.name}'), isTrue);
        expect(g.storage.achRides, hasLength(i + 1));
        expect(unlocked(g).contains('ride_all'), i == RideId.values.length - 1);
      }
      // Again: nothing new (idempotent).
      final n = spy.events.where((e) => e.$1 == 'achievement_unlocked').length;
      run.events.emit(const RideEnded(RideKind.portal, RideId.cannon));
      expect(
        spy.events.where((e) => e.$1 == 'achievement_unlocked'),
        hasLength(n),
      );
    },
  );

  tester(
    prefs: {
      'achRides': ['cannon', 'space', 'volcano', 'sea', 'pinball'],
    },
  ).testGameWidget(
    '§12.2 FREQUENT FLYER counts the stored rides of earlier runs',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events.emit(const RideEnded(RideKind.portal, RideId.storm));
      expect(unlocked(g), {'ride_storm', 'ride_all'});
    },
  );

  // --- items ---------------------------------------------------------------------

  test('§12.2 capsule mapping: hourglass / mini / frenzy; piggy coins, '
      'swarm and the comet map to nothing', () {
    CapsulePickup cap(CapsuleType t) => CapsulePickup(
      GapItemPlan(kind: ElementId.capsule, trackX: 0, y: 0, extra: t),
    );
    expect(
      AchievementsFeature.itemFor(
        PickupCollected(ElementId.capsule, cap(CapsuleType.hourglass)),
      ),
      AchievementId.itemHourglass,
    );
    expect(
      AchievementsFeature.itemFor(
        PickupCollected(ElementId.capsule, cap(CapsuleType.miniBird)),
      ),
      AchievementId.itemMiniBird,
    );
    expect(
      AchievementsFeature.itemFor(
        PickupCollected(ElementId.capsule, cap(CapsuleType.coinFrenzy)),
      ),
      AchievementId.itemCoinFrenzy,
    );
    for (final e in [
      ElementId.piggyCoins,
      ElementId.fireflySwarm,
      ElementId.comet,
    ]) {
      expect(AchievementsFeature.itemFor(PickupCollected(e, null)), isNull);
    }
    expect(
      AchievementsFeature.itemFor(
        const PickupCollected(ElementId.capsule, null),
      ),
      isNull,
    );
  });

  t.testGameWidget(
    '§12.2 each of the 11 items on its first catch, then MAGPIE; piggy '
    'coins and fireflies are ignored',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events
        ..emit(const PickupCollected(ElementId.piggyCoins, null))
        ..emit(const PickupCollected(ElementId.fireflySwarm, null))
        ..emit(const PickupCollected(ElementId.comet, null));
      expect(unlocked(g), isEmpty);
      final plain = {
        ElementId.heart: AchievementId.itemHeart,
        ElementId.shield: AchievementId.itemShield,
        ElementId.starTrail: AchievementId.itemStarTrail,
        ElementId.egg: AchievementId.itemEgg,
        ElementId.piggy: AchievementId.itemPiggy,
        ElementId.jar: AchievementId.itemJar,
        ElementId.feather: AchievementId.itemFeather,
        ElementId.puzzlePiece: AchievementId.itemPuzzle,
      };
      for (final MapEntry(:key, :value) in plain.entries) {
        run.events.emit(PickupCollected(key, null));
        expect(unlocked(g).contains(value.key), isTrue, reason: value.key);
      }
      expect(unlocked(g).contains('item_all'), isFalse);
      for (final c in CapsuleType.values) {
        run.events.emit(
          PickupCollected(
            ElementId.capsule,
            CapsulePickup(
              GapItemPlan(kind: ElementId.capsule, trackX: 0, y: 0, extra: c),
            ),
          ),
        );
      }
      for (final a in kItemAchievements) {
        expect(unlocked(g).contains(a.key), isTrue, reason: a.key);
      }
      expect(g.storage.achItems, hasLength(11));
      expect(unlocked(g).contains('item_all'), isTrue);
    },
  );

  // --- mastery ---------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 the four new events unlock MOTHER HEN, NIGHT OWL, SEEING STARS, '
    "BIRD'S-EYE VIEW",
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events.emit(const EggHatched());
      expect(unlocked(g), {'master_hatch'});
      run.events.emit(const JarFilled());
      run.events.emit(const StarTrailPerfect());
      run.events.emit(const PuzzleCompleted());
      expect(unlocked(g), {
        'master_hatch',
        'master_jar',
        'master_stars',
        'master_picture',
      });
    },
  );

  tester(prefs: {'puzzlePieces': 7}).testGameWidget(
    '§12.2 PuzzleCompleted is emitted where the picture completes '
    '(`puzzle_completed`)',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      expect(unlocked(g).contains('master_picture'), isTrue);
      expect(spy.events.any((e) => e.$1 == 'puzzle_completed'), isTrue);
    },
  );

  for (final counts in [true, false]) {
    tester(prefs: {'feathers': 3}).testGameWidget(
      '§12.2 GOLDEN EGG: popping the jackpot balloon '
      '${counts ? 'unlocks it' : 'of a non-counting run unlocks nothing'}',
      setUp: boot,
      verify: (g, _) async {
        g.achievements.countDebugRuns = counts;
        await startRun(g);
        killRunThroughSaves(g);
        await flushAndMount(g);
        expect(g.state, GameState.bonus);
        expect(g.achievements.lastRunCounted, counts);
        final b = g.bonusScreen!;
        for (var i = 0; i < 12; i++) {
          g.update(1 / 60);
        }
        final jackpot = b.prizes.indexOf(BonusConfig.jackpot);
        final other = b.prizes.indexWhere((p) => p != BonusConfig.jackpot);
        expect(b.tapTile(other), isTrue);
        expect(unlocked(g).contains('master_jackpot'), isFalse);
        for (var i = 0; i < 90; i++) {
          g.update(1 / 60);
        }
        expect(b.tapTile(jackpot), isTrue);
        expect(unlocked(g).contains('master_jackpot'), counts);
      },
    );
  }

  // --- hoops -----------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 hoops 10 / 25 / 50 / 100 by hoopsPassed (a train counts 3)',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      for (var i = 0; i < 9; i++) {
        run.debugPass();
      }
      expect(unlocked(g), isEmpty);
      // A train: three rings, three hoops passed.
      run.state.hoopsPassed += 2;
      run.debugPass();
      expect(run.state.hoopsPassed, 12);
      expect(unlocked(g), {'hoops_10'});
      run.state.hoopsPassed = 24;
      run.debugPass();
      expect(unlocked(g), {'hoops_10', 'hoops_25'});
      run.state.hoopsPassed = 49;
      run.debugPass();
      expect(unlocked(g).contains('hoops_50'), isTrue);
      expect(unlocked(g).contains('hoops_100'), isFalse);
      run.state.hoopsPassed = 99;
      run.debugPass();
      expect(unlocked(g).contains('hoops_100'), isTrue);
    },
  );

  t.testGameWidget(
    '§12.2 hoops: reaching 100 at once unlocks every lower one too',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.state.hoopsPassed = 99;
      run.debugPass();
      expect(unlocked(g), {'hoops_10', 'hoops_25', 'hoops_50', 'hoops_100'});
    },
  );

  // --- versus ---------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 versus wins count (1 / 10 / 50); draws, losses and solo runs '
    "don't",
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events
        ..emit(RunEnded(summary(duel: DuelResult.draw)))
        ..emit(RunEnded(summary(duel: DuelResult.lose)))
        ..emit(RunEnded(summary()));
      expect(g.storage.achVersusWins, 0);
      expect(unlocked(g), isEmpty);
      run.events.emit(RunEnded(summary(duel: DuelResult.win)));
      expect(g.storage.achVersusWins, 1);
      expect(unlocked(g), {'vs_1'});
      for (var i = 1; i < 10; i++) {
        run.events.emit(RunEnded(summary(duel: DuelResult.win)));
      }
      expect(g.storage.achVersusWins, 10);
      expect(unlocked(g), {'vs_1', 'vs_10'});
      for (var i = 10; i < 50; i++) {
        run.events.emit(RunEnded(summary(duel: DuelResult.win)));
      }
      expect(unlocked(g), {'vs_1', 'vs_10', 'vs_50'});
    },
  );

  // --- firsts ---------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 STILL TWEETING on Revived (any kind)',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      run.events.emit(const Revived(ReviveKind.coins, 100));
      expect(unlocked(g), {'first_revive'});
    },
  );

  t.testGameWidget(
    '§12.2 BIG BIRD: a run started with Big Hoops; a plain run does not',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      expect(unlocked(g), isEmpty);
      await finish(g);
      g.goHome();
      await flushAndMount(g);
      stepGame(g, 1);
      await flushAndMount(g);
      await startRun(g, starter: Powerup.bigHoops);
      expect(unlocked(g), {'first_big_hoops'});
    },
  );

  t.testGameWidget(
    '§12.2 HOT WINGS on a real FEVER (the pair gift / FEVER ring), never on '
    'the streak fire',
    setUp: boot,
    verify: (g, _) async {
      final run = await startRun(g);
      for (var i = 0; i < 4; i++) {
        run.debugPass(perfect: true);
      }
      expect(run.state.onFire, isTrue, reason: 'the streak fire is lit');
      expect(unlocked(g).contains('first_fever'), isFalse);
      final started = <FeverStarted>[];
      run.events.on<FeverStarted>(started.add);
      // Already burning: a real FEVER still counts.
      run.events.emit(const FeverIgnite('pair'));
      expect(started, hasLength(1));
      expect(unlocked(g).contains('first_fever'), isTrue);
    },
  );

  // --- shop ------------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 the shop: FRESH FEATHERS on the first purchase, PROUD PEACOCK at '
    'kCollectibleTotal owned',
    setUp: boot,
    verify: (g, _) async {
      final a = g.achievements;
      a.onShopPurchase(owned: 1, total: kCollectibleTotal);
      expect(unlocked(g), {'skin_first'});
      a.onShopPurchase(owned: kCollectibleTotal - 1, total: kCollectibleTotal);
      expect(unlocked(g).contains('skin_all'), isFalse);
      a.onShopPurchase(owned: kCollectibleTotal, total: kCollectibleTotal);
      expect(unlocked(g).contains('skin_all'), isTrue);
    },
  );

  t.testGameWidget(
    '§12.2 grantAll() (debug) unlocks nothing',
    setUp: boot,
    verify: (g, _) async {
      await g.menu.items.grantAll();
      await flushAndMount(g);
      expect(g.menu.items.ownedCount, kCollectibleTotal);
      expect(unlocked(g), isEmpty);
    },
  );

  // --- daily ---------------------------------------------------------------------

  t.testGameWidget(
    '§12.2 the daily streak over debugDayOffset: same day, next day, a gap '
    'resets, 7 and 30',
    setUp: boot,
    verify: (g, _) async {
      final s = g.storage;
      await startRun(g);
      await finish(g);
      expect(s.achDayStreak, 1);
      final d0 = s.achLastPlayDay;
      expect(d0, s.today);
      // Same day: unchanged.
      g.achievements.onRunDay(s.today);
      expect(s.achDayStreak, 1);
      Future<void> day(int offset) async {
        await s.saveDebugDayOffset(offset);
        g.achievements.onRunDay(s.today);
      }

      for (var i = 1; i < 6; i++) {
        await day(i);
      }
      expect(s.achDayStreak, 6);
      expect(unlocked(g).contains('daily_7'), isFalse);
      await day(6);
      expect(s.achDayStreak, 7);
      expect(unlocked(g).contains('daily_7'), isTrue);
      // A whole missed day resets the streak.
      await day(8);
      expect(s.achDayStreak, 1);
      for (var i = 9; i < 8 + 30; i++) {
        await day(i);
      }
      expect(s.achDayStreak, 30);
      expect(unlocked(g).contains('daily_30'), isTrue);
    },
  );

  // --- exclusions (§12.2 "which runs count") ---------------------------------------

  Future<void> bootStrict(FlappySpikesGame g, WidgetTester w) async {
    await boot(g, w);
    g.achievements.countDebugRuns = false;
  }

  t.testGameWidget(
    '§12.2 a normal run counts; a forced, startHoopIndex, ignoreGates or '
    'god-mode run does not',
    setUp: bootStrict,
    verify: (g, _) async {
      g.runDebug.ignoreGates = false;
      Future<RunController> fresh({
        int start = 0,
        List<ElementId> force = const [],
      }) async {
        if (g.run != null) {
          await finish(g);
          g.goHome();
          await flushAndMount(g);
          stepGame(g, 1);
          await flushAndMount(g);
        }
        return startRun(g, startHoopIndex: start, force: force);
      }

      expect((await fresh()).countsForAchievements, isTrue);
      expect(
        (await fresh(force: [ElementId.heart])).countsForAchievements,
        isFalse,
      );
      expect((await fresh(start: 20)).countsForAchievements, isFalse);
      g.runDebug.ignoreGates = true;
      expect((await fresh()).countsForAchievements, isFalse);
      g.runDebug.ignoreGates = false;
      final r = await fresh();
      g.runDebug.god = true;
      expect(r.countsForAchievements, isFalse);
      g.runDebug.god = false;
      // P1E-02: god mode used once excludes the run until it ends.
      expect(r.countsForAchievements, isFalse);
      final r2 = await fresh();
      expect(r2.countsForAchievements, isTrue);
      r2.debugForce(ElementId.heart);
      expect(r2.countsForAchievements, isFalse);
    },
  );

  t.testGameWidget(
    '§12.9 a forced run unlocks nothing (items, rides, ranks, daily)',
    setUp: bootStrict,
    verify: (g, _) async {
      final run = await startRun(g, force: [ElementId.heart]);
      expect(run.countsForAchievements, isFalse);
      run.events
        ..emit(const PickupCollected(ElementId.heart, null))
        ..emit(const RideEnded(RideKind.portal, RideId.cannon))
        ..emit(const Revived(ReviveKind.ad, 0))
        ..emit(const EggHatched());
      run.ctx.addScore(1000);
      await finish(g);
      expect(unlocked(g), isEmpty);
      expect(g.storage.achDayStreak, 0);
      expect(g.achievements.lastRunCounted, isFalse);
    },
  );

  t.testGameWidget(
    '§12.9 a startHoopIndex run unlocks nothing',
    setUp: bootStrict,
    verify: (g, _) async {
      g.runDebug.ignoreGates = false;
      final run = await startRun(g, startHoopIndex: 30);
      run.state.hoopsPassed = 99;
      run.events.emit(const HoopPassed(null));
      run.events.emit(const FeverIgnite('pair'));
      await finish(g);
      expect(unlocked(g), isEmpty);
    },
  );

  t.testGameWidget(
    '§12.9 a debugPass run unlocks nothing',
    setUp: bootStrict,
    verify: (g, _) async {
      g.runDebug.ignoreGates = false;
      final run = await startRun(g);
      expect(run.countsForAchievements, isTrue);
      for (var i = 0; i < 12; i++) {
        run.debugPass(perfect: true);
      }
      expect(run.countsForAchievements, isFalse);
      run.ctx.addScore(50);
      await finish(g);
      expect(unlocked(g), isEmpty);
    },
  );
}
