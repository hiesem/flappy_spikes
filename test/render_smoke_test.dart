import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  // The game must render headless at any aspect ratio: the virtual
  // resolution (320 wide, viewHeight tall — the 568 default in tests)
  // scales uniformly and letterboxes if the widget aspect differs.
  for (final size in [
    Vector2(Config.worldWidth, Config.worldHeight), // native canvas
    Vector2(1080, 1920), // tall phone
    Vector2(768, 1024), // tablet-ish, wider aspect
  ]) {
    FlameTester<FlappySpikesGame>(
      createTestGame,
      gameSize: size,
    ).testGameWidget(
      'renders without errors at ${size.x.toInt()}x${size.y.toInt()}',
      setUp: (game, tester) async {
        await game.ready();
        game.sound.enabled = false;
        game.onScreenTap(); // start -> playing
      },
      verify: (game, tester) async {
        stepGame(game, 0.5, flapBelow: 320);
        // Pump real frames through the widget tree (this is what throws if
        // rendering is broken at this size).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(game.state, GameState.playing);
      },
    );
  }
}
