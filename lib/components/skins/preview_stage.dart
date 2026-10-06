import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../game/sound.dart';
import '../../skins/art/art_paint.dart';
import '../../skins/art/hoop_painter.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/art/trail.dart';
import '../../skins/look.dart';
import 'item_art.dart';

/// One hoop scrolling through the preview.
class PreviewHoop {
  PreviewHoop(this.x);

  double x;
  bool passed = false;

  /// Seconds since the bird passed it (null before the pass).
  double? pulse;
}

/// One celebration confetti piece (some are stars).
class _Confetti {
  _Confetti({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.max,
    required this.color,
    required this.size,
    required this.rot,
    required this.vr,
    required this.star,
  });

  double x, y, vx, vy, rot;
  double life = 0;
  final double max, size, vr;
  final Color color;
  final bool star;
}

/// The skin shop's live preview (PRD-menu-v2 §4.2, mock `Stage` in
/// `design/menu_v2/skin_shop.js`, layout A): the current look at 1.9 x,
/// hovering at 42 % of the stage width with a ±3 pt bob and flapping; hoops
/// of the selected hoop skin scroll in from the right every 2.3 s at
/// 120 pt/s and the bird flies through them (back half behind it, front
/// half in front, a white pulse ring on each pass). The trail burns for
/// 1.7 s after each pass and always while the TRAILS tab is open.
///
/// The tried-on layer is drawn as one flat layer at `0.42 + 0.14 sin(4t)`
/// ([tryOnAlpha]). [hop] kicks the bird up (−150 pt/s, 900 pt/s² back);
/// [celebrate] throws confetti (and rays for epic / legendary).
class PreviewStage extends PositionComponent {
  PreviewStage({
    required Rect rect,
    required this.look,
    required this.triedLayer,
    required this.tab,
    required this.background,
    required this.play,
    required this.reduceMotion,
    math.Random? random,
  }) : _random = random ?? math.Random(),
       super(position: rect.topLeft.toVector2(), size: rect.size.toVector2()) {
    _trail = TrailEmitter(
      Look.defaults.trail,
      random: _random,
      lookPainter: paintLookForTrail,
    );
  }

  /// The look on the preview bird: equipped plus the try-on.
  final Look Function() look;

  /// The layer being tried on (null = none).
  final SkinLayer? Function() triedLayer;
  final SkinLayer Function() tab;
  final Color Function() background;

  /// Plays a sound (no-op while the screen is leaving).
  final void Function(Sfx sfx) play;
  final bool Function() reduceMotion;

  final math.Random _random;
  late final TrailEmitter _trail;

  double t = 0;
  double _vy = 0;
  double _dy = 0;
  double _next = Config.skinShopHoopFirst;
  double _fireT = 0;
  double _rays = 0;
  String? _lastHoop;
  String? _lastFire;
  final List<PreviewHoop> hoops = [];
  final List<_Confetti> _confetti = [];

  static const double k = Config.skinShopBirdScale;

  /// Bird centre x.
  double get birdX => width * Config.skinShopBirdX;

  /// Bird centre y without the bob.
  double get birdY => height / 2 + _dy;

  /// Vertical hop velocity (negative = rising).
  double get hopVelocity => _vy;

  /// Whether the trail shows right now.
  bool get showsTrail => _fireT > 0 || tab() == SkinLayer.trail;

  /// Live confetti pieces.
  int get confettiCount => _confetti.length;

  /// Seconds of light rays left (epic / legendary celebrations).
  double get rays => _rays;

  /// The trail emitter (tests).
  TrailEmitter get trail => _trail;

  /// Opacity of the tried-on layer right now.
  double get tryOnAlpha => reduceMotion() ? .42 : .42 + .14 * math.sin(t * 4);

  /// Remembers the equipped hoop / trail so only a CHANGE plays `sk_hoop` /
  /// `sk_fire` (PRD-menu-v2 §4.2).
  void primeSounds(Look look) {
    _lastHoop = look.hoop;
    _lastFire = look.trail;
  }

  /// The bird hops ([strength] x the −150 pt/s kick) with `flap.mp3`.
  void hop([double strength = 1]) {
    _vy = -Config.skinShopHopKick * strength;
    play(Sfx.flap);
  }

  /// Purchase celebration by [rarity] (§3.6): confetti from the bird in the
  /// rarity's colours (every fifth piece a star), rays behind the bird for
  /// epic (1.4 s) and legendary (2.6 s, unless [reduceMotion]), a big hop.
  void celebrate(Rarity rarity) {
    final (colors, count) = switch (rarity) {
      Rarity.common => (
        const [Color(0xFF9A9A9A), Color(0xFFFFFFFF), Config.menuPink],
        30,
      ),
      Rarity.rare => (
        const [
          Color(0xFF1E9BE0),
          Color(0xFF81D4FA),
          Color(0xFFFFFFFF),
          Config.menuPink,
        ],
        50,
      ),
      Rarity.epic => (
        const [
          Color(0xFF9B30D9),
          Color(0xFFE1BEE7),
          Config.menuPink,
          Color(0xFFFFFFFF),
        ],
        80,
      ),
      Rarity.legendary => (
        const [
          Config.menuGold,
          Color(0xFFFFE082),
          Color(0xFFFFFFFF),
          Color(0xFFFF9100),
          Config.menuPink,
        ],
        140,
      ),
    };
    final legendary = rarity == Rarity.legendary;
    for (var i = 0; i < count; i++) {
      final a = _random.nextDouble() * math.pi * 2;
      final v = 60 + _random.nextDouble() * (legendary ? 260 : 170);
      _confetti.add(
        _Confetti(
          x: birdX,
          y: birdY,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v - 60,
          max: .9 + _random.nextDouble() * .8,
          color: colors[i % colors.length],
          size: 3 + _random.nextDouble() * 4,
          rot: _random.nextDouble() * 6,
          vr: (_random.nextDouble() - .5) * 12,
          star: i % 5 == 0,
        ),
      );
    }
    if (!reduceMotion() && (legendary || rarity == Rarity.epic)) {
      _rays = legendary ? 2.6 : 1.4;
    }
    hop(1.3);
  }

  @override
  void update(double dt) {
    super.update(dt);
    t += dt;
    final current = look();
    _vy += Config.skinShopHopGravity * dt;
    _dy += _vy * dt;
    if (_dy > 0) {
      _dy = 0;
      _vy = 0;
    }

    _next -= dt;
    if (_next <= 0) {
      _next = Config.skinShopHoopInterval;
      hoops.add(PreviewHoop(width + 40));
    }
    for (final hoop in hoops) {
      hoop.x -= Config.skinShopHoopSpeed * dt;
      if (!hoop.passed && hoop.x < birdX) {
        hoop.passed = true;
        hoop.pulse = 0;
        _fireT = Config.skinShopFireAfterPass;
        if (_lastHoop != current.hoop) play(Sfx.skHoop);
        _lastHoop = current.hoop;
      } else if (hoop.pulse != null) {
        hoop.pulse = hoop.pulse! + dt;
      }
    }
    hoops.removeWhere((hoop) => hoop.x <= -50);

    _fireT -= dt;
    final onTrails = tab() == SkinLayer.trail;
    if (showsTrail && onTrails && _lastFire != current.trail) {
      play(Sfx.skFire);
    }
    if (onTrails) _lastFire = current.trail;

    _trail
      ..trailId = current.trail
      ..look = current;
    if (showsTrail) {
      _trail.emit(
        Offset(birdX - 17 * k, birdY + _bob),
        dt,
        k: k,
        vx: Config.skinShopTrailScroll,
      );
    } else {
      _trail.resetPath();
    }
    _trail.step(dt);

    for (final p in _confetti) {
      p.life += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 260 * dt;
      p.vx *= .985;
      p.rot += p.vr * dt;
    }
    _confetti.removeWhere((p) => p.life >= p.max);
    _rays = math.max(0, _rays - dt);
  }

  double get _bob =>
      math.sin(t * Config.skinShopBobSpeed) * Config.skinShopBobAmplitude;

  static final Paint _paint = Paint();
  static final Paint _layer = Paint();
  static final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(toRect());
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _paint..color = background());
    final current = look();
    final tried = triedLayer();
    final dim = tried == null ? null : tryOnAlpha;
    final bx = birdX;
    final bob = _bob;
    final by = birdY + bob;

    if (_rays > 0) {
      canvas.save();
      canvas.translate(bx, by);
      canvas.rotate(t * .6);
      final alpha = math.min(1.0, _rays) * .5;
      for (var i = 0; i < 12; i++) {
        _paint.color = (i.isOdd ? Config.menuGold : const Color(0xFFFFE082))
            .withValues(alpha: alpha);
        final a0 = i * math.pi * 2 / 12;
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..arcTo(
              Rect.fromCircle(center: Offset.zero, radius: width),
              a0,
              math.pi / 12,
              false,
            )
            ..close(),
          _paint,
        );
      }
      canvas.restore();
    }

    const ry = Config.skinShopHoopRy * k;
    const lw = ry * .17;
    final hoopDim = tried == SkinLayer.hoop ? dim : null;
    void hoopHalves({required bool front}) {
      _withAlpha(canvas, hoopDim, () {
        for (final hoop in hoops) {
          HoopPainter.paintHalf(
            canvas,
            current.hoop,
            Offset(hoop.x, by - bob),
            ry,
            t,
            front: front,
            lineWidth: lw,
          );
        }
      });
    }

    hoopHalves(front: false);
    _withAlpha(
      canvas,
      tried == SkinLayer.trail ? dim : null,
      () => _trail.paint(canvas, k: k),
    );

    final flap = (t * (_vy < 0 ? 9 : 3.3)) % 1 < .35;
    canvas.save();
    canvas.translate(bx, by);
    canvas.rotate((_vy / 600).clamp(-.35, .25));
    canvas.scale(k);
    LookPainter.paint(
      canvas,
      current,
      t: t,
      flap: flap,
      dim: tried == null || dim == null ? const {} : {tried: dim},
    );
    canvas.restore();

    hoopHalves(front: true);
    for (final hoop in hoops) {
      final pulse = hoop.pulse;
      if (pulse == null || pulse >= .4) continue;
      _ring.color = const Color(0xFFFFFFFF).withValues(alpha: 1 - pulse / .4);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(hoop.x, by - bob),
          width: 2 * ry * .26 * (1 + pulse * 2),
          height: 2 * ry * (1 + pulse * .6),
        ),
        _ring,
      );
    }

    for (final p in _confetti) {
      final u = p.life / p.max;
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rot);
      final color = p.color.withValues(alpha: (1 - u * u).clamp(0.0, 1.0));
      if (p.star) {
        ArtPaint.star(canvas, 0, 0, p.size * 1.3, color, 0);
      } else {
        canvas.drawRect(
          Rect.fromLTWH(-p.size / 2, -p.size / 4, p.size, p.size / 2),
          _paint..color = color,
        );
      }
      canvas.restore();
    }
  }

  void _withAlpha(Canvas canvas, double? alpha, void Function() draw) {
    if (alpha == null) {
      draw();
      return;
    }
    canvas.saveLayer(
      size.toRect(),
      _layer..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)),
    );
    draw();
    canvas.restore();
  }
}
