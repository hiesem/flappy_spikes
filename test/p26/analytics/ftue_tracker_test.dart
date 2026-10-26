import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/services/ftue_tracker.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every FTUE step fires once and survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final spy = AnalyticsSpy();
    final storage = GameStorage();
    await storage.load();
    final tracker = PersistedFtueTracker(
      services: spy,
      storage: storage,
      secondsSinceInstall: () => 123,
    );

    for (final name in FtueStep.bits.keys) {
      tracker.step(name, gamesPlayed: 1);
      tracker.step(name, gamesPlayed: 2);
    }
    await Future<void>.delayed(Duration.zero);

    expect(spy.events, hasLength(FtueStep.bits.length));
    expect(
      spy.events.map((event) => event.$2!['name']),
      FtueStep.bits.keys.toList(),
    );
    expect(
      spy.events.every((event) => event.$2!['s_since_install'] == 123),
      isTrue,
    );
    expect(storage.ftueSteps, (1 << FtueStep.bits.length) - 1);

    final restartedStorage = GameStorage();
    await restartedStorage.load();
    final restartedTracker = PersistedFtueTracker(
      services: spy,
      storage: restartedStorage,
      secondsSinceInstall: () => 456,
    );
    for (final name in FtueStep.bits.keys) {
      restartedTracker.step(name, gamesPlayed: 3);
    }

    expect(spy.events, hasLength(FtueStep.bits.length));
    expect(restartedStorage.ftueSteps, storage.ftueSteps);
  });

  test('the new names and parameter counts follow the WP-A limits', () {
    final snakeCase = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');
    const names = {
      'ftue_step': ['name', 's_since_install'],
      'highlight_seen': ['id', 'scripted', 'run_no', 'hoop'],
      'first_meet': ['element', 'hoop', 'games', 'forced', 'survived'],
    };

    for (final entry in names.entries) {
      expect(entry.key.length, lessThanOrEqualTo(40));
      expect(entry.key, matches(snakeCase));
      expect(entry.value, hasLength(lessThanOrEqualTo(25)));
    }
  });

  test(
    's_since_install uses wall-clock time across background and restarts',
    () async {
      var now = DateTime(2026, 10, 23, 23, 58, 30);
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage(clock: () => now);
      await storage.load();
      final firstInstallAt = storage.installAtMs;
      final spy = AnalyticsSpy();
      final tracker = PersistedFtueTracker(services: spy, storage: storage);

      now = now.add(const Duration(seconds: 30));
      tracker.step(FtueStep.firstTap, gamesPlayed: 0);
      expect(spy.events.single.$2!['s_since_install'], 30);
      now = now.add(const Duration(minutes: 2));
      tracker.step(FtueStep.run1End, gamesPlayed: 1);
      expect(spy.events.last.$2!['s_since_install'], 150);

      final restarted = GameStorage(clock: () => now);
      await restarted.load();
      expect(restarted.installAtMs, firstInstallAt);
      now = now.add(const Duration(hours: 1, seconds: 7));
      final restartedSpy = AnalyticsSpy();
      final restartedTracker = PersistedFtueTracker(
        services: restartedSpy,
        storage: restarted,
      );
      restartedTracker.step(FtueStep.run2End, gamesPlayed: 2);
      expect(restartedSpy.events.single.$1, 'ftue_step');
      expect(restartedSpy.events.single.$2, {
        'name': FtueStep.run2End,
        's_since_install': 3757,
      });
      expect(storage.installAtMs, firstInstallAt);
      expect(restarted.installAtMs, firstInstallAt);

      expect(
        storage.installAtMs,
        isNot(DateTime(2026, 10, 23).millisecondsSinceEpoch),
      );
    },
  );

  test('existing installs migrate from the first-launch day', () async {
    final installDay = DateTime.utc(
      2026,
      10,
      20,
    ).difference(DateTime.utc(1970)).inDays;
    SharedPreferences.setMockInitialValues({'installDay': installDay});
    final storage = GameStorage(clock: () => DateTime(2026, 10, 24, 12));
    await storage.load();
    final tracker = PersistedFtueTracker(
      services: AnalyticsSpy(),
      storage: storage,
    );
    tracker.step(FtueStep.firstTap, gamesPlayed: 3);

    expect(storage.installAtMs, DateTime(2026, 10, 20).millisecondsSinceEpoch);
  });

  test('a queued first meet is sent once after a process restart', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    final spy = AnalyticsSpy();
    final tracker = PersistedFtueTracker(services: spy, storage: storage);
    tracker.firstMeetEncountered(
      ElementId.saw,
      hoop: 12,
      games: 3,
      forced: true,
    );
    await Future<void>.delayed(Duration.zero);

    final restartedStorage = GameStorage();
    await restartedStorage.load();
    expect(restartedStorage.pendingFirstMeets, hasLength(1));
    final restartedTracker = PersistedFtueTracker(
      services: spy,
      storage: restartedStorage,
    );
    await restartedTracker.flushPendingFirstMeets();
    await restartedTracker.flushPendingFirstMeets();

    expect(spy.events.where((event) => event.$1 == 'first_meet').single.$2, {
      'element': 'saw',
      'hoop': 12,
      'games': 3,
      'forced': true,
      'survived': false,
    });
    expect(restartedStorage.pendingFirstMeets, isEmpty);
  });

  test('the default service user-property call is a safe no-op', () {
    GameServices().setUserProperty('fs_level', '1');
  });
}
