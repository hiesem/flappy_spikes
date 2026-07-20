import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';

/// Full-screen tap target sitting below everything else. Receives taps that
/// no button consumed: starts the game from the start scene, flaps while
/// playing, ignored on the game-over scene.
class TapCatcher extends PositionComponent with TapCallbacks, HasGameReference<FlappySpikesGame> {
  TapCatcher()
      : super(
          position: Vector2.zero(),
          size: Vector2(Config.worldWidth, Config.worldHeight),
          priority: -1000,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size.y = game.viewHeight;
  }

  @override
  void onTapDown(TapDownEvent event) {
    game.onScreenTap();
  }
}
