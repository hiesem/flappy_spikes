import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../game/config.dart';
import 'fadable_text.dart';

/// A short-lived, non-blocking message shown when a platform-service action
/// fails (e.g. Play Games sign-in behind the leaderboard button). Fades in
/// over [Config.uiFadeDuration], holds [Config.serviceMessageHoldDuration],
/// fades back out and removes itself — self-timed, so the game's fade runner
/// is not involved.
///
/// Bare text in the fixed UI accent pink ([Config.uiAccent]), matching the
/// game-over labels convention: readable over frozen pipes in every color
/// stage (deliberately NOT registered as a [Tintable]).
///
/// With [chip] (menu screens and popups, where the free bands are full of
/// content) the text sits in soft pink on a dark chip instead, so it stays
/// readable over whatever it covers.
class ServiceMessage extends PositionComponent {
  ServiceMessage({
    required this.message,
    required Vector2 position,
    this.chip = false,
  }) : super(position: position, priority: 30);

  final String message;
  final bool chip;

  static const Color chipColor = Color(0xE614141E); // rgba(20,20,30,.9)
  static const double chipPadX = 12;
  static const double chipPadY = 7;
  final Paint _chipPaint = Paint();

  /// Exposed for tests (copy + rendered color assertions).
  late final FadableTextComponent textComponent;

  double _time = 0;

  static const double _fade = Config.uiFadeDuration;
  static const double _hold = Config.serviceMessageHoldDuration;
  static const double _total = _fade + _hold + _fade;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    textComponent = FadableTextComponent(
      text: message,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: 16,
        color: chip ? Config.menuSoft : Config.uiAccent,
      ),
      anchor: Anchor.center,
    );
    textComponent.opacity = 0;
    add(textComponent);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_time >= _total) {
      removeFromParent();
      return;
    }
    textComponent.opacity = _time < _fade
        ? _time / _fade
        : _time < _fade + _hold
        ? 1
        : 1 - (_time - _fade - _hold) / _fade;
  }

  @override
  void render(Canvas canvas) {
    if (!chip) return;
    final text = textComponent.size;
    _chipPaint.color = chipColor.withValues(
      alpha: chipColor.a * textComponent.opacity,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: text.x + 2 * chipPadX,
        height: text.y + 2 * chipPadY,
      ),
      _chipPaint,
    );
  }
}
