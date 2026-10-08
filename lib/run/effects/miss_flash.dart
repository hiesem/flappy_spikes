import 'dart:ui';

import 'package:flame/components.dart';

import '../config/miss_flash_config.dart';
import '../hoops/hoop.dart';
import '../hoops/ring_painter.dart';
import 'easing.dart';
import 'screen_edge_glow.dart';
import 'shock_ring.dart';

/// §5.13 hoop miss flash "C · Shock ring" (`screen_miss_flash.html`, design
/// C), built from the shared parts (ARCH §3): the missed hoop's own ring
/// (master #3 through [Hoop.look]), [ShockRing.missWave] and
/// [ScreenEdgeGlow.miss]. With k = time since the miss:
///
/// - 0 – 0.12 s: both halves white, stroke 8, white glow (blur 24);
/// - 0 – 0.55 s: the red shockwave ring (1 → 2.6×, stroke 6 → 1, 1 → 0);
/// - 0 – 0.7 s: one red pulse on the screen edges (under the strips);
/// - 0.12 – 0.52 s: the hoop drains to grey (`#969696` / `#787878`, alpha
///   1 → 0.35, smoothstep), dashed 6/6 from 30 % of the way;
/// - after: the grey dashed ghost stays on the hoop and scrolls with it.
///
/// Lives in the run's fx track layer (game time); removes itself once the
/// ghost look is final. The sound (`miss_shock`) is played by the caller.
class MissFlash extends Component {
  MissFlash(this.hoop);

  final Hoop hoop;
  double time = 0;

  /// Starts the flash: marks the hoop missed (its tier look stays off),
  /// adds the shockwave to [fx] and the edge glow to [glowParent] (screen
  /// coordinates, sized [screen]) at [glowPriority]. The mock paints the
  /// glow over the hoops but under the spike strips (they stay grey), so the
  /// run puts it in the world right under the strips.
  static MissFlash play(
    Hoop hoop, {
    required Component fx,
    Component? glowParent,
    int glowPriority = 0,
    required Vector2 screen,
  }) {
    final flash = MissFlash(hoop);
    hoop.look.missed = true;
    flash._apply(0);
    fx.add(flash);
    final f = hoop.frame();
    for (final o in hoop.rings) {
      final c = f.toWorld(Vector2(0, o));
      fx.add(
        ShockRing()
          ..missWave(Offset(c.x, c.y), opening: hoop.opening, tilt: f.tilt),
      );
    }
    glowParent?.add(
      ScreenEdgeGlow.miss(screen.clone())..priority = glowPriority,
    );
    return flash;
  }

  /// The ring look at k seconds after the miss.
  static void lookAt(HoopLook look, double k) {
    if (k < MissFlashConfig.whiteSeconds) {
      look
        ..colors = RingColors.white
        ..strokeWidth = MissFlashConfig.whiteStroke
        ..glow = const Color(0xFFFFFFFF)
        ..glowBlur = MissFlashConfig.whiteGlowBlur
        ..dash = null;
      return;
    }
    final g = Ease.smooth(
      ((k - MissFlashConfig.whiteSeconds) / MissFlashConfig.drainSeconds).clamp(
        0.0,
        1.0,
      ),
    );
    final a =
        MissFlashConfig.ghostAlpha + (1 - MissFlashConfig.ghostAlpha) * (1 - g);
    look
      ..colors = RingColors(
        RingColors.ghost.front.withValues(alpha: a),
        RingColors.ghost.back.withValues(alpha: a),
      )
      ..strokeWidth = RingPainter.stroke
      ..glow = null
      ..dash = g > MissFlashConfig.dashFrom ? MissFlashConfig.dash : null;
  }

  void _apply(double k) => lookAt(hoop.look, k);

  bool get settled =>
      time >= MissFlashConfig.whiteSeconds + MissFlashConfig.drainSeconds;

  @override
  void update(double dt) {
    super.update(dt);
    time += dt;
    _apply(time);
    if (settled) removeFromParent();
  }
}
