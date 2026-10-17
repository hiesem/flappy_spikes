import 'dart:math' as math;

import '../../game/sound.dart';
import '../config/capsule_config.dart';
import '../config/run_config.dart';
import '../effects/easing.dart';
import '../effects/particle_pool.dart';
import '../run_state.dart';
import 'timed_powerup.dart';

/// Mini Bird (PRD-2 §3.31, §5.30): a shrink potion makes the bird 52 % for
/// 8 s. `RunState.birdScale` eases 1 → 0.52 over 0.15 s; the hitbox shrinks
/// with it (rims, spike strips, pickups — every plain-math contact reads
/// `RunConfig.birdRadius × birdScale`), and the drawn bird
/// (`LookComponent.scale`) follows. Physics are unchanged. At the end it
/// pops back to full size over 0.15 s (a rim touched while growing bounces
/// as usual — the growing radius is the collider).
///
/// Feedback: purple sparkles pull into the bird as it shrinks, little
/// bubbles trail from it while small, a pop and a green / purple / white
/// burst when it grows back; rising bubble blips + a falling whistle on
/// start, a rising whistle + pop at the end.
///
/// A portal ride pauses it: the ride drives the drawn bird's scale itself,
/// so the bird is full size (radius and look) for the ride and shrinks
/// again after the landing. A death puts it back to full size at once.
class MiniBirdFeature extends TimedPowerupEffect {
  @override
  TimedPowerup get type => TimedPowerup.mini;

  /// The scale this feature writes (1 = full size).
  double scale = 1;
  double _from = 1, _to = 1, _easeT = 1, _easeLen = CapsuleConfig.miniShrink;

  /// True while this feature owns the bird's scale (active or growing
  /// back).
  bool owning = false;

  double _bubbleAcc = 0;

  void _easeTo(double target, double length) {
    _from = scale;
    _to = target;
    _easeT = 0;
    _easeLen = length;
  }

  void _write({bool look = true}) {
    final ctx = c;
    if (ctx == null) return;
    ctx.s.birdScale = scale;
    if (!look || ctx.s.ride != null) return;
    final bird = ctx.game.runBird;
    if (bird != null && bird.isLoaded && !bird.inRide) {
      bird.lookComponent.scale.setValues(scale, scale);
    }
  }

  @override
  void onStart() {
    final ctx = c!;
    owning = true;
    _bubbleAcc = 0;
    _easeTo(RunConfig.miniBirdScale, CapsuleConfig.miniShrink);
    ctx.sfx(Sfx.miniStart);
    _sparkles();
  }

  /// §5.30 12 purple sparkles pull into the bird from 30 pt away.
  void _sparkles() {
    final ctx = c;
    final pos = ctx?.run.birdTrackPosition();
    if (ctx == null || pos == null) return;
    final r = ctx.cosmetic;
    const n = CapsuleConfig.miniSparkles;
    const from = CapsuleConfig.miniSparkleFrom;
    const life = CapsuleConfig.miniSparkleLife;
    for (var i = 0; i < n; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      ctx.run.particles.spawn(
        shape: ParticleShape.circle,
        x: pos.x + math.cos(a) * from,
        y: pos.y + math.sin(a) * from,
        // Inward over the life, riding along with the bird.
        vx: -math.cos(a) * from / life + ctx.s.forwardSpeed,
        vy: -math.sin(a) * from / life,
        w: CapsuleConfig.miniSparkleSize,
        color: CapsuleConfig.potionPurple,
        life: life,
        scale1: .4,
      );
    }
  }

  @override
  void onPause() {
    // The ride draws the bird at its own scale; full-size collider.
    scale = 1;
    _from = _to = 1;
    _easeT = 1;
    _write(look: false);
  }

  @override
  void onResume() {
    _easeTo(RunConfig.miniBirdScale, CapsuleConfig.miniShrink);
  }

  @override
  void onEnd({required bool death}) {
    final ctx = c;
    if (death || ctx == null) {
      reset();
      return;
    }
    _easeTo(1, CapsuleConfig.miniGrow);
    ctx.sfx(Sfx.miniEnd);
    _burst();
  }

  /// §5.30 the pop: a green / purple / white burst as it grows back.
  void _burst() {
    final ctx = c;
    final pos = ctx?.run.birdTrackPosition();
    if (ctx == null || pos == null) return;
    final r = ctx.cosmetic;
    const cols = CapsuleConfig.miniBurstColors;
    for (var i = 0; i < CapsuleConfig.miniBurst; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final v = CapsuleConfig.miniBurstSpeed * (.4 + r.nextDouble() * .8);
      ctx.run.particles.spawn(
        x: pos.x,
        y: pos.y,
        vx: math.cos(a) * v + ctx.s.forwardSpeed,
        vy: math.sin(a) * v,
        w: 3 + r.nextDouble() * 4,
        color: cols[i % cols.length],
        life: .6,
      );
    }
  }

  @override
  void step(double gameDt, double realDt) {
    final ctx = c;
    if (ctx == null || !owning) return;
    if (_easeT < 1) {
      _easeT = math.min(1, _easeT + realDt / _easeLen);
      scale = _from + (_to - _from) * Ease.cubicInOut(_easeT);
    }
    _write();
    // Audit HIDE: no bubbles from a hidden bird.
    if (on && ctx.s.ride == null && scale < 1 && ctx.game.runBirdPresented) {
      _bubbleAcc += realDt * CapsuleConfig.bubbleRate;
      final pos = ctx.run.birdTrackPosition();
      final r = ctx.cosmetic;
      while (_bubbleAcc >= 1) {
        _bubbleAcc -= 1;
        if (pos == null) continue;
        ctx.run.particles.spawn(
          shape: ParticleShape.circle,
          x: pos.x - 6 + (r.nextDouble() - .5) * 10,
          y: pos.y - 6,
          vx: CapsuleConfig.bubbleVx + ctx.s.forwardSpeed,
          vy: CapsuleConfig.bubbleVy,
          w: 2 * (1.6 + r.nextDouble() * 1.6),
          color: CapsuleConfig.bubble,
          life: CapsuleConfig.bubbleLife,
        );
      }
    }
    if (!active && _easeT >= 1 && scale == 1) owning = false;
  }

  @override
  void reset() {
    final ctx = c;
    if (owning && ctx != null) {
      scale = 1;
      _from = _to = 1;
      _easeT = 1;
      _write();
    }
    scale = 1;
    owning = false;
  }
}
