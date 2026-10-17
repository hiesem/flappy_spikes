import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../../game/config.dart';
import '../../../game/sound.dart';
import '../../../menu/wallet.dart';
import '../../config/run_config.dart';
import '../../config/special_hoops_config.dart';
import '../../hud/banners.dart';
import '../../hud/run_hud.dart';
import '../../run_context.dart';
import '../hoop.dart';
import '../../director/plans.dart';
import '../hoop_kind.dart';
import '../ring_painter.dart';
import 'normal.dart';

/// Lucky Spin (PRD-2 §3.25, §5.24; lab mock `?only=lucky`): a normal hoop
/// (score, coins, streak, rim bounce, tier look) with a small **prize
/// wheel** on a 3 pt post 36 pt above its top rim.
///
/// - The prize is **pre-rolled at spawn** by the director from the run's
///   `layout` stream ([SpinPrize]: slices +2, +5, +10, +3, +20, +5, equal
///   chance, Q64), so the same seed always pays the same.
/// - The wheel spins at 7 rad/s while the ring approaches (a soft tick per
///   slice). Its approach angle is a function of the bird's distance to the
///   plane, phased so that after the pass it slows (≈ 8 rad/s²) and stops
///   after ≈ 0.9 s **exactly on the pre-rolled slice**.
/// - At the stop the slice is paid at once ([CoinSource.luckySpin]): a
///   banner with the prize in the slice colour, a burst at the wheel, the
///   win chord and `lucky_spin` (prize). The pass itself plays the whoosh.
class LuckySpinHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.luckySpin;

  @override
  bool get usesTierLook => true;

  static final Expando<LuckyWheel> _wheels = Expando('luckyWheel');

  /// The wheel of [h] (tests).
  static LuckyWheel? wheelOf(Hoop h) => _wheels[h];

  static const double seg = 2 * math.pi / 6;

  /// §5.24 the slice under the top pointer for wheel angle [a] (the mock's
  /// `idxOf`).
  static int sliceAt(double a) {
    final u =
        ((-math.pi / 2 - a) % (2 * math.pi) + 2 * math.pi) % (2 * math.pi);
    return (u / seg).floor() % 6;
  }

  /// Distance (rad) the wheel turns while slowing from 7 rad/s at 8 rad/s².
  static double get stopDistance =>
      LuckySpinConfig.spin * LuckySpinConfig.spin / (2 * LuckySpinConfig.decel);

  @override
  void buildVisual(Hoop h, RunContext c) {
    final skin = c.game.menu.items.look.hoop;
    final prize = h.plan.extra is SpinPrize
        ? h.plan.extra! as SpinPrize
        : const SpinPrize(0, 2);
    final wheel = LuckyWheel(h, c, prize);
    _wheels[h] = wheel;
    h.add(wheel);
    h.paintBack = (canvas) => NormalHoopKind.paintRings(
      canvas,
      h,
      skin,
      front: false,
      t: c.s.runClock,
    );
    h.front.paintFront = (canvas) {
      NormalHoopKind.paintRings(canvas, h, skin, front: true, t: c.s.runClock);
      void paint() => paintWheel(
        canvas,
        Offset(0, -RingPainter.ryFor(h.opening) + h.rings.first),
        wheel.angle,
        c.game.foregroundColor,
      );
      if (!h.rewardStripped) {
        paint();
      } else if (h.rewardAlpha > 0) {
        // PRD-2.2 §27.3 the wheel fades, the ring stays.
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromRGBO(0, 0, 0, h.rewardAlpha),
        );
        paint();
        canvas.restore();
      }
    };
  }

  static final List<TextPainter> _labels = [
    for (final v in RunConfig.luckySpinSlices)
      TextPainter(
        text: TextSpan(
          text: '+$v',
          style: const TextStyle(
            fontFamily: Config.uiFont,
            fontSize: LuckySpinConfig.labelSize,
            color: Color(0xFFFFFFFF),
          ),
        ),
        textDirection: p.TextDirection.ltr,
      )..layout(),
  ];

  /// §5.24 the post (3 pt, stage foreground) from the top rim [rimTop]
  /// (hoop-local) up to the wheel (r 24, centre 36 pt above the rim), six
  /// coloured slices with white labels, a white rim and hub, and the
  /// pointer triangle on top.
  static void paintWheel(Canvas canvas, Offset rimTop, double angle, Color fg) {
    const r = LuckySpinConfig.radius;
    final c = rimTop.translate(0, -LuckySpinConfig.above);
    canvas.drawLine(
      rimTop,
      c.translate(0, r),
      Paint()
        ..strokeWidth = LuckySpinConfig.postWidth
        ..color = fg,
    );
    final fill = Paint();
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < 6; i++) {
      final a0 = angle + i * seg;
      fill.color = LuckySpinConfig.sliceColors[i];
      canvas.drawArc(rect, a0, seg, true, fill);
      final am = a0 + seg / 2;
      final tp = _labels[i];
      canvas.save();
      canvas.translate(
        c.dx + math.cos(am) * r * .64,
        c.dy + math.sin(am) * r * .64,
      );
      canvas.rotate(am + math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(c, 3.5, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 6, c.dy - r - 10)
        ..lineTo(c.dx + 6, c.dy - r - 10)
        ..lineTo(c.dx, c.dy - r + 3)
        ..close(),
      Paint()..color = fg,
    );
  }

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    // PRD-2.2 §27.3 an activity stripped the wheel: a normal pass.
    if (h.rewardStripped) return;
    _wheels[h]?.release();
    c.sfx(Sfx.luckyWhoosh);
  }
}

/// One hoop's prize wheel (world time: pauses with the run, slows with the
/// Hourglass, keeps turning through the death tumble).
class LuckyWheel extends Component {
  LuckyWheel(this.hoop, this.c, this.prize) {
    final jitter = (c.cosmetic.nextDouble() - .5) * .6;
    stopAngle =
        -math.pi / 2 - (prize.slice + .5 + jitter) * LuckySpinHoopKind.seg;
    _approachAngle = stopAngle - LuckySpinHoopKind.stopDistance;
    _speedRef = RunConfig.cruise(c.s.hoopIndex);
    angle = _angleAt(_distance());
  }

  final Hoop hoop;
  final RunContext c;
  final SpinPrize prize;

  /// The angle the wheel ends on (the prize slice under the pointer).
  late final double stopAngle;
  late final double _approachAngle;
  late final double _speedRef;

  double angle = 0;
  double _dMin = double.infinity;

  /// Seconds since the pass (null before).
  double? _since;
  double _from = 0, _decel = LuckySpinConfig.decel, _stopT = 0;

  bool get released => _since != null;
  bool stopped = false;
  bool paid = false;

  /// The bird's distance to the plane (pt; ≥ 0 before the pass).
  double _distance() {
    final bird = c.run.birdTrackPosition()?.x ?? c.s.camX + RunConfig.birdX;
    return hoop.planeX - bird;
  }

  double _angleAt(double d) {
    _dMin = math.min(_dMin, d);
    return _approachAngle - LuckySpinConfig.spin * _dMin / _speedRef;
  }

  /// The bird flew through: slow down onto the prize slice.
  void release() {
    if (released) return;
    _since = 0;
    _from = angle;
    var d = stopAngle - angle;
    // Keep the stop within one turn of the nominal 8 rad/s² slow-down.
    final nominal = LuckySpinHoopKind.stopDistance;
    while (d < nominal - math.pi) {
      d += 2 * math.pi;
    }
    while (d > nominal + math.pi) {
      d -= 2 * math.pi;
    }
    if (d < 1) d += 2 * math.pi;
    _decel = LuckySpinConfig.spin * LuckySpinConfig.spin / (2 * d);
    _stopT = 2 * d / LuckySpinConfig.spin;
    _target = _from + d;
  }

  double _target = 0;

  /// Seconds from the pass to the stop.
  double get stopSeconds => _stopT;

  @override
  void update(double dt) {
    final before = angle;
    final since = _since;
    if (since == null) {
      angle = _angleAt(_distance());
    } else if (!stopped) {
      final t = since + dt;
      _since = t;
      if (t >= _stopT) {
        angle = _target;
        stopped = true;
        _pay();
      } else {
        angle = _from + LuckySpinConfig.spin * t - _decel * t * t / 2;
      }
    }
    if (angle != before &&
        !hoop.rewardStripped && // PRD-2.2 §27.3 a faded wheel is silent
        LuckySpinHoopKind.sliceAt(angle) != LuckySpinHoopKind.sliceAt(before) &&
        _onScreen) {
      c.sfx(Sfx.luckyTick);
    }
  }

  bool get _onScreen {
    final x = hoop.planeX - c.s.camX;
    return x > c.s.viewLeft - LuckySpinConfig.tickMargin && // WP-TAB
        x < RunConfig.worldWidth + LuckySpinConfig.tickMargin;
  }

  void _pay() {
    if (paid) return;
    paid = true;
    final coins = prize.coins;
    c.earn(coins, CoinSource.luckySpin);
    final col = LuckySpinConfig.sliceColors[prize.slice % 6];
    if (!c.run.dying && !c.run.ended) {
      RunHud.ensureFor(c.run).banners.show(
        ElementBanner(
          '+$coins',
          color: col,
          subtitle: LuckySpinConfig.bannerSub,
        ),
      );
    }
    c.sfx(Sfx.luckyWin);
    final f = hoop.frame();
    final at = f.toWorld(
      Vector2(0, -RingPainter.ryFor(hoop.opening) - LuckySpinConfig.above),
    );
    final r = c.cosmetic;
    for (var i = 0; i < LuckySpinConfig.burst; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final v = LuckySpinConfig.burstSpeed * (.5 + r.nextDouble() * .7);
      c.run.particles.spawn(
        x: at.x,
        y: at.y,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 4 + r.nextDouble() * 3,
        color: i.isEven ? col : const Color(0xFFFFFFFF),
        life: .45 + r.nextDouble() * .25,
        damp: 2.4,
      );
    }
    c.track('lucky_spin', {'prize': coins});
  }

  @override
  void onRemove() {
    // Culled before the wheel settled: the prize is still paid.
    if (released && !paid && !c.run.ended) {
      angle = _target;
      stopped = true;
      _pay();
    }
    super.onRemove();
  }
}
