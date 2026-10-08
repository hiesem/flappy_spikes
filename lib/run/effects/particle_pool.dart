import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/parts_config.dart';
import 'life_icons.dart';
import 'twinkle.dart';

/// Shapes the shared pool can draw (flat, no textures — §5.4).
enum ParticleShape {
  /// Axis-aligned square/rectangle [Particle.w] × [Particle.h], centred.
  rect,

  /// Disc of diameter [Particle.w] (dust / feather puff).
  circle,

  /// Upward triangle [Particle.w] wide, [Particle.h] tall; the anchor is
  /// the base centre's opposite corner — i.e. it is centred like [rect].
  triangle,

  /// Four-point [Twinkle] star of size [Particle.w] that follows the §5.3
  /// twinkle curve (scale 0 → 1.1 → 0, 0° → 90°, opacity 0 → 1 → 0).
  twinkle,

  /// The §5.2 heart ([LifeIcons.heart24]) [Particle.w] wide, rotating with
  /// [Particle.rot] (the extra-life badge's pop, §5.5; WP-2a).
  heart,
}

/// One pooled particle. Plain mutable data, recycled in place.
class Particle {
  ParticleShape shape = ParticleShape.rect;
  double x = 0, y = 0, vx = 0, vy = 0;
  double w = 0, h = 0;

  /// Rotation (rad) and spin (rad/s).
  double rot = 0, spin = 0;
  Color color = const Color(0xFFFFFFFF);

  /// Age and lifetime (s). A particle with `t < 0` is delayed (not drawn).
  double t = 0, life = 1;

  /// Opacity and scale, interpolated linearly over the life.
  double alpha0 = 1, alpha1 = 0, scale0 = 1, scale1 = 1;

  /// Vertical acceleration (pt/s²) and horizontal slow-down (1/s).
  double gravity = 0, drag = 0;

  /// Exponential damping of both velocity axes (1/s): v × e^(−damp·dt). The
  /// mocks' per-frame `v *= .96` at 60 fps is `damp ≈ 2.45`.
  double damp = 0;

  /// Opacity curve exponent: alpha = a0 + (a1 − a0) · k^fadePow (2 = the
  /// mocks' `1 − u²`).
  double fadePow = 1;

  double get k => life <= 0 ? 1 : (t / life).clamp(0.0, 1.0);
}

/// The shared run particle pool (ARCH §3 "Particle pool"): bursts, trails,
/// dust, shards and sparks all live in one fixed-capacity array that is
/// recycled in place, so the steady state allocates nothing and the number
/// alive is capped ([PartsConfig.maxParticles] ≈ 130, §5.4). When full, new
/// spawns are dropped (cosmetic only).
///
/// It is a [Component]: mount it in the layer the effects should live in
/// (`RunTrack.fx` for world effects, the HUD for screen effects); the
/// coordinates are that parent's local coordinates. [step] / [paint] can
/// also be driven by hand (ring-local pools in `RingTierFx`).
class ParticlePool extends Component {
  ParticlePool({this.capacity = PartsConfig.maxParticles, super.priority})
    : _items = List.generate(capacity, (_) => Particle(), growable: false);

  final int capacity;
  final List<Particle> _items;
  int _alive = 0;

  /// Freezes the pool (debug freeze, pause screens).
  bool frozen = false;

  int get alive => _alive;

  /// The live particles (index 0 .. [alive] − 1), for tests.
  Iterable<Particle> get particles => _items.take(_alive);

  /// Claims a particle with default values, or `null` when the pool is full.
  Particle? spawn({
    ParticleShape shape = ParticleShape.rect,
    required double x,
    required double y,
    double vx = 0,
    double vy = 0,
    required double w,
    double? h,
    required Color color,
    required double life,
    double delay = 0,
    double alpha0 = 1,
    double alpha1 = 0,
    double scale0 = 1,
    double scale1 = 1,
    double rot = 0,
    double spin = 0,
    double gravity = 0,
    double drag = 0,
    double damp = 0,
    double fadePow = 1,
  }) {
    if (_alive >= capacity) return null;
    final p = _items[_alive++]
      ..shape = shape
      ..x = x
      ..y = y
      ..vx = vx
      ..vy = vy
      ..w = w
      ..h = h ?? w
      ..color = color
      ..life = life
      ..t = -delay
      ..alpha0 = alpha0
      ..alpha1 = alpha1
      ..scale0 = scale0
      ..scale1 = scale1
      ..rot = rot
      ..spin = spin
      ..gravity = gravity
      ..drag = drag
      ..damp = damp
      ..fadePow = fadePow;
    return p;
  }

  void clear() => _alive = 0;

  /// Advances every particle by [dt] and recycles the finished ones
  /// (swap-remove, so live particles stay contiguous).
  void step(double dt) {
    var i = 0;
    while (i < _alive) {
      final p = _items[i];
      final wasDelayed = p.t < 0;
      p.t += dt;
      if (p.t >= p.life) {
        _alive--;
        _items[i] = _items[_alive];
        _items[_alive] = p;
        continue;
      }
      if (!wasDelayed || p.t > 0) {
        final d = wasDelayed ? p.t : dt;
        p.vy += p.gravity * d;
        if (p.drag != 0) p.vx *= math.max(0, 1 - p.drag * d);
        if (p.damp != 0) {
          final f = math.exp(-p.damp * d);
          p.vx *= f;
          p.vy *= f;
        }
        p.x += p.vx * d;
        p.y += p.vy * d;
        p.rot += p.spin * d;
      }
      i++;
    }
  }

  final Paint _paint = Paint();
  final Path _tri = Path();

  void paint(Canvas canvas) {
    for (var i = 0; i < _alive; i++) {
      final p = _items[i];
      if (p.t < 0) continue;
      final k = p.k;
      if (p.shape == ParticleShape.twinkle) {
        final (s, a, o) = Twinkle.curve(k);
        Twinkle.paint(
          canvas,
          Offset(p.x, p.y),
          p.w * s,
          p.color.withValues(alpha: p.color.a * o),
          rotation: p.rot + a,
        );
        continue;
      }
      final kf = p.fadePow == 1 ? k : math.pow(k, p.fadePow).toDouble();
      final alpha = p.alpha0 + (p.alpha1 - p.alpha0) * kf;
      if (alpha <= 0) continue;
      final s = p.scale0 + (p.scale1 - p.scale0) * k;
      final w = p.w * s, h = p.h * s;
      _paint.color = p.color.withValues(alpha: p.color.a * alpha.clamp(0, 1));
      switch (p.shape) {
        case ParticleShape.rect:
          if (p.rot == 0) {
            canvas.drawRect(
              Rect.fromCenter(center: Offset(p.x, p.y), width: w, height: h),
              _paint,
            );
          } else {
            canvas
              ..save()
              ..translate(p.x, p.y)
              ..rotate(p.rot)
              ..drawRect(
                Rect.fromCenter(center: Offset.zero, width: w, height: h),
                _paint,
              )
              ..restore();
          }
        case ParticleShape.circle:
          canvas.drawCircle(Offset(p.x, p.y), w / 2, _paint);
        case ParticleShape.triangle:
          _tri
            ..reset()
            ..moveTo(0, -h / 2)
            ..lineTo(w / 2, h / 2)
            ..lineTo(-w / 2, h / 2)
            ..close();
          canvas
            ..save()
            ..translate(p.x, p.y)
            ..rotate(p.rot)
            ..drawPath(_tri, _paint)
            ..restore();
        case ParticleShape.twinkle:
          break;
        case ParticleShape.heart:
          LifeIcons.paintHeart(
            canvas,
            Offset(p.x, p.y),
            w,
            fill: _paint.color,
            rotation: p.rot,
          );
      }
    }
  }

  @override
  void update(double dt) {
    if (!frozen) step(dt);
  }

  @override
  void render(Canvas canvas) => paint(canvas);
}

/// A timed one-shot effect component that can be recycled by an
/// [EffectPool] (ARCH §3 "pool the effects"). Subclasses implement
/// [renderAt] for their normalised time and call [restart] from their
/// `play`-style setter.
abstract class PooledEffect extends PositionComponent {
  PooledEffect({super.priority});

  /// Seconds since start (negative = waiting for its delay).
  double time = 0;

  /// Total length in seconds (excluding delay).
  double get duration;

  /// Called when the effect ends; the pool hooks it to recycle.
  void Function(PooledEffect e)? onDone;

  bool get done => time >= duration;

  /// 0..1 progress (0 while delayed).
  double get progress => duration <= 0 ? 1 : (time / duration).clamp(0.0, 1.0);

  void restart({double delay = 0}) => time = -delay;

  @override
  void update(double dt) {
    super.update(dt);
    time += dt;
    if (done) {
      final cb = onDone;
      if (cb != null) {
        cb(this);
      } else {
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (time < 0) return;
    renderAt(canvas, progress);
  }

  void renderAt(Canvas canvas, double k);
}

/// Free list of finished [PooledEffect]s of one type. `obtain` reuses a
/// finished instance (or builds one with the factory) and the effect returns
/// itself on finish, so popups / shock rings stop allocating after warm-up.
class EffectPool<T extends PooledEffect> {
  EffectPool(this._create, {this.maxFree = 8});

  final T Function() _create;
  final int maxFree;
  final List<T> _free = [];

  int get freeCount => _free.length;

  /// A ready instance, not mounted; the caller configures and adds it.
  T obtain() {
    final e = _free.isNotEmpty ? _free.removeLast() : _create();
    e.onDone = _release;
    return e;
  }

  void _release(PooledEffect e) {
    e.removeFromParent();
    if (_free.length < maxFree) _free.add(e as T);
  }
}
