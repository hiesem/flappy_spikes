import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/painting.dart';

import '../game/config.dart';
import '../game/tintable.dart';
import 'ui/fadable_text.dart';

/// The giant watermark score: LVDC Common2 at 125 pt, colored with the
/// current background color, drawn over the background_score circle, both
/// positioned behind the pipes.
///
/// Setters are safe to call before [onLoad] has run: values are stored and
/// applied once the children exist.
class ScoreHud extends PositionComponent implements OpacityProvider, Tintable {
  ScoreHud({Vector2? position})
      : super(
          position: position ?? Config.scoreHudPosition,
          priority: -100,
        );

  late final SpriteComponent _circle;
  late final FadableTextComponent _scoreText;

  int _score = 0;
  double _opacity = 1;
  Color _tint = const Color(0xFF828282);
  Color _scoreColor = const Color(0xFFF1F1F1);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _circle = SpriteComponent(
      sprite: Sprite(await findGame()!.images.load('background_score.png')),
      size: Config.scoreCircleSize,
      anchor: Anchor.center,
      priority: 0,
    );
    _scoreText = FadableTextComponent(
      text: '0',
      style: const TextStyle(
        fontFamily: Config.scoreFont,
        fontSize: 125,
        color: Color(0xFFF1F1F1),
      ),
      anchor: Anchor.center,
      priority: 1,
    );
    addAll([_circle, _scoreText]);
    _apply();
  }

  void _apply() {
    _scoreText.text = '$_score';
    _circle.opacity = _opacity;
    _scoreText.opacity = _opacity;
    _circle.paint.colorFilter = ColorFilter.mode(_tint, BlendMode.modulate);
    _scoreText.setColor(_scoreColor);
  }

  void setScore(int score) {
    _score = score;
    if (isLoaded) {
      _scoreText.text = '$_score';
    }
  }

  /// The watermark color follows the background color.
  void setScoreColor(Color color) {
    _scoreColor = color;
    if (isLoaded) {
      _scoreText.setColor(color);
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (isLoaded) {
      _circle.paint.colorFilter = ColorFilter.mode(color, BlendMode.modulate);
    }
  }

  @override
  double get opacity => _opacity;

  @override
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    if (isLoaded) {
      _circle.opacity = _opacity;
      _scoreText.opacity = _opacity;
    }
  }
}
