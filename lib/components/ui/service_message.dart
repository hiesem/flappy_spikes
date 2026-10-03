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
class ServiceMessage extends PositionComponent {
  ServiceMessage({required this.message, required Vector2 position})
    : super(position: position, priority: 30);

  final String message;

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
      style: const TextStyle(
        fontFamily: Config.uiFont,
        fontSize: 16,
        color: Config.uiAccent,
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
}
