// PRD-2.3.1 §12.2 / §12.9 "runs with any debug or test start never unlock
// achievements": the regression tests of QA findings P1E-01 (a debug-forced
// slot starter), P1E-02 (god mode latches the exclusion) and P1E-03 (a run
// never grants permanent unlocks and then turns into a debug run: its rules
// stay staged until it ends), QA P2-02 (the debug origin of an armed
// starter survives a restart) and P2-03 (a clean run's completed events
// survive the app dying before the run ends). Every run here is strict
// (`countDebugRuns = false`, `ignoreGates = false`), signed in on a fake.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievements.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/debug/force_menu.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
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
  final t = FlameTester<FlappySpikesGame>(() {
    services = _Services()
      ..markInitialized()
      ..debugSetPlayer('p1');
    return createRunTestGame(services: services);
  }, gameSize: Vector2(320, 568));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
    g.runDebug.ignoreGates = false;
    g.achievements.countDebugRuns = false;
  }

  Future<void> finish(FlappySpikesGame g) async {
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
  }

  Iterable<String> achEvents() => services.events
      .where((e) => e.$1 == 'achievement_unlocked')
      .map((e) => e.$2!['id']! as String);

  /// Nothing of the run reached storage, the platform, analytics or the
  /// toast queue.
  void expectNothing(FlappySpikesGame g) {
    expect(g.storage.achUnlocked, isEmpty);
    expect(g.storage.achReported, isEmpty);
    expect(g.storage.achItems, isEmpty);
    expect(g.storage.achDayStreak, 0);
    expect(services.unlocks, isEmpty);
    expect(achEvents(), isEmpty);
    expect(g.achievements.toastQueue, isEmpty);
    expect(g.achievements.lastRunCounted, isFalse);
  }

  // --- P1E-01 a debug-forced slot starter -------------------------------------

  t.testGameWidget(
    'P1E-01 a Home debug "Slot: force BIG HOOPS" starter never counts',
    setUp: boot,
    verify: (g, _) async {
      g.menu.slot.debugForce = Powerup.bigHoops;
      g.menu.slot.rollForArrival();
      await g.menu.slot.armOffered();
      final r = await startRun(g);
      expect(r.setup.starter, Powerup.bigHoops);
      expect(r.setup.debugStarter, isTrue);
      expect(r.countsForAchievements, isFalse);
      r.ctx.addScore(50);
      await finish(g);
      expectNothing(g);
    },
  );

  t.testGameWidget(
    'P1E-01 a forced SHIELD starter stays excluded after "Slot: random"',
    setUp: boot,
    verify: (g, _) async {
      g.menu.slot.debugForce = Powerup.shield;
      g.menu.slot.rollForArrival();
      await g.menu.slot.armOffered();
      // "Slot: random (re-roll)" after arming: the armed one keeps its origin.
      g.menu.slot.debugForce = null;
      g.menu.slot.rollForArrival();
      final r = await startRun(g);
      expect(r.setup.starter, Powerup.shield);
      expect(r.setup.debugStarter, isTrue);
      expect(r.countsForAchievements, isFalse);
      r.events.emit(const PickupCollected(ElementId.heart, null));
      r.ctx.addScore(50);
      await finish(g);
      expectNothing(g);
    },
  );

  t.testGameWidget(
    'P1E-01 a normally acquired BIG HOOPS counts (and the debug origin '
    'does not leak into the next run)',
    setUp: boot,
    verify: (g, _) async {
      g.menu.slot.debugForce = Powerup.shield;
      g.menu.slot.rollForArrival();
      g.menu.slot.debugForce = null; // a random offer replaces it, unarmed
      for (var i = 0; i < 64 && g.menu.slot.offered != Powerup.bigHoops; i++) {
        g.menu.slot.rollForArrival();
      }
      expect(g.menu.slot.offered, Powerup.bigHoops);
      await g.menu.slot.armOffered();
      final r = await startRun(g);
      expect(r.setup.starter, Powerup.bigHoops);
      expect(r.setup.debugStarter, isFalse);
      expect(r.countsForAchievements, isTrue);
      await finish(g);
      expect(g.storage.achUnlocked, contains('first_big_hoops'));
      expect(g.achievements.lastRunCounted, isTrue);
    },
  );

  // --- P1E-02 god mode latches ------------------------------------------------

  t.testGameWidget(
    'P1E-02 god mode switched on and off mid-run excludes the whole run',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      expect(r.countsForAchievements, isTrue);
      final god = ForceMenu.actions(
        g,
      ).firstWhere((a) => a.label().startsWith('God mode:'));
      await god.run();
      expect(
        r.mistake(const Mistake(MistakeCause.spikes)),
        MistakeOutcome.ignored,
      );
      await god.run();
      expect(g.runDebug.god, isFalse);
      expect(r.countsForAchievements, isFalse);
      r.events.emit(const FeverIgnite('pair'));
      r.ctx.addScore(50);
      await finish(g);
      expectNothing(g);
    },
  );

  t.testGameWidget(
    'P1E-02 god mode set on the debug state for a single frame latches too',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      g.runDebug.god = true;
      stepGame(g, 1 / 60);
      g.runDebug.god = false;
      expect(r.countsForAchievements, isFalse);
      r.ctx.addScore(50);
      await finish(g);
      expectNothing(g);
    },
  );

  // --- P1E-03 no permanent unlock before the run is known to count -------------

  final lateDebug =
      <String, Future<void> Function(FlappySpikesGame, RunController)>{
        'debugPass()': (g, r) async => r.debugPass(),
        'force menu element': (g, r) async =>
            g.debugForceElement(ElementId.heart),
        'force menu ride': (g, r) async => g.debugForceRide(RideId.cannon),
        'force menu god mode': (g, r) async {
          final god = ForceMenu.actions(
            g,
          ).firstWhere((a) => a.label().startsWith('God mode:'));
          await god.run();
          await god.run();
        },
      };
  for (final MapEntry(key: name, value: act) in lateDebug.entries) {
    t.testGameWidget(
      'P1E-03 catch → $name → finish: no unlock, report, counter, '
      'analytics or toast survives',
      setUp: boot,
      verify: (g, _) async {
        final r = await startRun(g);
        r.events
          ..emit(const PickupCollected(ElementId.heart, null))
          ..emit(const RideEnded(RideKind.portal, RideId.space))
          ..emit(const FeverIgnite('pair'));
        await flushAndMount(g);
        // Staged: nothing is permanent while the run can still change.
        expect(g.storage.achUnlocked, isEmpty);
        expect(services.unlocks, isEmpty);
        await act(g, r);
        expect(r.countsForAchievements, isFalse);
        r.ctx.addScore(50);
        await finish(g);
        expectNothing(g);
        expect(g.storage.achRides, isEmpty);
      },
    );
  }

  t.testGameWidget(
    'P1E-03 a clean run commits its staged unlocks at the end, in order, '
    'reported and queued for the results page',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      r.events
        ..emit(const PickupCollected(ElementId.heart, null))
        ..emit(const FeverIgnite('pair'));
      r.ctx.addScore(10);
      await flushAndMount(g);
      expect(g.storage.achUnlocked, isEmpty);
      await finish(g);
      expect(g.achievements.lastRunCounted, isTrue);
      // PRD-2.3.1 §19: the catch counts (1 of the heart goal); the run
      // unlocks only its first earned achievement (FEVER), EGG waits.
      expect(g.storage.achItemCounts, {'item_heart': 1});
      expect(g.storage.achUnlocked, {'first_fever'});
      expect(g.storage.achPending, ['rank_egg']);
      expect(g.storage.achDayStreak, 1);
      expect(achEvents(), ['first_fever']);
      expect(services.unlocks, ['unlock:first_fever']);
      expect(g.storage.achReported, {'first_fever'});
      // Signed in: the platform shows its own popup, the game's toast stays
      // off (owner 2026-10-14).
      expect(g.achievements.toastQueue, isEmpty);
    },
  );

  t.testGameWidget(
    'P1E-03 the shop stays eligible after an excluded run',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      r.debugPass();
      await finish(g);
      expect(g.achievements.lastRunCounted, isFalse);
      g.achievements.onShopPurchase(owned: 1, total: kCollectibleTotal);
      await flushAndMount(g);
      expect(g.storage.achUnlocked, {'skin_first'});
      expect(services.unlocks, ['unlock:skin_first']);
    },
  );

  // --- QA P2-02 the armed starter's debug origin survives a restart ----------

  /// Lets unawaited storage writes finish (works in fake-async tests too).
  Future<void> microtasks() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.value();
    }
  }

  /// A fresh launch: storage and slot rebuilt from the persisted prefs.
  Future<PowerupSlot> relaunchSlot() async {
    final reloaded = GameStorage();
    await reloaded.load();
    return PowerupSlot(reloaded);
  }

  for (final p in [Powerup.bigHoops, Powerup.shield]) {
    test(
      'P2-02 a forced ${p.name} armed before a restart stays debug',
      () async {
        SharedPreferences.setMockInitialValues({});
        final s = GameStorage();
        await s.load();
        final slot = PowerupSlot(s)..debugForce = p;
        slot.rollForArrival();
        await slot.armOffered();
        final restarted = await relaunchSlot();
        expect(restarted.consume(), p);
        expect(restarted.takeConsumedDebug(), isTrue);
        // Consumed: both keys cleared on disk.
        await microtasks();
        final after = GameStorage();
        await after.load();
        expect(after.armedPowerup, 'none');
        expect(after.armedPowerupDebug, isFalse);
      },
    );
  }

  test('P2-02 a normal arm replaces a forced one (origin cleared)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GameStorage();
    await s.load();
    final slot = PowerupSlot(s)..debugForce = Powerup.shield;
    slot.rollForArrival();
    await slot.armOffered();
    slot.debugForce = null;
    slot.rollForArrival();
    await slot.armOffered();
    final restarted = await relaunchSlot();
    expect(restarted.consume(), isNot(Powerup.none));
    expect(restarted.takeConsumedDebug(), isFalse);
  });

  test('P2-02 the menu reset clears the armed origin', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GameStorage();
    await s.load();
    final slot = PowerupSlot(s)..debugForce = Powerup.bigHoops;
    slot.rollForArrival();
    await slot.armOffered();
    expect(s.armedPowerupDebug, isTrue);
    await s.resetMenuState();
    final reloaded = GameStorage();
    await reloaded.load();
    expect(reloaded.armedPowerup, 'none');
    expect(reloaded.armedPowerupDebug, isFalse);
  });

  FlameTester<FlappySpikesGame> withPrefs(Map<String, Object> prefs) =>
      FlameTester<FlappySpikesGame>(() {
        services = _Services()
          ..markInitialized()
          ..debugSetPlayer('p1');
        return createRunTestGame(prefs: prefs, services: services);
      }, gameSize: Vector2(320, 568));

  // A real launch clears a stale armed powerup (an app killed between arm
  // and START); its persisted debug origin goes with it and never leaks
  // into the next normally armed START.
  for (final p in [Powerup.bigHoops, Powerup.shield]) {
    withPrefs({
      'armedPowerup': p.name,
      'armedPowerupDebug': true,
    }).testGameWidget(
      'P2-02 a forced ${p.name} left armed at a relaunch is cleared with '
      'its origin; the next normal START counts',
      setUp: boot,
      verify: (g, _) async {
        expect(g.menu.slot.armed, Powerup.none);
        expect(g.storage.armedPowerupDebug, isFalse);
        final disk = GameStorage();
        await disk.load();
        expect(disk.armedPowerupDebug, isFalse);
        for (
          var i = 0;
          i < 64 && g.menu.slot.offered != Powerup.bigHoops;
          i++
        ) {
          g.menu.slot.rollForArrival();
        }
        await g.menu.slot.armOffered();
        final r = await startRun(g);
        expect(r.setup.starter, Powerup.bigHoops);
        expect(r.setup.debugStarter, isFalse);
        expect(r.countsForAchievements, isTrue);
        await finish(g);
        expect(g.storage.achUnlocked, contains('first_big_hoops'));
      },
    );
  }

  test(
    'P2-02 a normally armed starter keeps counting across a restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = GameStorage();
      await s.load();
      final slot = PowerupSlot(s);
      await slot.armOffered();
      final armed = slot.offered;
      final restarted = await relaunchSlot();
      expect(restarted.consume(), armed);
      expect(restarted.takeConsumedDebug(), isFalse);
    },
  );

  // --- QA P2-03 the provisional journal of an open run ------------------------

  /// The next launch's recovery: fresh storage and tracker from disk.
  Future<(GameStorage, _Services)> relaunchTracker() async {
    final storage = GameStorage();
    await storage.load();
    final next = _Services()
      ..markInitialized()
      ..debugSetPlayer('p1');
    final tracker = AchievementTracker(storage: storage, services: next);
    await tracker.recoverJournal();
    await microtasks();
    await tracker.syncAll();
    return (storage, next);
  }

  t.testGameWidget(
    'P2-03 a clean run killed after backgrounding keeps its catch and ride',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      expect(r.countsForAchievements, isTrue);
      r.events
        ..emit(const PickupCollected(ElementId.heart, null))
        ..emit(const RideEnded(RideKind.portal, RideId.space));
      g.lifecycleStateChange(AppLifecycleState.paused);
      await flushAndMount(g);
      // Nothing committed or reported early.
      expect(g.storage.achUnlocked, isEmpty);
      expect(services.unlocks, isEmpty);
      // The process dies here; the next launch commits the journal.
      // PRD-2.3.1 §19.2: what it earned goes into achPending (no unlock, no
      // report); the catch adds to the lifetime count.
      final (storage, next) = await relaunchTracker();
      expect(storage.achUnlocked, isEmpty);
      expect(storage.achPending, ['ride_space']);
      expect(storage.achRides, {'space'});
      expect(storage.achItemCounts, {'item_heart': 1});
      expect(next.unlocks, isEmpty);
      expect(storage.achJournal, isEmpty);
      // Committed once: a second launch adds nothing.
      final (again, _) = await relaunchTracker();
      expect(again.achPending, storage.achPending);
      expect(again.achItemCounts, storage.achItemCounts);
    },
  );

  t.testGameWidget(
    'P2-03 completed events are journaled as they happen (no pause needed)',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      r.events
        ..emit(const PickupCollected(ElementId.heart, null))
        ..emit(const Revived(ReviveKind.coins, 100));
      await flushAndMount(g);
      final (storage, _) = await relaunchTracker();
      expect(storage.achItemCounts, {'item_heart': 1});
      expect(storage.achPending, ['first_revive']); // §19.2 queued
      // An unfinished ride (no RideEnded) never counts.
      expect(storage.achRides, isEmpty);
    },
  );

  t.testGameWidget(
    'P2-03 a debug assist excludes the journal of the killed run',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      r.events.emit(const PickupCollected(ElementId.heart, null));
      await flushAndMount(g);
      r.debugPass();
      g.lifecycleStateChange(AppLifecycleState.paused);
      await flushAndMount(g);
      final (storage, next) = await relaunchTracker();
      expect(storage.achUnlocked, isEmpty);
      expect(storage.achItemCounts, isEmpty);
      expect(storage.achPending, isEmpty);
      expect(next.unlocks, isEmpty);
      expect(storage.achJournalExcluded, isFalse); // discarded
    },
  );

  t.testGameWidget(
    'P2-03 god mode switched on after a catch excludes the killed run',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      r.events.emit(const PickupCollected(ElementId.heart, null));
      await flushAndMount(g);
      final god = ForceMenu.actions(
        g,
      ).firstWhere((a) => a.label().startsWith('God mode'));
      await god.run();
      g.lifecycleStateChange(AppLifecycleState.paused);
      await flushAndMount(g);
      final (storage, _) = await relaunchTracker();
      expect(storage.achUnlocked, isEmpty);
      expect(storage.achItemCounts, isEmpty);
    },
  );

  t.testGameWidget(
    'P2-03 the run end clears the journal (no double commit)',
    setUp: boot,
    verify: (g, _) async {
      final r = await startRun(g);
      r.events
        ..emit(const PickupCollected(ElementId.heart, null))
        ..emit(const Revived(ReviveKind.coins, 100));
      g.lifecycleStateChange(AppLifecycleState.paused);
      g.lifecycleStateChange(AppLifecycleState.resumed);
      g.resume();
      await finish(g);
      expect(g.storage.achUnlocked, contains('first_revive'));
      expect(g.storage.achItemCounts, {'item_heart': 1});
      expect(g.storage.achJournal, isEmpty);
      final (storage, next) = await relaunchTracker();
      expect(storage.achJournal, isEmpty);
      expect(storage.achItemCounts, {'item_heart': 1}); // counted once
      expect(next.events.where((e) => e.$1 == 'achievement_unlocked'), isEmpty);
    },
  );

  withPrefs({
    'achJournal': ['item:item_heart', 'ride:space', 'hoops:12'],
  }).testGameWidget(
    'P2-03 the launch commits a clean journal (PRD-2.3.1 §19.2: into the '
    'pending queue, reported only once a run end unlocks it)',
    setUp: boot,
    verify: (g, _) async {
      await flushAndMount(g);
      expect(g.storage.achUnlocked, isEmpty);
      expect(g.storage.achPending, ['ride_space', 'hoops_10']);
      expect(g.storage.achItemCounts, {'item_heart': 1});
      expect(g.storage.achJournal, isEmpty);
      expect(services.unlocks, isEmpty);
      expect(g.achievements.toastQueue, isEmpty);
    },
  );

  withPrefs({
    'achJournal': ['item:item_heart'],
    'achJournalExcluded': true,
  }).testGameWidget(
    'P2-03 the launch discards an excluded journal',
    setUp: boot,
    verify: (g, _) async {
      await flushAndMount(g);
      expect(g.storage.achUnlocked, isEmpty);
      expect(g.storage.achJournal, isEmpty);
      expect(g.storage.achJournalExcluded, isFalse);
      expect(services.unlocks, isEmpty);
    },
  );
}
