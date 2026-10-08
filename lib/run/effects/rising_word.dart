import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextAlign;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';

/// A short outlined word that pops in, rises and fades (ARCH §3, added by
/// WP-3d so the switch rings' open words — §5.19 "POWER OFF", "POWER ON",
/// "WAKE UP!", "SNIP!" — and the pair gifts' reward words — §5.20
/// "SHIELD!", "+10 COINS" — share one drawing). Opificio, a solid or
/// vertical-gradient fill, an outline; pop-in 0.6 → 1.1 → 1 over 0.22 s,
/// rises [rise] pt over [life] s and fades over the last 0.3 s.
///
/// Lives in whatever parent it is added to (track coordinates in
/// `RunTrack.fx`, screen coordinates in the world).
class RisingWord extends PositionComponent {
  RisingWord(
    this.text, {
    required Vector2 at,
    required this.fontSize,
    required this.fill,
    this.fillBottom,
    required this.outline,
    required this.outlineWidth,
    this.life = 1.1,
    this.rise = 26,
    this.tilt = 0,
    super.priority,
  }) : super(position: at.clone());

  final String text;

  /// Font size (pt).
  final double fontSize;

  /// Fill colour (the top of the gradient when [fillBottom] is set).
  final Color fill;
  final Color? fillBottom;
  final Color outline;
  final double outlineWidth;
  final double life;
  final double rise;

  /// Radians.
  final double tilt;

  double _t = 0;
  double get time => _t;

  late final TextPainter _stroke = _painter(
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineWidth
      ..strokeJoin = StrokeJoin.round
      ..color = outline,
  );

  late final TextPainter _fill = _painter(
    Paint()
      ..shader = fillBottom == null
          ? null
          : Gradient.linear(
              Offset(0, -fontSize * .5),
              Offset(0, fontSize * .5),
              [fill, fillBottom!],
            )
      ..color = fill,
  );

  TextPainter _painter(Paint paint) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: fontSize,
        foreground: paint,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: p.TextDirection.ltr,
  )..layout();

  /// The pop-in scale at [t] s (0.6 → 1.1 at 0.12 s → 1 at 0.22 s).
  static double popScale(double t) => t < .12
      ? .6 + t / .12 * .5
      : t < .22
      ? 1.1 - (t - .12)
      : 1;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final u = (_t / life).clamp(0.0, 1.0);
    final alpha = math.min(1.0, (life - _t) / .3).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    final s = popScale(_t);
    canvas.save();
    canvas.translate(0, -rise * u);
    canvas.rotate(tilt);
    canvas.scale(s);
    final w = _fill.width, h = _fill.height;
    canvas.saveLayer(
      Rect.fromLTWH(
        -w / 2 - outlineWidth,
        -h / 2 - outlineWidth,
        w + 2 * outlineWidth,
        h + 2 * outlineWidth,
      ),
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
    );
    _stroke.paint(canvas, Offset(-w / 2, -h / 2));
    _fill.paint(canvas, Offset(-w / 2, -h / 2));
    canvas.restore();
    canvas.restore();
  }
}
