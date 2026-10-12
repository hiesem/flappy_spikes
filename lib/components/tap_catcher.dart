import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/playfield.dart';

/// Full-screen tap target sitting below everything else. Receives taps that
/// no button consumed: flaps while playing; ignored on the menus (only the
/// START button starts a run, PRD-1 §4.2) and on the game-over scene.
class TapCatcher extends PositionComponent
    with TapCallbacks, HasGameReference<FlappySpikesGame>
    implements PlayfieldResizable {
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
    game.registerResizable(this);
  }

  @override
  void onRemove() {
    game.unregisterResizable(this);
    super.onRemove();
  }

  /// PRD-2.2 §7.5.2: covers the whole playfield at every height.
  @override
  void onPlayfieldResize(double viewHeight) => size.y = viewHeight;

  @override
  void onTapDown(TapDownEvent event) {
    game.onPlayfieldTap();
  }
}
