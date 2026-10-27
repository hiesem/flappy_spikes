import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan;

import '../../game/config.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';

/// The small vector glyphs of the skin shop (PRD-menu-v2 §4), ported from
/// the inline SVGs in `design/menu_v2/skin_shop.js` (`IC`). All draw into a
/// box at the canvas origin; callers translate.
abstract final class ShopGlyphs {
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// Gold coin (`IC.coin`, 24-unit viewBox) in a [size] box.
  static void coin(Canvas canvas, double size) {
    final k = size / 24;
    canvas.drawCircle(
      Offset(12 * k, 12 * k),
      11 * k,
      _fill..color = Config.menuGold,
    );
    canvas.drawCircle(
      Offset(12 * k, 12 * k),
      7.2 * k,
      _stroke
        ..color = const Color(0xBFFFFFFF)
        ..strokeWidth = 2 * k,
    );
  }

  /// Padlock (`IC.lock`, 24-unit viewBox) in a [size] box.
  static void lock(Canvas canvas, double size, Color color) {
    final k = size / 24;
    canvas.drawRect(
      Rect.fromLTWH(4 * k, 10 * k, 16 * k, 12 * k),
      _fill..color = color,
    );
    final shackle = Path()
      ..moveTo(8 * k, 10 * k)
      ..lineTo(8 * k, 7 * k)
      ..arcToPoint(Offset(16 * k, 7 * k), radius: Radius.circular(4 * k))
      ..lineTo(16 * k, 10 * k);
    canvas.drawPath(
      shackle,
      _stroke
        ..color = color
        ..strokeWidth = 2.6 * k,
    );
  }

  /// Check mark (`IC.check`, 24-unit viewBox) in a [size] box.
  static void check(Canvas canvas, double size, Color color) {
    final k = size / 24;
    final path = Path()
      ..moveTo(4 * k, 12 * k)
      ..lineTo(9 * k, 17 * k)
      ..lineTo(20 * k, 6 * k);
    canvas.drawPath(
      path,
      _stroke
        ..color = color
        ..strokeWidth = 3.4 * k,
    );
  }

  // Tab silhouettes in the mock's 44 x 36 viewBox.
  static final Path _birdIcon = Path()
    ..moveTo(0, 8)
    ..lineTo(9, 14)
    ..lineTo(0, 20)
    ..close()
    ..addRect(const Rect.fromLTWH(6, 3, 30, 30))
    ..moveTo(36, 14)
    ..lineTo(44, 20)
    ..lineTo(36, 26)
    ..close();

  static final Path _gearIcon = () {
    const r = Radius.circular(6);
    return Path()
      ..moveTo(2, 12)
      ..lineTo(42, 12)
      ..lineTo(42, 16)
      ..lineTo(39, 16)
      ..lineTo(39, 22)
      ..arcToPoint(const Offset(33, 28), radius: r)
      ..lineTo(27, 28)
      ..arcToPoint(const Offset(21, 22), radius: r)
      ..lineTo(21, 20)
      ..lineTo(19, 20)
      ..lineTo(19, 22)
      ..arcToPoint(const Offset(13, 28), radius: r)
      ..lineTo(7, 28)
      ..arcToPoint(const Offset(1, 22), radius: r)
      ..lineTo(1, 16)
      ..close();
  }();

  static final Path _hatIcon = Path()
    ..addRect(const Rect.fromLTWH(12, 2, 20, 24))
    ..addRect(const Rect.fromLTWH(4, 26, 36, 5));

  static final Path _hoopIcon = Path()
    ..addOval(
      Rect.fromCenter(center: const Offset(22, 18), width: 18, height: 32),
    );

  static final Path _trailIcon = Path()
    ..moveTo(30, 2)
    ..relativeCubicTo(2, 7, 10, 11, 10, 20)
    ..relativeArcToPoint(
      const Offset(-24, 0),
      radius: const Radius.circular(12),
    )
    ..relativeCubicTo(0, -5, 3, -8, 5, -10)
    ..relativeCubicTo(0, 4, 2, 6, 4, 6)
    ..relativeCubicTo(-1, -6, 1, -11, 5, -16)
    ..close()
    ..addRect(const Rect.fromLTWH(2, 14, 12, 4))
    ..addRect(const Rect.fromLTWH(6, 22, 9, 4));

  /// The tab silhouette of [layer] (`IC.bird/acc/hat/hoop/fire`) fitted
  /// into a [width] x [height] box (SVG `xMidYMid meet`).
  static void tabIcon(
    Canvas canvas,
    SkinLayer layer,
    double width,
    double height,
    Color color,
  ) {
    final k = math.min(width / 44, height / 36);
    canvas.save();
    canvas.translate((width - 44 * k) / 2, (height - 36 * k) / 2);
    canvas.scale(k);
    if (layer == SkinLayer.hoop) {
      canvas.drawPath(
        _hoopIcon,
        _stroke
          ..color = color
          ..strokeWidth = 6,
      );
    } else {
      final path = switch (layer) {
        // region P26-F9a
        SkinLayer.card => _birdIcon,
        // endregion
        SkinLayer.bird => _birdIcon,
        SkinLayer.gear => _gearIcon,
        SkinLayer.hat => _hatIcon,
        SkinLayer.trail => _trailIcon,
        SkinLayer.hoop => _hoopIcon,
      };
      canvas.drawPath(path, _fill..color = color);
    }
    canvas.restore();
  }
}

/// One cached line of menu text, painted directly (no component): the
/// mocks' CSS line box ([menuTextStyle]) with the letter spacing after each
/// glyph as browsers do (see [MenuText.render]).
class ShopText {
  ShopText(
    String text, {
    required this.fontSize,
    required this._color,
    this.letterSpacingEm = 0,
  }) : _text = text {
    _layout();
  }

  final double fontSize;
  final double letterSpacingEm;
  String _text;
  Color _color;
  late TextPainter _painter;

  String get text => _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _layout();
  }

  Color get color => _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    _layout();
  }

  double get width => _painter.width;
  double get height => _painter.height;

  void _layout() {
    _painter = TextPainter(
      text: TextSpan(
        text: _text,
        style: menuTextStyle(
          fontSize: fontSize,
          color: _color,
          letterSpacingEm: letterSpacingEm,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Paints the line box with its top-left at [offset].
  void paint(Canvas canvas, Offset offset) => _painter.paint(
    canvas,
    offset - Offset(letterSpacingEm * fontSize / 2, 0),
  );
}

/// The coin price chip (mock `.price`): 3 pt padding left / top / bottom,
/// 6 pt right, a 13 pt coin, 4 pt gap, 12 pt text; [background] pink in
/// tiles, soft on the BUY button.
class PriceChip {
  PriceChip(int price, {required this.background, required Color textColor})
    : label = ShopText(
        formatCoins(price),
        fontSize: Config.skinShopPriceFontSize,
        color: textColor,
        letterSpacingEm: 0.04,
      );

  final ShopText label;
  Color background;

  static const double padLeft = 3, padRight = 6, padY = 3, gap = 4;
  static const double coinSize = Config.skinShopPriceCoin;

  static final Paint _paint = Paint();

  double get width => padLeft + coinSize + gap + label.width + padRight;
  double get height => coinSize + 2 * padY;

  void paint(Canvas canvas, Offset topLeft) {
    canvas.drawRect(topLeft & Size(width, height), _paint..color = background);
    canvas.save();
    canvas.translate(topLeft.dx + padLeft, topLeft.dy + padY);
    ShopGlyphs.coin(canvas, coinSize);
    canvas.restore();
    label.paint(
      canvas,
      Offset(
        topLeft.dx + padLeft + coinSize + gap,
        topLeft.dy + (height - label.height) / 2,
      ),
    );
  }
}
