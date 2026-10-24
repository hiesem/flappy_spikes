import 'package:flappy_spikes/game/storage.dart';
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

  test('the default service user-property call is a safe no-op', () {
    GameServices().setUserProperty('fs_level', '1');
  });
}
