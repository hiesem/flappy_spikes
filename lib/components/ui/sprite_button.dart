import 'package:flame/components.dart';
import 'package:flame/events.dart';

/// A sprite that acts as a tap target. Consumes the tap so it does not
/// propagate to the full-screen tap catcher below.
class SpriteButton extends SpriteComponent with TapCallbacks {
  SpriteButton({
    required super.sprite,
    required this.onPressed,
    super.position,
    super.size,
    super.anchor,
  });

  final void Function() onPressed;

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    onPressed();
  }
}
