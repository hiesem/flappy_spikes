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

  /// Pointer ids whose pointer-down fell on a waiting run (PRD-2.3 §10.1):
  /// they start it on tap-up, not on pointer-down.
  final Set<int> _pendingFirstTaps = {};

  @override
  void onTapDown(TapDownEvent event) {
    // S8-14 (PRD-2.3 §10.1 / PRD-2.2 §8): an Android back edge swipe first
    // delivers a pointer-down, then the OS cancels the pointer. The first
    // tap of a waiting run can't be undone, so it waits for a confirmed tap
    // (tap-up); a cancelled pointer (back gesture, a drag past the touch
    // slop) leaves the run waiting. Mid-run flaps stay on pointer-down: no
    // added latency.
    if (game.runWaitingForFirstTap) {
      _pendingFirstTaps.add(event.pointerId);
      return;
    }
    game.onPlayfieldTap();
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_pendingFirstTaps.remove(event.pointerId)) game.onPlayfieldTap();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pendingFirstTaps.remove(event.pointerId);
  }
}
