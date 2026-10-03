import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';

/// Full-screen tap target sitting below everything else. Receives taps that
/// no button consumed: flaps while playing; ignored on the menus (only the
/// START button starts a run, PRD-1 §4.2) and on the game-over scene.
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
    game.onPlayfieldTap();
  }
}
