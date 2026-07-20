import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/painting.dart';

/// A TextComponent that supports opacity (for fade in/out effects) and
/// live color changes (for the color stage system).
class FadableTextComponent extends TextComponent<TextPaint>
    implements OpacityProvider {
  FadableTextComponent({
    required String text,
    required TextStyle style,
    super.position,
    super.anchor,
    super.priority,
  })  : _style = style,
        _baseColor = style.color ?? const Color(0xFFFFFFFF),
        super(text: text, textRenderer: TextPaint(style: style));

  final TextStyle _style;
  Color _baseColor;
  double _opacity = 1;

  @override
  double get opacity => _opacity;

  @override
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    _refresh();
  }

  void setColor(Color color) {
    _baseColor = color;
    _refresh();
  }

  void _refresh() {
    textRenderer = TextPaint(
      style: _style.copyWith(
        color: _baseColor.withValues(alpha: _baseColor.a * _opacity),
      ),
    );
  }
}
