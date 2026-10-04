import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextLeadingDistribution, TextStyle;

import '../../game/config.dart';

/// Building blocks of the 2.0 menu screens (home now; Shop / Skins / popups
/// reuse them). Geometry always comes from [Config]; these only draw.

/// CSS `line-height: normal` of Opificio Neue: (hhea ascent 992 + descent
/// 264 + lineGap 28) / 1000 em. The HTML mocks lay text out with it, so
/// using the same box (with the leading split evenly, as browsers do) puts
/// glyphs on the same pixels.
const double kNormalLineHeight = 1.284;

/// A text style matching the mocks' CSS: [fontSize] in pt, letter spacing in
/// em, line box [lineHeight] x fontSize with even half-leading.
TextStyle menuTextStyle({
  required double fontSize,
  required Color color,
  double letterSpacingEm = 0,
  double lineHeight = kNormalLineHeight,
  String fontFamily = Config.uiFont,
}) => TextStyle(
  fontFamily: fontFamily,
  fontSize: fontSize,
  color: color,
  letterSpacing: letterSpacingEm * fontSize,
  height: lineHeight,
  leadingDistribution: TextLeadingDistribution.even,
);

/// Single-line text whose component box is the CSS line box (so `position`
/// with a top anchor is the line-box top, as in the mocks).
class MenuText extends TextComponent<TextPaint> {
  MenuText(
    String text, {
    required double fontSize,
    required Color color,
    double letterSpacingEm = 0,
    double lineHeight = kNormalLineHeight,
    super.position,
    super.anchor,
    super.priority,
  }) : _fontSize = fontSize,
       _letterSpacingEm = letterSpacingEm,
       _lineHeight = lineHeight,
       _color = color,
       super(
         text: text,
         textRenderer: TextPaint(
           style: menuTextStyle(
             fontSize: fontSize,
             color: color,
             letterSpacingEm: letterSpacingEm,
             lineHeight: lineHeight,
           ),
         ),
       );

  final double _fontSize;
  final double _letterSpacingEm;
  final double _lineHeight;
  Color _color;

  Color get color => _color;

  // SkParagraph spreads letter spacing half before / half after each glyph;
  // CSS (the mocks) puts all of it after. Shift left by half a spacing so
  // the ink lands where the browser draws it (the box width already
  // matches: one spacing per glyph either way).
  @override
  void render(Canvas canvas) {
    final shift = _letterSpacingEm * _fontSize / 2;
    if (shift == 0) {
      super.render(canvas);
      return;
    }
    canvas.save();
    canvas.translate(-shift, 0);
    super.render(canvas);
    canvas.restore();
  }

  set color(Color value) {
    if (value == _color) return;
    _color = value;
    textRenderer = TextPaint(
      style: menuTextStyle(
        fontSize: _fontSize,
        color: value,
        letterSpacingEm: _letterSpacingEm,
        lineHeight: _lineHeight,
      ),
    );
  }
}

/// Fades a whole subtree as one layer (no per-child opacity plumbing, no
/// double-blending where children overlap).
mixin GroupOpacity on PositionComponent implements OpacityProvider {
  double _groupOpacity = 1;

  @override
  double get opacity => _groupOpacity;

  @override
  set opacity(double value) => _groupOpacity = value.clamp(0.0, 1.0);

  @override
  void renderTree(Canvas canvas) {
    if (_groupOpacity <= 0) return;
    if (_groupOpacity >= 1) {
      super.renderTree(canvas);
      return;
    }
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromRGBO(0, 0, 0, _groupOpacity),
    );
    super.renderTree(canvas);
    canvas.restore();
  }
}

/// A flat menu button: optional solid [color] fill, arbitrary children,
/// tap feedback (darkens while pressed) and its action on tap-up.
///
/// [isActive] gates hit-testing: while it returns false (e.g. the home
/// screen fading out after START) taps pass straight through to whatever
/// is below — a flap must never be eaten by a fading button. [tappable]
/// does the same per button (e.g. a pending purchase). [dimmed] draws the
/// button at half opacity but keeps it tappable (unavailable ad -> toast).
class MenuButton extends PositionComponent with TapCallbacks {
  MenuButton({
    required this.onPressed,
    this.color,
    this.isActive,
    super.position,
    super.size,
    super.priority,
    super.children,
  });

  void Function() onPressed;
  Color? color;
  bool Function()? isActive;
  bool tappable = true;
  bool dimmed = false;

  static const double dimmedOpacity = 0.5;
  static const Color _pressedShade = Color(0x26000000); // 15 % black

  bool _pressed = false;

  /// Exposed for tests.
  bool get pressed => _pressed;

  final Paint _fill = Paint();
  final Paint _pressPaint = Paint()..color = _pressedShade;

  @override
  bool containsLocalPoint(Vector2 point) =>
      tappable && (isActive?.call() ?? true) && super.containsLocalPoint(point);

  @override
  void renderTree(Canvas canvas) {
    if (!dimmed) {
      super.renderTree(canvas);
      return;
    }
    canvas.saveLayer(
      null,
      Paint()..color = const Color.fromRGBO(0, 0, 0, dimmedOpacity),
    );
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    final fill = color;
    if (fill != null) {
      _fill.color = fill;
      canvas.drawRect(size.toRect(), _fill);
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _pressed = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    _pressed = false;
    onPressed();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressed = false;
  }

  // The pressed shade must cover the children too, so it is a topmost
  // child rather than part of render().
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_PressShade(this));
  }
}

/// Topmost child of a [MenuButton]: the pressed-state darkening.
class _PressShade extends Component {
  _PressShade(this._button) : super(priority: 1 << 20);

  final MenuButton _button;

  @override
  void render(Canvas canvas) {
    if (_button._pressed) {
      canvas.drawRect(_button.size.toRect(), _button._pressPaint);
    }
  }
}

/// A sprite icon from `assets/images/menu/` at its logical size; optional
/// [recolor] paints it in one flat colour (srcIn), e.g. the soft check
/// glyph in plum on the gold slot.
class MenuIcon extends SpriteComponent {
  MenuIcon(
    Sprite sprite, {
    required Vector2 size,
    Color? recolor,
    super.position,
    super.anchor,
    super.priority,
  }) : super(sprite: sprite, size: size) {
    if (recolor != null) {
      paint.colorFilter = ColorFilter.mode(recolor, BlendMode.srcIn);
    }
  }
}

/// Gold corner tag ("NEW"): white 11 pt text, 2/5 pt padding (mock `.tag`;
/// the Skins grid's `.tg` is 10 pt at 0.05 em).
class MenuTag extends PositionComponent {
  MenuTag(
    String text, {
    double fontSize = 11,
    double letterSpacingEm = 0.04,
    super.position,
    super.anchor,
    super.priority,
  }) : _label = MenuText(
         text,
         fontSize: fontSize,
         color: const Color(0xFFFFFFFF),
         letterSpacingEm: letterSpacingEm,
         position: Vector2(padX, padY),
       );

  final MenuText _label;
  static const double padX = 5;
  static const double padY = 2;
  final Paint _paint = Paint()..color = Config.menuGold;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_label);
    size = Vector2(_label.width + 2 * padX, _label.height + 2 * padY);
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}

/// Lays [items] out left-to-right as one centred group inside [parent]
/// (the mocks' `display:flex; justify-content:center; align-items:center;
/// gap`), vertically centred, and adds them to [parent]. With [right] set
/// the group's right edge sits at that x instead (`justify-content:
/// flex-end` with padding); with [left], its left edge.
void layoutRow(
  PositionComponent parent,
  List<PositionComponent> items, {
  required double gap,
  double? left,
  double? right,
}) {
  final width =
      items.fold<double>(0, (sum, c) => sum + c.width) +
      gap * (items.length - 1);
  var x = left ?? (right != null ? right - width : (parent.width - width) / 2);
  for (final item in items) {
    item
      ..anchor = Anchor.topLeft
      ..position = Vector2(x, (parent.height - item.height) / 2);
    x += item.width + gap;
  }
  parent.addAll(items);
}

/// Formats a coin balance like the mocks: thousands grouped with a space
/// ("1 250").
String formatCoins(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
