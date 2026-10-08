import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/hud_config.dart';
import '../config/lives_config.dart';
import '../effects/life_icons.dart';
import 'run_hud.dart';

/// §5.7 / §3.3 the single heart indicator (x 14, y 52, 38 × 38): a soft
/// panel (stage foreground 18 % over the background) with a 28 pt heart
/// centred at [LivesConfig.indicatorCentre] (33, 71) — where WP-2a's
/// flying hearts land. Empty = dashed outline; 1 or 2 of 3 hearts = red
/// `#FF3B5C` filled one / two thirds, clipped from the bottom; extra life
/// ready = full and pulsing 1.0 ↔ 1.14 every 0.9 s. Reads `RunState.hearts`
/// and `RunState.extraLife` every frame.
class HeartIndicator extends PositionComponent {
  HeartIndicator(this.hud)
    : super(
        position: Vector2(HudConfig.heartLeft, HudConfig.rowTop),
        size: Vector2.all(HudConfig.rowHeight),
      );

  final RunHud hud;
  double _t = 0;

  static final Rect _bounds = LifeIcons.heart24.getBounds();

  /// 0..1 of the heart filled now.
  double get fill {
    final s = hud.run.state;
    if (s.extraLife) return 1;
    return (s.hearts / LivesConfig.heartsPerLife).clamp(0.0, 1.0);
  }

  /// The current pulse scale (1 unless the extra life is ready).
  double get pulse {
    if (!hud.run.state.extraLife) return 1;
    final k = .5 - .5 * math.cos(2 * math.pi * _t / HudConfig.heartPulsePeriod);
    return 1 + (HudConfig.heartPulse - 1) * k;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  final Paint _panel = Paint();
  final Paint _fill = Paint();
  final Paint _outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    final a = hud.rowOpacity;
    if (a <= 0) return;
    final g = hud.game;
    final fg = g.foregroundColor, bg = g.stageBackground;
    canvas.save();
    final c = size.toOffset() / 2;
    final sc = pulse;
    canvas
      ..translate(c.dx, c.dy)
      ..scale(sc)
      ..translate(-c.dx, -c.dy);
    _panel.color = Color.lerp(
      bg,
      fg,
      HudConfig.heartPanelMix,
    )!.withValues(alpha: a);
    canvas.drawRect(size.toRect(), _panel);
    // The heart in its 24-unit box, 28 pt, centred.
    final k = HudConfig.heartIcon / 24;
    canvas
      ..translate(c.dx - 12 * k, c.dy - 12 * k)
      ..scale(k);
    final f = fill;
    if (f > 0) {
      final b = _bounds;
      final top = b.bottom - f * b.height;
      canvas
        ..save()
        ..clipRect(Rect.fromLTRB(-2, top, 26, 26));
      _fill.color = LivesConfig.heartRed.withValues(alpha: a);
      canvas
        ..drawPath(LifeIcons.heart24, _fill)
        ..restore();
    }
    if (f < 1) {
      _outline
        ..strokeWidth = HudConfig.heartOutline
        ..color = fg.withValues(alpha: a);
      _drawDashed(canvas, LifeIcons.heart24, HudConfig.heartDash, _outline);
    }
    canvas.restore();
  }

  /// The outline in [dash] (on, off) pt — box units scaled back.
  static void _drawDashed(
    Canvas canvas,
    Path path,
    List<double> dash,
    Paint p,
  ) {
    final k = HudConfig.heartIcon / 24;
    final on = dash[0] / k, off = dash[1] / k;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), p);
        d += on + off;
      }
    }
  }
}
