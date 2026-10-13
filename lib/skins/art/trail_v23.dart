import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'ctx2d.dart';
import 'shapes.dart';

/// PRD-2.3 §19.2 / §19.4: the 15 new trails, a 1:1 port of
/// `design/skins_v23/parts/trails.js` (T1–T15; app id = page id without
/// `n_`). Emit / step / draw as `trailEmit` / `trailStep` / `trailDraw`:
/// particles move with the scroll (`st.vx = vx · k / 2`), sizes and speeds
/// in the page's particle unit `k / 2`, the same spawn rates (each with its
/// own accumulator, at most 6 spawns per frame), particle counts, colours
/// and timings. Path-history trails (Prism, Paint stroke) keep `st.hist`.
/// Randomness comes from the owning [TrailEmitter]'s seeded [math.Random].
///
/// Pooled: particles are recycled in place (capacity [capacity]), the path
/// history is a fixed ring, so a steady stream allocates nothing.
final class TrailV23 {
  TrailV23(this.id, this._random) {
    for (var i = 0; i < capacity; i++) {
      _pool.add(_P());
    }
  }

  /// The new trail ids in tag order (T1–T15).
  static const List<String> ids = [
    'sunset', 'leaves', 'snow', 'petals', 'ink', //
    'planes', 'popcorn', 'fireworks', 'steps', 'fish',
    'galaxy', 'prism', 'lavadrip', 'supernova', 'paint',
  ];

  /// The shop tile's head-dot colour of each trail (the page's `dot`).
  static const Map<String, Color> dots = {
    'sunset': Color(0xFFFF7A3D),
    'leaves': Color(0xFF7CB342),
    'snow': Color(0xFF4FC3F7),
    'petals': Color(0xFFFF80AB),
    'ink': Color(0xFF311B92),
    'planes': Color(0xFF4FC3F7),
    'popcorn': Color(0xFFFFD54F),
    'fireworks': Color(0xFFFFB529),
    'steps': artPlum,
    'fish': Color(0xFFFF7043),
    'galaxy': Color(0xFFB388FF),
    'prism': Color(0xFFB2EBF2),
    'lavadrip': Color(0xFFFF6D00),
    'supernova': Color(0xFFFFE57F),
    'paint': artPink,
  };

  static final Set<String> _set = ids.toSet();

  /// Whether [id] is one of the 2.3 trails.
  static bool has(String id) => _set.contains(id);

  /// Pool size (same bound as the 2.0 trails).
  static const int capacity = 512;
  static const int _histSize = 90;

  final String id;
  final math.Random _random;
  final List<_P> _pool = [];
  int _alive = 0;

  /// `st.vx` (the scroll drift, px/s).
  double _vx = 0;

  /// `st.T` (Prism / Supernova / Paint clocks).
  double _clock = 0;

  /// `st.f` (Footprints: which foot).
  bool _f = false;
  final Float64List _acc = Float64List(3);

  final Float64List _hx = Float64List(_histSize);
  final Float64List _hy = Float64List(_histSize);
  final Float64List _hr = Float64List(_histSize);
  final Float64List _hc = Float64List(_histSize);
  int _hHead = 0, _hCount = 0;

  int get particleCount => _alive;

  /// Path-history points (Prism, Paint stroke).
  int get historyLength => _hCount;

  void clear() {
    _alive = 0;
    _acc.fillRange(0, 3, 0);
    _hCount = 0;
  }

  void resetPath() => _hCount = 0;

  // ------------------------------------------------------------- helpers
  double _r(double a, double b) => a + _random.nextDouble() * (b - a);

  T _pick<T>(List<T> a) => a[(_random.nextDouble() * a.length).truncate()];

  /// `every(st, key, rate, dt, fn)`: how many spawns this frame.
  int _every(int key, double rate, double dt) {
    _acc[key] += dt;
    var n = 0;
    while (_acc[key] > rate && n < 6) {
      _acc[key] -= rate;
      n++;
    }
    if (_acc[key] > rate) _acc[key] = 0;
    return n;
  }

  /// `phys(st, dt)`: gravity and drag on top of the step.
  void _phys(double dt) {
    for (var i = 0; i < _alive; i++) {
      final p = _pool[i];
      if (p.g != 0) p.vy += p.g * dt;
      if (p.dr != 0) {
        final f = math.max(0.0, 1 - p.dr * dt);
        p.vx *= f;
        p.vy *= f;
      }
    }
  }

  /// `P(x, y, {...})` defaults; null when the pool is full.
  _P? _spawn(double x, double y) {
    if (_alive >= capacity) return null;
    return _pool[_alive++]..reset(x, y);
  }

  /// `head(st, dt, x, y, n)`: newest point first, all shifted with the scroll.
  void _head(double dt, double x, double y, int n) {
    _hHead = (_hHead + 1) % _histSize;
    _hx[_hHead] = x;
    _hy[_hHead] = y;
    _hr[_hHead] = _random.nextDouble();
    _hc[_hHead] = _clock;
    if (_hCount < n) _hCount++;
    if (_hCount > n) _hCount = n;
    for (var i = 0; i < _hCount; i++) {
      _hx[_hi(i)] += _vx * dt;
    }
  }

  int _hi(int i) => (_hHead - i + _histSize) % _histSize;

  // ---------------------------------------------------------------- emit
  void emit(double x, double y, double dt, double k, double vx) {
    _vx = vx * k / 2;
    final u = k / 2;
    switch (id) {
      case 'sunset':
        for (var n = _every(0, .012, dt); n > 0; n--) {
          final px = x + _r(-2, 2) * k, py = y + _r(-4, 4) * k;
          final p = _spawn(px, py);
          final a = _r(-20, 10) * u, b = _r(-12, 12) * u - 14 * u;
          final m = _r(.38, .58), s = _r(5, 9) * u;
          p?.set(vx: a, vy: b, max: m, s: s);
        }
      case 'leaves':
        for (var i = 0; i < _alive; i++) {
          final p = _pool[i];
          p.vy = p.v0 + math.sin(p.life * 5 + p.ph) * 16 * u;
        }
        for (var n = _every(0, .085, dt); n > 0; n--) {
          final v0 = _r(4, 18) * u;
          final px = x + _r(-3, 1) * k, py = y + _r(-5, 5) * k;
          final a = _r(-14, 8) * u, m = _r(.9, 1.2), s = _r(6.5, 8.5) * u;
          final rot = _r(0, tau), vr = _r(-4, 4), ph = _r(0, tau);
          final c = _pick(_leaf);
          _spawn(px, py)?.set(vx: a, vy: v0, max: m, s: s, rot: rot, vr: vr)
            ?..v0 = v0
            ..ph = ph
            ..c0 = c.$1
            ..c1 = c.$2;
        }
      case 'snow':
        for (var n = _every(0, .09, dt); n > 0; n--) {
          final px = x + _r(-3, 1) * k, py = y + _r(-5, 5) * k;
          final a = _r(-14, 6) * u, b = _r(6, 20) * u, m = _r(.9, 1.2);
          final s = _r(5.5, 7.5) * u, rot = _r(0, tau), vr = _r(-2.5, 2.5);
          final c = _pick(_snowC);
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s, rot: rot, vr: vr).c0 =
              c;
        }
      case 'petals':
        for (var i = 0; i < _alive; i++) {
          final p = _pool[i];
          p.vy = p.v0 + math.cos(p.life * 4 + p.ph) * 12 * u;
        }
        for (var n = _every(0, .07, dt); n > 0; n--) {
          final v0 = _r(-4, 14) * u;
          final px = x + _r(-3, 1) * k, py = y + _r(-5, 5) * k;
          final a = _r(-12, 8) * u, m = _r(.9, 1.2), s = _r(6, 8) * u;
          final rot = _r(0, tau), vr = _r(-3, 3), ph = _r(0, tau);
          final c = _pick(_pet);
          _spawn(px, py)?.set(vx: a, vy: v0, max: m, s: s, rot: rot, vr: vr)
            ?..v0 = v0
            ..ph = ph
            ..c0 = c.$1
            ..c1 = c.$2;
        }
      case 'ink':
        _phys(dt);
        for (var n = _every(0, .06, dt); n > 0; n--) {
          final px = x + _r(-3, 1) * k, py = y + _r(-4, 4) * k;
          final a = _r(-12, 6) * u, b = _r(-16, 6) * u, m = _r(.6, .85);
          final s = _r(4, 6.5) * u, c = _pick(_ink);
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s)
            ?..g = 200 * u
            ..c0 = c;
        }
      case 'planes':
        for (var i = 0; i < _alive; i++) {
          final p = _pool[i];
          p.vy = math.sin(p.life * 3.2 + p.ph) * 20 * u;
          p.rot = math.cos(p.life * 3.2 + p.ph) * .32;
        }
        for (var n = _every(0, .26, dt); n > 0; n--) {
          final px = x + _r(-4, 0) * k, py = y + _r(-8, 8) * k;
          final a = _r(20, 46) * u, m = _r(1.3, 1.6), s = _r(10, 12.5) * u;
          final ph = _r(0, tau), c = _pick(_pln);
          _spawn(px, py)?.set(vx: a, max: m, s: s)
            ?..ph = ph
            ..c0 = c.$1
            ..c1 = c.$2;
        }
      case 'popcorn':
        _phys(dt);
        for (var i = 0; i < _alive; i++) {
          final p = _pool[i];
          if (!p.flag && p.life > p.pt) {
            p.flag = true;
            p.vy = -_r(40, 75) * u;
            p.vx = _r(-25, 15) * u;
            p.vr = _r(-6, 6);
            p.g = 170 * u;
          }
        }
        for (var n = _every(0, .075, dt); n > 0; n--) {
          final px = x + _r(-3, 1) * k, py = y + _r(-3, 3) * k;
          final a = _r(-8, 0) * u, b = _r(-4, 4) * u, m = _r(.9, 1.1);
          final s = _r(6, 7.5) * u, rot = _r(0, tau), pt = _r(.08, .2);
          _random.nextDouble(); // b: Math.random() (unused by the art)
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s, rot: rot).pt = pt;
        }
      case 'fireworks':
        _phys(dt);
        for (var n = _every(0, .2, dt); n > 0; n--) {
          final px = x - _r(4, 10) * k, py = y + _r(-9, 9) * k;
          final a = _r(-6, 6) * u, s = _r(16, 22) * u, rot = _r(0, tau);
          final c = _pick(_fw);
          _spawn(px, py)?.set(vx: a, max: .66, s: s, rot: rot)
            ?..kind = _kB
            ..c0 = c;
        }
        for (var n = _every(1, .035, dt); n > 0; n--) {
          final px = x + _r(-2, 1) * k, py = y + _r(-2, 2) * k;
          final a = _r(-20, 0) * u, b = _r(-10, 10) * u, s = _r(1.4, 2.2) * u;
          final c = _random.nextDouble() < .6 ? artGold : const Color(0xFFFF9100);
          _spawn(px, py)?.set(vx: a, vy: b, max: .35, s: s)
            ?..kind = _kS
            ..g = 60 * u
            ..c0 = c;
        }
      case 'steps':
        for (var n = _every(0, .14, dt); n > 0; n--) {
          _f = !_f;
          _spawn(x - 2 * k, y + (_f ? -4 : 4) * k)?.set(
            max: 1.15,
            s: 7 * u,
            rot: _f ? -.22 : .22,
          ).c0 = _f ? artPlum : artPink;
        }
      case 'fish':
        for (var i = 0; i < _alive; i++) {
          final p = _pool[i];
          if (p.kind == _kF) p.vy = math.cos(p.life * 7 + p.ph) * 16 * u;
        }
        for (var n = _every(0, .24, dt); n > 0; n--) {
          final px = x + _r(-3, 0) * k, py = y + _r(-8, 8) * k;
          final a = -_r(6, 26) * u, m = _r(1.1, 1.4), s = _r(7.5, 9.5) * u;
          final ph = _r(0, tau), c = _pick(_fish);
          _spawn(px, py)?.set(vx: a, max: m, s: s)
            ?..kind = _kF
            ..ph = ph
            ..c0 = c.$1
            ..c1 = c.$2;
        }
        for (var n = _every(1, .16, dt); n > 0; n--) {
          final px = x + _r(-4, 0) * k, py = y + _r(-6, 6) * k;
          final b = -_r(14, 26) * u, s = _r(1.6, 2.6) * u;
          _spawn(px, py)?.set(vy: b, max: .8, s: s).kind = _kB;
        }
      case 'galaxy':
        for (var n = _every(0, .028, dt); n > 0; n--) {
          final px = x + _r(-3, 1) * k, py = y + _r(-4, 4) * k;
          final a = _r(-12, 6) * u, b = _r(-8, 8) * u, m = _r(.7, 1);
          final s = _r(5, 8) * u, c = _pick(_neb);
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s)
            ?..kind = _kN
            ..c0 = c;
        }
        for (var n = _every(1, .06, dt); n > 0; n--) {
          final px = x + _r(-4, 1) * k, py = y + _r(-8, 8) * k;
          final a = _r(-10, 10) * u, b = _r(-10, 10) * u, m = _r(.8, 1.1);
          final s = _r(2.5, 4.2) * u, ph = _r(0, tau), vr = _r(-2, 2);
          final c = _random.nextDouble() < .65
              ? const Color(0xFFFFFFFF)
              : const Color(0xFFFFE57F);
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s, vr: vr)
            ?..kind = _kS
            ..ph = ph
            ..c0 = c;
        }
        for (var n = _every(2, .03, dt); n > 0; n--) {
          final px = x + _r(-6, 2) * k, py = y + _r(-7, 7) * k;
          final a = _r(-10, 10) * u, b = _r(-6, 6) * u, m = _r(.5, .9);
          final s = _r(.8, 1.3) * u;
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s).kind = _kD;
        }
      case 'prism':
        _clock += dt;
        _head(dt, x, y, 14);
        if (_hCount > 9) {
          final qx = _hx[_hi(9)], qy = _hy[_hi(9)];
          for (var n = _every(0, .05, dt); n > 0; n--) {
            final ci = (_random.nextDouble() * 6).truncate();
            final a = math.pi + (ci - 2.5) * .13 + _r(-.05, .05);
            final v = _r(60, 110) * u;
            final m = _r(.35, .55), s = _r(1.8, 2.8) * u, ph = _r(0, tau);
            _spawn(qx, qy)?.set(
              vx: math.cos(a) * v + 60 * u,
              vy: math.sin(a) * v,
              max: m,
              s: s,
            )?..c0 = _spec[ci]
              ..ph = ph;
          }
        }
      case 'lavadrip':
        _phys(dt);
        for (var n = _every(0, .05, dt); n > 0; n--) {
          final px = x + _r(-3, 1) * k, py = y + _r(-2, 5) * k;
          final a = _r(-10, 8) * u, b = _r(-10, 10) * u, m = _r(.7, .95);
          final s = _r(4.5, 6.5) * u;
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s)
            ?..kind = _kD
            ..g = 190 * u;
        }
        for (var n = _every(1, .06, dt); n > 0; n--) {
          final px = x + _r(-3, 1) * k, py = y + _r(-4, 4) * k;
          final a = _r(-16, 4) * u, b = -_r(14, 34) * u, m = _r(.4, .6);
          final s = _r(1.3, 2.2) * u, vr = _r(-6, 6);
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s, vr: vr).kind = _kE;
        }
      case 'supernova':
        _clock += dt;
        _phys(dt);
        for (var n = _every(0, .012, dt); n > 0; n--) {
          final px = x + _r(-2, 1) * k, py = y + _r(-3, 3) * k;
          final a = _r(-30, 0) * u, b = _r(-12, 12) * u, m = _r(.35, .55);
          final s = _r(5, 9) * u;
          _spawn(px, py)?.set(vx: a, vy: b, max: m, s: s).kind = _kC;
        }
        for (var n = _every(1, .36, dt); n > 0; n--) {
          final bx = x - 3 * k, by = y;
          _spawn(bx, by)?.set(vx: -6 * u, max: .8, s: 34 * u).kind = _kR;
          _spawn(bx, by)?.set(vx: -6 * u, max: .6, s: 20 * u)
            ?..kind = _kR
            ..w = .6;
          for (var i = 0; i < 8; i++) {
            final a = i * tau / 8 + _r(-.2, .2), v = _r(90, 130) * u;
            final m = _r(.6, .8), s = _r(4.2, 5.8) * u, vr = _r(-6, 6);
            final c = _pick(_novaStars);
            _spawn(bx, by)?.set(
              vx: math.cos(a) * v - 10 * u,
              vy: math.sin(a) * v,
              max: m,
              s: s,
              vr: vr,
            )?..kind = _kS
              ..dr = 3
              ..c0 = c;
          }
        }
      case 'paint':
        _clock += dt * 2.6;
        _head(dt, x, y, 90);
        _phys(dt);
        for (var n = _every(0, .07, dt); n > 0; n--) {
          final c = _paintC(_clock);
          _r(-2.6, -.5); // a: unused by the art
          _random.nextDouble();
          final v = _r(30, 70) * u, sg = _random.nextDouble() < .5 ? -1 : 1;
          final px = x - _r(0, 6) * k, py = y + sg * _r(1, 3) * k;
          final a = -_r(0, 30) * u, m = _r(.6, .9), s = _r(1.6, 3) * u;
          final sat = _random.nextDouble() < .6;
          _spawn(px, py)?.set(vx: a, vy: sg * v, max: m, s: s)
            ?..g = 150 * u
            ..dr = 1.5
            ..c0 = c
            ..flag = sat;
        }
    }
  }

  /// `trailStep(st, dt)`.
  void step(double dt) {
    var write = 0;
    for (var read = 0; read < _alive; read++) {
      final p = _pool[read];
      p.life += dt;
      p.x += (_vx + p.vx) * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
      if (p.life < p.max) {
        final swap = _pool[write];
        _pool[write] = p;
        _pool[read] = swap;
        write++;
      }
    }
    _alive = write;
  }

  // ---------------------------------------------------------------- draw
  /// `trailDraw(ctx, st, k, head)`.
  void paint(Canvas canvas, double k, Offset? head) {
    Ctx2D.run(canvas, (c) {
      c.save();
      switch (id) {
        case 'sunset':
          _drawSunset(c);
        case 'leaves':
          _drawLeaves(c);
        case 'snow':
          _drawSnow(c);
        case 'petals':
          _drawPetals(c);
        case 'ink':
          _drawInk(c, k);
        case 'planes':
          _drawPlanes(c);
        case 'popcorn':
          _drawPopcorn(c, k);
        case 'fireworks':
          _drawFireworks(c, k);
        case 'steps':
          _drawSteps(c);
        case 'fish':
          _drawFish(c, k);
        case 'galaxy':
          _drawGalaxy(c);
        case 'prism':
          _drawPrism(c, k);
        case 'lavadrip':
          _drawLava(c, k);
        case 'supernova':
          _drawNova(c, k, head);
        case 'paint':
          _drawPaint(c, k);
      }
      c.restore();
    });
  }

  Iterable<_P> get _live sync* {
    for (var i = 0; i < _alive; i++) {
      yield _pool[i];
    }
  }

  void _drawSunset(Ctx2D c) {
    for (final p in _live) {
      final u = p.life / p.max;
      final col = u < .25
          ? lerpC(_sun[0], _sun[1], u / .25)
          : u < .6
          ? lerpC(_sun[1], _sun[2], (u - .25) / .35)
          : lerpC(_sun[2], _sun[3], (u - .6) / .4);
      c.globalAlpha = 1 - u * u;
      c.circ(p.x, p.y, p.s * (1.1 - u * .6), col);
    }
  }

  void _drawLeaves(Ctx2D c) {
    for (final p in _live) {
      final u = p.life / p.max, s = p.s;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.globalAlpha = u > .7 ? (1 - u) / .3 : 1;
      c.fillStyle = p.c0;
      c.beginPath();
      c.moveTo(-s, 0);
      c.quadraticCurveTo(0, -s * .95, s, 0);
      c.quadraticCurveTo(0, s * .95, -s, 0);
      c.fill();
      c.fillStyle = p.c1;
      c.beginPath();
      c.moveTo(-s, 0);
      c.quadraticCurveTo(0, s * .95, s, 0);
      c.closePath();
      c.fill();
      c.fillRect(-s * 1.45, -s * .1, s * .5, s * .2);
      c.restore();
    }
  }

  void _drawSnow(Ctx2D c) {
    c.lineCap = StrokeCap.round;
    for (final p in _live) {
      final u = p.life / p.max, s = p.s;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.globalAlpha = u > .65 ? (1 - u) / .35 : 1;
      c.strokeStyle = p.c0;
      c.lineWidth = math.max(1.3, s * .3);
      c.beginPath();
      for (var i = 0; i < 3; i++) {
        final a = i * math.pi / 3, co = math.cos(a), n = math.sin(a);
        c.moveTo(-co * s, -n * s);
        c.lineTo(co * s, n * s);
      }
      c.stroke();
      c.lineWidth = math.max(1, s * .22);
      c.beginPath();
      // The page rotates the context between path commands (the canvas
      // bakes the transform into each point); the same points, rotated here.
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3, co = math.cos(a), sn = math.sin(a);
        double rx(double px, double py) => px * co - py * sn;
        double ry(double px, double py) => px * sn + py * co;
        c.moveTo(rx(s * .55, 0), ry(s * .55, 0));
        c.lineTo(rx(s * .85, -s * .28), ry(s * .85, -s * .28));
        c.moveTo(rx(s * .55, 0), ry(s * .55, 0));
        c.lineTo(rx(s * .85, s * .28), ry(s * .85, s * .28));
      }
      c.stroke();
      c.circ(0, 0, s * .24, const Color(0xFFFFFFFF));
      c.restore();
    }
  }

  void _drawPetals(Ctx2D c) {
    for (final p in _live) {
      final u = p.life / p.max, s = p.s;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.scale(.35 + .65 * math.cos(p.life * 5 + p.ph).abs(), 1);
      c.globalAlpha = u > .7 ? (1 - u) / .3 : 1;
      c.fillStyle = p.c0;
      c.beginPath();
      c.moveTo(0, s);
      c.bezierCurveTo(s * 1.05, s * .35, s * .9, -s * .85, s * .3, -s * .95);
      c.lineTo(0, -s * .6);
      c.lineTo(-s * .3, -s * .95);
      c.bezierCurveTo(-s * .9, -s * .85, -s * 1.05, s * .35, 0, s);
      c.fill();
      c.fillStyle = p.c1;
      c.beginPath();
      c.ellipse(0, s * .45, s * .22, s * .42, 0, 0, tau);
      c.fill();
      c.restore();
    }
  }

  void _drop(Ctx2D c, double s) {
    c.beginPath();
    c.arc(0, 0, s, 0, math.pi);
    c.quadraticCurveTo(-s, -s * .9, 0, -s * 1.9);
    c.quadraticCurveTo(s, -s * .9, s, 0);
    c.fill();
  }

  void _drawInk(Ctx2D c, double k) {
    for (final p in _live) {
      final u = p.life / p.max, s = p.s * (1 - u * .25);
      final st2 = 1.0 + math.min<double>(.9, math.max(0.0, p.vy) / (130 * k));
      c.save();
      c.translate(p.x, p.y);
      c.globalAlpha = u > .75 ? (1 - u) / .25 : 1;
      c.rotate(math.atan2(p.vy, p.vx + 60 * k) - math.pi / 2);
      c.scale(1, st2);
      c.fillStyle = p.c0;
      _drop(c, s);
      c.circ(-s * .35, s * .05, s * .3, rgba(255, 255, 255, .75));
      c.restore();
    }
  }

  void _drawPlanes(Ctx2D c) {
    for (final p in _live) {
      final u = p.life / p.max, s = p.s;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.globalAlpha = u > .75 ? (1 - u) / .25 : math.min(1, u * 8);
      c.fillStyle = p.c0;
      c.beginPath();
      c.moveTo(s * 1.2, 0);
      c.lineTo(-s, -s * .62);
      c.lineTo(-s * .45, 0);
      c.closePath();
      c.fill();
      c.fillStyle = p.c1;
      c.beginPath();
      c.moveTo(s * 1.2, 0);
      c.lineTo(-s * .45, 0);
      c.lineTo(-s * .75, s * .42);
      c.closePath();
      c.fill();
      c.fillStyle = rgba(255, 255, 255, .85);
      c.beginPath();
      c.moveTo(s * .7, -s * .06);
      c.lineTo(-s * .5, -s * .48);
      c.lineTo(-s * .25, -s * .06);
      c.closePath();
      c.globalAlpha *= .6;
      c.fill();
      c.restore();
    }
  }

  void _drawPopcorn(Ctx2D c, double k) {
    for (final p in _live) {
      final u = p.life / p.max, s = p.s;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.globalAlpha = u > .8 ? (1 - u) / .2 : 1;
      if (!p.flag) {
        c.fillStyle = const Color(0xFFFFB529);
        c.beginPath();
        c.ellipse(0, 0, s * .45, s * .32, 0, 0, tau);
        c.fill();
        c.circ(-s * .12, -s * .1, s * .12, const Color(0xFFFFF3C4));
      } else {
        final z = math.min(1.0, (p.life - p.pt) * 14), r = s * (.55 + .45 * z);
        const o = .7;
        c.fillStyle = const Color(0xFFE8961A);
        for (var i = 0; i < _pop.length; i += 3) {
          c.beginPath();
          c.arc(_pop[i] * r, _pop[i + 1] * r,
              _pop[i + 2] * r + math.max(.9, k * .45), 0, tau);
          c.fill();
        }
        c.fillStyle = const Color(0xFFFFFBEA);
        for (var i = 0; i < _pop.length; i += 3) {
          c.beginPath();
          c.arc(_pop[i] * r, _pop[i + 1] * r, _pop[i + 2] * r, 0, tau);
          c.fill();
        }
        c.circ(-o * r * .2, o * r * .25, r * .34, const Color(0xFFFFB529));
        c.circ(o * r * .75, -o * r * .6, r * .18, const Color(0xFFFFFFFF));
      }
      c.restore();
    }
  }

  void _drawFireworks(Ctx2D c, double k) {
    c.lineCap = StrokeCap.round;
    for (final p in _live) {
      final u = p.life / p.max;
      if (p.kind == _kS) {
        c.globalAlpha = 1 - u;
        c.fillStyle = p.c0;
        c.fillRect(p.x - p.s, p.y - p.s, p.s * 2, p.s * 2);
        continue;
      }
      final e = 1 - (1 - u) * (1 - u) * (1 - u), r = p.s * e;
      c.globalAlpha = u > .55 ? (1 - u) / .45 : 1;
      if (u < .22) {
        c.globalAlpha = 1 - u / .22;
        c.circ(p.x, p.y, p.s * .35 * (1 + u * 3), const Color(0xFFFFFFFF));
        c.circ(p.x, p.y, p.s * .22, p.c0);
        c.globalAlpha = 1;
      }
      c.strokeStyle = p.c0;
      c.lineWidth = math.max(1.5, k * 1.25 * (1 - u * .5));
      c.beginPath();
      for (var i = 0; i < 8; i++) {
        final a = p.rot + i * tau / 8, co = math.cos(a), n = math.sin(a);
        c.moveTo(p.x + co * r * .55, p.y + n * r * .55);
        c.lineTo(p.x + co * r, p.y + n * r);
      }
      c.stroke();
      for (var i = 0; i < 8; i++) {
        final a = p.rot + (i + .5) * tau / 8;
        c.circ(
          p.x + math.cos(a) * r * .8,
          p.y + math.sin(a) * r * .8 + u * u * 4 * k,
          math.max(1, k * .85 * (1 - u)),
          i.isOdd ? const Color(0xFFFFFFFF) : p.c0,
        );
      }
    }
  }

  void _drawSteps(Ctx2D c) {
    c.lineCap = StrokeCap.round;
    c.lineJoin = StrokeJoin.round;
    for (final p in _live) {
      final u = p.life / p.max, s = p.s, z = u < .08 ? 1.35 - u / .08 * .35 : 1.0;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.rot);
      c.scale(z, z);
      c.globalAlpha = u > .6 ? (1 - u) / .4 : 1;
      c.strokeStyle = p.c0;
      c.lineWidth = math.max(1.5, s * .34);
      c.beginPath();
      c.moveTo(-s * .55, 0);
      c.lineTo(s, 0);
      c.moveTo(0, 0);
      c.lineTo(s * .75, -s * .62);
      c.moveTo(0, 0);
      c.lineTo(s * .75, s * .62);
      c.stroke();
      c.circ(0, 0, s * .3, p.c0);
      c.restore();
    }
  }

  void _drawFish(Ctx2D c, double k) {
    for (final p in _live) {
      final u = p.life / p.max, s = p.s;
      c.save();
      c.translate(p.x, p.y);
      c.globalAlpha = u > .75 ? (1 - u) / .25 : math.min(1, u * 8);
      if (p.kind == _kB) {
        c.strokeStyle = const Color(0xFF4FC3F7);
        c.lineWidth = math.max(1.1, k * .5);
        c.beginPath();
        c.arc(0, 0, p.s, 0, tau);
        c.stroke();
        c.circ(-p.s * .35, -p.s * .35, p.s * .3, const Color(0xFFFFFFFF));
        c.restore();
        continue;
      }
      c.rotate(math.sin(p.life * 7 + p.ph) * .25);
      final w = math.sin(p.life * 14 + p.ph) * .35;
      c.fillStyle = p.c0;
      c.beginPath();
      c.moveTo(s * .7, 0);
      c.lineTo(s * 1.4, -s * (.55 + w * .4));
      c.lineTo(s * 1.3, s * (.55 - w * .4));
      c.closePath();
      c.fill();
      c.beginPath();
      c.ellipse(0, 0, s, s * .6, 0, 0, tau);
      c.fill();
      c.save();
      c.clip();
      c.fillStyle = p.c1;
      c.fillRect(s * .05, -s, s * .28, s * 2);
      c.restore();
      c.circ(-s * .5, -s * .12, s * .2, const Color(0xFFFFFFFF));
      c.circ(-s * .55, -s * .12, s * .11, const Color(0xFF212121));
      c.restore();
    }
  }

  void _star4(Ctx2D c, double r, Color col) {
    c.fillStyle = col;
    c.beginPath();
    for (var i = 0; i < 8; i++) {
      final q = i.isOdd ? r * .32 : r, a = i * math.pi / 4;
      c.lineTo(math.cos(a) * q, math.sin(a) * q);
    }
    c.fill();
  }

  void _drawGalaxy(Ctx2D c) {
    for (final p in _live) {
      final u = p.life / p.max;
      if (p.kind == _kN) {
        final a = math.sin(math.pi * math.min(1, u * 1.3 + .15));
        c.globalAlpha = .32 * a;
        c.circ(p.x, p.y, p.s * (1 + u * 1.4) * 1.5, p.c0);
        c.globalAlpha = .5 * a;
        c.circ(p.x, p.y, p.s * (1 + u * 1.4) * .8, p.c0);
      }
    }
    for (final p in _live) {
      final u = p.life / p.max;
      if (p.kind == _kS) {
        final tw = .55 + .45 * math.sin(p.life * 14 + p.ph);
        c.globalAlpha = 1 - u * u;
        c.save();
        c.translate(p.x, p.y);
        c.rotate(p.rot);
        c.shadowColor = const Color(0xFFE040FB);
        c.shadowBlur = 6;
        _star4(c, p.s * (.6 + .6 * tw), p.c0);
        c.restore();
      } else if (p.kind == _kD) {
        c.globalAlpha = 1 - u;
        c.fillStyle = const Color(0xFFFFFFFF);
        c.fillRect(p.x - p.s, p.y - p.s, p.s * 2, p.s * 2);
      }
    }
  }

  void _drawPrism(Ctx2D c, double k) {
    const q = 9;
    if (_hCount <= q + 2) return;
    final T = _clock;
    final px = _hx[_hi(q)], py = _hy[_hi(q)];
    final bx = _hx[_hi(q + 2)], by = _hy[_hi(q + 2)];
    // spectrum fan: six wedges opening backwards from the prism
    final base =
        math.pi - math.max(-.35, math.min(.35, math.atan2(by - py, px - bx) * .45));
    final da = .13 * (1 + .12 * math.sin(T * 7)), L = 38 * k;
    for (final (f, a) in const [(1.0, .28), (.68, .35), (.36, .55)]) {
      c.globalAlpha = a;
      for (var ci = 0; ci < 6; ci++) {
        final a0 = base + (ci - 3) * da, a1 = base + (ci - 2) * da;
        final l = L * f * (1 + .05 * math.sin(T * 11 + ci));
        c.fillStyle = _spec[ci];
        c.beginPath();
        c.moveTo(px, py);
        c.lineTo(px + math.cos(a0) * l, py + math.sin(a0) * l);
        c.lineTo(px + math.cos(a1) * l, py + math.sin(a1) * l);
        c.closePath();
        c.fill();
      }
    }
    c.globalAlpha = 1;
    // white beam from the bird into the prism (violet halo)
    c.lineCap = StrokeCap.round;
    c.lineJoin = StrokeJoin.round;
    c.beginPath();
    for (var i = 0; i <= q; i++) {
      i == 0 ? c.moveTo(_hx[_hi(i)], _hy[_hi(i)]) : c.lineTo(_hx[_hi(i)], _hy[_hi(i)]);
    }
    c.strokeStyle = rgba(179, 136, 255, .6);
    c.lineWidth = 3.8 * k;
    c.stroke();
    c.strokeStyle = const Color(0xFFFFFFFF);
    c.lineWidth = 1.8 * k;
    c.shadowColor = const Color(0xFFFFFFFF);
    c.shadowBlur = 8;
    c.stroke();
    c.shadowBlur = 0;
    // glass prism at the split point
    final r = 5.4 * k;
    c.save();
    c.translate(px, py);
    c.rotate(math.sin(T * 3) * .12);
    c.fillStyle = rgba(178, 235, 242, .95);
    c.strokeStyle = const Color(0xFF00ACC1);
    c.lineWidth = math.max(1.3, .8 * k);
    c.beginPath();
    c.moveTo(0, -r);
    c.lineTo(r * .9, r * .62);
    c.lineTo(-r * .9, r * .62);
    c.closePath();
    c.fill();
    c.stroke();
    c.fillStyle = const Color(0xFFFFFFFF);
    c.beginPath();
    c.moveTo(-r * .1, -r * .55);
    c.lineTo(-r * .5, r * .35);
    c.lineTo(-r * .28, r * .35);
    c.closePath();
    c.fill();
    c.restore();
    for (final p in _live) {
      final u = p.life / p.max;
      c.globalAlpha = 1 - u;
      c.save();
      c.translate(p.x, p.y);
      c.rotate(p.ph + p.life * 4);
      _star4(c, p.s * 1.5, p.c0);
      c.restore();
    }
  }

  void _drawLava(Ctx2D c, double k) {
    for (final p in _live) {
      final u = p.life / p.max;
      if (p.kind == _kE) {
        c.globalAlpha = 1 - u;
        c.save();
        c.translate(p.x, p.y);
        c.rotate(p.rot);
        c.fillStyle = u < .4 ? const Color(0xFFFFE57F) : const Color(0xFFFF6D00);
        c.fillRect(-p.s, -p.s, p.s * 2, p.s * 2);
        c.restore();
        continue;
      }
      final s = p.s * (1 - u * .2), hot = math.max(0.0, 1 - u * 1.5);
      final col = u < .3
          ? lerpC(const Color(0xFFFFE57F), const Color(0xFFFF9100), u / .3)
          : u < .65
          ? lerpC(const Color(0xFFFF9100), const Color(0xFFE53935), (u - .3) / .35)
          : lerpC(const Color(0xFFE53935), const Color(0xFF4E1A10), (u - .65) / .35);
      c.save();
      c.translate(p.x, p.y);
      c.globalAlpha = u > .8 ? (1 - u) / .2 : 1;
      if (hot > 0) {
        c.fillStyle =
            rgba(255, 109, 0, double.parse((.32 * hot).toStringAsFixed(3)));
        c.beginPath();
        c.arc(0, 0, s * 2.1, 0, tau);
        c.fill();
      }
      final sx = 1.0 + math.min<double>(.8, math.max(0.0, p.vy) / (140 * k));
      c.rotate(math.atan2(p.vy, p.vx + 60 * k) - math.pi / 2);
      c.scale(1, sx);
      c.fillStyle = col;
      _drop(c, s);
      c.circ(
        0,
        s * .1,
        s * .45,
        u < .5
            ? const Color(0xFFFFF8E1)
            : lerpC(const Color(0xFFFFB529), const Color(0xFF8D2A12),
                math.min(1, (u - .5) * 2)),
      );
      c.restore();
    }
  }

  void _drawNova(Ctx2D c, double k, Offset? hd) {
    final T = _clock;
    // pulsing core glow at the head
    if (hd != null) {
      final pu = .5 + .5 * math.sin(T * 10);
      c.globalAlpha = .12 + .1 * pu;
      c.circ(hd.dx, hd.dy, (9 + 3 * pu) * k, const Color(0xFFFF9100));
      c.globalAlpha = .3;
      c.circ(hd.dx, hd.dy, 7 * k, const Color(0xFFFFE57F));
    }
    for (final p in _live) {
      if (p.kind == _kC) {
        final u = p.life / p.max;
        c.globalAlpha = 1 - u * u;
        c.circ(p.x, p.y, p.s * (1 - u * .65), _novaC(u));
      }
    }
    c.shadowColor = const Color(0xFFFF4FB7);
    c.shadowBlur = 10;
    for (final p in _live) {
      if (p.kind == _kR) {
        final u = p.life / p.max;
        final e = 1 - (1 - u) * (1 - u) * (1 - u), r = p.s * (.12 + e);
        final w = p.w == 0 ? 1.0 : p.w;
        c.globalAlpha = (1 - u) * w;
        c.strokeStyle = _novaC(math.min(1, u * 1.2 + .1));
        c.lineWidth = math.max(1.2, (1 - u) * 3.6 * k * w);
        c.beginPath();
        c.ellipse(p.x, p.y, r * .82, r, 0, 0, tau);
        c.stroke();
      }
    }
    c.shadowBlur = 0;
    for (final p in _live) {
      if (p.kind == _kS) {
        final u = p.life / p.max;
        c.globalAlpha = 1 - u * u;
        c.star(p.x, p.y, p.s * (1.25 - u * .5), p.c0, p.rot);
        if (u < .5) c.circ(p.x, p.y, p.s * .3, const Color(0xFFFFFFFF));
      }
    }
  }

  void _drawPaint(Ctx2D c, double k) {
    final N = _hCount;
    if (N < 3) return;
    final W = 7 * k;
    c.lineCap = StrokeCap.round;
    c.lineJoin = StrokeJoin.round;
    // main brush body: per-segment colour from the time each point was
    // painted; tapers and dries out at the tail
    for (var i = 0; i < N - 1; i++) {
      final d = i / N, a = _hi(i), b = _hi(i + 1);
      if (d > .62 && _hr[a] < (d - .62) * 2.2) continue;
      c.globalAlpha = d > .8 ? math.max(0, (1 - d) / .2) : 1;
      c.strokeStyle = _paintC(_hc[a]);
      c.lineWidth = W * (d < .06 ? .55 + d / .06 * .45 : 1 - d * .45);
      c.beginPath();
      c.moveTo(_hx[a], _hy[a]);
      c.lineTo(_hx[b], _hy[b]);
      c.stroke();
    }
    // bristle streaks: one light, one dark
    c.lineWidth = math.max(1, W * .13);
    for (final (off, col, al) in const [
      (-.24, Color(0xFFFFFFFF), .45),
      (.22, Color(0xFF000000), .18),
    ]) {
      c.globalAlpha = al;
      c.strokeStyle = col;
      c.beginPath();
      for (var i = 0; i < N * .7; i++) {
        final h = _hi(i), w = W * (1 - i / N * .45);
        i == 0
            ? c.moveTo(_hx[h], _hy[h] + off * w)
            : c.lineTo(_hx[h], _hy[h] + off * w);
      }
      c.stroke();
    }
    c.globalAlpha = 1;
    for (final p in _live) {
      final u = p.life / p.max;
      c.globalAlpha = u > .7 ? (1 - u) / .3 : 1;
      c.circ(p.x, p.y, p.s, p.c0);
      if (p.flag) c.circ(p.x - p.vx * .02, p.y - p.vy * .025, p.s * .5, p.c0);
    }
  }
}

// sub-kinds (the page's `k` field)
const int _kNone = 0, _kB = 1, _kS = 2, _kF = 3, _kN = 4, _kD = 5;
const int _kE = 6, _kC = 7, _kR = 8;

/// One pooled particle (`P(x, y, {...})`); mutable on purpose.
final class _P {
  int kind = _kNone;
  double x = 0, y = 0, vx = 0, vy = 0, life = 0, max = 1, s = 4;
  double rot = 0, vr = 0, ph = 0, v0 = 0, g = 0, dr = 0, pt = 0, w = 0;
  Color c0 = const Color(0xFFFFFFFF), c1 = const Color(0xFFFFFFFF);

  /// popcorn `pop` / paint `sat`.
  bool flag = false;

  void reset(double px, double py) {
    kind = _kNone;
    x = px;
    y = py;
    vx = vy = life = rot = vr = ph = v0 = g = dr = pt = w = 0;
    max = 1;
    s = 4;
    flag = false;
  }

  _P set({
    double vx = 0,
    double vy = 0,
    double max = 1,
    double s = 4,
    double rot = 0,
    double vr = 0,
  }) {
    this.vx = vx;
    this.vy = vy;
    this.max = max;
    this.s = s;
    this.rot = rot;
    this.vr = vr;
    return this;
  }
}

const List<Color> _sun = [
  Color(0xFFFFF59D), Color(0xFFFFB529), artPink, Color(0xFF6A1B9A), //
];
const List<(Color, Color)> _leaf = [
  (Color(0xFF7CB342), Color(0xFF558B2F)),
  (Color(0xFF43A047), Color(0xFF2E7D32)),
  (Color(0xFFC0CA33), Color(0xFF9E9D24)),
  (Color(0xFFFFA726), Color(0xFFEF6C00)),
];
const List<Color> _snowC = [
  Color(0xFF29B6F6), Color(0xFF4FC3F7), Color(0xFF81D4FA), //
];
const List<(Color, Color)> _pet = [
  (Color(0xFFFF5FA8), Color(0xFFB0006A)),
  (Color(0xFFFF8AC0), Color(0xFFEC008C)),
  (Color(0xFFFFFFFF), Color(0xFFFF4FA0)),
];
const List<Color> _ink = [
  Color(0xFF1A237E), Color(0xFF311B92), Color(0xFF4A148C), //
];
const List<(Color, Color)> _pln = [
  (Color(0xFF81D4FA), Color(0xFF0288D1)),
  (Color(0xFFFFE082), Color(0xFFFF8F00)),
  (Color(0xFFF48FB1), Color(0xFFC2185B)),
  (Color(0xFFB39DDB), Color(0xFF5E35B1)),
];
const List<double> _pop = [-.7, 0, .7, .56, -.28, .62, .1, -.7, .6, .2, .49, .6];
const List<Color> _fw = [
  artPink, artGold, Color(0xFF00B8D4), Color(0xFF64DD17), //
  Color(0xFFFF5722), Color(0xFF9B30D9),
];
const List<(Color, Color)> _fish = [
  (Color(0xFFFF7043), Color(0xFFFFFFFF)),
  (Color(0xFF29B6F6), Color(0xFFFFE082)),
  (Color(0xFFFFB529), Color(0xFFFF7043)),
  (Color(0xFFEC407A), Color(0xFFFFFFFF)),
];
const List<Color> _neb = [
  Color(0xFF7C4DFF), Color(0xFFE040FB), Color(0xFF536DFE), Color(0xFFFF4FB7), //
];
const List<Color> _spec = [
  Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFFFFCC00), //
  Color(0xFF34C759), Color(0xFF00A2FF), Color(0xFFAF52DE),
];
const List<Color> _nova = [
  Color(0xFFFFF59D), Color(0xFFFFB529), artPink, Color(0xFF7C4DFF), //
];
const List<Color> _novaStars = [
  artGold, Color(0xFFFFFFFF), Color(0xFFFF4FB7), Color(0xFFFFE57F), //
];

Color _novaC(double u) => u < .3
    ? lerpC(_nova[0], _nova[1], u / .3)
    : u < .65
    ? lerpC(_nova[1], _nova[2], (u - .3) / .35)
    : lerpC(_nova[2], _nova[3], (u - .65) / .35);

const List<Color> _paint = [
  artPink, Color(0xFF9B30D9), Color(0xFF1E9BE0), //
  Color(0xFF00C853), Color(0xFFFFB529), Color(0xFFFF5722),
];

Color _paintC(double t) {
  final f = ((t % 6) + 6) % 6, i = f.truncate();
  return lerpC(_paint[i], _paint[(i + 1) % 6], f - i);
}
