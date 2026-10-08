import 'dart:ui';

import '../config/lives_config.dart';
import '../config/parts_config.dart';

/// The run's heart and shield icons (PRD-2 §5.2, §5.5), one drawing each:
/// the heart pickup, the extra-life badge, the heart shards and the flying
/// heart (and the HUD indicator, WP-2d) use [paintHeart]; the shield pickup
/// (and any HUD use) uses [paintShield]. Shapes from the approved mocks'
/// SVGs (`HEARTP`, 24 × 24; the shield, 24 × 26.4).
abstract final class LifeIcons {
  /// `M12 21s-9-5.6-9-12a5 5 0 0 1 9-3 5 5 0 0 1 9 3c0 6.4-9 12-9 12z`
  /// in its 24 × 24 box.
  static final Path heart24 = Path()
    ..moveTo(12, 21)
    ..cubicTo(12, 21, 3, 15.4, 3, 9)
    ..arcToPoint(const Offset(12, 6), radius: const Radius.circular(5))
    ..arcToPoint(const Offset(21, 9), radius: const Radius.circular(5))
    ..cubicTo(21, 15.4, 12, 21, 12, 21)
    ..close();

  /// The badge's highlight stroke `M8 8.5a3 3 0 0 1 3-1.3`.
  static final Path _shine = Path()
    ..moveTo(8, 8.5)
    ..arcToPoint(const Offset(11, 7.2), radius: const Radius.circular(3));

  /// The shield outline in its 24 × 26.4 box.
  static final Path shield24 = Path()
    ..moveTo(12, 1.5)
    ..lineTo(21.5, 5)
    ..lineTo(21.5, 11.5)
    ..cubicTo(21.5, 17, 17.5, 21, 12, 22.5)
    ..cubicTo(6.5, 21, 2.5, 17, 2.5, 11.5)
    ..lineTo(2.5, 5)
    ..close();

  static final Path _star = Path()
    ..addPolygon(const [
      Offset(12, 7.5),
      Offset(13.5, 10.7),
      Offset(17, 11.1),
      Offset(14.4, 13.5),
      Offset(15.1, 17),
      Offset(12, 15.2),
      Offset(8.9, 17),
      Offset(9.6, 13.5),
      Offset(7, 11.1),
      Offset(10.5, 10.7),
    ], true);

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// A heart [size] pt wide centred at [c] (the 24-unit box scaled), filled
  /// [fill] (default §5.2 red), with an optional white outline [outline]
  /// (box units) and the badge's highlight ([shine]).
  static void paintHeart(
    Canvas canvas,
    Offset c,
    double size, {
    Color fill = LivesConfig.heartRed,
    double outline = 0,
    Color outlineColor = const Color(0xFFFFFFFF),
    bool shine = false,
    double opacity = 1,
    double rotation = 0,
  }) {
    if (size <= 0 || opacity <= 0) return;
    canvas
      ..save()
      ..translate(c.dx, c.dy);
    if (rotation != 0) canvas.rotate(rotation);
    canvas
      ..scale(size / 24)
      ..translate(-12, -12);
    _fill.color = fill.withValues(alpha: fill.a * opacity);
    canvas.drawPath(heart24, _fill);
    if (outline > 0) {
      _stroke
        ..strokeWidth = outline
        ..color = outlineColor.withValues(alpha: outlineColor.a * opacity);
      canvas.drawPath(heart24, _stroke);
    }
    if (shine) {
      _stroke
        ..strokeWidth = 1.4
        ..color = Color.fromRGBO(255, 255, 255, .8 * opacity);
      canvas.drawPath(_shine, _stroke);
    }
    canvas.restore();
  }

  /// The §5.5 shield icon, [width] pt wide (height × 1.1) centred at [c]:
  /// pink `#EC008C` fill, gold `#FFB529` border, a thin white inner line,
  /// a gold star with a white outline (the home slot / shop asset's look).
  static void paintShield(
    Canvas canvas,
    Offset c,
    double width, {
    double opacity = 1,
  }) {
    if (width <= 0 || opacity <= 0) return;
    Color a(Color k) => k.withValues(alpha: k.a * opacity);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(width / 24)
      ..translate(-12, -13.2);
    _fill.color = a(PartsConfig.pink);
    canvas.drawPath(shield24, _fill);
    _stroke
      ..strokeWidth = 2.2
      ..color = a(PartsConfig.gold);
    canvas.drawPath(shield24, _stroke);
    canvas
      ..save()
      ..translate(12, 12.5)
      ..scale(.8)
      ..translate(-12, -12.5);
    _stroke
      ..strokeWidth = .9
      ..color = a(const Color(0xFFFFFFFF));
    canvas
      ..drawPath(shield24, _stroke)
      ..restore();
    _fill.color = a(PartsConfig.gold);
    canvas.drawPath(_star, _fill);
    _stroke
      ..strokeWidth = .6
      ..color = a(const Color(0xFFFFFFFF));
    canvas
      ..drawPath(_star, _stroke)
      ..restore();
  }
}
