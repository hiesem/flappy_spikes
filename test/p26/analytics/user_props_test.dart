import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      prefs: {'gamesPlayed': 3},
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
        ('fs_best_hb', '05-09'),
        ('fs_showcase', '1'),
        ('fs_arm', '0'),
      ]);
      for (final (name, _) in spy.properties) {
        expect(name.length, lessThanOrEqualTo(24), reason: name);
      }
    },
  );
}
