import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../run_context.dart';
import '../run_layers.dart';
import 'particle_pool.dart';
import 'run_shake.dart';

/// The collectables' screen-space bursts (PRD-2 §5.26 hatch, §5.27 piggy
/// smash, §5.28 jar full). The mock's `burst()` throws [pieces] pieces from
/// [at] in random directions at `speed × (0.4 … 1.2)`, size 3…7, for 0.6 s
/// with a linear fade. Positions are screen coordinates, so the owner adds
/// this to `game.world` (never a track layer).
class CollectBursts extends Component {
  CollectBursts() : super(priority: RunLayer.fx);

  final ParticlePool pool = ParticlePool(capacity: 40);

  /// §5.26–§5.28 one burst. [shape] `rect` is the mock default (`sq`),
  /// `triangle` the hatch shell, `circle` the jar's dots.
  void burst({
    required Offset at,
    required List<Color> colors,
    required int pieces,
    required double speed,
    ParticleShape shape = ParticleShape.rect,
    double sizeMin = 3,
    double sizeMax = 7,
    double life = .6,
  }) {
    final r = math.Random();
    for (var i = 0; i < pieces; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final s = speed * (.4 + r.nextDouble() * .8);
      final size = sizeMin + r.nextDouble() * (sizeMax - sizeMin);
      final (w, h) = switch (shape) {
        ParticleShape.circle => (2 * size, 2 * size),
        ParticleShape.triangle => (1.2 * size, 1.5 * size),
        _ => (size, size),
      };
      pool.spawn(
        shape: shape,
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * s,
        vy: math.sin(a) * s,
        w: w,
        h: h,
        color: colors[i % colors.length],
        life: life,
      );
    }
  }

  @override
  void update(double dt) => pool.step(dt);

  @override
  void render(Canvas canvas) => pool.paint(canvas);
}

/// One decaying world shake (PRD-2 §5.27 the piggy smash's 4 pt camera
/// kick). Applies the [RunShake] offset to the camera as a delta, so it
/// composes with the FEVER / squeeze shakes, and puts the camera back when
/// it is done — the `FeverShake` pattern (WP-3c), reused instead of copied
/// per feature.
class CollectShake extends Component {
  CollectShake(this.c, {double amplitude = 4, double decay = 20})
    : _shake = RunShake(random: c.cosmetic)..kick(amplitude, decay: decay);

  final RunContext c;
  final RunShake _shake;
  Offset _applied = Offset.zero;

  @override
  void update(double dt) {
    _shake.update(dt);
    final o = _shake.offset;
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position + Vector2(o.dx - _applied.dx, o.dy - _applied.dy);
    _applied = o;
    if (!_shake.active) removeFromParent();
  }

  @override
  void onRemove() {
    final vf = c.game.camera.viewfinder;
    vf.position = vf.position - Vector2(_applied.dx, _applied.dy);
    _applied = Offset.zero;
    super.onRemove();
  }
}
