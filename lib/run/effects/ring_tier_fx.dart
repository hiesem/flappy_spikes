import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../config/parts_config.dart';
import '../hoops/ring_painter.dart';
import 'particle_pool.dart';

/// Master #11 — the ring tier looks (PRD §3.0.9 #11, §3.5, §5.3
/// `screen_ringtiers.html` `sparkle()`), one instance per ring on screen.
///
/// * Tint: [ringColors] — pink (equipped skin) at tier 0–1, gold at tier 2,
///   bright gold at tier 3+ (via [RingPainter.colorsForTier]).
/// * Sparkles (tier 1+): four-point stars at a random point on the rim
///   (`rx · cos θ · U(0.9, 1.4)`, `ry · sin θ · U(0.95, 1.1)`), 9–15 / 10–17 /
///   12–24 pt, emitted at 7 / 16 / 38 per second, each twinkling 0.5–0.9 s;
///   tier 1–2 colours `#FFD54A`, white, `#FFE9A8`; tier 3+ adds `#FFB529`,
///   `#FF7A1A`.
/// * Flame flicks (tier 3+): half the sparkles also launch a gold/orange
///   triangle 7–12 pt wide × 1.6–2.4 tall, rising 20–45 pt (drifting 8–26 pt
///   right) while shrinking to 0.1 and fading in 0.4–0.7 s.
/// * Glow (tier 3+): a radial gold gradient ≈ 96 × 152 pt behind the ring
///   (`#FFD54Aaa → #FFB52955 → clear`), fading in over 0.25 s.
///
/// Particles are ring-local (they move with the ring, §3.5 "children of
/// each ring") and live in a small private [ParticlePool] (capped). A streak
/// break ([tier] → 0) clears everything at once. The owner of the ring calls
/// [update] and paints [paintBack] in the ring's back layer and [paintFront]
/// in its front layer, in ring-local coordinates (origin = ring centre).
class RingTierFx {
  RingTierFx({math.Random? random, this.opening = 118})
    : _r = random ?? math.Random();

  /// Per-ring particle cap (tier 3: 38/s × ≤ 0.9 s + flames ≈ 55).
  static const int capacity = 64;

  static const List<Color> _lowColors = [
    Color(0xFFFFD54A),
    Color(0xFFFFFFFF),
    Color(0xFFFFE9A8),
  ];
  static const List<Color> _highColors = [
    Color(0xFFFFD54A),
    Color(0xFFFFFFFF),
    Color(0xFFFFB529),
    Color(0xFFFF7A1A),
  ];
  static const List<Color> _flameColors = [
    Color(0xFFFFD54A),
    Color(0xFFFFB529),
    Color(0xFFFF7A1A),
  ];

  final math.Random _r;
  final ParticlePool pool = ParticlePool(capacity: capacity);

  /// The ring's opening (pt); sets the rim the sparkles sit on.
  double opening;

  int _tier = 0;
  double _acc = 0;
  double _glow = 0;

  int get tier => _tier;

  /// The streak tier (0 = none). Dropping to 0 clears every sparkle, flame
  /// and the glow at once (§3.5 streak break).
  set tier(int value) {
    final v = math.max(0, value);
    if (v == _tier) return;
    if (v < 3) _glow = 0;
    if (v == 0) {
      pool.clear();
      _acc = 0;
    }
    _tier = v;
  }

  /// Visual level 0..3 (tiers 4+ reuse tier 3).
  int get level => math.min(_tier, 3);

  /// Colour override of the ring for the current tier (null = skin).
  RingColors? get ringColors => RingPainter.colorsForTier(_tier);

  /// Glow opacity 0..1.
  double get glow => _glow;

  void update(double dt) {
    final l = level;
    if (l >= 3) {
      _glow = math.min(1, _glow + dt / PartsConfig.glowFadeIn);
    }
    if (l >= 1) {
      _acc += PartsConfig.sparkleRate[l] * dt;
      while (_acc >= 1) {
        _acc -= 1;
        _sparkle(l);
      }
    }
    pool.step(dt);
  }

  double _u(double a, double b) => a + _r.nextDouble() * (b - a);

  void _sparkle(int l) {
    final th = _r.nextDouble() * math.pi * 2;
    final ry = RingPainter.ryFor(opening);
    final px = RingPainter.rx * math.cos(th) * _u(.9, 1.4);
    final py = ry * math.sin(th) * _u(.95, 1.1);
    final (lo, hi) = PartsConfig.sparkleSize[l - 1];
    final size = _u(lo, hi).roundToDouble();
    final cols = l >= 3 ? _highColors : _lowColors;
    pool.spawn(
      shape: ParticleShape.twinkle,
      x: px,
      y: py,
      w: size,
      color: cols[_r.nextInt(cols.length)],
      life: _u(PartsConfig.sparkleLifeMin, PartsConfig.sparkleLifeMax),
    );
    if (l >= 3 && _r.nextDouble() < PartsConfig.flameChance) {
      final w = _u(PartsConfig.flameWidthMin, PartsConfig.flameWidthMax);
      final h = w * _u(PartsConfig.flameTallMin, PartsConfig.flameTallMax);
      final life = _u(PartsConfig.flameLifeMin, PartsConfig.flameLifeMax);
      pool.spawn(
        shape: ParticleShape.triangle,
        x: px,
        y: py - h / 2,
        vx: _u(8, 26) / life,
        vy: -_u(PartsConfig.flameRiseMin, PartsConfig.flameRiseMax) / life,
        w: w,
        h: h,
        color: _flameColors[_r.nextInt(3)],
        life: life,
        alpha0: .95,
        scale1: .1,
      );
    }
  }

  /// Glow sprite size for the current opening (96 × ring height + 60).
  Size get glowSize => Size(
    PartsConfig.glowWidth,
    2 * RingPainter.ryFor(opening) + (PartsConfig.glowHeight - 92),
  );

  /// The back-layer part: the tier-3 glow behind the ring.
  void paintBack(Canvas canvas) {
    if (_glow <= 0) return;
    final s = glowSize;
    final rect = Rect.fromCenter(center: Offset.zero, width: s.width, height: s.height);
    final a = _glow;
    final paint = Paint()
      ..shader = Gradient.radial(
        Offset.zero,
        s.width / 2,
        [
          Color.fromRGBO(255, 213, 74, (0xAA / 255) * a),
          Color.fromRGBO(255, 181, 41, (0x55 / 255) * a),
          const Color(0x00FFB529),
        ],
        const [0, .55, 1],
        TileMode.clamp,
        // closest-side ellipse: stretch the circle to the sprite box.
        Matrix4Ops.scaleY(s.height / s.width),
      );
    canvas.drawOval(rect, paint);
  }

  /// The front-layer part: sparkles and flame flicks.
  void paintFront(Canvas canvas) => pool.paint(canvas);

  void clear() {
    pool.clear();
    _acc = 0;
    _glow = 0;
  }
}

/// Column-major 4×4 matrices for gradient transforms.
abstract final class Matrix4Ops {
  /// Scales y by [s] (about the origin).
  static Float64List scaleY(double s) => Float64List.fromList([
    1, 0, 0, 0, //
    0, s, 0, 0, //
    0, 0, 1, 0, //
    0, 0, 0, 1, //
  ]);
}
