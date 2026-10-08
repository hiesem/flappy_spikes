import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// How a [ScreenEdgeGlow] is drawn.
enum EdgeGlowStyle {
  /// Radial gradient: clear inside [ScreenEdgeGlow.inner], [color] at
  /// [ScreenEdgeGlow.outer] and beyond (miss, Hourglass vignette).
  radial,

  /// Blurred inset border (CSS `inset box-shadow`, revive urgency).
  inset,

  /// Plain stroked frame inset by half its width (Coin Frenzy border).
  frame,
}

/// The screen edge glow (ARCH §3 "ScreenEdgeGlow"): one class for the miss
/// red edge pulse (§5.13), the revive urgency glow (§5.9), the Hourglass
/// blue vignette (§5.29) and the Coin Frenzy gold border (§5.31). Lives in
/// the viewport (screen space, real time). Parameters: colour, style,
/// radii/width, an optional flat [tint], and the envelope (one sine pulse,
/// a looping pulse, or a manual [intensity] the owner drives).
class ScreenEdgeGlow extends PositionComponent {
  ScreenEdgeGlow({
    required Vector2 size,
    required this.color,
    this.style = EdgeGlowStyle.radial,
    this.inner = 180,
    this.outer = 430,
    this.edgeWidth = 80,
    this.tint,
    this.tintAlpha = 0,
    this.centre,
    super.priority,
  }) : super(size: size);

  /// §5.13 miss: `#FF1F3D` from clear at r 180 to full at r 430 round the
  /// screen centre, opacity 0 → 0.55 → 0 (sine) over 0.7 s.
  factory ScreenEdgeGlow.miss(Vector2 size) =>
      ScreenEdgeGlow(size: size, color: const Color(0xFFFF1F3D))
        ..pulseOnce(length: .7, peak: .55);

  /// §5.9 revive urgency: inset 80 pt `#FF1F3D` glow at 0.82, pulsing at
  /// 1.1 Hz (0.5 + 0.5 sin); the revive screen scales it with its own
  /// envelope through [intensity].
  factory ScreenEdgeGlow.reviveUrgency(Vector2 size) => ScreenEdgeGlow(
    size: size,
    color: const Color(0xD1FF1F3D),
    style: EdgeGlowStyle.inset,
    edgeWidth: 80,
  )..loop(frequency: 1.1, base: .5, amplitude: .5);

  /// §5.29 Hourglass: blue tint rgba(47,128,255,.10) + vignette clear at
  /// r 200 → rgba(20,40,120,.30) at r 460; [intensity] follows the slow-down.
  factory ScreenEdgeGlow.hourglass(Vector2 size) => ScreenEdgeGlow(
    size: size,
    color: const Color(0x4D142878),
    inner: 200,
    outer: 460,
    tint: const Color(0xFF2F80FF),
    tintAlpha: .10,
  );

  /// §5.31 Coin Frenzy: a 10 pt gold frame at 0.35 + 0.2 sin(8 t).
  factory ScreenEdgeGlow.coinFrenzy(Vector2 size) => ScreenEdgeGlow(
    size: size,
    color: const Color(0xFFFFB529),
    style: EdgeGlowStyle.frame,
    edgeWidth: 10,
  )..loop(frequency: 8 / (2 * math.pi), base: .35, amplitude: .2);

  Color color;
  EdgeGlowStyle style;
  double inner, outer, edgeWidth;
  Color? tint;
  double tintAlpha;
  Offset? centre;

  /// Manual multiplier (0..1) on top of the envelope.
  double intensity = 1;

  double _t = 0;
  double _pulseLength = 0, _peak = 1;
  double _freq = 0, _base = 1, _amp = 0;
  bool _once = false;

  double get time => _t;

  /// One sine pulse: alpha = peak · sin(π t / length); removes itself after.
  void pulseOnce({required double length, double peak = 1}) {
    _once = true;
    _pulseLength = length;
    _peak = peak;
    _t = 0;
  }

  /// A looping pulse: alpha = base + amplitude · sin(2π f t).
  void loop({required double frequency, double base = .5, double amplitude = .5}) {
    _once = false;
    _freq = frequency;
    _base = base;
    _amp = amplitude;
    _t = 0;
  }

  /// The envelope value now (0..1, before [intensity]).
  double get envelope {
    if (_once) {
      if (_t >= _pulseLength) return 0;
      return _peak * math.sin(math.pi * _t / _pulseLength);
    }
    if (_freq == 0) return _base;
    return (_base + _amp * math.sin(2 * math.pi * _freq * _t)).clamp(0.0, 1.0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_once && _t >= _pulseLength) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = (envelope * intensity).clamp(0.0, 1.0);
    if (a <= 0) return;
    final rect = size.toRect();
    final t = tint;
    if (t != null && tintAlpha > 0) {
      canvas.drawRect(rect, Paint()..color = t.withValues(alpha: tintAlpha * a));
    }
    final c = color.withValues(alpha: color.a * a);
    switch (style) {
      case EdgeGlowStyle.radial:
        final o = centre ?? Offset(size.x / 2, size.y / 2);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = Gradient.radial(
              o,
              outer,
              [c.withValues(alpha: 0), c],
              [inner / outer, 1],
            ),
        );
      case EdgeGlowStyle.inset:
        canvas.save();
        canvas.clipRect(rect);
        canvas.drawRect(
          rect.inflate(edgeWidth / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = edgeWidth
            ..color = c
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, edgeWidth / 2),
        );
        canvas.restore();
      case EdgeGlowStyle.frame:
        canvas.drawRect(
          rect.deflate(edgeWidth / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = edgeWidth
            ..color = c,
        );
    }
  }
}
