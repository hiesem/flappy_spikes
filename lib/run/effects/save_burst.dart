import 'dart:math' as math;
import 'dart:ui';

import '../config/lives_config.dart';
import 'particle_pool.dart';

/// The §5.5 save burst (PRD-2 §3.3 / §3.7): what a save looks like at the
/// bird — the extra-life badge popping into small hearts, the shield
/// shattering into triangles. Pure spawns into the shared [ParticlePool].
abstract final class SaveBurst {
  /// §5.5 hit burst at the bird ([at], the pool's coordinates): a white
  /// flash disc (80 pt, 0.5 → 1.6, 0.8 → 0 in 0.26 s) and 12 shards that
  /// fly 60–110 pt out (+20 pt up), spin and fade over 0.62 s — small hearts
  /// for the extra life (starting 20 pt above the bird), gold / pink
  /// triangles for the shield.
  static void emit(
    ParticlePool pool,
    Offset at,
    math.Random r, {
    required bool hearts,
  }) {
    pool.spawn(
      shape: ParticleShape.circle,
      x: at.dx,
      y: at.dy,
      w: 2 * LivesConfig.hitFlashRadius,
      color: const Color(0xFFFFFFFF),
      life: LivesConfig.hitFlashLength,
      alpha0: .8,
      scale0: .5,
      scale1: 1.6,
    );
    final y0 = at.dy - (hearts ? LivesConfig.shardRise : 0);
    const life = LivesConfig.shardLife;
    for (var i = 0; i < LivesConfig.shards; i++) {
      final a = i / LivesConfig.shards * math.pi * 2;
      final d =
          LivesConfig.shardDistMin +
          r.nextDouble() *
              (LivesConfig.shardDistMax - LivesConfig.shardDistMin);
      final spin = (r.nextDouble() * 2 - 1) * 2 * math.pi / life;
      pool.spawn(
        shape: hearts ? ParticleShape.heart : ParticleShape.triangle,
        x: at.dx,
        y: y0,
        vx: math.cos(a) * d / life,
        vy: (math.sin(a) * d - LivesConfig.shardRise) / life,
        w: LivesConfig.shardSize,
        color: hearts
            ? LivesConfig.heartRed
            : (i.isOdd ? const Color(0xFFFFB529) : const Color(0xFFEC008C)),
        life: life,
        spin: spin,
      );
    }
  }
}
