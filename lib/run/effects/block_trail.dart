import 'dart:math' as math;
import 'dart:ui';

import '../config/parts_config.dart';
import 'particle_pool.dart';

/// Master #10 — the block trail (PRD §3.0.9 #10, §5.3 trail + the rides'
/// direction rule): one 8–13 pt square every ≈ 33 ms (30/s), 50/50 gold /
/// pink, spawned 26 pt behind the bird **along its flight direction** (± 8 pt
/// sideways) and drifting 70 pt **opposite** to the flight direction while
/// its opacity falls 0.9 → 0 in 450 ms. With [heading] 0 (level flight to
/// the right) this is exactly the 5.3 mock: spawn at x − 26, drift 70 pt
/// left; diagonal and curved flight (rides, launch flight, glide, comet)
/// bends the trail with the heading.
///
/// Stateful only for the emission accumulator; the squares live in the
/// shared [ParticlePool]. Density is fixed (not a parameter).
class BlockTrail {
  BlockTrail({math.Random? random}) : _r = random ?? math.Random();

  final math.Random _r;
  double _acc = 0;

  static const List<Color> colors = [PartsConfig.gold, PartsConfig.pink];

  /// Resets the emission phase (a trail that switches off and on again
  /// starts with a fresh block budget).
  void reset() => _acc = 0;

  /// Emits for [dt] seconds behind a bird at [bird] flying along [heading]
  /// (radians, 0 = right, y down). Returns the number of blocks spawned.
  /// PRD-2.2 §21.1: [scale] multiplies the block size (the run trail draws
  /// it at 2×) and [back] is the spawn distance behind the bird.
  int update(
    ParticlePool pool,
    double dt,
    Offset bird,
    double heading, {
    double scale = 1,
    double back = PartsConfig.trailBack,
  }) {
    if (dt <= 0) return 0;
    _acc += dt * PartsConfig.trailRate;
    var n = 0;
    final hx = math.cos(heading), hy = math.sin(heading);
    const v = PartsConfig.trailDrift / PartsConfig.trailLife;
    while (_acc >= 1) {
      _acc -= 1;
      final j = (_r.nextDouble() * 2 - 1) * PartsConfig.trailSide;
      final size = scale *
          (PartsConfig.trailSizeMin +
              _r.nextDouble() *
                  (PartsConfig.trailSizeMax - PartsConfig.trailSizeMin));
      final p = pool.spawn(
        x: bird.dx - hx * back - hy * j,
        y: bird.dy - hy * back + hx * j,
        vx: -hx * v,
        vy: -hy * v,
        w: size,
        color: _r.nextBool() ? colors[0] : colors[1],
        life: PartsConfig.trailLife,
        alpha0: PartsConfig.trailAlpha,
      );
      if (p != null) n++;
    }
    return n;
  }
}
