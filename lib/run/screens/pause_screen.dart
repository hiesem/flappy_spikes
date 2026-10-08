import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../game/flappy_game.dart';
import '../config/hud_config.dart';
import '../hud/run_hud.dart';

/// §5.7 the pause screen (G3): the frozen game under a dark overlay, a
/// centred stage-background card with "PAUSED" (pink 34 pt, 0.14 em), a
/// gold RESUME button (56 tall) and a row of two pink buttons, sound and
/// settings. **No Quit** (Q25): a paused run can only be resumed. RESUME is
/// "straight back in" — no countdown (owner decision 2026-10-08).
///
/// Lives in the viewport (real time). While the settings overlay is open
/// over it, [hidden] is set and it takes no taps.
class PauseScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  PauseScreen() : super(priority: 30);

  double _t = 0;

  /// True while the settings overlay is on top.
  bool hidden = false;

  double get opacity => (_t / HudConfig.cardFade).clamp(0.0, 1.0);

  late final HudText _paused = HudText(
    HudConfig.pausedText,
    size: HudConfig.pausedSize,
    color: HudConfig.pink,
    spacing: HudConfig.pausedSpacing,
  );
  late final HudText _resume = HudText(
    HudConfig.resumeText,
    size: HudConfig.resumeSize,
    color: HudConfig.plum,
    spacing: HudConfig.resumeSpacing,
  );

  Rect get card {
    final top = game.viewHeight / 2 + HudConfig.cardTopOffset;
    final h =
        HudConfig.cardPad +
        _paused.height +
        HudConfig.pausedGap +
        HudConfig.resumeHeight +
        HudConfig.rowGap +
        HudConfig.smallHeight +
        HudConfig.cardPadBottom;
    return Rect.fromLTRB(
      HudConfig.cardInset,
      top,
      320 - HudConfig.cardInset,
      top + h,
    );
  }

  Rect get resumeRect {
    final c = card;
    final top =
        c.top + HudConfig.cardPad + _paused.height + HudConfig.pausedGap;
    return Rect.fromLTRB(
      c.left + HudConfig.cardPad,
      top,
      c.right - HudConfig.cardPad,
      top + HudConfig.resumeHeight,
    );
  }

  Rect get soundRect {
    final r = resumeRect;
    final top = r.bottom + HudConfig.rowGap;
    final w = (r.width - HudConfig.smallGap) / 2;
    return Rect.fromLTWH(r.left, top, w, HudConfig.smallHeight);
  }

  Rect get settingsRect {
    final s = soundRect;
    return s.translate(s.width + HudConfig.smallGap, 0);
  }

  @override
  Future<void> onLoad() async {
    size = Vector2(320, game.viewHeight);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  bool containsLocalPoint(Vector2 point) => !hidden;

  @override
  void onTapDown(TapDownEvent event) => tapAt(event.localPosition.toOffset());

  /// A tap at [p] (screen points).
  void tapAt(Offset p) {
    if (hidden) return;
    if (resumeRect.contains(p)) {
      game.resume();
    } else if (soundRect.contains(p)) {
      game.toggleSound();
    } else if (settingsRect.contains(p)) {
      game.openRunSettings();
    }
  }

  final Paint _p = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    if (hidden) return;
    final a = opacity;
    _p.color = HudConfig.pauseDim.withValues(alpha: HudConfig.pauseDim.a * a);
    canvas.drawRect(size.toRect(), _p);
    final c = card;
    _p.color = game.stageBackground.withValues(alpha: a);
    canvas.drawRect(c, _p);
    _paused.paintCentred(
      canvas,
      Offset(160, c.top + HudConfig.cardPad + _paused.height / 2),
      opacity: a,
    );
    _p.color = HudConfig.gold.withValues(alpha: a);
    canvas.drawRect(resumeRect, _p);
    _resume.paintCentred(canvas, resumeRect.center, opacity: a);
    _p.color = HudConfig.pink.withValues(alpha: a);
    canvas
      ..drawRect(soundRect, _p)
      ..drawRect(settingsRect, _p);
    _speaker(canvas, soundRect.center, a, muted: game.sound.muted);
    _gear(canvas, settingsRect.center, a);
  }

  /// The mock's speaker glyph (24-unit box, stroke 2): `M3 9v6h4l5 4V5L7
  /// 9z` + two waves; muted: an × instead of the waves.
  void _speaker(Canvas canvas, Offset c, double a, {required bool muted}) {
    final k = HudConfig.smallIcon / 24;
    canvas
      ..save()
      ..translate(c.dx - 12 * k, c.dy - 12 * k)
      ..scale(k);
    _line
      ..color = HudConfig.soft.withValues(alpha: a)
      ..strokeWidth = 2;
    canvas.drawPath(
      Path()
        ..moveTo(3, 9)
        ..lineTo(3, 15)
        ..lineTo(7, 15)
        ..lineTo(12, 19)
        ..lineTo(12, 5)
        ..lineTo(7, 9)
        ..close(),
      _line,
    );
    if (muted) {
      canvas
        ..drawLine(const Offset(16, 9), const Offset(22, 15), _line)
        ..drawLine(const Offset(22, 9), const Offset(16, 15), _line);
    } else {
      canvas
        ..drawArc(
          Rect.fromCircle(center: const Offset(15, 12), radius: 4),
          -1.2,
          2.4,
          false,
          _line,
        )
        ..drawArc(
          Rect.fromCircle(center: const Offset(13, 12), radius: 8),
          -1.0,
          2.0,
          false,
          _line,
        );
    }
    canvas.restore();
  }

  /// A gear: a toothed ring with a hole (the mock's settings glyph).
  void _gear(Canvas canvas, Offset c, double a) {
    final k = HudConfig.smallIcon / 24;
    _p.color = HudConfig.soft.withValues(alpha: a);
    final path = Path()..fillType = PathFillType.evenOdd;
    const teeth = 8;
    for (var i = 0; i < teeth; i++) {
      final ang = i * 2 * 3.141592653589793 / teeth;
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..rotate(ang)
        ..drawRect(Rect.fromLTWH(-2.2 * k, -11 * k, 4.4 * k, 5 * k), _p)
        ..restore();
    }
    path
      ..addOval(Rect.fromCircle(center: c, radius: 8 * k))
      ..addOval(Rect.fromCircle(center: c, radius: 3.5 * k));
    canvas.drawPath(path, _p);
  }
}
