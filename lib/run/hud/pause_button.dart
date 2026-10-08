import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../game/flappy_game.dart';
import '../config/hud_config.dart';
import 'run_hud.dart';

/// §5.7 the pause button: 38 × 38 pink box, right edge 306 (the gear /
/// back buttons' spot), two soft-pink bars. The tap target is at least
/// 48 pt. Tapping pauses the run ([FlappySpikesGame.pause]).
class PauseButton extends PositionComponent with TapCallbacks {
  PauseButton(this.hud)
    : super(
        position: Vector2(
          HudConfig.pauseRight - HudConfig.rowHeight,
          HudConfig.rowTop,
        ),
        size: Vector2.all(HudConfig.rowHeight),
      );

  final RunHud hud;

  bool get _live => hud.rowOpacity > .5 && hud.game.state == GameState.playing;

  @override
  bool containsLocalPoint(Vector2 point) {
    if (!_live) return false;
    final pad = (HudConfig.minTarget - HudConfig.rowHeight) / 2;
    return point.x >= -pad &&
        point.y >= -pad &&
        point.x <= size.x + pad &&
        point.y <= size.y + pad;
  }

  @override
  void onTapDown(TapDownEvent event) => hud.game.pause();

  final Paint _box = Paint();
  final Paint _bar = Paint();

  @override
  void render(Canvas canvas) {
    final a = hud.rowOpacity;
    if (a <= 0) return;
    _box.color = HudConfig.pink.withValues(alpha: a);
    canvas.drawRect(size.toRect(), _box);
    // The 24-unit glyph `rect 5,3 5×18` + `rect 14,3 5×18` in a 20 pt box.
    final k = HudConfig.pauseIcon / 24;
    final o = (size.x - HudConfig.pauseIcon) / 2;
    _bar.color = HudConfig.soft.withValues(alpha: a);
    canvas
      ..drawRect(Rect.fromLTWH(o + 5 * k, o + 3 * k, 5 * k, 18 * k), _bar)
      ..drawRect(Rect.fromLTWH(o + 14 * k, o + 3 * k, 5 * k, 18 * k), _bar);
  }
}
