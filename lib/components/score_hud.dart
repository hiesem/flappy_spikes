import 'dart:math' as math;

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
    _circle.paint.colorFilter = ColorFilter.mode(_circleTint, BlendMode.modulate);
    _scoreText.setColor(_textColor);
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
      _scoreText.setColor(_textColor);
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (isLoaded) {
      _circle.paint.colorFilter = ColorFilter.mode(
        _circleTint,
        BlendMode.modulate,
      );
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

  // region WP-3g — spike squeeze (PRD-2 §3.17)
  double _cover = 0;
  Color _coverText = const Color(0xFF828282);

  /// §3.17 how much a squeezing wall covers the circle (0..1): the grey
  /// circle crossfades to white and, past half, the score turns the wall
  /// grey so it stays readable.
  double get squeezeCover => _cover;

  Color get _circleTint => _cover <= 0
      ? _tint
      : Color.lerp(_tint, const Color(0xFFFFFFFF), _cover)!;

  Color get _textColor => _cover > .5 ? _coverText : _scoreColor;

  /// Sets the cover (0..1) and the score colour used while covered.
  void setSqueezeCover(double cover, Color textColor) {
    final c = cover.clamp(0.0, 1.0);
    if (c == _cover && textColor == _coverText) return;
    _cover = c;
    _coverText = textColor;
    if (isLoaded) {
      _circle.paint.colorFilter = ColorFilter.mode(
        _circleTint,
        BlendMode.modulate,
      );
      _scoreText.setColor(_textColor);
    }
  }

  /// §3.17 the cover of a circle centred at [centreY] with [radius] by the
  /// tooth lines [top] / [floor]: 0 until a line reaches the circle, then
  /// rising to 1 over [ramp] pt.
  static double coverFor({
    required double centreY,
    required double radius,
    required double top,
    required double floor,
    double ramp = 30,
  }) {
    final over = math.max(top - (centreY - radius), (centreY + radius) - floor);
    return (over / ramp).clamp(0.0, 1.0);
  }

  /// Paints the circle and the score again (for [ScoreCoverOverlay]).
  void renderCopy(Canvas canvas) {
    if (!isLoaded) return;
    canvas.save();
    canvas.translate(position.x, position.y);
    _circle.renderTree(canvas);
    _scoreText.renderTree(canvas);
    canvas.restore();
  }
  // endregion WP-3g
}

// region WP-3g — spike squeeze (PRD-2 §3.17)
/// §3.17 "the HUD stays on top of the walls": the score circle lives behind
/// the play (priority −100), so where a squeezing wall covers it this
/// overlay — just above the spike strips — paints the circle and the score
/// again, clipped to the walls ([top] / [floor] = the tooth lines).
class ScoreCoverOverlay extends Component {
  ScoreCoverOverlay(this.hud, {super.priority});

  final ScoreHud hud;

  /// The current tooth lines (screen y).
  double top = 0, floor = double.infinity;

  @override
  void render(Canvas canvas) {
    if (hud.squeezeCover <= 0 || hud.opacity <= 0) return;
    canvas.save();
    final clip = Path()
      ..addRect(Rect.fromLTRB(-100, -100, 420, top))
      ..addRect(Rect.fromLTRB(-100, floor, 420, floor + 2000));
    canvas.clipPath(clip);
    hud.renderCopy(canvas);
    canvas.restore();
  }
}
// endregion WP-3g
