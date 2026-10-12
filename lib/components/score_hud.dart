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
    : super(position: position ?? Config.scoreHudPosition, priority: -100);

  late final SpriteComponent _circle;
  late final FadableTextComponent _scoreText;

  // region PRD-2.2 §13.2 — points count-up and shrink-to-fit
  /// PRD-2.2 §13.2 The largest score font size (pt); short scores keep it.
  static const double fontSize = 125;

  /// PRD-2.2 §13.2 The side margin (pt, each side) the score keeps inside
  /// the circle ([Config.scoreCircleSize]).
  static const double sideMargin = 12;

  /// PRD-2.2 §13.2 A gain of more than 1 counts up over this long (s,
  /// ease-out cubic).
  static const double countDuration = .3;

  /// PRD-2.2 §13.2 The small pop at the end of a count-up: peak scale and
  /// length (s).
  static const double popScale = 1.12;
  static const double popDuration = .16;

  /// PRD-2.2 §13.2 (fix S7-01) The font size for a [digits]-digit score:
  /// min([fontSize], the size at which the widest [digits]-digit number,
  /// measured with the real font metrics of [style], fits the circle with
  /// [sideMargin] on each side). Measuring the widest number of a digit
  /// count keeps "the size changes only when the digit count changes" while
  /// every value of that count fits.
  static double fontSizeFor(int digits, {TextStyle? style}) {
    final base = (style ?? const TextStyle(fontFamily: Config.scoreFont))
        .copyWith(fontSize: fontSize);
    double widthOf(String text) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: base),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    var widest = '0';
    var widestW = widthOf(widest);
    for (var d = 1; d <= 9; d++) {
      final w = widthOf('$d');
      if (w > widestW) {
        widest = '$d';
        widestW = w;
      }
    }
    final width = widthOf(widest * math.max(1, digits));
    final maxWidth = Config.scoreCircleSize.x - 2 * sideMargin;
    if (width <= maxWidth || width <= 0) return fontSize;
    // Text width scales linearly with the font size.
    return fontSize * maxWidth / width;
  }

  final Map<int, double> _fontSizes = {};

  static const TextStyle _baseStyle = TextStyle(
    fontFamily: Config.scoreFont,
    fontSize: fontSize,
  );

  /// The score shown right now (counting up toward [score]).
  int get shownScore => _shown.round();

  /// The target score.
  int get score => _score;

  /// Whether a count-up is running.
  bool get counting => _countT != null;

  double _shown = 0;
  double _from = 0;
  double? _countT;
  double? _popT;
  // endregion PRD-2.2 §13.2

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
      style: _baseStyle.copyWith(color: const Color(0xFFF1F1F1)),
      anchor: Anchor.center,
      priority: 1,
    );
    addAll([_circle, _scoreText]);
    _apply();
  }

  void _apply() {
    _showText();
    _circle.opacity = _opacity;
    _scoreText.opacity = _opacity;
    _circle.paint.colorFilter = ColorFilter.mode(
      _circleTint,
      BlendMode.modulate,
    );
    _scoreText.setColor(_textColor);
  }

  /// PRD-2.2 §13.2 sets the score (points). A gain of more than 1 (or any
  /// gain during a count) counts up from the shown value to the new total
  /// over [countDuration] and ends with a small pop; a +1 or a reset shows
  /// at once.
  void setScore(int score) {
    final old = _score;
    _score = score;
    if (score > old && (score - _shown.round() > 1 || counting)) {
      _from = _shown;
      _countT = 0;
    } else {
      _countT = null;
      _shown = score.toDouble();
      if (score <= old) _popT = null;
    }
    if (isLoaded) _showText();
  }

  void _showText() {
    final v = _shown.round();
    final text = '$v';
    _scoreText.setFontSize(
      _fontSizes[text.length] ??= fontSizeFor(text.length, style: _baseStyle),
    );
    _scoreText.text = text;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final t = _countT;
    if (t != null) {
      final nt = t + dt;
      final u = (nt / countDuration).clamp(0.0, 1.0);
      final e = 1 - math.pow(1 - u, 3).toDouble();
      _shown = _from + (_score - _from) * e;
      if (u >= 1) {
        _shown = _score.toDouble();
        _countT = null;
        _popT = 0;
      } else {
        _countT = nt;
      }
      if (isLoaded) _showText();
    }
    final p = _popT;
    if (p != null && isLoaded) {
      final np = p + dt;
      final u = (np / popDuration).clamp(0.0, 1.0);
      final k = u < .5 ? u / .5 : (1 - u) / .5;
      _scoreText.scale.setAll(1 + (popScale - 1) * k);
      _popT = u >= 1 ? null : np;
      if (u >= 1) _scoreText.scale.setAll(1);
    }
  }

  /// The score text's laid-out width at its current size (tests).
  double get textWidth => _scoreText.size.x;

  /// The score text's current font size (tests).
  double get textFontSize => _scoreText.textRenderer.style.fontSize ?? fontSize;

  /// Whether the end-of-count pop is running (tests).
  bool get popping => _popT != null;

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

  Color get _circleTint =>
      _cover <= 0 ? _tint : Color.lerp(_tint, const Color(0xFFFFFFFF), _cover)!;

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
