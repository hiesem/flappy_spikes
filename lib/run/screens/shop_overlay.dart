import 'dart:ui';

import 'package:flame/components.dart';

import 'package:flame/effects.dart';
import '../../game/flappy_game.dart';
import '../config/run_config.dart';

/// World priority of the in-run menu overlay's backdrop: over the frozen
/// run and the revive dim (17), under the menu chrome (corner box 19,
/// screens 20, coin pill 21).
const int kRunMenuBackdropPriority = 18;

/// The opaque stage-background sheet under a menu screen opened over a
/// paused run (PRD-2 §3.14 GET COINS → the Shop as an overlay on the paused
/// game, countdown paused, music × 0.5; §5.7 pause → settings). The game
/// puts the reused [ShopScreen] / [SettingsPanel] and its chrome on top, so
/// they look exactly as in the menus; closing the overlay returns to the
/// screen below with the run untouched.
class RunMenuBackdrop extends PositionComponent
    with HasGameReference<FlappySpikesGame>
    implements OpacityProvider {
  RunMenuBackdrop() : super(priority: kRunMenuBackdropPriority);

  double _opacity = 0;

  @override
  double get opacity => _opacity;

  @override
  set opacity(double v) => _opacity = v.clamp(0.0, 1.0);

  final Paint _p = Paint();

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    _p.color = game.stageBackground.withValues(alpha: _opacity);
    canvas.drawRect(
      Rect.fromLTWH(-40, -40, RunConfig.worldWidth + 80, game.viewHeight + 80),
      _p,
    );
  }
}
