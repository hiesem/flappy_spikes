import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../config/run_config.dart';
import '../run_controller.dart';

/// Prototype-style debug view (ARCH §1.12): rim-end circles, pass planes and
/// hoop index / kind / angle, drawn in track coordinates. Debug builds only
/// (the debug menu toggles it).
class RunDebugOverlay extends Component {
  RunDebugOverlay(this.run) : super(priority: 100);

  final RunController run;

  static final Paint _rim = Paint()
    ..color = const Color(0xFF00C8FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final Paint _plane = Paint()
    ..color = const Color(0x8800C8FF)
    ..strokeWidth = 1;
  static final TextPaint _text = TextPaint(
    style: const TextStyle(fontSize: 9, color: Color(0xFF0050A0)),
  );

  @override
  void render(Canvas canvas) {
    for (final h in run.spawner.hoops) {
      canvas.save();
      canvas.translate(h.position.x, h.position.y);
      canvas.rotate(h.angle);
      for (final o in h.rings) {
        final e = h.opening / 2 + RunConfig.rimRadius;
        canvas.drawLine(Offset(0, o - e), Offset(0, o + e), _plane);
        canvas.drawCircle(Offset(0, o - e), RunConfig.rimRadius, _rim);
        canvas.drawCircle(Offset(0, o + e), RunConfig.rimRadius, _rim);
      }
      canvas.restore();
      _text.render(
        canvas,
        '#${h.plan.index} ${h.plan.kind.name} '
        '${(h.angle * 180 / math.pi).toStringAsFixed(0)}°',
        Vector2(h.position.x - 20, h.position.y + h.opening / 2 + 14),
      );
    }
  }
}
