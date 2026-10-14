// PRD-2.3.1 §12.4 / §12.9 platform reporting through the GameServices seams:
// no plugin call while signed out, syncAll on sign-in reports exactly the
// unreported keys, an account switch re-reports everything, a timeout /
// error logs pgs_error and leaves the key unreported, iOS progress only on
// iOS, and showAchievements' busy guard and results.
import 'dart:async';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/achievements/achievements.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every plugin call instead of making it.
class FakeGameServices extends GameServices {
  final List<String> calls = [];
  final List<(String, Map<String, Object>?)> events = [];
  Object? unlockError;
  Completer<void>? hang;
  bool signInFails = false;
  bool showFails = false;
  Completer<void>? showGate;

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));

  @override
  Future<void> unlockAchievementPlugin(AchievementId id) async {
    calls.add('unlock:${id.key}');
    final h = hang;
    if (h != null) await h.future;
    final e = unlockError;
    if (e != null) throw e;
  }

  @override
  Future<void> setAchievementProgressPlugin(
    AchievementId id,
    double percent,
  ) async {
    calls.add('progress:${id.key}:${percent.toStringAsFixed(1)}');
  }

  @override
  Future<void> signInPlugin() async {
    calls.add('signIn');
    if (signInFails) {
      throw PlatformException(code: 'failed_to_authenticate');
    }
  }

  @override
  Future<void> showAchievementsPlugin() async {
    calls.add('show');
    if (showFails) throw PlatformException(code: 'not_authenticated');
    final g = showGate;
    if (g != null) await g.future;
  }

  List<String> get unlocks =>
      calls.where((c) => c.startsWith('unlock:')).toList();
}

void main() {
  late GameStorage storage;
  late FakeGameServices services;
  late AchievementTracker tracker;

  Future<void> setUpWith([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    storage = GameStorage();
    await storage.load();
    services = FakeGameServices()
      ..markInitialized()
      ..isIOSPlatform = (() => true)
      ..pluginTimeout = const Duration(milliseconds: 50);
    tracker = AchievementTracker(storage: storage, services: services);
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('§12.9 no plugin call while signed out; unlocks stay local', () async {
    await setUpWith();
    tracker.unlock(AchievementId.rankEgg);
    tracker.onVersusWin();
    await settle();
    expect(services.calls, isEmpty);
    // PRD-2.3.1 §19.2: a run rule (the versus win) waits in achPending.
    expect(storage.achUnlocked, {'rank_egg'});
    expect(storage.achPending, ['vs_1']);
    expect(storage.achReported, isEmpty);
    // Never signs in for an unlock.
    expect(services.calls.contains('signIn'), isFalse);
  });

  test(
    '§12.9 syncAll on sign-in reports exactly the unreported keys',
    () async {
      await setUpWith({
        'achUnlocked': ['rank_egg', 'hoops_10', 'first_revive'],
        'achReported': ['rank_egg'],
        'achReportedPlayer': 'p1',
      });
      services.debugSetPlayer('p1');
      await settle();
      expect(services.unlocks..sort(), [
        'unlock:first_revive',
        'unlock:hoops_10',
      ]);
      expect(storage.achReported, {'rank_egg', 'hoops_10', 'first_revive'});
      // Signed in: a new unlock is reported at once.
      services.calls.clear();
      tracker.unlock(AchievementId.firstBigHoops);
      await settle();
      expect(services.unlocks, ['unlock:first_big_hoops']);
      // A second sync has nothing left.
      services.calls.clear();
      await tracker.syncAll();
      expect(services.calls, isEmpty);
    },
  );

  test('§12.9 an account switch re-reports everything', () async {
    await setUpWith({
      'achUnlocked': ['rank_egg', 'hoops_10'],
      'achReported': ['rank_egg', 'hoops_10'],
      'achReportedPlayer': 'p1',
    });
    services.debugSetPlayer('p2');
    await settle();
    expect(services.unlocks..sort(), ['unlock:hoops_10', 'unlock:rank_egg']);
    expect(storage.achReportedPlayer, 'p2');
    expect(storage.achReported, {'rank_egg', 'hoops_10'});
  });

  test('§12.9 a timeout or an error logs pgs_error and leaves the key '
      'unreported', () async {
    await setUpWith({
      'achUnlocked': ['rank_egg'],
    });
    services.unlockError = PlatformException(
      code: 'not_authenticated',
      message: 'nope',
    );
    services.debugSetPlayer('p1');
    await settle();
    expect(storage.achReported, isEmpty);
    expect(services.events.where((e) => e.$1 == 'pgs_error').single.$2, {
      'op': 'unlock_achievement',
      'code': 'not_authenticated',
      'message': 'nope',
    });
    services
      ..unlockError = null
      ..hang = Completer<void>();
    services.events.clear();
    await tracker.syncAll();
    expect(storage.achReported, isEmpty);
    expect(services.events.where((e) => e.$1 == 'pgs_error').single.$2, {
      'op': 'unlock_achievement',
      'code': 'timeout',
      'message': '',
    });
    services.hang = null;
    await tracker.syncAll();
    expect(storage.achReported, {'rank_egg'});
  });

  test('§12.4 Android: a key without an Android id is skipped (no plugin '
      'call), with an id it is reported', () async {
    await setUpWith({
      'achUnlocked': ['rank_egg'],
    });
    services.isIOSPlatform = () => false;
    services.debugSetPlayer('p1');
    await settle();
    final id = AchievementId.rankEgg;
    if (id.androidId.isEmpty) {
      expect(services.calls, isEmpty);
      expect(storage.achReported, isEmpty);
    } else {
      expect(services.unlocks, ['unlock:rank_egg']);
      expect(storage.achReported, {'rank_egg'});
    }
  });

  test(
    '§12.9 iOS progress only when the iOS seam is on, never on Android',
    () async {
      await setUpWith();
      services.debugSetPlayer('p1');
      await settle();
      services.calls.clear();
      services.isIOSPlatform = () => false;
      tracker.onVersusWin();
      tracker.onRideFinished(RideId.values.first);
      await settle();
      expect(services.calls.where((c) => c.startsWith('progress:')), isEmpty);
      services.isIOSPlatform = () => true;
      services.calls.clear();
      tracker.onVersusWin(); // 2 of 10, 2 of 50
      tracker.onShopPurchase(owned: 74, total: 148);
      await settle();
      final progress = services.calls
          .where((c) => c.startsWith('progress:'))
          .toList();
      expect(
        progress,
        containsAll([
          'progress:vs_10:20.0',
          'progress:vs_50:4.0',
          'progress:skin_all:50.0',
        ]),
      );
      // Never 100 through progress (the unlock reports that); capped at 99.
      services.calls.clear();
      for (var i = 0; i < 7; i++) {
        tracker.onVersusWin();
      } // 9 of 10
      await settle();
      expect(services.calls, contains('progress:vs_10:90.0'));
    },
  );

  test('§12.9 showAchievements: unavailable, busy guard, sign-in and '
      'failure results', () async {
    await setUpWith();
    expect(
      await GameServices().showAchievements(),
      ShowAchievementsResult.unavailable,
    );
    // Signed out: an interactive sign-in first, then the list.
    expect(await services.showAchievements(), ShowAchievementsResult.opened);
    expect(services.calls, ['signIn', 'show']);
    // Busy while one is in flight.
    services.showGate = Completer<void>();
    final first = services.showAchievements();
    expect(await services.showAchievements(), ShowAchievementsResult.busy);
    services.showGate!.complete();
    expect(await first, ShowAchievementsResult.opened);
    // Sign-in failure.
    final s2 = FakeGameServices()
      ..markInitialized()
      ..signInFails = true;
    expect(await s2.showAchievements(), ShowAchievementsResult.signInFailed);
    expect(s2.events.single.$2!['op'], 'sign_in');
    // The list fails to open.
    services.showFails = true;
    expect(await services.showAchievements(), ShowAchievementsResult.failed);
    expect(services.events.last.$2!['op'], 'show_achievements');
  });
}
