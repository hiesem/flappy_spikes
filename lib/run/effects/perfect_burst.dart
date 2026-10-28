import 'dart:math' as math;
import 'dart:ui';

import '../config/parts_config.dart';
import 'particle_pool.dart';

/// Master #9 — the perfect-pass small burst (PRD §3.0.9 #9, §5.3 `pop`):
/// 8 + 3 × min(tier, 3) flat squares (11 / 14 / 17), 5–8 pt, cycling pink /
/// gold / soft pink, each flying 25–55 pt in a random direction and fading
/// out linearly in 350–600 ms. No rotation, no shockwave ring.
///
/// Used by every perfect pass (normal play, comet, portal, rides). The only
/// parameters are the tier and the position.
abstract final class PerfectBurst {
  static const List<Color> colors = [
    PartsConfig.pink,
    PartsConfig.gold,
    PartsConfig.softPink,
  ];

  /// Squares for a pass at [tier] (≥ 1).
  static int countFor(int tier) =>
      PartsConfig.burstBase +
      PartsConfig.burstPerTier * math.min(math.max(tier, 1), 3);

  /// Spawns the burst into [pool] centred at [at]; returns the number of
  /// squares actually spawned (fewer when the pool is full).
  static int emit(
    ParticlePool pool,
    Offset at,
    int tier,
    math.Random r, {
    List<Color> palette = colors,
  }) {
    final n = countFor(tier);
    var spawned = 0;
    for (var i = 0; i < n; i++) {
      final a = r.nextDouble() * math.pi * 2;
      final d = _range(r, PartsConfig.burstDistMin, PartsConfig.burstDistMax);
      final life = _range(
        r,
        PartsConfig.burstLifeMin,
        PartsConfig.burstLifeMax,
      );
      final size = _range(
        r,
        PartsConfig.burstSizeMin,
        PartsConfig.burstSizeMax,
      );
      final p = pool.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * d / life,
        vy: math.sin(a) * d / life,
        w: size,
        h: _range(r, PartsConfig.burstSizeMin, PartsConfig.burstSizeMax),
        color: palette[i % palette.length],
        life: life,
      );
      if (p != null) spawned++;
    }
    return spawned;
  }

  static double _range(math.Random r, double a, double b) =>
      a + r.nextDouble() * (b - a);
}
