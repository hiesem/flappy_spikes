import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';

import 'fadable_text.dart';

/// A text label that acts as a tap target (the privacy-policy link on the
/// start scene). Consumes the tap so it does not start the game or flap.
/// Supports opacity and tinting like the other start-scene labels.
class TextButton extends PositionComponent with TapCallbacks {
  TextButton({
    required String text,
    required TextStyle style,
    required this.onPressed,
    super.position,
    super.anchor,
  }) : label = FadableTextComponent(
          text: text,
          style: style,
          anchor: Anchor.center,
        );

  /// Exposed for tests and fade/tint plumbing.
  final FadableTextComponent label;
  final void Function() onPressed;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(label);
    await label.loaded;
    // Generous padding around the glyphs makes the small link easy to tap.
    size = label.size + Vector2(32, 24);
    label.position = size / 2;
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    onPressed();
  }

  /// Retints the link text (color-stage system).
  void setColor(Color color) {
    label.setColor(color);
  }

  double get opacity => label.opacity;

  set opacity(double value) => label.opacity = value;
}
