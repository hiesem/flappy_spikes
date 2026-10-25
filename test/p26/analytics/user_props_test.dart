import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class PropertySpy extends GameServices {
  final List<(String, String?)> properties = [];

  @override
  void setUserProperty(String name, String? value) =>
      properties.add((name, value));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final spy = PropertySpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      services: spy,
      prefs: {'gamesPlayed': 3, 'bestHoops': 12},
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'the router sets the five WP-A properties at run end',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      game.storage.playerLevel = 2;
      game.storage.showcaseDoneAt = 4;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.hoopsPassed = 7;
      run.endRun();

      expect(spy.properties, [
        ('fs_level', '2'),
        ('fs_gb', '4-5'),
        ('fs_best_hb', '10-14'),
        ('fs_showcase', '1'),
        ('fs_arm', '0'),
      ]);
      for (final (name, _) in spy.properties) {
        expect(name.length, lessThanOrEqualTo(24), reason: name);
      }
      expect(game.storage.bestHoops, 12);
    },
  );

  final worseSpy = PropertySpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      services: worseSpy,
      prefs: {'gamesPlayed': 3, 'bestHoops': 17},
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'fs_best_hb stays at the lifetime best after a worse run',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.hoopsPassed = 13;
      run.endRun();

      expect(
        worseSpy.properties
            .singleWhere((property) => property.$1 == 'fs_best_hb')
            .$2,
        '15-19',
      );
      expect(game.storage.bestHoops, 17);
    },
  );

  final restartSpy = PropertySpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      services: restartSpy,
      prefs: {'gamesPlayed': 3, 'bestHoops': 12},
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'fs_best_hb stays at the lifetime best after a restart',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, tester) async {
      game.achievements.countDebugRuns = true;
      final run = await startRun(game);
      run.state.hoopsPassed = 17;
      run.endRun();
      await flushAndMount(game);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('bestHoops'), 17);

      // A fresh game and storage, with the same persisted preferences.
      final freshSpy = PropertySpy();
      final fresh = FlappySpikesGame(
        worldHeight: 711,
        services: freshSpy,
        soundEnabled: false,
      )..runSeed = 7;
      fresh.onGameResize(Vector2(320, 711));
      await tester.pumpWidget(GameWidget(game: fresh));
      await tester.runAsync(() async {
        await fresh.ready();
        await preloadImages(fresh);
      });
      expect(fresh.storage.bestHoops, 17);
      final worse = await startRun(fresh);
      worse.state.hoopsPassed = 12;
      worse.endRun();
      expect(
        freshSpy.properties
            .singleWhere((property) => property.$1 == 'fs_best_hb')
            .$2,
        '15-19',
      );
      fresh.onRemove();
    },
  );

  final newBestSpy = PropertySpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      services: newBestSpy,
      prefs: {'gamesPlayed': 3, 'bestHoops': 12},
    ),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'fs_best_hb includes the current run when it is a new best',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      game.achievements.countDebugRuns = true;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.hoopsPassed = 17;
      run.endRun();

      expect(
        newBestSpy.properties
            .singleWhere((property) => property.$1 == 'fs_best_hb')
            .$2,
        '15-19',
      );
      expect(game.storage.bestHoops, 17);
    },
  );
}
