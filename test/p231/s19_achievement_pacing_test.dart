// PRD-2.3.1 §19.6 achievement pacing: the item achievements count lifetime
// catches (§19.1), a counting run unlocks at most one achievement through
// the persistent FIFO `achPending` queue (§19.2), and the hidden flags
// (§19.3).
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/achievements/achievements.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 's12_sync_test.dart' show FakeGameServices;

class _Services extends FakeGameServices {
  @override
  Future<void> submitScorePlugin(int score) async {}
}

void main() {
  late _Services services;
  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
  }) => FlameTester<FlappySpikesGame>(() {
    services = _Services()
      ..markInitialized()
      ..debugSetPlayer('p1');
    return createRunTestGame(prefs: prefs, services: services);
  }, gameSize: Vector2(320, 568));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
    g.achievements.countDebugRuns = true;
  }

  Future<void> finish(FlappySpikesGame g) async {
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
  }

  Future<void> home(FlappySpikesGame g) async {
    g.goHome();
    await flushAndMount(g);
    stepGame(g, 1);
    await flushAndMount(g);
  }

  /// One counting run that emits [events], then ends (results page).
  Future<RunController> runWith(
    FlappySpikesGame g, [
    List<RunEvent> events = const [],
  ]) async {
    final r = await startRun(g);
    events.forEach(r.events.emit);
    await finish(g);
    return r;
  }

  Set<String> unlocked(FlappySpikesGame g) => g.storage.achUnlocked;
  List<String> pending(FlappySpikesGame g) => g.storage.achPending;

  final t = tester();

  // --- §19.1 item counts ---------------------------------------------------------

  t.testGameWidget(
    '§19.1 N−1 catches earn nothing; the N-th earns the item, which unlocks '
    'at the run end through the queue',
    setUp: boot,
    verify: (g, _) async {
      const id = AchievementId.itemHeart;
      final n = itemGoal(id);
      expect(n, greaterThanOrEqualTo(3));
      var r = await startRun(g);
      for (var i = 0; i < n - 1; i++) {
        r.events.emit(const PickupCollected(ElementId.heart, null));
      }
      expect(g.achievements.earned, isEmpty);
      expect(g.achievements.itemCount(id), n - 1);
      await finish(g);
      expect(unlocked(g), isEmpty);
      await home(g);
      r = await startRun(g);
      r.events.emit(const PickupCollected(ElementId.heart, null));
      // Earned, not unlocked before the run ends.
      expect(pending(g), [id.key]);
      expect(unlocked(g), isEmpty);
      await finish(g);
      expect(unlocked(g), {id.key});
      expect(pending(g), isEmpty);
    },
  );

  t.testGameWidget(
    '§19.1 the catches of one run count each (no fold in the run journal)',
    setUp: boot,
    verify: (g, _) async {
      g.achievements.countDebugRuns = false;
      g.runDebug.ignoreGates = false;
      final r = await startRun(g);
      expect(r.countsForAchievements, isTrue);
      for (var i = 0; i < 3; i++) {
        r.events.emit(const PickupCollected(ElementId.shield, null));
      }
      // Staged until the run ends.
      expect(g.storage.achItemCounts, isEmpty);
      expect(g.storage.achJournal, hasLength(3));
      await finish(g);
      expect(g.storage.achItemCounts['item_shield'], 3);
    },
  );

  test('§19.1 the counts survive a restart; debug reset clears them', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GameStorage();
    await s.load();
    await s.saveAchItemCounts({'item_heart': 4, 'item_jar': 1});
    await s.saveAchPending(['rank_egg', 'hoops_10']);
    final again = GameStorage();
    await again.load();
    expect(again.achItemCounts, {'item_heart': 4, 'item_jar': 1});
    expect(again.achPending, ['rank_egg', 'hoops_10']);
    await again.resetAchievements();
    final cleared = GameStorage();
    await cleared.load();
    expect(cleared.achItemCounts, isEmpty);
    expect(cleared.achPending, isEmpty);
  });

  tester(
    prefs: {
      'achItemCounts': ['item_heart=6', 'item_puzzle=2'],
    },
  ).testGameWidget(
    '§19.1 the stored counts carry on after a restart',
    setUp: boot,
    verify: (g, _) async {
      expect(g.achievements.itemCount(AchievementId.itemHeart), 6);
      final r = await startRun(g);
      r.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
      expect(g.achievements.itemCount(AchievementId.itemPuzzle), 3);
    },
  );

  tester(
    prefs: {
      'achUnlocked': [
        for (final a in kItemAchievements)
          if (a != AchievementId.itemPuzzle) a.key,
      ],
      'achPending': ['item_puzzle'],
    },
  ).testGameWidget(
    '§19.1 MAGPIE needs all 11 item achievements unlocked (pending is not '
    'enough), then waits for its own slot',
    setUp: boot,
    verify: (g, _) async {
      final a = g.achievements;
      expect(a.isUnlocked(AchievementId.itemAll), isFalse);
      expect(a.isPending(AchievementId.itemAll), isFalse);
      await runWith(g);
      expect(unlocked(g).contains('item_puzzle'), isTrue);
      expect(unlocked(g).contains('item_all'), isFalse);
      expect(pending(g), ['item_all']);
      await home(g);
      await runWith(g);
      expect(unlocked(g).contains('item_all'), isTrue);
    },
  );

  test('§19.1 every item has a goal from the allowed set, said in its '
      'description; MAGPIE reads "Reach every item goal."', () {
    for (final a in kItemAchievements) {
      final n = itemGoal(a);
      expect([3, 5, 10, 15, 20, 25, 50], contains(n), reason: a.key);
      expect(a.description, contains('$n '), reason: a.key);
      expect(a.description, startsWith('Catch '), reason: a.key);
    }
    expect(kItemGoals.keys, unorderedEquals(kItemAchievements));
    expect(AchievementId.itemAll.description, 'Reach every item goal.');
  });

  // --- §19.2 at most one unlock per run -------------------------------------------

  t.testGameWidget(
    '§19.2 a run that earns 3 unlocks 1; the next two counting runs unlock '
    'the others in FIFO order; the toast shows only the one',
    setUp: boot,
    verify: (g, _) async {
      await runWith(g, const [
        Revived(ReviveKind.coins, 100),
        EggHatched(),
        JarFilled(),
      ]);
      expect(unlocked(g), {'first_revive'});
      expect(pending(g), ['master_hatch', 'master_jar']);
      expect(
        g.achievements.toastQueue.length + (g.achievementToast == null ? 0 : 1),
        1,
      );
      final shown = g.achievementToast;
      if (shown != null) {
        // The pill holds only the one unlock.
        expect(g.achievements.toastQueue, isEmpty);
      } else {
        expect(g.achievements.toastQueue, [AchievementId.firstRevive]);
      }
      await home(g);
      await runWith(g);
      expect(unlocked(g), {'first_revive', 'master_hatch'});
      expect(pending(g), ['master_jar']);
      await home(g);
      await runWith(g);
      expect(unlocked(g), {'first_revive', 'master_hatch', 'master_jar'});
      expect(pending(g), isEmpty);
      // Nothing left: a further run unlocks nothing.
      await home(g);
      await runWith(g);
      expect(unlocked(g), hasLength(3));
    },
  );

  tester(
    prefs: {
      'achPending': ['master_hatch', 'master_jar'],
    },
  ).testGameWidget(
    '§19.2 a later run with new earnings releases the oldest pending first; '
    'the new ones join the end of the queue',
    setUp: boot,
    verify: (g, _) async {
      await runWith(g, const [Revived(ReviveKind.ad, 0)]);
      expect(unlocked(g), {'master_hatch'});
      expect(pending(g), ['master_jar', 'first_revive']);
    },
  );

  tester(
    prefs: {
      'achPending': ['master_hatch'],
    },
  ).testGameWidget(
    '§19.2 excluded runs earn nothing and release nothing',
    setUp: boot,
    verify: (g, _) async {
      g.achievements.countDebugRuns = false;
      final r = await startRun(g, force: [ElementId.heart]);
      expect(r.countsForAchievements, isFalse);
      r.events
        ..emit(const Revived(ReviveKind.coins, 100))
        ..emit(const JarFilled());
      r.ctx.addScore(500);
      await finish(g);
      expect(unlocked(g), isEmpty);
      expect(pending(g), ['master_hatch']);
    },
  );

  tester(
    prefs: {
      'achPending': ['master_hatch'],
    },
  ).testGameWidget(
    '§19.2 the shop unlocks at once and uses no run slot',
    setUp: boot,
    verify: (g, _) async {
      g.achievements.onShopPurchase(owned: 1, total: kCollectibleTotal);
      expect(unlocked(g), {'skin_first'});
      g.achievements.onShopPurchase(
        owned: kCollectibleTotal,
        total: kCollectibleTotal,
      );
      expect(unlocked(g), {'skin_first', 'skin_all'});
      expect(pending(g), ['master_hatch']);
      // The next run still releases its own one.
      await runWith(g);
      expect(unlocked(g), contains('master_hatch'));
    },
  );

  tester(
    prefs: {
      'feathers': 3,
      'achPending': ['master_hatch', 'master_jar'],
    },
  ).testGameWidget(
    '§19.2 the jackpot unlocks at once, besides the run slot',
    setUp: boot,
    verify: (g, _) async {
      await startRun(g);
      killRunThroughSaves(g);
      await flushAndMount(g);
      expect(g.state, GameState.bonus);
      // The run end released its one slot.
      expect(unlocked(g), {'master_hatch'});
      final b = g.bonusScreen!;
      for (var i = 0; i < 12; i++) {
        g.update(1 / 60);
      }
      expect(b.tapTile(b.prizes.indexOf(BonusConfig.jackpot)), isTrue);
      expect(unlocked(g), {'master_hatch', 'master_jackpot'});
      expect(pending(g), ['master_jar']);
    },
  );

  t.testGameWidget(
    '§19.2 the debug "unlock one" is immediate and leaves the queue',
    setUp: boot,
    verify: (g, _) async {
      await runWith(g, const [Revived(ReviveKind.coins, 1), EggHatched()]);
      expect(pending(g), ['master_hatch']);
      g.achievements.unlock(AchievementId.masterHatch);
      expect(pending(g), isEmpty);
      expect(unlocked(g), {'first_revive', 'master_hatch'});
    },
  );

  t.testGameWidget(
    '§19.2 an unlocked achievement is never queued again',
    setUp: boot,
    verify: (g, _) async {
      await runWith(g, const [Revived(ReviveKind.coins, 1)]);
      expect(unlocked(g), {'first_revive'});
      await home(g);
      final r = await startRun(g);
      r.events.emit(const Revived(ReviveKind.coins, 1));
      expect(pending(g), isEmpty);
    },
  );

  tester(
    prefs: {
      'achJournal': ['u:first_revive', 'item:item_heart', 'ride:space'],
    },
  ).testGameWidget(
    '§19.2 a recovered journal goes into the queue (no unlock, no toast, '
    'no report)',
    setUp: boot,
    verify: (g, _) async {
      await flushAndMount(g);
      expect(unlocked(g), isEmpty);
      expect(pending(g), ['first_revive', 'ride_space']);
      expect(g.storage.achItemCounts, {'item_heart': 1});
      expect(g.achievements.toastQueue, isEmpty);
      expect(services.unlocks, isEmpty);
      // The next counting run end releases the oldest.
      await runWith(g);
      expect(unlocked(g), {'first_revive'});
    },
  );

  t.testGameWidget(
    '§19.2 nothing pending is reported to Play Games',
    setUp: boot,
    verify: (g, _) async {
      await runWith(g, const [
        Revived(ReviveKind.coins, 1),
        EggHatched(),
        FeverStarted(),
      ]);
      for (var i = 0; i < 5; i++) {
        await flushAndMount(g);
      }
      expect(services.unlocks, ['unlock:first_revive']);
      expect(g.storage.achReported, {'first_revive'});
      expect(pending(g), ['master_hatch', 'first_fever']);
    },
  );

  test('§19.2 the queue logic without a game: FIFO, ties in earning order, '
      'stale keys skipped', () async {
    SharedPreferences.setMockInitialValues({
      'achPending': ['rank_egg', 'nope', 'hoops_10'],
      'achUnlocked': ['rank_egg'],
    });
    final s = GameStorage();
    await s.load();
    final services = FakeGameServices();
    final a = AchievementTracker(storage: s, services: services);
    expect(a.releaseOne(), AchievementId.hoops10);
    expect(s.achPending, isEmpty);
    expect(a.releaseOne(), isNull);
    // A 120-point run (hoops staged first, then the ranks) earns in order.
    a.onHoops(25);
    a.onRunScore(120);
    expect(s.achPending, [
      'hoops_25',
      'rank_chick',
      'rank_fledgling',
    ]);
  });

  // --- §19.3 hidden flags ---------------------------------------------------------

  test('§19.3 hidden: the 7 rides, the 5 masteries, MAGPIE, vs_10, vs_50, '
      'skin_all and daily_30; nothing else', () {
    final want = {
      for (final a in AchievementId.values)
        if (a.group == AchievementGroup.ride) a.key,
      'master_hatch',
      'master_jar',
      'master_stars',
      'master_picture',
      'master_jackpot',
      'item_all',
      'vs_10',
      'vs_50',
      'skin_all',
      'daily_30',
    };
    expect({
      for (final a in AchievementId.values)
        if (a.hidden) a.key,
    }, want);
  });
}
