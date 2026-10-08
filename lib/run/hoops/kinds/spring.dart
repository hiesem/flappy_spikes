import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../../game/config.dart';
import '../../../game/sound.dart';
import '../../config/special_hoops_config.dart';
import '../../run_context.dart';
import '../hoop.dart';
import '../../director/plans.dart';
import '../hoop_kind.dart';
import '../ring_painter.dart';
import 'normal.dart';

/// Spring Ring (PRD-2 §3.23, §5.22; lab mock `?only=spring`): a springy
/// green ring that **launches** the bird the way its chevrons point.
///
/// - **Launch:** passing through it *sets* the bird's vertical speed to
///   **−770 pt/s (up)** or **+420 pt/s (down)** and ignores flap input for
///   **0.45 s / 0.28 s** (`RunState.flapLock`; counted down by
///   `BirdMotion.step`, taps dropped by the game while it runs). Up rises
///   ≈ 235 pt; the director put the next ring 240 pt above / below (out of
///   normal reach), so the boost is needed.
/// - Otherwise a normal hoop: +1 score, coins, streak, rim bounce (no tier
///   look — the ring stays green).
/// - **Feedback:** the ring wobbles (±7 pt for 0.5 s), a green burst, the
///   "BOING ↑ / ↓" pop, the boing sound and `spring_used` (up / down).
/// - **Comet boost:** springs don't launch (§3.0.3).
class SpringHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.spring;

  @override
  bool get usesTierLook => false;

  /// §5.22 green ring colours (master #3 colours).
  static const RingColors colors = RingColors(
    SpringConfig.front,
    SpringConfig.back,
  );

  static final Expando<_SpringState> _states = Expando('spring');

  /// The launch direction of [h] (−1 up, +1 down).
  static int dirOf(Hoop h) => h.plan.extra == SpringDir.down ? 1 : -1;

  /// The wobble left on [h] (1 → 0 over 0.5 s; tests).
  static double wobbleOf(Hoop h) => _states[h]?.boing ?? 0;

  /// §5.22 the wobble offset (pt) of the rim ends for a wobble level [b]
  /// (1 → 0): sin(b × 30) × b × 7.
  static double wobbleAt(double b) => b <= 0
      ? 0
      : math.sin(b * SpringConfig.wobbleFreq) * b * SpringConfig.wobble;

  @override
  void buildVisual(Hoop h, RunContext c) {
    final state = _SpringState();
    _states[h] = state;
    h.add(state);
    h.look.colors = colors;
    final dir = dirOf(h);
    h.paintBack = (canvas) => _paintRing(canvas, h, state, front: false);
    h.front.paintFront = (canvas) {
      _paintRing(canvas, h, state, front: true);
      if (!h.look.missed) {
        paintDecor(canvas, h.opening, dir, state.t, state.boing);
      }
    };
  }

  void _paintRing(
    Canvas canvas,
    Hoop h,
    _SpringState s, {
    required bool front,
  }) {
    final w = wobbleAt(s.boing);
    if (w == 0 || h.look.missed) {
      NormalHoopKind.paintRings(canvas, h, '', front: front);
      return;
    }
    RingPainter.paintHalf(
      canvas,
      centre: Offset(0, h.rings.first),
      opening: h.opening + 2 * w,
      front: front,
      colors: h.look.colors ?? colors,
    );
  }

  /// §5.22 the coils (6 zig-zag turns, 2.6 pt, back green) above the top
  /// and below the bottom rim end, and three chevrons inside the ring that
  /// move in the launch direction [dir] (fade in / out, 1.6 cycles/s).
  static void paintDecor(
    Canvas canvas,
    double opening,
    int dir,
    double t,
    double boing,
  ) {
    final ry = RingPainter.ryFor(opening) + wobbleAt(boing);
    final coil = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = SpringConfig.coilWidth
      ..color = SpringConfig.back;
    for (final s in const [-1.0, 1.0]) {
      final y0 = s * (ry + 4);
      final path = Path()..moveTo(0, y0);
      for (var i = 1; i <= SpringConfig.coilTurns; i++) {
        path.lineTo(
          i.isOdd ? SpringConfig.coilHalfWidth : -SpringConfig.coilHalfWidth,
          y0 + s * i * SpringConfig.coilStep,
        );
      }
      canvas.drawPath(path, coil);
    }
    final chevron = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const half = SpringConfig.chevronTravel / 2;
    for (var k = 0; k < 3; k++) {
      final u = (t * SpringConfig.chevronSpeed + k / 3) % 1;
      final y = dir * (-half + SpringConfig.chevronTravel * u);
      chevron.color = SpringConfig.front.withValues(
        alpha: math.sin(u * math.pi),
      );
      canvas.drawPath(
        Path()
          ..moveTo(-7, y - dir * 6)
          ..lineTo(0, y)
          ..lineTo(7, y - dir * 6),
        chevron,
      );
    }
  }

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    final state = _states[h];
    state?.boing = 1;
    if (p.duringRide || c.s.ride != null) return; // §3.0.3 comet: no launch
    final bird = c.game.runBird;
    if (bird == null || !bird.isLoaded) return;
    final up = dirOf(h) < 0;
    bird.setFlight(
      y: bird.body.position.y,
      vy: up ? SpringConfig.launchUp : SpringConfig.launchDown,
    );
    c.s.flapLock = up ? SpringConfig.lockUp : SpringConfig.lockDown;
    c.sfx(up ? Sfx.springUp : Sfx.springDown);
    final at = c.geo.toTrack(bird.body.position);
    final r = c.cosmetic;
    for (var i = 0; i < SpringConfig.burst; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final v = SpringConfig.burstSpeed * (.5 + r.nextDouble() * .7);
      c.run.particles.spawn(
        x: at.x,
        y: at.y,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 4 + r.nextDouble() * 3,
        color: i.isEven ? SpringConfig.front : const Color(0xFFFFFFFF),
        life: .4 + r.nextDouble() * .25,
        damp: 2.4,
      );
    }
    c.layers.fx.add(
      TextPop(
        up ? SpringConfig.popUp : SpringConfig.popDown,
        Vector2(at.x + 40, at.y - 30),
        SpringConfig.front,
      ),
    );
    c.track('spring_used', {'dir': up ? 'up' : 'down'});
  }
}

/// Per-hoop chevron clock and wobble (world time).
class _SpringState extends Component {
  double t = 0;
  double boing = 0;

  @override
  void update(double dt) {
    t += dt;
    if (boing > 0) boing = math.max(0, boing - dt / SpringConfig.wobbleSeconds);
  }
}

/// A short text pop that rises and fades (the lab mocks' `pop()`: 20 pt
/// Opificio, rises 28 pt/s, fades over 1 s) — "BOING ↑ / ↓".
class TextPop extends PositionComponent {
  TextPop(this.text, Vector2 at, this.color, {this.fontSize = 20})
    : super(position: at, anchor: Anchor.center);

  final String text;
  final Color color;
  final double fontSize;
  double _t = 0;

  static const double life = 1;
  static const double rise = 28;

  late final TextPainter _tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: fontSize,
        color: color,
      ),
    ),
    textDirection: p.TextDirection.ltr,
  )..layout();

  @override
  void update(double dt) {
    _t += dt;
    position.y -= rise * dt;
    if (_t >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = (1 - _t / life).clamp(0.0, 1.0);
    if (a <= 0) return;
    canvas.saveLayer(
      Rect.fromCenter(
        center: Offset.zero,
        width: _tp.width + 8,
        height: _tp.height + 8,
      ),
      Paint()..color = Color.fromRGBO(0, 0, 0, a),
    );
    _tp.paint(canvas, Offset(-_tp.width / 2, -_tp.height / 2));
    canvas.restore();
  }
}
