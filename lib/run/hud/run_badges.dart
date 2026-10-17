import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/look.dart';
import '../config/egg_config.dart';
import '../config/tuning_values.dart';
import '../config/jar_config.dart';
import '../config/piggy_config.dart';
import '../effects/collect_art.dart';
import '../pickups/jar_pickup.dart';
import '../pickups/piggy_pickup.dart';
import '../run_controller.dart';
import '../run_state.dart';
import 'run_hud.dart';

/// The collectables' HUD badges (PRD-2 §5.26–§5.28). Each is a plain
/// child of [RunHud] (viewport → screen coordinates, real time, no shake,
/// drawn over the run). A feature mounts its badge when its collectable is
/// picked up and drops it when the collectable is resolved — [RunHud]
/// also clears every non-top-row child on a death, so a feature must
/// re-mount the badge on a new pickup rather than keep one around.
///
/// Every badge reads `RunState` on render and draws nothing while its
/// collectable is not running.
///
/// A badge keeps its count text between frames ([_BadgeText]): a [HudText]
/// lays its text out once, so a new one per frame would lay it out again
/// every frame (A2-10).

/// One badge text, re-created only when its string, size or colour changes.
class _BadgeText {
  HudText? _text;

  HudText of(String text, {required double size, required Color color}) {
    final t = _text;
    if (t != null && t.text == text && t.size == size && t.color == color) {
      return t;
    }
    return _text = HudText(text, size: size, color: color);
  }
}

/// §5.26 the gold "×2" pill with the chick (mock `drawHud`: `rr(128,202,
/// 64,24,12)` gold, the chick at (144,214) at 36 %, "×2" white 17 pt at
/// (172,215)).
class EggBadge extends PositionComponent {
  EggBadge(this.run);

  final RunController run;
  double _t = 0;
  final _BadgeText _plus = _BadgeText();

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    final egg = run.state.egg;
    if (egg == null || egg.stage != EggStage.chick) return;
    CollectArt.roundRect(
      canvas,
      const Rect.fromLTWH(
        EggConfig.hudX,
        EggConfig.hudY,
        EggConfig.hudW,
        EggConfig.hudH,
      ),
      EggConfig.hudRadius,
      EggConfig.gold,
    );
    canvas.save();
    canvas.translate(EggConfig.hudChickX, EggConfig.hudChickY);
    canvas.scale(EggConfig.hudChickScale * Config.lookScale);
    LookPainter.paint(
      canvas,
      const Look(bird: 'golden'),
      t: _t * EggConfig.chickArtRate,
    );
    canvas.restore();
    // PRD-2.3 §14.3 (call) the pill shows the chick's "+1" (was "×2").
    _plus
        .of(
          '+${TuningValues.current.i('point_chick')}',
          size: EggConfig.hudTextSize,
          color: const Color(0xFFFFFFFF),
        )
        .paintCentred(canvas, const Offset(EggConfig.hudTextX, EggConfig.hudTextY));
  }
}

/// §5.27 the piggy HUD (mock `drawHud`): the pig at (46,216) 1.4×, "n / 20"
/// `#E05A99` 16 pt left at (68,209), a 90 × 8 bar at (68,220) (caught pink
/// from the left, missed grey from the right) and "n missed" 11 pt at
/// (68,236).
class PiggyBadge extends PositionComponent {
  PiggyBadge(this.run);

  final RunController run;
  final _BadgeText _count = _BadgeText();
  final _BadgeText _missed = _BadgeText();

  @override
  void render(Canvas canvas) {
    final p = run.state.piggy;
    if (p == null) return;
    PiggyArt.paint(
      canvas,
      const Offset(PiggyConfig.hudPigX, PiggyConfig.hudPigY),
      PiggyConfig.hudScale,
    );
    final count = _count.of(
      '${p.caught} / ${PiggyConfig.total}',
      size: PiggyConfig.hudTextSize,
      color: PiggyConfig.hudText,
    );
    count.paintCentred(
      canvas,
      Offset(PiggyConfig.hudTextX + count.width / 2, PiggyConfig.hudTextY),
    );
    final bar = Rect.fromLTWH(
      PiggyConfig.hudBarX,
      PiggyConfig.hudBarY,
      PiggyConfig.hudBarW,
      PiggyConfig.hudBarH,
    );
    CollectArt.roundRect(
      canvas,
      bar,
      PiggyConfig.hudBarRadius,
      PiggyConfig.hudBarTrack,
    );
    if (p.caught > 0) {
      CollectArt.roundRect(
        canvas,
        Rect.fromLTWH(
          bar.left,
          bar.top,
          bar.width * p.caught / PiggyConfig.total,
          bar.height,
        ),
        PiggyConfig.hudBarRadius,
        PiggyConfig.hudBarCaught,
      );
    }
    if (p.missed > 0) {
      final w = bar.width * p.missed / PiggyConfig.total;
      canvas.drawRect(
        Rect.fromLTWH(bar.right - w, bar.top, w, bar.height),
        Paint()..color = PiggyConfig.hudBarMissed,
      );
    }
    if (p.missed > 0) {
      final missed = _missed.of(
        '${p.missed} missed',
        size: PiggyConfig.hudMissedSize,
        color: PiggyConfig.hudMissed,
      );
      missed.paintCentred(
        canvas,
        Offset(PiggyConfig.hudBarX + missed.width / 2, PiggyConfig.hudMissedY),
      );
    }
  }
}

/// §5.28 the jar HUD (mock `drawHud`): the jar at (46,218) 0.95× filling
/// with lime light, "n / 20" `#7CB518` 14 pt left at (66,210) and three ✕
/// marks at (72 + 16i, 228), red for each escape else grey.
class JarBadge extends PositionComponent {
  JarBadge(this.run);

  final RunController run;
  final _BadgeText _count = _BadgeText();

  @override
  void render(Canvas canvas) {
    final j = run.state.jar;
    if (j == null) return;
    JarArt.paint(
      canvas,
      const Offset(JarConfig.hudJarX, JarConfig.hudJarY),
      JarConfig.hudJarScale,
      fill: j.caught / JarConfig.total,
    );
    final count = _count.of(
      '${j.caught} / ${JarConfig.total}',
      size: JarConfig.hudTextSize,
      color: JarConfig.hudText,
    );
    count.paintCentred(
      canvas,
      Offset(JarConfig.hudTextX + count.width / 2, JarConfig.hudTextY),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = JarConfig.markWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < JarConfig.maxEscapes; i++) {
      final cx = JarConfig.markX + i * JarConfig.markStep;
      final cy = JarConfig.markY;
      stroke.color = i < j.escaped ? JarConfig.markRed : JarConfig.markGrey;
      canvas.drawLine(
        Offset(cx - JarConfig.markSize, cy - JarConfig.markSize),
        Offset(cx + JarConfig.markSize, cy + JarConfig.markSize),
        stroke,
      );
      canvas.drawLine(
        Offset(cx + JarConfig.markSize, cy - JarConfig.markSize),
        Offset(cx - JarConfig.markSize, cy + JarConfig.markSize),
        stroke,
      );
    }
  }
}
