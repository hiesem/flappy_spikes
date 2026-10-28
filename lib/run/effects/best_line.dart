import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../config/hud_config.dart';
import '../config/run_config.dart';
import '../hoops/hoop.dart';
import '../hud/run_hud.dart';
import '../run_controller.dart';

/// WP-K variant A: a course marker, never a scoring sensor. Its plane is
/// taken from the real slot (including ride spacing and moving hoops).
class BestLine extends PositionComponent {
  BestLine(this.run) : super(priority: -61);

  final RunController run;
  Hoop? _hoop;
  double? _trackX;
  double? _collapseAge;
  double _collapseX = 0;
  double _collapseY = 0;
  // region P26-G5b
  String get flagText => run.setup.weekly ? 'WEEK ${run.weeklyBestBefore}' : 'BEST ${run.bestBefore}';
  // endregion P26-G5b
  late final HudText _flagLabel = HudText(
    // region P26-G5b
    flagText,
    // endregion P26-G5b
    size: 9.5,
    spacing: 1.1 / 9.5,
    color: HudConfig.plum,
  );

  double get screenX => position.x;
  bool get visible =>
      run.bestGoalEligible &&
      _trackX != null &&
      (_collapseAge != null || screenX <= Config.worldWidth);

  void collapse() {
    if (_collapseAge != null) return;
    _collapseAge = 0;
    _collapseX = position.x;
    _collapseY = run.game.runBirdPosition?.y ?? run.state.viewHeight / 2;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (run.isRemoved || run.ended || !run.bestGoalEligible) {
      removeFromParent();
      return;
    }
    if (run.dying) return;
    final age = _collapseAge;
    if (age != null) {
      _collapseAge = age + dt;
      final u = (_collapseAge! / .32).clamp(0.0, 1.0);
      position.x =
          _collapseX + (RunConfig.birdX - _collapseX) * (1 - (1 - u) * (1 - u));
      if (u >= 1) removeFromParent();
      return;
    }
    for (final h in run.spawner.hoops) {
      if (h.plan.index == run.bestTargetHoops) {
        _hoop = h;
        break; // Ring Train's extra rings share the slot's index.
      }
    }
    final ahead = run.spawner.plannedAhead;
    if (_hoop != null) {
      _trackX = _hoop!.planeX;
    } else if (ahead?.index == run.bestTargetHoops) {
      _trackX = ahead!.trackX;
    }
    if (_trackX != null) position.x = _trackX! - run.state.camX;
    if (screenX < run.state.viewLeft - 100 && _trackX != null) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (!visible || run.dying) return;
    final u = ((_collapseAge ?? 0) / .32).clamp(0.0, 1.0);
    final pull = 1 - (1 - u) * (1 - u);
    final top = run.geo.topTooth;
    final bottom = run.geo.floorTooth;
    final a = top + (_collapseY - top) * pull;
    final b = bottom + (_collapseY - bottom) * pull;
    canvas.drawRect(
      Rect.fromLTRB(-1, a, 1, b),
      Paint()..color = HudConfig.gold.withValues(alpha: 1 - u),
    );
    if (_collapseAge == null) {
      // Variant A's 2 × 6 pole above the flag (fy 106, flag height 17).
      canvas.drawRect(
        const Rect.fromLTWH(-1, 106 - 8.5 - 6, 2, 6),
        Paint()..color = HudConfig.gold,
      );
    }
    final flagScale = (1 - ((_collapseAge ?? 0) / .3)).clamp(0.0, 1.0);
    final label = _flagLabel;
    final width = label.width + 16;
    canvas.save();
    canvas.translate(1, 106);
    canvas.scale(flagScale);
    final flag = Path()
      ..moveTo(0, -8.5)
      ..lineTo(width + 5, -8.5)
      ..lineTo(width - 1, 0)
      ..lineTo(width + 5, 8.5)
      ..lineTo(0, 8.5)
      ..close();
    canvas.drawPath(flag, Paint()..color = HudConfig.gold);
    label.paintCentred(canvas, Offset(6 + label.width / 2, 1));
    canvas.restore();
  }
}
