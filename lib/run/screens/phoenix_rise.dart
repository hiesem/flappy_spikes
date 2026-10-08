import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../components/bird.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../config/revive_config.dart';
import '../config/run_config.dart';
import '../effects/easing.dart';
import '../effects/shock_ring.dart';
import '../run_controller.dart';
import '../run_layers.dart';

/// World priority of the revive overlay: over every run layer (fx 15, the
/// heart flight 16), under the menu overlay backdrop (18) and the phoenix.
const int kReviveDimPriority = RunLayer.fx + 2;

/// §5.9 the dark overlay over the frozen game (world space, so the
/// phoenix's flames and bird can rise above it). [alpha] is driven by the
/// revive screen (62 %) and the phoenix (→ 35 % → 0).
class ReviveDim extends Component with HasGameReference<FlappySpikesGame> {
  ReviveDim() : super(priority: kReviveDimPriority);

  double alpha = 0;
  double _from = 0, _to = 0, _len = 0, _t = 0;
  bool _removeAtEnd = false;

  /// Fades [alpha] to [to] over [seconds] (removes itself at the end when
  /// [remove]).
  void fadeTo(double to, double seconds, {bool remove = false}) {
    _from = alpha;
    _to = to;
    _len = seconds;
    _t = 0;
    _removeAtEnd = remove;
    if (seconds <= 0) {
      alpha = to;
      if (remove) removeFromParent();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_len <= 0) return;
    _t += dt;
    final k = (_t / _len).clamp(0.0, 1.0);
    alpha = _from + (_to - _from) * k;
    if (k >= 1) {
      _len = 0;
      if (_removeAtEnd) removeFromParent();
    }
  }

  final Paint _p = Paint();

  @override
  void render(Canvas canvas) {
    if (alpha <= 0) return;
    _p.color = ReviveConfig.dimColor.withValues(alpha: alpha);
    canvas.drawRect(
      Rect.fromLTWH(-40, -40, RunConfig.worldWidth + 80, game.viewHeight + 80),
      _p,
    );
  }
}

/// §3.14 the safe line: the vertical centre of the next hoop still ahead,
/// clamped to the band (squeeze-free tooth lines: a running squeeze opens
/// during the phoenix); with no hoop ahead, the band's centre.
double reviveSafeLine(RunController run) {
  final s = run.state;
  final geo = run.geo;
  final r = RunConfig.birdRadius * s.birdScale;
  final lo = geo.stripHeight + r + ReviveConfig.safeMargin;
  final hi = s.viewHeight - geo.stripHeight - r - ReviveConfig.safeMargin;
  final birdX = s.camX + RunConfig.birdX;
  final h = run.spawner.hoops
      .where((h) => !h.resolved && h.planeX > birdX - 4)
      .firstOrNull;
  final y = h != null ? h.frame().centre.y - s.camY : s.viewHeight / 2;
  return lo > hi ? s.viewHeight / 2 : y.clamp(lo, hi).toDouble();
}

/// §5.9 the phoenix rise (≈ 1.65 s), in world (= screen) coordinates:
///
/// | t | |
/// |---|---|
/// | 0–0.5 s | overlay 62 % → 35 % (0.6 s); flames catch around the dead bird (Black Hole: around a shock ring at its last position); the bird trembles ±1.5 pt |
/// | 0.5–1.0 s | the bird rises to the safe line (smoothstep) in a flame column, turning upright with a swing, drifting back to x 70; flame wings spread; gold glow |
/// | 1.0 s | burst: warm flash, gold shockwave 20 → 170 pt, 34 feathers, 46 embers; X eyes open |
/// | 1.0–1.65 s | hover and flap; flames die out |
/// | 1.65 s | [onDone]: straight back in (the game resumes the run) |
///
/// Sounds: `rv_ignite` at 0, `rv_burst` at the burst (AudioPool).
class PhoenixRise extends Component with HasGameReference<FlappySpikesGame> {
  PhoenixRise({
    required this.run,
    required this.dim,
    required this.onDone,
    math.Random? random,
  }) : _r = random ?? math.Random(),
       super(priority: kReviveDimPriority + 1);

  final RunController run;
  final ReviveDim dim;
  final void Function(double safeY) onDone;
  final math.Random _r;

  double _t = 0;
  late Offset _from;
  late double _fromAngle;
  late double _safeY;
  late bool _noBody;
  Offset _bird = Offset.zero;
  double _angle = 0;
  bool _burst = false;
  bool _done = false;
  double _flapClock = 0;

  /// Seconds since the start.
  double get time => _t;

  /// The safe line this phoenix rises to.
  double get safeY => _safeY;

  /// The bird's screen centre now.
  Offset get birdAt => _bird;

  bool get burst => _burst;
  bool get done => _done;

  final List<_Flame> _flames = [];
  final List<_Ember> _embers = [];
  final List<_Feather> _feathers = [];
  double _flash = 0;

  Bird? get _b {
    final b = game.runBird;
    return b != null && b.isLoaded ? b : null;
  }

  @override
  void onMount() {
    super.onMount();
    final b = _b;
    final p = b?.body.position;
    _from = p != null
        ? Offset(p.x, p.y)
        : Offset(RunConfig.birdX, run.state.viewHeight / 2);
    _fromAngle = _normal(b?.body.angle ?? math.pi);
    _bird = _from;
    _angle = _fromAngle;
    _safeY = reviveSafeLine(run);
    _noBody = run.lastDeath?.themed?.noBody ?? false;
    if (b != null) b.priority = kReviveDimPriority + 2;
    dim.fadeTo(ReviveConfig.phoenixDim, ReviveConfig.phoenixDimFade);
    game.sound.play(Sfx.rvIgnite);
    if (_noBody) {
      // §3.14 Black Hole: the bird re-forms from a shock ring.
      parent?.add(
        ShockRing(priority: priority + 2).play(
          _from,
          rx: ReviveConfig.shockFrom,
          color: ReviveConfig.shockColor,
          length: ReviveConfig.burstAt,
          scaleFrom: 3,
          scaleTo: 1,
          strokeFrom: 5,
          strokeTo: 2,
        ),
      );
    }
  }

  /// An angle in (−π, π].
  static double _normal(double a) {
    var x = a % (2 * math.pi);
    if (x > math.pi) x -= 2 * math.pi;
    return x;
  }

  double _rnd(double a, double b) => a + _r.nextDouble() * (b - a);

  @override
  void update(double dt) {
    super.update(dt);
    if (_done) {
      // The feathers and embers finish over the resumed run.
      _step(dt);
      if (_flash > 0) _flash = math.max(0, _flash - dt);
      if (idle && _flash <= 0) removeFromParent();
      return;
    }
    _t += dt;
    final t = _t;
    // Flames: growing during the ignite, steady in the column, dying out.
    final rate = t < 1.05
        ? (t < ReviveConfig.igniteEnd ? .4 + t / ReviveConfig.igniteEnd : 1.4) *
              6
        : math.max(0, 8 - (t - 1.05) * 16);
    final n = rate.floor() + (_r.nextDouble() < rate - rate.floor() ? 1 : 0);
    for (var i = 0; i < n; i++) {
      _flame(
        _bird.dx,
        _bird.dy + (t < ReviveConfig.igniteEnd ? 6 : 10),
        t < ReviveConfig.igniteEnd ? .8 + t : 1.3,
      );
    }
    // The bird.
    const x1 = RunConfig.birdX;
    if (t < ReviveConfig.igniteEnd) {
      _bird = Offset(
        _from.dx + math.sin(t * 80) * ReviveConfig.tremble,
        _from.dy,
      );
    } else if (t < ReviveConfig.burstAt) {
      final k =
          (t - ReviveConfig.igniteEnd) /
          (ReviveConfig.burstAt - ReviveConfig.igniteEnd);
      final e = Ease.smooth(k);
      _bird = Offset(
        _from.dx + (x1 - _from.dx) * e,
        _from.dy + (_safeY - _from.dy) * e,
      );
      _angle = _fromAngle * (1 - e) + math.sin(k * math.pi) * .4;
    } else {
      if (!_burst) _doBurst();
      final k = t - ReviveConfig.burstAt;
      _bird = Offset(x1, _safeY + math.sin(k * 6) * ReviveConfig.hoverBob);
      _angle = 0;
      _flapClock += dt;
      if (_flapClock >= ReviveConfig.hoverFlapPeriod) {
        _flapClock = 0;
        _b?.phoenixFlap();
      }
    }
    final b = _b;
    if (b != null) {
      b.placeTumble(Vector2(_bird.dx, _bird.dy), _angle);
      if (_noBody) {
        b.setSpriteOpacity(((t - ReviveConfig.igniteEnd) / .3).clamp(0.0, 1.0));
      }
    }
    _step(dt);
    if (_flash > 0) _flash = math.max(0, _flash - dt);
    if (t >= ReviveConfig.phoenixLength) {
      _done = true;
      onDone(_safeY);
    }
  }

  void _doBurst() {
    _burst = true;
    _flapClock = 0;
    _b?.phoenixAlive();
    _b?.phoenixFlap();
    game.sound.play(Sfx.rvBurst);
    _flash = ReviveConfig.flashLength;
    final at = Offset(RunConfig.birdX, _safeY);
    parent?.add(
      ShockRing(priority: priority + 2).play(
        at,
        rx: ReviveConfig.shockFrom,
        color: ReviveConfig.shockColor,
        length: ReviveConfig.shockLength,
        scaleTo: ReviveConfig.shockTo / ReviveConfig.shockFrom,
        strokeFrom: 7,
        strokeTo: 1,
      ),
    );
    for (var i = 0; i < ReviveConfig.feathers; i++) {
      _feathers.add(
        _Feather(
          x: at.dx + _rnd(-30, 30),
          y: at.dy + _rnd(-20, 10),
          vx: _rnd(-90, 90),
          vy: _rnd(-200, -60),
          rot: _rnd(0, 6),
          vr: _rnd(-6, 6),
          sw: _rnd(0, 6),
          life: _rnd(1.4, 2.2),
          gold: _r.nextDouble() < .6,
        ),
      );
    }
    for (var i = 0; i < ReviveConfig.embers; i++) {
      final a = _rnd(0, 2 * math.pi), v = _rnd(80, 300);
      _embers.add(
        _Ember(
          at.dx,
          at.dy,
          math.cos(a) * v,
          math.sin(a) * v - 60,
          _rnd(.5, 1),
        ),
      );
    }
  }

  void _flame(double x, double y, double s) {
    _flames.add(
      _Flame(
        x: x + _rnd(-1, 1) * ReviveConfig.flameSpread * s,
        y: y + _rnd(-4, 8),
        vx: _rnd(-14, 14),
        vy: -_rnd(ReviveConfig.flameVMin, ReviveConfig.flameVMax) * s,
        r: _rnd(ReviveConfig.flameRMin, ReviveConfig.flameRMax) * s,
        life: _rnd(ReviveConfig.flameLifeMin, ReviveConfig.flameLifeMax),
      ),
    );
  }

  void _step(double dt) {
    for (final f in _flames) {
      f.t += dt;
      f.x += f.vx * dt;
      f.y += f.vy * dt;
    }
    _flames.removeWhere((f) => f.t >= f.life);
    for (final e in _embers) {
      e.t += dt;
      e.vy += 120 * dt;
      e.x += e.vx * dt;
      e.y += e.vy * dt;
    }
    _embers.removeWhere((e) => e.t >= e.life);
    for (final p in _feathers) {
      p.t += dt;
      p.vy = math.min(p.vy + 180 * dt, 70);
      p.sw += dt * 4;
      p.x += p.vx * dt + math.sin(p.sw) * 30 * dt;
      p.vx *= 1 - 1.5 * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
    }
    _feathers.removeWhere((p) => p.t >= p.life);
  }

  /// Particles still alive (the component stays until they are gone).
  bool get idle => _flames.isEmpty && _embers.isEmpty && _feathers.isEmpty;

  final Paint _p = Paint();

  @override
  void render(Canvas canvas) {
    // Gold glow behind the rising bird.
    final t = _t;
    final glow = t < ReviveConfig.burstAt
        ? ReviveConfig.glowFrom +
              t /
                  ReviveConfig.burstAt *
                  (ReviveConfig.glowTo - ReviveConfig.glowFrom)
        : math.max(0, ReviveConfig.glowTo - (t - ReviveConfig.burstAt) * 80);
    if (t > .2 && glow > 0 && !_done) {
      _p
        ..blendMode = BlendMode.srcOver
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow / 2)
        ..color = ReviveConfig.glowColor.withValues(alpha: .85);
      canvas.drawCircle(_bird, 20, _p);
      _p.maskFilter = null;
    }
    // Additive flames + embers.
    for (final f in _flames) {
      final k = 1 - f.t / f.life;
      final r = f.r * (.5 + k * .7);
      final c = k > .66
          ? ReviveConfig.flameHot
          : k > .33
          ? ReviveConfig.flameMid
          : ReviveConfig.flameCool;
      _p
        ..blendMode = BlendMode.plus
        ..shader = Gradient.radial(Offset(f.x, f.y), r, [
          c.withValues(alpha: .85 * k),
          c.withValues(alpha: 0),
        ]);
      canvas.drawCircle(Offset(f.x, f.y), r, _p);
    }
    _p.shader = null;
    for (final e in _embers) {
      final k = 1 - e.t / e.life;
      _p.color = Color.fromRGBO(255, (180 + 60 * k).round(), 80, k);
      canvas.drawRect(Rect.fromLTWH(e.x - 1.5, e.y - 1.5, 3, 3), _p);
    }
    _p.blendMode = BlendMode.srcOver;
    // Flame wings (0.45 s → spread by 0.85 s, gone after 1.05 s).
    if (t < 1.05) {
      final sp = ((t - .45) / .4).clamp(0.0, 1.0);
      if (sp > 0) {
        _p.blendMode = BlendMode.plus;
        for (final side in const [-1.0, 1.0]) {
          for (var i = 0; i < ReviveConfig.wingBlades; i++) {
            final a = -.62 + i * .25 + math.sin(t * 1000 / 90 + i) * .06;
            final len =
                (ReviveConfig.wingBase + i * ReviveConfig.wingStep) * sp;
            _p.color = Color.fromRGBO(255, 110 + i * 24, 30, .8 * sp);
            Offset pt(double ang, double l, double dy) => Offset(
              _bird.dx + side * (6 + math.cos(ang) * l),
              _bird.dy + math.sin(ang) * l + dy,
            );
            canvas.drawPath(
              Path()
                ..moveTo(_bird.dx + side * 6, _bird.dy)
                ..lineTo(pt(a, len, -10).dx, pt(a, len, -10).dy)
                ..lineTo(
                  pt(a + .14, len * .8, -4).dx,
                  pt(a + .14, len * .8, -4).dy,
                )
                ..close(),
              _p,
            );
          }
        }
        _p.blendMode = BlendMode.srcOver;
      }
    }
    // Gold feathers.
    for (final f in _feathers) {
      final k = 1 - f.t / f.life;
      final a = math.min(1.0, k * 2);
      canvas
        ..save()
        ..translate(f.x, f.y)
        ..rotate(f.rot);
      _p.color = (f.gold ? const Color(0xFFFFB529) : const Color(0xFFFFD54A))
          .withValues(alpha: a);
      canvas.drawOval(const Rect.fromLTRB(-9, -3, 9, 3), _p);
      _p
        ..color = const Color(0xFFC98A00).withValues(alpha: a)
        ..strokeWidth = 1;
      canvas
        ..drawLine(const Offset(-9, 0), const Offset(9, 0), _p)
        ..restore();
    }
    // The warm flash.
    if (_flash > 0) {
      _p.color = ReviveConfig.flashColor.withValues(
        alpha: ReviveConfig.flashAlpha * _flash / ReviveConfig.flashLength,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, RunConfig.worldWidth, game.viewHeight),
        _p,
      );
    }
  }
}

class _Flame {
  _Flame({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.life,
  });
  double x, y, vx, vy, r, life, t = 0;
}

class _Ember {
  _Ember(this.x, this.y, this.vx, this.vy, this.life);
  double x, y, vx, vy, life, t = 0;
}

class _Feather {
  _Feather({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rot,
    required this.vr,
    required this.sw,
    required this.life,
    required this.gold,
  });
  double x, y, vx, vy, rot, vr, sw, life, t = 0;
  final bool gold;
}
