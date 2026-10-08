import 'dart:math' as math;
import 'dart:ui';

import '../config/parts_config.dart';
import 'easing.dart';
import 'particle_pool.dart';

/// Parameters of one pickup's touch effect.
class PickupTouchSpec {
  const PickupTouchSpec({
    this.flashFrom = 0,
    this.flashTo = 0,
    this.flashLength = 0,
    this.ringFrom = 0,
    this.ringTo = 0,
    this.ringStroke = 3,
    this.ringLength = 0,
    this.ringEase = true,
    this.ringColor = PartsConfig.gold,
    this.squares = 0,
    this.squareMin = 5,
    this.squareMax = 9,
    this.speedMin = 90,
    this.speedMax = 200,
    this.damp = 2.45,
    this.spin = 8,
    this.lifeMin = .35,
    this.lifeMax = .55,
    this.colors = const [PartsConfig.pink, PartsConfig.gold, PartsConfig.softPink],
  });

  /// White flash disc radius from → to (pt) over [flashLength] (s); 0 = none.
  final double flashFrom, flashTo, flashLength;

  /// Ring radius from → to (pt), stroke, length (s); [ringEase] = cubic
  /// in-out radius (`eio`), else linear. 0 length = none.
  final double ringFrom, ringTo, ringStroke, ringLength;
  final bool ringEase;
  final Color ringColor;

  /// Squares: count, size range, speed range (pt/s), damping (1/s), spin
  /// (± rad/s), life range (s), colours (cycled by index).
  final int squares;
  final double squareMin, squareMax, speedMin, speedMax, damp, spin;
  final double lifeMin, lifeMax;
  final List<Color> colors;

  double get length => math.max(flashLength, ringLength);

  /// §5.14 feather (`collect.js burst()`).
  static const PickupTouchSpec feather = PickupTouchSpec(
    flashFrom: 8,
    flashTo: 30,
    flashLength: .22,
    ringFrom: 8,
    ringTo: 34,
    ringStroke: 3,
    ringLength: .45,
    squares: 9,
  );

  /// §5.15 puzzle piece (`collect4.js burst()`). The odd squares take the
  /// round's body colour — pass it with [withBodyColor].
  static const PickupTouchSpec puzzlePiece = PickupTouchSpec(
    flashFrom: 10,
    flashTo: 40,
    flashLength: .25,
    ringFrom: 10,
    ringTo: 52,
    ringStroke: 3.5,
    ringLength: .5,
    squares: 16,
    squareMin: 5,
    squareMax: 10,
    speedMin: 100,
    speedMax: 230,
    damp: 3.08,
    lifeMin: .35,
    lifeMax: .6,
  );

  /// §5.19 switch (flash 8 → 30, gold ring 8 → 34, 0.5 s, 9 squares).
  static const PickupTouchSpec switchTouch = PickupTouchSpec(
    flashFrom: 8,
    flashTo: 30,
    flashLength: .23,
    ringFrom: 8,
    ringTo: 34,
    ringStroke: 3,
    ringLength: .5,
    ringEase: false,
    squares: 9,
  );

  /// §5.2 / §5.5 heart and shield pickups: one gold ring (80 pt circle,
  /// 5 pt, scale 0.3 → 2, 450 ms linear); no flash, no squares.
  static const PickupTouchSpec heart = PickupTouchSpec(
    ringFrom: 12,
    ringTo: 80,
    ringStroke: 5,
    ringLength: .45,
    ringEase: false,
  );

  /// §5.5 shield pickup (same as the heart).
  static const PickupTouchSpec shield = heart;

  /// §3.30–3.32 capsules: 18 squares in the powerup colour and white
  /// (`lab_engine.js burst()`); pass the colour with [withBodyColor].
  static const PickupTouchSpec capsule = PickupTouchSpec(
    squares: 18,
    squareMin: 3,
    squareMax: 7,
    speedMin: 72,
    speedMax: 216,
    damp: 0,
    spin: 0,
    lifeMin: .6,
    lifeMax: .6,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  /// A copy whose odd squares use [body] (puzzle round colour, capsule).
  PickupTouchSpec withBodyColor(Color body) => PickupTouchSpec(
    flashFrom: flashFrom,
    flashTo: flashTo,
    flashLength: flashLength,
    ringFrom: ringFrom,
    ringTo: ringTo,
    ringStroke: ringStroke,
    ringLength: ringLength,
    ringEase: ringEase,
    ringColor: ringColor,
    squares: squares,
    squareMin: squareMin,
    squareMax: squareMax,
    speedMin: speedMin,
    speedMax: speedMax,
    damp: damp,
    spin: spin,
    lifeMin: lifeMin,
    lifeMax: lifeMax,
    colors: [
      for (var i = 0; i < math.max(2, colors.length); i++)
        i.isOdd ? body : colors[i % colors.length],
    ],
  );
}

/// The shared pickup touch effect (ARCH §3 "PickupTouchFx"): a white flash
/// disc, a gold ring and a square burst at the pickup — feather, puzzle
/// piece, switch, heart, shield, capsule ([PickupTouchSpec] presets). The
/// flash and ring are drawn by this pooled component, the squares go to the
/// shared [ParticlePool].
class PickupTouchFx extends PooledEffect {
  PickupTouchFx({super.priority});

  static EffectPool<PickupTouchFx> newPool() => EffectPool(PickupTouchFx.new);

  PickupTouchSpec spec = PickupTouchSpec.feather;

  @override
  double get duration => spec.length;

  /// Starts at [at]; squares are spawned into [pool] (when given).
  PickupTouchFx play(
    Offset at,
    PickupTouchSpec spec, {
    ParticlePool? pool,
    math.Random? random,
  }) {
    this.spec = spec;
    position.setValues(at.dx, at.dy);
    restart();
    if (pool != null) emitSquares(pool, at, spec, random ?? math.Random());
    return this;
  }

  /// The square part on its own (e.g. the capsule, which has no flash).
  static int emitSquares(
    ParticlePool pool,
    Offset at,
    PickupTouchSpec spec,
    math.Random r,
  ) {
    var n = 0;
    double u(double a, double b) => a + r.nextDouble() * (b - a);
    for (var i = 0; i < spec.squares; i++) {
      final a = r.nextDouble() * math.pi * 2;
      final v = u(spec.speedMin, spec.speedMax);
      final p = pool.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: u(spec.squareMin, spec.squareMax),
        color: spec.colors[i % spec.colors.length],
        life: u(spec.lifeMin, spec.lifeMax),
        damp: spec.damp,
        spin: u(-spec.spin, spec.spin),
        fadePow: 2,
      );
      if (p != null) n++;
    }
    return n;
  }

  /// Flash radius and alpha at [t] seconds (null after the flash).
  (double, double)? flashAt(double t) {
    if (spec.flashLength <= 0 || t >= spec.flashLength) return null;
    final u = t / spec.flashLength;
    return (spec.flashFrom + (spec.flashTo - spec.flashFrom) * u, 1 - u);
  }

  /// Ring radius and alpha at [t] seconds (null after the ring).
  (double, double)? ringAt(double t) {
    if (spec.ringLength <= 0 || t >= spec.ringLength) return null;
    final u = t / spec.ringLength;
    final e = spec.ringEase ? Ease.cubicInOut(u) : u;
    return (spec.ringFrom + (spec.ringTo - spec.ringFrom) * e, 1 - u);
  }

  final Paint _fill = Paint();
  final Paint _ring = Paint()..style = PaintingStyle.stroke;

  @override
  void renderAt(Canvas canvas, double k) {
    final t = time;
    final f = flashAt(t);
    if (f != null) {
      _fill.color = Color.fromRGBO(255, 255, 255, f.$2.clamp(0.0, 1.0));
      canvas.drawCircle(Offset.zero, f.$1, _fill);
    }
    final r = ringAt(t);
    if (r != null) {
      _ring
        ..strokeWidth = spec.ringStroke
        ..color = spec.ringColor.withValues(alpha: r.$2.clamp(0.0, 1.0));
      canvas.drawCircle(Offset.zero, r.$1, _ring);
    }
  }
}
