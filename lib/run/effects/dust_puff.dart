import 'dart:math' as math;
import 'dart:ui';

import '../config/parts_config.dart';
import 'particle_pool.dart';

/// Shared dust / feather puff (PRD §3.0.9 "Dust / feather puff", master =
/// the space ride's Mars dust, `rides84.js dust()`): 12–22 soft round
/// particles, radius 4–9 pt, in the surface colour (spikes: the stage
/// foreground; feathers: the bird colour). Each flies at ±140 pt/s sideways
/// and 10–90 pt/s up, slows down (vx × (1 − 2 dt), +60 pt/s² down) and fades
/// from 0.8 to 0 in 0.6–1 s.
///
/// Used by the death-tumble bounces (§3.0.5) and landings. Parameters:
/// colour, count, position.
abstract final class DustPuff {
  static int emit(
    ParticlePool pool,
    Offset at,
    Color color,
    math.Random r, {
    int count = PartsConfig.dustCount,
  }) {
    var spawned = 0;
    for (var i = 0; i < count; i++) {
      final radius = _range(r, PartsConfig.dustSizeMin, PartsConfig.dustSizeMax);
      final p = pool.spawn(
        shape: ParticleShape.circle,
        x: at.dx,
        y: at.dy,
        vx: _range(r, -PartsConfig.dustVx, PartsConfig.dustVx),
        vy: _range(r, PartsConfig.dustVyMin, PartsConfig.dustVyMax),
        w: radius * 2,
        color: color,
        life: _range(r, PartsConfig.dustLifeMin, PartsConfig.dustLifeMax),
        alpha0: PartsConfig.dustAlpha,
        gravity: PartsConfig.dustGravity,
        drag: PartsConfig.dustDrag,
      );
      if (p != null) spawned++;
    }
    return spawned;
  }

  static double _range(math.Random r, double a, double b) =>
      a + r.nextDouble() * (b - a);
}
