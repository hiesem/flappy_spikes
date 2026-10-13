import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart'
    show FontWeight, TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/paints.dart';
import '../../game/palettes.dart';
import '../config/first_run_config.dart';
import '../config/hud_config.dart';
import '../config/run_config.dart';
import '../effects/dashed_path.dart';
import '../effects/easing.dart';
import '../run_controller.dart';
import '../run_layers.dart';
import 'banners.dart';

/// What the [FirstRunHint] draws (PRD-2.3 §10.3 / §10.3b).
enum FirstRunHintMode {
  /// §10.3 the full first-run instructions (veil, bands, flap path, banner,
  /// hand), up from the start of the very first run's wait.
  firstRun,

  /// §10.3b only the hand and the TAP TO FLAP! banner, after
  /// `Config.tapReminderDelay` s of waiting without a tap.
  reminder,
}

/// PRD-2.3 §10.3 / §10.3b the first-run instructions (approved design D,
/// `design/onboarding_v23/first_run_src.html`) and the tap reminder: one
/// component in the run's HUD layer, below the pause button. The reminder
/// mode draws the same hand and banner (one master each, CLAUDE.md), nothing
/// else. The veil over the score circle is a [FirstRunVeil] in the world
/// (between the score circle and the gameplay), driven by this component.
///
/// The game calls [dismiss] on the first tap: the instructions fade out over
/// `Config.firstRunHintFadeOut` (linear, as in the design), a visible
/// reminder over `Config.tapReminderFadeOut` (ease-in); a reminder that never
/// showed goes at once. The fade never delays the flap. While the pause card
/// is up nothing is drawn and the animation (and the reminder count, which
/// lives in the run's `waitClock`) stands still.
class FirstRunHint extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  FirstRunHint({required this.run, required this.mode})
    : super(priority: -1) {
    _opacity = mode == FirstRunHintMode.firstRun ? 1 : 0;
    _shown = mode == FirstRunHintMode.firstRun;
  }

  final RunController run;
  final FirstRunHintMode mode;

  double _opacity = 0;
  bool _shown = false;
  bool _dismissed = false;

  /// Fade-in / fade-out progress (s) and the opacity the fade-out started at.
  double _fadeT = 0;
  double _fadeFrom = 1;

  /// The design's animation clock `S.t` (s since the hint showed).
  double _t = 0;

  final List<_Ripple> _ripples = [];
  int _lastTapKey = -1;
  bool _press = false;
  double _tapK = 0;

  FirstRunVeil? _veil;
  _WarningBand? _topBand;
  _WarningBand? _bottomBand;

  /// The current group opacity (0..1).
  double get opacity => _opacity;

  /// S8-07 the top AVOID THE SPIKES band in HUD coordinates (tests); null
  /// in the reminder mode.
  Rect? get topBandRect {
    final b = _topBand;
    if (b == null) return null;
    return Rect.fromLTWH(
      position.x + b.position.x,
      position.y + b.position.y,
      Config.worldWidth,
      b.bandHeight,
    );
  }

  /// The hint is on screen (the first-run instructions from the start; the
  /// reminder once its count ran out).
  bool get shown => _shown;

  /// The first tap dismissed it (it is fading out or gone).
  bool get dismissed => _dismissed;

  bool get _paused => game.state == GameState.paused;

  double get _mid => run.state.viewHeight / 2;

  @override
  Future<void> onLoad() async {
    size = Vector2(Config.worldWidth, run.state.viewHeight);
    if (mode == FirstRunHintMode.firstRun) {
      final strip = run.geo.stripHeight;
      final top = _topBand = _WarningBand(up: true);
      final bottom = _bottomBand = _WarningBand(up: false);
      // S8-07: under the HUD row (and the versus name chips), not over it.
      final hudBottom = run.setup.opponent != null
          ? HudConfig.chipTop + HudConfig.chipHeight
          : HudConfig.rowTop + HudConfig.rowHeight;
      top.position.setValues(
        0,
        math.max(
          strip + FirstRunConfig.warningGap,
          hudBottom + FirstRunConfig.warningHudGap,
        ),
      );
      bottom.position.setValues(
        0,
        run.state.viewHeight -
            strip -
            FirstRunConfig.warningGap -
            bottom.bandHeight,
      );
      addAll([top, bottom]);
      final veil = _veil = FirstRunVeil(this);
      game.world.add(veil);
    }
  }

  @override
  void onRemove() {
    _veil?.removeFromParent();
    _veil = null;
    super.onRemove();
  }

  /// PRD-2.3 §10.1 the first tap: fade out (or go at once if never shown).
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    if (!_shown || _opacity <= 0) {
      removeFromParent();
      return;
    }
    _fadeT = 0;
    _fadeFrom = _opacity;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (run.isRemoved || !identical(game.run, run) || run.dying) {
      removeFromParent();
      return;
    }
    if (_dismissed) {
      _fadeT += dt;
      if (mode == FirstRunHintMode.firstRun) {
        _opacity = _fadeFrom - _fadeT / Config.firstRunHintFadeOut;
      } else {
        final u = (_fadeT / Config.tapReminderFadeOut).clamp(0.0, 1.0);
        _opacity = _fadeFrom * (1 - u * u); // ease-in
      }
      if (_opacity <= 0) {
        _opacity = 0;
        removeFromParent();
        return;
      }
    } else if (_paused) {
      return; // the pause card is up: hidden, standing still
    } else if (!_shown) {
      if (run.waiting &&
          run.waitingBegun &&
          run.waitClock >= Config.tapReminderDelay) {
        _shown = true;
        _fadeT = 0;
        _t = 0;
        game.services.track('tap_reminder_shown', {
          'mode': game.homeMode.analytics,
        });
      } else {
        return;
      }
    }
    if (mode == FirstRunHintMode.reminder && !_dismissed) {
      // §10.3b fade in over 0.3 s, ease-out (from the frame it showed).
      _fadeT += dt;
      _opacity = Ease.outQuad(_fadeT / Config.tapReminderFadeIn);
    }
    _t += dt;
    _stepTaps(dt);
    final pulse = (math.sin(_t * FirstRunConfig.chevronPulseOmega) + 1) / 2;
    _topBand?.pulse = pulse;
    _bottomBand?.pulse = pulse;
  }

  // --- the loop (design: `cyc`, `u`, `draw`, the taps) ------------------------

  double get _u =>
      (_t % FirstRunConfig.loop) / FirstRunConfig.loop;

  double get _draw => math.min(1, _u / FirstRunConfig.drawShare);

  double get _out => _u > FirstRunConfig.outFrom
      ? 1 - (_u - FirstRunConfig.outFrom) / (1 - FirstRunConfig.outFrom)
      : 1;

  void _stepTaps(double dt) {
    final path = _FlapPath.of(_mid);
    final draw = _draw;
    _press = false;
    _tapK = 0;
    final taps = [0.0, ...path.kinks];
    for (var i = 0; i < taps.length; i++) {
      final dk = draw - taps[i];
      if (dk >= 0 && dk < FirstRunConfig.burstShare) {
        _tapK = math.max(_tapK, 1 - dk / FirstRunConfig.burstShare);
      }
      if (dk >= 0 && dk < FirstRunConfig.pressShare) {
        _press = true;
        final key = i + (_t / FirstRunConfig.loop).floor() * 10;
        if (_lastTapKey != key) {
          _lastTapKey = key;
          _ripples.add(_Ripple());
        }
      }
    }
    for (final r in _ripples) {
      r
        ..r += dt * FirstRunConfig.rippleGrowth
        ..a -= dt * FirstRunConfig.rippleFade;
    }
    _ripples.removeWhere((r) => r.a <= 0);
  }

  // --- drawing ----------------------------------------------------------------

  @override
  void renderTree(Canvas canvas) {
    if (!_shown || _opacity <= 0 || _paused) return;
    canvas.saveLayer(null, layerPaint(_opacity.clamp(0.0, 1.0)));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    final mid = _mid;
    if (mode == FirstRunHintMode.firstRun) _paintPath(canvas, mid);
    // Design order: ripples, the banner, the hand (the bands are children,
    // drawn after).
    final tip = tipAt(mid);
    for (final r in _ripples) {
      _stroke
        ..color = FirstRunConfig.pink.withValues(alpha: r.a.clamp(0.0, 1.0))
        ..strokeWidth = FirstRunConfig.rippleWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawCircle(tip, r.r, _stroke);
    }
    paintTapBanner(canvas, mid, _t);
    paintHand(canvas, mid, press: _press, burst: _tapK);
  }

  void _paintPath(Canvas canvas, double mid) {
    final path = _FlapPath.of(mid);
    final draw = _draw, out = _out;
    final fg = paletteForStage(0).foreground;
    final drawn = path.upTo(draw * path.total);
    DashedPathPainter.stroke(
      canvas,
      drawn,
      color: fg.withValues(alpha: FirstRunConfig.pathAlpha * out),
      width: FirstRunConfig.pathWidth,
      dashes: FirstRunConfig.pathDash,
    );
    if (draw >= 1) {
      canvas
        ..save()
        ..translate(path.end.dx, path.end.dy)
        ..rotate(path.angle);
      canvas.drawPath(
        Path()
          ..moveTo(FirstRunConfig.arrowLength, 0)
          ..lineTo(0, -FirstRunConfig.arrowHalfWidth)
          ..lineTo(0, FirstRunConfig.arrowHalfWidth)
          ..close(),
        fillPaint(fg.withValues(alpha: FirstRunConfig.pathAlpha * out)),
      );
      canvas.restore();
    }
    final label = _flapLabel(fg.withValues(alpha: out));
    for (var i = 0; i < 2; i++) {
      if (draw < path.kinks[i]) continue;
      final k = i == 0 ? FirstRunConfig.flap1 : FirstRunConfig.flap2;
      // Letter-spacing trails the last glyph; shift by half to stay centred.
      label.paint(
        canvas,
        Offset(
          k.dx - (label.width - FirstRunConfig.flapLetterSpacing) / 2,
          mid + k.dy + FirstRunConfig.flapLabelDy - label.height / 2,
        ),
      );
    }
  }

  TextPainter? _flapTp;
  Color? _flapColor;
  TextPainter _flapLabel(Color c) {
    if (_flapTp != null && _flapColor == c) return _flapTp!;
    _flapColor = c;
    return _flapTp = TextPainter(
      text: TextSpan(
        text: FirstRunConfig.flapText,
        style: TextStyle(
          fontFamily: Config.uiFont,
          fontSize: FirstRunConfig.flapFontSize,
          letterSpacing: FirstRunConfig.flapLetterSpacing,
          color: c,
          height: 1,
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
  }

  // --- the masters: the hand and the TAP TO FLAP! banner ----------------------

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// The fingertip on screen (the ripple's and the strokes' centre), hand
  /// not pressed.
  static Offset tipAt(double mid) {
    const a = FirstRunConfig.handAnchor;
    const len = FirstRunConfig.handTipLength * FirstRunConfig.handScale;
    return Offset(
      a.dx + math.sin(FirstRunConfig.handRotation) * len,
      mid + a.dy - math.cos(FirstRunConfig.handRotation) * len,
    );
  }

  /// §10.3 the hand (design D): shadow, white fill, plum outline and the
  /// folded fingers' lines; [press] moves it down 6 pt; [burst] (0..1) the
  /// five pink strokes around the fingertip.
  static void paintHand(
    Canvas canvas,
    double mid, {
    bool press = false,
    double burst = 0,
  }) {
    const a = FirstRunConfig.handAnchor;
    const s = FirstRunConfig.handScale;
    final dy = press ? FirstRunConfig.pressDepth : 0.0;
    void draw(Offset o, Color fill, {bool outline = false}) {
      canvas
        ..save()
        ..translate(a.dx + o.dx, mid + a.dy + dy + o.dy)
        ..rotate(FirstRunConfig.handRotation)
        ..scale(s, s);
      _fill.color = fill;
      canvas.drawPath(_HandArt.outline, _fill);
      if (outline) {
        _stroke
          ..color = FirstRunConfig.plum
          ..strokeWidth = FirstRunConfig.handOutline / s
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
        canvas
          ..drawPath(_HandArt.outline, _stroke)
          ..drawPath(_HandArt.lines, _stroke);
        _stroke.strokeJoin = StrokeJoin.miter;
      }
      canvas.restore();
    }

    draw(FirstRunConfig.handShadow, FirstRunConfig.plum);
    draw(Offset.zero, FirstRunConfig.handFill, outline: true);
    if (burst <= 0) return;
    final tip = tipAt(mid) + Offset(0, dy);
    final k = burst.clamp(0.0, 1.0);
    final r0 =
        FirstRunConfig.burstInner + (1 - k) * FirstRunConfig.burstSpread;
    final r1 = r0 + FirstRunConfig.burstLength;
    _stroke
      ..color = FirstRunConfig.pink.withValues(alpha: math.min(1, k * 1.6))
      ..strokeWidth = FirstRunConfig.burstWidth
      ..strokeCap = StrokeCap.round;
    for (final deg in FirstRunConfig.burstAngles) {
      final r = deg * math.pi / 180;
      final d = Offset(math.cos(r), math.sin(r));
      canvas.drawLine(tip + d * r0, tip + d * r1, _stroke);
    }
  }

  static TextPainter? _ctaTp;

  /// §10.3 the tilted TAP TO FLAP! banner at (160, mid + 80) with its ±4 %
  /// pulse at time [t].
  static void paintTapBanner(Canvas canvas, double mid, double t) {
    final sc =
        1 + FirstRunConfig.ctaPulse * math.sin(t * FirstRunConfig.ctaPulseOmega);
    const c = FirstRunConfig.ctaCentre;
    canvas
      ..save()
      ..translate(c.dx, mid + c.dy)
      ..rotate(FirstRunConfig.ctaRotation)
      ..scale(sc, sc);
    canvas
      ..drawRect(
        FirstRunConfig.ctaBox.shift(FirstRunConfig.ctaShadow),
        fillPaint(FirstRunConfig.plum),
      )
      ..drawRect(FirstRunConfig.ctaBox, fillPaint(FirstRunConfig.pink));
    final tp = _ctaTp ??= TextPainter(
      text: const TextSpan(
        text: FirstRunConfig.ctaText,
        style: TextStyle(
          fontFamily: HudConfig.nameFont,
          fontWeight: FontWeight.w600,
          fontSize: FirstRunConfig.ctaFontSize,
          letterSpacing: FirstRunConfig.ctaLetterSpacing,
          color: Color(0xFFFFFFFF),
          height: 1,
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        -(tp.width - FirstRunConfig.ctaLetterSpacing) / 2,
        FirstRunConfig.ctaTextDy - tp.height / 2,
      ),
    );
    canvas.restore();
  }
}

/// PRD-2.3 §10.3 the veil that dims the score circle while the first-run
/// instructions show: `#F1F1F1` at 72 % × the hint's fade, full screen, in
/// the world between the score circle (−100) and the banner layer (−60), so
/// the bird, hoop 0 and the spikes stay bright.
class FirstRunVeil extends Component with HasGameReference<FlappySpikesGame> {
  FirstRunVeil(this.hint) : super(priority: RunLayer.scoreCircle + 20);

  final FirstRunHint hint;

  @override
  void render(Canvas canvas) {
    if (!hint.shown || hint._paused) return;
    final a = FirstRunConfig.veilAlpha * hint.opacity.clamp(0.0, 1.0);
    if (a <= 0) return;
    // The world is drawn through the viewfinder (moved by run shakes):
    // cancel its offset so the veil stays on the screen.
    final o = game.camera.viewfinder.position;
    canvas.drawRect(
      Rect.fromLTWH(o.x, o.y, Config.worldWidth, game.viewHeight),
      fillPaint(FirstRunConfig.veilColor.withValues(alpha: a)),
    );
  }
}

class _Ripple {
  double r = FirstRunConfig.rippleStart;
  double a = 1;
}

/// §10.3 AVOID THE SPIKES: the run's full-width banner band (master #7,
/// [RunBanner]) held on screen, with a white chevron at each end pulsing
/// 4 pt towards the spikes ([up]: the top band).
class _WarningBand extends RunBanner {
  _WarningBand({required this.up}) : super(lane: BannerLane.element);

  final bool up;

  /// 0..1 (`(sin(t × 6) + 1) / 2`), set by the hint.
  double pulse = 0;

  @override
  String get text => FirstRunConfig.warningText;

  @override
  Color get color => FirstRunConfig.warningColor;

  @override
  double get fontSize => FirstRunConfig.warningFontSize;

  @override
  double get duration => double.infinity;

  /// Held: no scale-in / fade (the hint fades the whole group).
  @override
  (double, double) curveAt(double t) => (1, 1);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final h = bandHeight;
    final cy = h / 2 + (up ? -1 : 1) * pulse * FirstRunConfig.chevronPulse;
    final paint = fillPaint(
      const Color(0xFFFFFFFF).withValues(alpha: .6 + .4 * pulse),
    );
    for (final x in FirstRunConfig.chevronX) {
      canvas
        ..save()
        ..translate(x, cy);
      if (!up) canvas.scale(1, -1);
      canvas
        ..scale(FirstRunConfig.chevronScale, FirstRunConfig.chevronScale)
        ..drawPath(_chevron, paint)
        ..restore();
    }
  }

  static final Path _chevron = Path()
    ..moveTo(-22, 8)
    ..lineTo(0, -12)
    ..lineTo(22, 8)
    ..lineTo(22, 16)
    ..lineTo(0, -4)
    ..lineTo(-22, 16)
    ..close();
}

/// §10.3 the hand's paths, kept 1:1 from the design file's `Path2D`
/// (fingertip at (0, −34); canvas `arc(cx, cy, r, a0, a1)` clockwise =
/// `arcTo(circle, a0, a1 − a0 (+ 2π), false)`).
abstract final class _HandArt {
  static Rect _c(double x, double y, double r) =>
      Rect.fromCircle(center: Offset(x, y), radius: r);

  static final Path outline = Path()
    ..moveTo(-7, 14)
    ..lineTo(-7, -27)
    ..arcTo(_c(0, -27, 7), math.pi, math.pi, false) // index finger
    ..lineTo(7, -10)
    ..arcTo(_c(12.5, -10, 5.5), math.pi, math.pi, false) // knuckle 1
    ..arcTo(_c(23.5, -7, 5.5), math.pi, math.pi, false) // knuckle 2
    ..arcTo(_c(33.5, -2, 4.5), math.pi, math.pi, false) // knuckle 3
    ..lineTo(38, 20)
    ..quadraticBezierTo(37.5, 38, 26, 42) // palm, right side
    ..lineTo(4, 42)
    ..quadraticBezierTo(-6, 41, -11, 33) // wrist
    ..lineTo(-27, 13)
    ..arcTo(_c(-22.5, 9.4, 5.8), math.pi * .79, math.pi, false) // thumb
    ..lineTo(-7, 14)
    ..close();

  /// The folded fingers' separations.
  static final Path lines = Path()
    ..moveTo(18, -9)
    ..lineTo(18, 3)
    ..moveTo(29, -5)
    ..lineTo(29, 6);
}

/// §10.3 the flap path (design: `seg(P0, K1, 66, 30)`, `seg(K1, K2, 60,
/// 30)`, `seg(K2, H, 44, 34)`, then 4 × 3.4 pt on along the last direction),
/// in screen coordinates for a playfield middle [mid].
class _FlapPath {
  _FlapPath._(this.mid) {
    final p0 = Offset(
      FirstRunConfig.pathStart.dx,
      mid + FirstRunConfig.pathStart.dy,
    );
    final k1 = FirstRunConfig.flap1.translate(0, mid);
    final k2 = FirstRunConfig.flap2.translate(0, mid);
    final h = Offset(RunConfig.hoop0X, mid + RunConfig.hoop0DropY);
    final ends = [p0, k1, k2, h];
    for (var s = 0; s < 3; s++) {
      final a = ends[s], b = ends[s + 1];
      final n = FirstRunConfig.arcPoints[s];
      final peak = FirstRunConfig.arcPeaks[s];
      for (var i = 0; i <= n; i++) {
        final u = i / n;
        pts.add(
          Offset(
            a.dx + (b.dx - a.dx) * u,
            a.dy + (b.dy - a.dy) * u - peak * 4 * u * (1 - u),
          ),
        );
      }
    }
    final pa = pts[pts.length - 2], pb = pts.last;
    final dir = (pb - pa) / (pb - pa).distance;
    for (var i = 1; i <= FirstRunConfig.tailSteps; i++) {
      pts.add(h + dir * (FirstRunConfig.tailStep * i));
    }
    end = pts.last;
    angle = math.atan2(dir.dy, dir.dx);
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) acc += (pts[i] - pts[i - 1]).distance;
      lens.add(acc);
    }
    total = acc;
    final n0 = FirstRunConfig.arcPoints[0];
    kinks = [lens[n0] / acc, lens[n0 + 1 + FirstRunConfig.arcPoints[1]] / acc];
  }

  final double mid;
  final List<Offset> pts = [];
  final List<double> lens = [];
  late final double total;
  late final Offset end;
  late final double angle;

  /// The FLAP points' share of the path (the design's `KINKS`).
  late final List<double> kinks;

  static _FlapPath? _cache;
  static _FlapPath of(double mid) {
    final c = _cache;
    if (c != null && c.mid == mid) return c;
    return _cache = _FlapPath._(mid);
  }

  /// The points up to [length] along the path (the design draws whole
  /// points only).
  Path upTo(double length) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      if (lens[i] > length) break;
      if (i == 0) {
        path.moveTo(pts[i].dx, pts[i].dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }
    return path;
  }
}
