import 'dart:ui';

import 'package:flame/components.dart';

import '../config/capsule_config.dart';
import '../items/timed_powerup.dart';
import '../pickups/capsule.dart';
import '../run_controller.dart';
import '../run_state.dart';
import 'run_hud.dart';

/// §3.30 / §5.29 the timer pill of a running capsule powerup: a fixed spot
/// near the top (x 100, y 156 — see `CapsuleConfig.pillY` —, 120 × 22 pt,
/// radius 11) with the powerup's
/// icon in a 26 pt disc and a bar draining in the powerup colour; the
/// Hourglass adds the seconds left ("14 s") to its right. Lives in the run
/// HUD (viewport, real time). Reads `RunState.timed` every frame; it fades
/// in when a capsule powerup starts and out when it ends (never shown for
/// the comet, which has its own countdown ring, §5.6).
class TimerPill extends PositionComponent {
  TimerPill(this.run)
    : super(
        position: Vector2(CapsuleConfig.pillX, CapsuleConfig.pillY),
        size: Vector2(CapsuleConfig.pillWidth, CapsuleConfig.pillHeight),
        priority: 5,
      );

  final RunController run;

  /// 0..1, fading with the powerup.
  double alpha = 0;

  /// The powerup shown (kept while fading out).
  TimedPowerup? shown;

  /// Bar fill 0..1 (remaining / duration).
  double fraction = 1;

  /// Seconds left (the Hourglass label).
  double secondsLeft = 0;

  double _t = 0;
  HudText? _label;
  String _labelText = '';

  /// The Hourglass label text now ("14 s"), or null.
  String? get label =>
      shown == TimedPowerup.hourglass ? '${secondsLeft.ceil()} s' : null;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final timed = run.state.timed;
    final want = timed != null && timed.type.isCapsule;
    if (want) {
      shown = timed.type;
      fraction = timed.duration <= 0
          ? 0
          : (timed.remaining / timed.duration).clamp(0.0, 1.0);
      secondsLeft = timed.remaining;
    }
    final step = dt / CapsuleConfig.pillFade;
    alpha = want
        ? (alpha + step).clamp(0.0, 1.0)
        : (alpha - step).clamp(0.0, 1.0);
  }

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final type = shown;
    if (alpha <= 0 || type == null) return;
    final layer = alpha < 1;
    if (layer) {
      canvas.saveLayer(
        Rect.fromLTWH(-4, -6, size.x + 80, size.y + 12),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    const w = CapsuleConfig.pillWidth, h = CapsuleConfig.pillHeight;
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, w, h, const Radius.circular(h / 2)),
      _paint..color = CapsuleConfig.pillTrack,
    );
    final col = type.color;
    final barW = (w - CapsuleConfig.barShort) * fraction;
    if (barW > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          CapsuleConfig.barInset,
          CapsuleConfig.barTop,
          CapsuleConfig.barInset + barW,
          CapsuleConfig.barTop + CapsuleConfig.barHeight,
          Radius.circular(
            (barW / 2).clamp(0, CapsuleConfig.barHeight / 2).toDouble(),
          ),
        ),
        _paint..color = col,
      );
    }
    const disc = Offset(11, h / 2);
    canvas.drawCircle(disc, CapsuleConfig.discRadius, _paint..color = col);
    canvas.save();
    canvas.translate(disc.dx, disc.dy);
    canvas.scale(CapsuleConfig.discIconScale);
    CapsuleArt.paintIcon(canvas, type, _t);
    canvas.restore();
    final text = label;
    if (text != null) {
      if (_label == null || text != _labelText) {
        _labelText = text;
        _label = HudText(
          text,
          size: CapsuleConfig.labelSize,
          color: CapsuleConfig.hourglass,
        );
      }
      final l = _label!;
      l.paintCentred(
        canvas,
        Offset(CapsuleConfig.labelX - position.x + l.width / 2, h / 2),
      );
    }
    if (layer) canvas.restore();
  }
}
