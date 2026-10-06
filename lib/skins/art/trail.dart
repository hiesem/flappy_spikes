import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../look.dart';
import 'art_paint.dart';

/// Paints a complete [Look] centred on the origin, one art unit per canvas
/// unit, inside the 44 x 36 bird box — the `drawLook` contract of
/// `design/menu_v2/skin_art.js`.
///
/// Injected into [TrailEmitter] so the Afterimage trail can stamp ghost
/// copies of the player's look without this file depending on the bird
/// painter (WP-B1). Without it the Afterimage copies draw nothing.
typedef LookPaint =
    void Function(Canvas canvas, Look look, double t, bool flap);

/// Canvas port of the trail ("fire") particle system in
/// `design/menu_v2/skin_art.js` (`Trail` / `trailEmit` / `trailStep` /
/// `trailDraw`), PRD-menu-v2 §5.5.
///
/// Pure state + painting: no Flame, no game. Positions are screen units; `k`
/// is pixels per bird art unit (the mock's `k`). Particles live in a
/// fixed-capacity pool that is recycled in place, so a steady stream
/// allocates nothing. All randomness comes from the injected [math.Random]
/// (seed it for deterministic tests).
class TrailEmitter {
  TrailEmitter(this._trailId, {math.Random? random, this.lookPainter})
    : _random = random ?? math.Random() {
    for (var i = 0; i < capacity; i++) {
      _pool.add(_Particle());
    }
  }

  /// Maximum live particles. When the pool is full new emissions are dropped,
  /// so memory and per-frame cost stay bounded however long the trail runs.
  static const int capacity = 512;

  /// Trail ids in catalogue order (PRD-menu-v2 §5.5).
  static List<String> get ids => [for (final def in _defs) def.id];

  /// The free default, used when an unknown id is requested.
  static const String fallbackId = 'flame';

  /// Particle scale of the shop thumbnail (`skin_shop.js` draws the tile art
  /// in an 84 pt wide box with `k = w / 80`).
  static const double tileScale = 1.05;

  /// Neon cycle of the Afterimage copies (`ECHO_C`).
  static const List<Color> _echoColors = [
    Color(0xFF00E5FF),
    Color(0xFFFF2BD6),
    Color(0xFFFFE600),
    Color(0xFF7C4DFF),
  ];

  /// History capacity (`_histSize` >= the ribbon's 120 points).
  static const int _histSize = 120;

  final math.Random _random;
  final List<_Particle> _pool = [];
  final Float64List _histX = Float64List(_histSize);
  final Float64List _histY = Float64List(_histSize);
  final Uint8List _histFlap = Uint8List(_histSize);

  String _trailId;
  int _alive = 0;
  double _acc = 0;
  double _scrollVx = 0;
  double _time = 0;
  int _histCap = _histSize;
  int _histHead = 0;
  int _histCount = 0;

  /// The equipped trail's look (used by the Afterimage copies).
  Look look = Look.defaults;

  /// Bird painter injected by the caller; `null` disables the Afterimage art.
  LookPaint? lookPainter;

  /// The equipped trail id. Assigning a different id keeps the emitter
  /// running but [clear]s the particles and path history of the old kind.
  String get trailId => _trailId;

  set trailId(String value) {
    if (value == _trailId) return;
    _trailId = value;
    clear();
  }

  /// Live particle count (history points are tracked separately).
  int get particleCount => _alive;

  /// Colour of the dot the shop thumbnail puts at the head of the trail
  /// (`drawThumb`: the second flame colour, or the per-kind fallback).
  Color get orbColor {
    final def = _def;
    final cols = def.cols;
    if (cols != null) return cols[1];
    return switch (def.kind) {
      _Kind.star => const Color(0xFFFFB529),
      _Kind.bubble => const Color(0xFF4FC3F7),
      _Kind.heart => const Color(0xFFFF1F64),
      _Kind.laser => const Color(0xFFFF1744),
      _Kind.echo => const Color(0xFF00E5FF),
      _Kind.conf => const Color(0xFF34C759),
      _Kind.bolt => const Color(0xFF00B0FF),
      _Kind.sq => const Color(0xFFEC008C),
      _Kind.note => const Color(0xFF9B30D9),
      _Kind.ribbon => const Color(0xFFFF3B30),
      _ => const Color(0xFFFFFFFF),
    };
  }

  /// Emits the trail at the bird's tail [head] for [dt] seconds. [k] is pixels
  /// per art unit; [vx] is the world scroll in px/s (the mock's -140 in runs,
  /// -90 in the shop thumbnail) and moves the whole trail left with the world.
  void emit(Offset head, double dt, {double k = 1, double vx = -140}) {
    if (dt <= 0) return;
    final def = _def;
    final x = head.dx;
    final y = head.dy;
    _acc += dt;
    _scrollVx = vx * k / 2;

    switch (def.kind) {
      case _Kind.ribbon:
        _histCap = _histSize;
        _histPush(x, y, false);
        _histShift(_scrollVx * dt);
        return;
      case _Kind.echo:
        _histCap = 84;
        _histPush(x, y, (_acc * 6.6) % 1 < .4);
        _histShift(_scrollVx * dt);
        if (_random.nextDouble() < dt * 14) {
          final p = _spawn(
            x + _between(-30, 0) * k / 2,
            y + _between(-12, 12) * k / 2,
            _Kind.sq,
            k,
          );
          if (p != null) {
            p.vx = _between(-30, 0) * k / 2;
            p.vy = 0;
            p.max = .35;
            p.s = _between(2, 4) * k / 2;
            p.rot = 0;
            p.vr = 0;
            p.color = _echoColors[_random.nextInt(_echoColors.length)];
          }
        }
        return;
      default:
        break;
    }

    final rate = switch (def.kind) {
      _Kind.laser => .008,
      _Kind.flame => .012,
      _Kind.bolt => .05,
      _ => .04,
    };
    while (_acc > rate) {
      _acc -= rate;
      final p = _spawn(
        x + _between(-2, 2) * k,
        y + _between(-4, 4) * k,
        def.kind,
        k,
      );
      if (p == null) continue;
      switch (def.kind) {
        case _Kind.flame:
          p.max = _between(.35, .55);
          p.vy -= 14 * k / 2;
          p.ramp = def.cols!;
        case _Kind.star:
          p.max = .7;
          p.color = _starColors[_random.nextInt(_starColors.length)];
          p.s *= .9;
        case _Kind.bubble:
          p.max = .9;
          p.vy = -_between(8, 24) * k / 2;
          p.s = _between(3, 7) * k / 2;
        case _Kind.heart:
          p.max = .9;
          p.vy = -_between(10, 24) * k / 2;
          p.color = _random.nextBool()
              ? const Color(0xFFFF1F64)
              : const Color(0xFFEC008C);
        case _Kind.laser:
          if (_random.nextDouble() < .12) {
            p.kind = _Kind.lspark;
            p.max = .3;
            p.vy = _between(-40, 40) * k / 2;
            p.vx = _between(-10, 30) * k / 2;
            p.s = _between(1.5, 3) * k / 2;
          } else {
            p.max = .6;
            p.y = y;
            p.vx = 0;
            p.vy = 0;
            p.ph = _time * 1000 / 90;
          }
        case _Kind.conf:
          p.max = .9;
          p.color = _confColors[_random.nextInt(_confColors.length)];
          p.vy = _between(-10, 24) * k / 2;
        case _Kind.bolt:
          p.max = .22;
          for (var i = 0; i < 6; i++) {
            p.pts[i * 2] = -i * 7 * k / 2;
            p.pts[i * 2 + 1] = _between(-7, 7) * k / 2;
          }
        case _Kind.sq:
          p.max = .45;
          p.color = _random.nextBool()
              ? const Color(0xFFFFB529)
              : const Color(0xFFEC008C);
        case _Kind.note:
          p.max = 1;
          p.vy = -_between(12, 22) * k / 2;
          p.color = _noteColors[_random.nextInt(_noteColors.length)];
          p.glyph = _random.nextBool() ? 1 : 0;
        default:
          break;
      }
    }
  }

  /// Ages and moves every particle. [dt] also advances the trail's clock
  /// (used by the ribbon sparkle and the Afterimage tint cycle).
  void step(double dt) {
    if (dt <= 0) return;
    _time += dt;
    var write = 0;
    for (var read = 0; read < _alive; read++) {
      final p = _pool[read];
      p.life += dt;
      p.x += (_scrollVx + p.vx) * dt;
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

  /// Draws the current trail. [k] is pixels per art unit (as in [emit]).
  void paint(Canvas canvas, {double k = 1}) {
    final def = _def;
    if (def.kind == _Kind.ribbon) {
      _paintRibbon(canvas, k);
      return;
    }
    if (def.kind == _Kind.echo) _paintEcho(canvas, k);
    for (var i = 0; i < _alive; i++) {
      _paintParticle(canvas, _pool[i], k);
    }
  }

  /// Drops every particle and the path history. The clock keeps running.
  void clear() {
    _alive = 0;
    _acc = 0;
    _histCount = 0;
    _histHead = 0;
  }

  /// Shop-grid thumbnail (the `fire` branch of `drawThumb` in skin_shop.js):
  /// advances/emits a mini trail behind the small glowing orb at [orb], then
  /// draws both. Pass `dt == 0` to re-draw without emitting. The mock bobs the
  /// orb (`sin(t * 4) * h * .08`) — the caller passes the bobbed [orb]; [t] is
  /// the tile clock.
  static void paintTrailTile(
    Canvas c,
    TrailEmitter e,
    Offset orb,
    double dt,
    double t,
  ) {
    if (dt > 0) {
      e.emit(orb, dt, k: tileScale, vx: -90);
      e.step(dt);
    }
    e.paint(c, k: tileScale);
    ArtPaint.circ(c, orb.dx, orb.dy, 4.2 * tileScale, e.orbColor);
    ArtPaint.circ(
      c,
      orb.dx + 1.3 * tileScale,
      orb.dy - 1.3 * tileScale,
      1.3 * tileScale,
      const Color(0xCCFFFFFF),
    );
  }

  /// Takes a particle from the pool (dropping the emission when full) and
  /// resets it to the mock's shared per-particle defaults.
  _Particle? _spawn(double x, double y, _Kind kind, double k) {
    if (_alive >= capacity) return null;
    final p = _pool[_alive++];
    p.kind = kind;
    p.x = x;
    p.y = y;
    p.vx = _between(-20, 10) * k / 2;
    p.vy = _between(-12, 12) * k / 2;
    p.life = 0;
    p.max = .5;
    p.s = _between(5, 9) * k / 2;
    p.rot = _between(0, ArtPaint.tau);
    p.vr = _between(-4, 4);
    p.ph = 0;
    p.glyph = 0;
    p.color = const Color(0xFFEC008C);
    p.ramp = null;
    return p;
  }

  void _paintRibbon(Canvas canvas, double k) {
    if (_histCount < 2) return;
    final w = 2.6 * k;
    for (var c = 0; c < 6; c++) {
      final path = Path();
      for (var i = 0; i < _histCount; i++) {
        final xx = _histXAt(i);
        final yy = _histYAt(i) + (c - 2.5) * w;
        if (i == 0) {
          path.moveTo(xx, yy);
        } else {
          path.lineTo(xx, yy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w + .5
          ..strokeCap = StrokeCap.round
          ..color = _rainbowRibbon[c].withValues(alpha: .95),
      );
    }
    ArtPaint.star(
      canvas,
      _histXAt(0),
      _histYAt(0),
      3 * k,
      const Color(0xFFFFFFFF),
      _time * 1000 / 300,
    );
  }

  /// The four Afterimage copies, chased backwards along the path history
  /// (`H[n * 20]`, n = 4..1) and tinted in a cycling neon colour.
  void _paintEcho(Canvas canvas, double k) {
    final paint = lookPainter;
    if (paint == null || _histCount < 2) return;
    for (var n = 4; n >= 1; n--) {
      final index = n * 20;
      if (index >= _histCount) continue;
      _echoDraw(
        canvas,
        paint,
        _histXAt(index) + 17 * k,
        _histYAt(index),
        k,
        _echoColors[(n + (_time * 3).floor()) % _echoColors.length],
        .78 - n * .13,
        _random.nextDouble() < .07,
        _histFlapAt(index),
      );
    }
  }

  /// Stamps one tinted, scanlined ghost of the look. The mock renders the look
  /// to an offscreen canvas and composites it with `source-atop`; the same
  /// result comes from a saveLayer, which also gives the glitch slices for
  /// free (each slice is its own shifted copy of the layer).
  void _echoDraw(
    Canvas canvas,
    LookPaint paint,
    double x,
    double y,
    double k,
    Color color,
    double alpha,
    bool glitch,
    bool flap,
  ) {
    final w = (90 * k).ceilToDouble();
    final top = y - w / 2;
    if (!glitch) {
      _echoSlice(
        canvas,
        paint,
        Rect.fromLTWH(x - w / 2, top, w, w),
        x,
        y,
        k,
        color,
        alpha,
        flap,
        top,
        w,
      );
      return;
    }
    const slices = 5;
    final sh = w / slices;
    for (var i = 0; i < slices; i++) {
      final slice = Rect.fromLTWH(x - w / 2, top + i * sh, w, sh);
      final jitter = (_random.nextDouble() - .5) * 10 * k;
      _echoSlice(
        canvas,
        paint,
        slice,
        x + jitter,
        y,
        k,
        color,
        alpha,
        flap,
        top,
        w,
      );
    }
  }

  void _echoSlice(
    Canvas canvas,
    LookPaint paint,
    Rect slice,
    double centreX,
    double centreY,
    double k,
    Color color,
    double alpha,
    bool flap,
    double top,
    double w,
  ) {
    canvas.saveLayer(
      slice,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
    );
    canvas.save();
    canvas.translate(centreX, centreY);
    canvas.scale(k);
    paint(canvas, look, _time, flap);
    canvas.restore();
    canvas.drawRect(
      slice,
      Paint()
        ..color = color.withValues(alpha: .8)
        ..blendMode = BlendMode.srcATop,
    );
    final scan = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: .35)
      ..blendMode = BlendMode.srcATop;
    var yy = top + ((slice.top - top) / 6).ceil() * 6;
    for (; yy < slice.bottom; yy += 6) {
      final height = math.min(1.5, slice.bottom - yy);
      if (height <= 0) break;
      canvas.drawRect(Rect.fromLTWH(slice.left, yy, w, height), scan);
    }
    canvas.restore();
  }

  void _paintParticle(Canvas canvas, _Particle p, double k) {
    final u = p.life / p.max;
    canvas.save();
    canvas.translate(p.x, p.y);
    switch (p.kind) {
      case _Kind.flame:
        final ramp = p.ramp!;
        final color = u < .25
            ? ArtPaint.lerpColor(ramp[0], ramp[1], u / .25)
            : u < .6
            ? ArtPaint.lerpColor(ramp[1], ramp[2], (u - .25) / .35)
            : ArtPaint.lerpColor(ramp[2], ramp[3], (u - .6) / .4);
        ArtPaint.circ(
          canvas,
          0,
          0,
          p.s * (1.1 - u * .6),
          color.withValues(alpha: 1 - u * u),
        );
      case _Kind.star:
        ArtPaint.star(
          canvas,
          0,
          0,
          p.s * (1 - u * .4) * .8,
          p.color.withValues(alpha: 1 - u),
          p.rot,
        );
      case _Kind.bubble:
        canvas.drawCircle(
          Offset.zero,
          p.s,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFF4FC3F7).withValues(alpha: 1 - u * .6),
        );
        ArtPaint.circ(
          canvas,
          -p.s * .35,
          -p.s * .35,
          p.s * .25,
          const Color(0xE6FFFFFF),
        );
      case _Kind.heart:
        canvas.rotate(math.sin(p.rot) * .3);
        ArtPaint.heart(
          canvas,
          0,
          0,
          p.s * 1.6,
          p.color.withValues(alpha: 1 - u),
        );
      case _Kind.laser:
        final hw = (1.7 + .5 * math.sin(p.ph)) * k * (1 - u * .5);
        final width = 8 * k / 2 + 2;
        final alpha = 1 - u * u;
        canvas.drawRect(
          Rect.fromLTWH(-1, -hw * 2.2, width, hw * 4.4),
          Paint()
            ..color = const Color(0xFFFF1744).withValues(alpha: .35 * alpha),
        );
        canvas.drawRect(
          Rect.fromLTWH(-1, -hw, width, hw * 2),
          Paint()..color = const Color(0xFFFF1744).withValues(alpha: alpha),
        );
        canvas.drawRect(
          Rect.fromLTWH(-1, -hw * .35, width, hw * .7),
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
        );
      case _Kind.lspark:
        final color = _random.nextBool()
            ? const Color(0xFFFF1744)
            : const Color(0xFFFFFFFF);
        canvas.drawRect(
          Rect.fromLTWH(-p.s / 2, -p.s / 2, p.s, p.s),
          Paint()..color = color.withValues(alpha: 1 - u),
        );
      case _Kind.conf:
        canvas.rotate(p.rot);
        canvas.drawRect(
          Rect.fromLTWH(-p.s * .4, -p.s * .2, p.s * .8, p.s * .4),
          Paint()..color = p.color.withValues(alpha: 1 - u * u),
        );
      case _Kind.bolt:
        final path = Path()..moveTo(p.pts[0], p.pts[1]);
        for (var i = 1; i < 6; i++) {
          path.lineTo(p.pts[i * 2], p.pts[i * 2 + 1]);
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..color = const Color(0xFF40C4FF).withValues(alpha: 1 - u)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .9
            ..color = const Color(0xFFFFFFFF).withValues(alpha: 1 - u),
        );
      case _Kind.sq:
        canvas.rotate(p.rot * .2);
        final z = p.s * (1 - u * .5);
        canvas.drawRect(
          Rect.fromLTWH(-z / 2, -z / 2, z, z),
          Paint()..color = p.color.withValues(alpha: 1 - u),
        );
      case _Kind.note:
        canvas.rotate(math.sin(p.rot) * .25);
        final z = p.s / 5;
        final fill = Paint()..color = p.color.withValues(alpha: 1 - u);
        _noteHead(canvas, -2 * z, 4 * z, z, fill);
        canvas.drawRect(Rect.fromLTWH(.1 * z, -5 * z, 1.1 * z, 9 * z), fill);
        if (p.glyph == 1) {
          _noteHead(canvas, 5 * z, 3 * z, z, fill);
          canvas.drawRect(Rect.fromLTWH(7.1 * z, -6 * z, 1.1 * z, 9 * z), fill);
          canvas.drawRect(Rect.fromLTWH(.1 * z, -6 * z, 8 * z, 1.6 * z), fill);
        } else {
          canvas.drawPath(
            ArtPaint.poly([
              Offset(1.2 * z, -5 * z),
              Offset(4.5 * z, -2 * z),
              Offset(1.2 * z, -2.6 * z),
            ]),
            fill,
          );
        }
      default:
        break;
    }
    canvas.restore();
  }

  /// One note head: an ellipse rotated -0.4 rad (`ctx.ellipse(...,-.4,...)`).
  static void _noteHead(
    Canvas canvas,
    double x,
    double y,
    double z,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-.4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 4.8 * z, height: 3.6 * z),
      paint,
    );
    canvas.restore();
  }

  _TrailDef get _def {
    for (final def in _defs) {
      if (def.id == _trailId) return def;
    }
    return _defs.first;
  }

  double _between(double a, double b) => a + _random.nextDouble() * (b - a);

  void _histPush(double x, double y, bool flap) {
    _histHead = (_histHead + 1) % _histSize;
    _histX[_histHead] = x;
    _histY[_histHead] = y;
    _histFlap[_histHead] = flap ? 1 : 0;
    if (_histCount < _histCap) {
      _histCount++;
    } else if (_histCount > _histCap) {
      _histCount = _histCap;
    }
  }

  void _histShift(double dx) {
    for (var i = 0; i < _histCount; i++) {
      _histX[_histIndex(i)] += dx;
    }
  }

  int _histIndex(int i) => (_histHead - i + _histSize) % _histSize;

  double _histXAt(int i) => _histX[_histIndex(i)];

  double _histYAt(int i) => _histY[_histIndex(i)];

  bool _histFlapAt(int i) => _histFlap[_histIndex(i)] == 1;
}

/// One trail skin: its particle kind plus the 4-colour flame ramp (if any).
class _TrailDef {
  const _TrailDef(this.id, this.kind, [this.cols]);

  final String id;
  final _Kind kind;
  final List<Color>? cols;
}

enum _Kind {
  flame,
  star,
  bubble,
  heart,
  laser,
  lspark,
  conf,
  bolt,
  sq,
  note,
  ribbon,
  echo,
}

const List<Color> _starColors = [
  Color(0xFFFFB529),
  Color(0xFFFF9100),
  Color(0xFFEC008C),
  Color(0xFFFFFFFF),
];

const List<Color> _confColors = [
  Color(0xFFFF3B30),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF00A2FF),
  Color(0xFFEC008C),
];

const List<Color> _noteColors = [
  Color(0xFF9B30D9),
  Color(0xFFEC008C),
  Color(0xFF1E9BE0),
];

/// The six ribbon stripes (`trailDraw`: `FF3B30 ... AF52DE`).
const List<Color> _rainbowRibbon = [
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF00A2FF),
  Color(0xFFAF52DE),
];

/// `FIRES` in skin_art.js, in display order. The mock's JS-only `puff` and
/// `comet` kinds are not in the 2.0 catalogue and are skipped.
const List<_TrailDef> _defs = [
  _TrailDef('flame', _Kind.flame, [
    Color(0xFFFFF59D),
    Color(0xFFFFB529),
    Color(0xFFFF5722),
    Color(0xFFB71C1C),
  ]),
  _TrailDef('blue', _Kind.flame, [
    Color(0xFFFFFFFF),
    Color(0xFF80DEEA),
    Color(0xFF039BE5),
    Color(0xFF01579B),
  ]),
  _TrailDef('toxic', _Kind.flame, [
    Color(0xFFF4FF81),
    Color(0xFFAEEA00),
    Color(0xFF43A047),
    Color(0xFF1B5E20),
  ]),
  _TrailDef('hot', _Kind.flame, [
    Color(0xFFFFFFFF),
    Color(0xFFFCD9EE),
    Color(0xFFEC008C),
    Color(0xFF7A0044),
  ]),
  _TrailDef('shadow', _Kind.flame, [
    Color(0xFFE1BEE7),
    Color(0xFF9B30D9),
    Color(0xFF4A148C),
    Color(0xFF1A0630),
  ]),
  _TrailDef('sparkle', _Kind.star),
  _TrailDef('bubbles', _Kind.bubble),
  _TrailDef('hearts', _Kind.heart),
  _TrailDef('laser', _Kind.laser),
  _TrailDef('confetti', _Kind.conf),
  _TrailDef('bolt', _Kind.bolt),
  _TrailDef('blocks', _Kind.sq),
  _TrailDef('notes', _Kind.note),
  _TrailDef('rainbow', _Kind.ribbon),
  _TrailDef('echo', _Kind.echo),
];

/// One pooled particle. Mutable on purpose: particles are recycled in place.
class _Particle {
  _Kind kind = _Kind.flame;
  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  double life = 0;
  double max = 1;
  double s = 0;
  double rot = 0;
  double vr = 0;
  double ph = 0;
  Color color = const Color(0xFFEC008C);
  List<Color>? ramp;

  /// 0 = single note, 1 = beamed pair.
  int glyph = 0;

  /// The six lightning-bolt vertices (x, y pairs).
  final Float32List pts = Float32List(12);
}
