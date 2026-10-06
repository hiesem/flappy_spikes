import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flutter/animation.dart' show Curves;

/// The shared idle-motion language of the live home & Shop (PRD-menu-v2
/// §8.1), ported from the CSS keyframes of
/// `design/menu_v2/build55.py` (`screen_home_shop_live.html`). The timings
/// are final (approved after being slowed 2x).
///
/// Three parts:
/// - [LiveCurves]: pure functions "value at loop time t" (unit-testable);
/// - decorators that draw an effect on any [PositionComponent]
///   ([WiggleEffect], [PulseEffect], [LightStreak]) — add them with
///   `component.decorator.addLast(effect)`; they work in the component's
///   local space, after its own transform;
/// - [LiveClock], a component that advances one idle clock (frozen while
///   [LiveClock.paused]) and pushes the curves into the decorators every
///   frame, or rests them all while [LiveClock.still] (reduce motion).

/// One keyframe track: (offset 0..1, value) stops, CSS `ease-in-out`
/// between neighbouring stops (the animation timing function applies per
/// keyframe interval, as in CSS).
double evalKeyframes(List<(double, double)> stops, double u) {
  if (u <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    final (o1, v1) = stops[i];
    if (u <= o1) {
      final (o0, v0) = stops[i - 1];
      final span = o1 - o0;
      if (span <= 0) return v1;
      final k = Curves.easeInOut.transform(((u - o0) / span).clamp(0.0, 1.0));
      return v0 + (v1 - v0) * k;
    }
  }
  return stops.last.$2;
}

/// Phase 0..1 of a [period] s loop at time [t] started after [delay] s
/// (CSS `animation-delay`); -1 before the delay (the animation has not
/// started yet and the element shows its un-animated style).
double loopPhase(double t, double period, {double delay = 0}) {
  final local = t - delay;
  if (local < 0) return -1;
  return (local % period) / period;
}

/// A scale + rotation pair (rotation in degrees, as in the CSS).
typedef LivePose = ({double scale, double degrees});

abstract final class LiveCurves {
  /// Light streak loop (s) and the share of it spent sweeping.
  static const double streakPeriod = 6.4;
  static const double streakSweep = 0.28;

  /// Band width as a share of the button width; skew (deg); peak alpha.
  static const double streakWidth = 0.45;
  static const double streakSkewDegrees = -20;
  static const double streakAlpha = 0.55;

  /// Pulse loop (s), shared by the home slot, GET and the camera nod.
  static const double pulsePeriod = 3.2;

  static const double glintPeriod = 8.4;
  static const double newTagPeriod = 4.4;
  static const double packTagPeriod = 6;
  static const double trophyPeriod = 10;

  /// Left edge of the streak band as a share of the button width (CSS
  /// `left` -70 % -> 135 % during the first 28 % of the loop), or null
  /// while it rests off the button (also before [delay]).
  static double? streak(double t, {double delay = 0}) {
    final u = loopPhase(t, streakPeriod, delay: delay);
    if (u < 0 || u >= streakSweep) return null;
    return evalKeyframes(const [(0, -0.7), (streakSweep, 1.35)], u);
  }

  /// Pulse amount 0 (rest) .. 1 (peak at mid-loop): scale `1 + amount * k`
  /// and the glow's blur / spread / alpha all follow it (`spulse`,
  /// `gpulse`).
  static double pulse(double t) => evalKeyframes(const [
    (0, 0),
    (0.5, 1),
    (1, 0),
  ], loopPhase(t, pulsePeriod));

  /// Camera icon nod in degrees (`camnod`): −10° then +6° at each pulse
  /// peak.
  static double cameraNod(double t) => evalKeyframes(const [
    (0, 0),
    (0.4, 0),
    (0.5, -10),
    (0.6, 6),
    (1, 0),
  ], loopPhase(t, pulsePeriod));

  /// Home Skins-tile NEW tag (`wob`): pop to 114 % at +5°, then −3°.
  static LivePose newTagWobble(double t) {
    final u = loopPhase(t, newTagPeriod);
    return (
      scale: evalKeyframes(const [
        (0, 1),
        (0.7, 1),
        (0.78, 1.14),
        (0.86, 1),
        (1, 1),
      ], u),
      degrees: evalKeyframes(const [
        (0, 0),
        (0.7, 0),
        (0.78, 5),
        (0.86, -3),
        (1, 0),
      ], u),
    );
  }

  /// Shop MOST POPULAR / BEST DEAL flaps (`wob2`): 107 %, −2° / +1°.
  static LivePose packTagWiggle(double t) {
    final u = loopPhase(t, packTagPeriod);
    return (
      scale: evalKeyframes(const [
        (0, 1),
        (0.8, 1),
        (0.86, 1.07),
        (0.92, 1),
        (1, 1),
      ], u),
      degrees: evalKeyframes(const [
        (0, 0),
        (0.8, 0),
        (0.86, -2),
        (0.92, 1),
        (1, 0),
      ], u),
    );
  }

  /// Home trophy (`tro`): −8° at 106 %, then +5°.
  static LivePose trophyWiggle(double t) {
    final u = loopPhase(t, trophyPeriod);
    return (
      scale: evalKeyframes(const [
        (0, 1),
        (0.88, 1),
        (0.92, 1.06),
        (0.96, 1),
        (1, 1),
      ], u),
      degrees: evalKeyframes(const [
        (0, 0),
        (0.88, 0),
        (0.92, -8),
        (0.96, 5),
        (1, 0),
      ], u),
    );
  }

  /// White 4-point glint on the pill coin (`glint`): opacity, scale and
  /// rotation (deg); invisible for the first 86 % of the 8.4 s loop.
  static ({double opacity, double scale, double degrees}) glint(double t) {
    final u = loopPhase(t, glintPeriod);
    const fade = [
      (0.0, 0.0),
      (0.86, 0.0),
      (0.91, 1.0),
      (0.97, 0.0),
      (1.0, 0.0),
    ];
    return (
      opacity: evalKeyframes(fade, u),
      scale: evalKeyframes(fade, u),
      degrees: evalKeyframes(const [
        (0, 0),
        (0.86, 0),
        (0.91, 45),
        (0.97, 90),
        (1, 90),
      ], u),
    );
  }

  /// Pack coin-stack hop on press (`hop`, 0.35 s ease-out): −4 pt at mid.
  static const double packHopDuration = 0.35;
  static double packHop(double t) {
    if (t < 0 || t >= packHopDuration) return 0;
    final u = t / packHopDuration;
    final k = Curves.easeOut.transform(u < .5 ? u * 2 : (1 - u) * 2);
    return -4 * k;
  }
}

/// Scales and rotates a component about [pivot] (a fraction of its size;
/// CSS `transform-origin`, default centre). Identity draws straight
/// through.
class WiggleEffect extends Decorator {
  WiggleEffect(this.target, {this.pivot = Anchor.center});

  /// The component whose size the pivot refers to (rebuilt children
  /// re-target the same effect).
  PositionComponent target;
  final Anchor pivot;

  double scale = 1;

  /// Rotation in radians.
  double angle = 0;

  void setPose(LivePose pose) {
    scale = pose.scale;
    angle = pose.degrees * math.pi / 180;
  }

  void rest() {
    scale = 1;
    angle = 0;
  }

  bool get isIdentity => scale == 1 && angle == 0;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    if (isIdentity) {
      draw(canvas);
      return;
    }
    final px = target.size.x * pivot.x, py = target.size.y * pivot.y;
    canvas.save();
    canvas.translate(px, py);
    if (angle != 0) canvas.rotate(angle);
    if (scale != 1) canvas.scale(scale);
    canvas.translate(-px, -py);
    draw(canvas);
    canvas.restore();
  }
}

/// The focus pulse (§8.1): `1 + amount * k` scale about the centre and a
/// soft coloured box-shadow glow `0 0 blur spread color` whose blur,
/// spread and alpha all grow with [k] (0 rest .. 1 peak). [inflate] grows
/// the glowing box beyond the component's box (e.g. the home slot's
/// outline).
class PulseEffect extends WiggleEffect {
  PulseEffect(
    super.target, {
    required this.amount,
    required this.glowColor,
    required this.glowBlur,
    this.glowSpread = 3,
    this.inflate = 0,
  });

  /// Peak scale increase (0.035 home slot, 0.05 GET).
  final double amount;

  /// Glow colour at the peak (alpha included).
  final Color glowColor;

  /// CSS blur radius (pt) at the peak; sigma is half of it.
  final double glowBlur;
  final double glowSpread;
  final double inflate;

  double _k = 0;
  final Paint _glow = Paint();

  double get k => _k;
  set k(double value) {
    _k = value.clamp(0.0, 1.0);
    scale = 1 + amount * _k;
  }

  @override
  void rest() {
    super.rest();
    _k = 0;
  }

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    if (_k <= 0) {
      draw(canvas);
      return;
    }
    super.apply((c) {
      _glow
        ..color = glowColor.withValues(alpha: glowColor.a * _k)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur * _k / 2);
      c.drawRect(
        (Vector2.zero() & target.size).inflate(inflate + glowSpread * _k),
        _glow,
      );
      draw(c);
    }, canvas);
  }
}

/// The light streak (§8.1): a white band [LiveCurves.streakWidth] of the
/// button's width, skewed −20°, soft gradient (transparent -> white 55 %
/// -> transparent at CSS 100deg), drawn over the component clipped to its
/// box. [progress] is the band's left edge as a share of the width (null =
/// resting, nothing drawn).
class LightStreak extends Decorator {
  LightStreak(this.target, {this.delay = 0});

  PositionComponent target;

  /// Cascade delay of this button's loop (s).
  final double delay;

  double? progress;

  final Paint _paint = Paint();

  /// Sets [progress] from the idle clock.
  void at(double t) => progress = LiveCurves.streak(t, delay: delay);

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    draw(canvas);
    final p = progress;
    if (p == null) return;
    final w = target.size.x, h = target.size.y;
    if (w <= 0 || h <= 0) return;
    final bw = w * LiveCurves.streakWidth, bh = h * 1.2;
    final band = Rect.fromLTWH(p * w, -0.1 * h, bw, bh);
    // CSS linear-gradient(100deg): direction (sin, -cos) of 100°, gradient
    // line long enough to touch the box corners.
    const a = 100 * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final half = (bw * dir.dx.abs() + bh * dir.dy.abs()) / 2;
    final c = band.center;
    _paint.shader = Gradient.linear(
      c - dir * half,
      c + dir * half,
      const [
        Color(0x00FFFFFF),
        Color.fromRGBO(255, 255, 255, LiveCurves.streakAlpha),
        Color(0x00FFFFFF),
      ],
      const [0, 0.5, 1],
    );
    canvas.save();
    canvas.clipRect(Vector2.zero() & target.size);
    // skewX(-20deg) about the band's centre (CSS transform-origin).
    canvas.translate(c.dx, c.dy);
    canvas.skew(math.tan(LiveCurves.streakSkewDegrees * math.pi / 180), 0);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRect(band, _paint);
    canvas.restore();
  }
}

/// One idle clock for a screen: advances only while not [paused] (a
/// dialog, popup, ad or the debug panel is on top, §8.4) and every frame
/// calls each binding with the clock and whether motion is [still]
/// (reduce motion: bindings rest their effects).
class LiveClock extends Component {
  LiveClock({required this.paused, required this.still});

  final bool Function() paused;
  final bool Function() still;

  double _t = 0;

  /// Idle time in seconds (frozen while paused).
  double get t => _t;

  final List<void Function(double t, bool still)> _bindings = [];

  /// Registers [binding]; it runs once right away so effects start in
  /// their t = 0 pose.
  void bind(void Function(double t, bool still) binding) {
    _bindings.add(binding);
    binding(_t, still());
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!paused()) _t += dt;
    final s = still();
    for (final binding in _bindings) {
      binding(_t, s);
    }
  }
}
