import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';

/// A short text pop that rises and fades (the lab mocks' `pop()`: 20 pt
/// Opificio, rises 28 pt/s, fades over 1 s) — "BOING ↑ / ↓" (the spring,
/// WP-3c) and the collectables' countdowns / "n / 8" / "EGG!" (WP-3e).
///
/// Master shared part (ARCH §9.1): moved here from `hoops/kinds/spring.dart`
/// in WP-3e, which re-exports it so the spring and `s3_23_spring_test` keep
/// compiling. Parent it in `layers.fx` (track coordinates) or the HUD
/// (screen coordinates); [at] is in the parent's coordinates.
class TextPop extends PositionComponent {
  TextPop(this.text, Vector2 at, this.color, {this.fontSize = 20})
    : super(position: at, anchor: Anchor.center);

  final String text;
  final Color color;
  final double fontSize;
  double _t = 0;

  static const double life = 1;
  static const double rise = 28;

  late final TextPainter _tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: fontSize,
        color: color,
      ),
    ),
    textDirection: p.TextDirection.ltr,
  )..layout();

  @override
  void update(double dt) {
    _t += dt;
    position.y -= rise * dt;
    if (_t >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = (1 - _t / life).clamp(0.0, 1.0);
    if (a <= 0) return;
    canvas.saveLayer(
      Rect.fromCenter(
        center: Offset.zero,
        width: _tp.width + 8,
        height: _tp.height + 8,
      ),
      Paint()..color = Color.fromRGBO(0, 0, 0, a),
    );
    _tp.paint(canvas, Offset(-_tp.width / 2, -_tp.height / 2));
    canvas.restore();
  }
}
