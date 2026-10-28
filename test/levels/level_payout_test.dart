// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flappy_spikes/game/save_seal.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import '../p26/showcase/bot_highlights_test.dart' show FixedShowcase;
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/level_progress.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

class _FailLevelWrite extends InMemorySharedPreferencesStore {
  _FailLevelWrite(super.data) : super.withData();
  bool failed = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.lvlPending') {
      failed = true;
      throw StateError('simulated level write failure');
    }
    return super.setValue(valueType, key, value);
  }
}

class _Killed implements Exception {}

class _KillStorage extends GameStorage {
  String? kill;
  void after(String stage) {
    if (kill == stage) throw _Killed();
  }

  @override
  Future<void> saveLevelStep({
    required int index,
    required int points,
    required List<Map<String, Object?>> pending,
  }) async {
    if (kill == 'rolled') {
      // Disk image of a kill after the first write of the level-step transaction.
      await saveLvlPending(pending);
      return;
    }
    await super.saveLevelStep(index: index, points: points, pending: pending);
  }

  @override
  Future<void> saveLvlPayout(int value) async {
    await super.saveLvlPayout(value);
    after(value == 0 ? 'settled' : 'target');
  }

  @override
  Future<void> saveOwnedItems(Set<String> value) async {
    await super.saveOwnedItems(value);
    after('item');
  }

  @override
  Future<void> saveCoins(int value) async {
    await super.saveCoins(value);
    after('coins');
  }

  @override
  Future<void> saveLvlPending(List<Map<String, Object?>> value) async {
    await super.saveLvlPending(value);
    after(value.isEmpty ? 'cleared' : 'rolled');
  }
}

class _Events extends GameServices {
  final events = <(String, Map<String, Object>?)>[];
  final properties = <String, String?>{};
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));
  @override
  void setUserProperty(String name, String? value) => properties[name] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'J5 a sealed step and reward payout reload without a seal alarm',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sealer = MemorySaveSealer();
      final storage = GameStorage(sealer: sealer);
      await storage.load();
      await storage.sealVerified;
      final menu = MenuState(storage, random: Random(7));
      await menu.levels.recordRun(25);
      final reader = GameStorage(sealer: sealer);
      await reader.load();
      await reader.sealVerified;
      expect(reader.sealUntrusted, isFalse);
      expect(reader.lvlIndex, 1);
      expect(reader.lvlPending, hasLength(1));
      await MenuState(reader).levels.payPending();
      final paid = GameStorage(sealer: sealer);
      await paid.load();
      await paid.sealVerified;
      expect(paid.sealUntrusted, isFalse);
      expect(paid.coins, 50);
      expect(paid.lvlPending, isEmpty);
      expect(paid.ownedItems, hasLength(1));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame()..runDebug.ignoreGates = false,
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'J2 failed level write still opens results',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final run = await startRun(g);
      run.ctx.addScore(25);
      final prefs = await SharedPreferences.getInstance();
      final original = SharedPreferencesStorePlatform.instance;
      final failing = _FailLevelWrite({
        for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
      });
      SharedPreferencesStorePlatform.instance = failing;
      try {
        g.endRun(null);
        for (var i = 0; i < 30 && g.resultsScreen == null; i++) {
          await flushAndMount(g);
        }
        expect(g.state, GameState.results);
        expect(g.resultsScreen, isNotNull);
        expect(failing.failed, isTrue);
      } finally {
        SharedPreferencesStorePlatform.instance = original;
      }
    },
  );

  for (final stage in [
    'before',
    'target',
    'item',
    'coins',
    'cleared',
    'settled',
  ]) {
    test(
      'J12 kill $stage payout: one credit, item owned, never equipped',
      () async {
        SharedPreferences.setMockInitialValues({'coins': 10});
        final storage = _KillStorage();
        await storage.load();
        final menu = MenuState(storage, random: Random(7));
        final look = menu.items.look;
        await menu.levels.recordRun(100);
        final row = menu.levels.pending.single;
        final item = allItems.singleWhere((item) => item.key == row['item']);
        final reward = (row['coins'] as int) + (row['extraCoins'] as int);
        expect(row.containsKey('star'), isFalse);
        expect(storage.lvlIndex, 1);
        expect(storage.lvlPoints, 0);
        expect(menu.items.isOwned(item.layer, item.id), isFalse);
        storage.kill = stage;
        if (stage != 'before') {
          await expectLater(menu.levels.payPending(), throwsA(isA<_Killed>()));
        }
        final reader = GameStorage();
        await reader.load();
        final resumed = MenuState(reader, random: Random(999));
        await resumed.levels.payPending();
        expect(resumed.wallet.balance, 10 + reward);
        expect(resumed.items.isOwned(item.layer, item.id), isTrue);
        expect(resumed.items.look, look);
        expect(resumed.levels.pending, isEmpty);
        expect(reader.lvlPayout, 0);
        expect(await resumed.levels.payPending(), 0);
        expect(resumed.wallet.balance, 10 + reward);
      },
    );
  }

  test('J10 claim event precedes clearing the durable pending reward', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = _KillStorage();
    await storage.load();
    final events = _Events();
    final menu = MenuState(storage, random: Random(7));
    menu.levels.services = events;
    await menu.levels.recordRun(25);
    storage.kill = 'cleared';
    await expectLater(menu.levels.payPending(), throwsA(isA<_Killed>()));
    expect(events.events.where((e) => e.$1 == 'level_reward_claimed'), hasLength(1));
    expect(storage.lvlPending, isEmpty);
    final reader = GameStorage();
    await reader.load();
    await MenuState(reader).levels.payPending();
    expect(reader.coins, 50);
    expect(reader.lvlPayout, 0);
  });

  test('J12 kill after durable roll recovers index without reroll', () async {
    SharedPreferences.setMockInitialValues({'lvlPoints': 24});
    final storage = _KillStorage();
    await storage.load();
    storage.kill = 'rolled';
    final levels = LevelProgress(storage, Wallet(storage), random: Random(7));
    await expectLater(levels.recordRun(1), throwsA(isA<_Killed>()));
    final rolled = levels.pending.single;
    final reader = GameStorage();
    await reader.load();
    expect(reader.lvlIndex, 1);
    expect(reader.lvlPoints, 0);
    expect(reader.lvlPending.single, rolled);
  });

  test(
    'J12 multiple pending rolls exclude each other; concurrent payout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final events = _Events();
      final menu = MenuState(storage, random: Random(9));
      menu.levels.services = events;
      await menu.levels.recordRun(100);
      await menu.levels.recordRun(100);
      final rows = menu.levels.pending;
      expect(rows.map((row) => row['item']).toSet(), hasLength(2));
      final paid = await Future.wait([
        menu.levels.payPending(),
        menu.levels.payPending(),
      ]);
      expect(paid..sort(), [0, 100]);
      expect(menu.wallet.balance, 100);
      expect(storage.ownedItems, containsAll(rows.map((row) => row['item'])));
      final ups = events.events
          .where((event) => event.$1 == 'level_up')
          .toList();
      expect(ups, hasLength(2));
      expect(ups.first.$2!.keys.toSet(), {
        'level',
        'games',
        'run_score',
        's_since_install',
      });
      final claims = events.events
          .where((event) => event.$1 == 'level_reward_claimed')
          .toList();
      expect(claims, hasLength(2));
      expect(claims.first.$2!.keys.toSet(), {
        'level',
        'coins',
        'item_layer',
        'rarity',
        'fallback',
      });
      expect(events.properties['fs_level'], '2');
    },
  );

  for (final eligible in [false, true]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame()..runDebug.ignoreGates = !eligible,
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      'J3 endRun eligibility $eligible',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final run = await startRun(g);
        run.ctx.addScore(30);
        expect(run.countsForUpload, eligible);
        g.endRun(null);
        await flushAndMount(g);
        expect(g.menu.levels.level, eligible ? 1 : 0);
        expect(g.menu.levels.points, 0);
        expect(g.menu.levels.pending.length, eligible ? 1 : 0);
      },
    );
  }
  for (final versus in [false, true]) {
    for (final revive in ['none', 'free', 'ad', 'coins']) {
      final service = FakeVersusService(
        pool: [
          if (versus)
            OpponentRun(
              uid: 'rival',
              name: 'Rival',
              score: 20,
              best: 20,
              level: 2,
              timeline: RunTimeline()..end(10),
              runId: 'r',
            ),
        ],
      );
      final events = _Events();
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({
          'lvlIndex': 2,
          'lvlPoints': 13,
        });
        return FlappySpikesGame(
          soundEnabled: false,
          services: events,
          versus: service,
          showcasePlan: FixedShowcase(ShowcaseScript.planFor(0, 1)),
        );
      }, gameSize: Vector2(320, 568)).testGameWidget(
        'J3 showcase versus=$versus revive=$revive earns points',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, _) async {
          if (!versus) await g.storage.saveHomeMode(HomeMode.freeFly);
          final run = await startRun(g);
          expect(run.setup.opponent != null, versus);
          expect(run.setup.showcase, isNotNull);
          if (revive != 'none') {
            if (revive == 'free') {
              ReviveLadder.record(run.state, const ReviveOffer.free());
            }
            run.revive(revive == 'ad' ? ReviveKind.ad : ReviveKind.coins);
          }
          run.ctx.addScore(10);
          expect(run.countsForUpload, isTrue);
          final summary = run.endRun();
          g.endRun(summary);
          await flushAndMount(g);
          expect(g.menu.levels.level, 2);
          expect(g.menu.levels.points, 23);
          final end = events.events.singleWhere((e) => e.$1 == 'run_end').$2!;
          expect(end['level'], 2);
          expect(end['lvl_pts_before'], 13);
        },
      );
    }
  }
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame()..runDebug.ignoreGates = false,
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'J3 killed run never persists points',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final run = await startRun(g);
      run.ctx.addScore(100);
      final reader = GameStorage();
      await reader.load();
      expect(reader.lvlIndex, 0);
      expect(reader.lvlPoints, 0);
      expect(reader.lvlPending, isEmpty);
    },
  );
}
