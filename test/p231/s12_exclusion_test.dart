// PRD-2.3.1 §12.2 / §12.9 "runs with any debug or test start never unlock
// achievements": the regression tests of QA findings P1E-01 (a debug-forced
// slot starter), P1E-02 (god mode latches the exclusion) and P1E-03 (a run
// never grants permanent unlocks and then turns into a debug run: its rules
// stay staged until it ends). Every run here is strict
// (`countDebugRuns = false`, `ignoreGates = false`), signed in on a fake.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/debug/force_menu.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(
        g.storage.achUnlocked,
        containsAll(['item_heart', 'first_fever', 'rank_egg']),
      );
      expect(g.storage.achItems, {'item_heart'});
      expect(g.storage.achDayStreak, 1);
      expect(
        achEvents(),
        containsAll(['item_heart', 'first_fever', 'rank_egg']),
      );
      expect(services.unlocks, contains('unlock:item_heart'));
      expect(g.storage.achReported, contains('item_heart'));
      expect(g.achievements.toastQueue.take(2), [
        AchievementId.itemHeart,
        AchievementId.firstFever,
      ]);
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
}
