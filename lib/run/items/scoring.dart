import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../config/run_config.dart';
import '../effects/coin_popup.dart';
import '../effects/shock_ring.dart';
import '../hoops/ring_painter.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_layers.dart';
import '../run_state.dart';
import '../director/plans.dart' show RideKind;
import '../../versus/timeline.dart' show PointFlags;

/// What a hoop pass is worth (PRD-2 §3.0.1 score, §3.1 rules, §3.2 coins,
/// §5.1 pass feedback):
///
/// - **+1 point** per hoop passed ([RunContext.addScore] → HUD, versus
///   timeline via [ScoreChanged]);
/// - **a coin per hoop** through the one in-run wallet path
///   ([RunContext.earn]: credited at once, kept if the run ends): 1 for a
///   pass with a rim touch ([CoinSource.hoop]), 2 for a perfect pass
///   ([CoinSource.perfect]); shown by master #8 ([CoinPopup]) at the hoop;
/// - the **colour stage** every 10 hoops passed
///   (`RunConfig.stageForHoops`, palettes in order, gold last);
/// - a **non-perfect** pass plays `point.mp3` and the §5.1 ring-outline
///   pulse ([ShockRing.passPulse]); perfect-pass sounds, bursts and banners
///   belong to the streak (WP-2b).
///
/// The controller has already counted the pass (`hoopsPassed`, `passes`,
/// `perfectPasses`) when [HoopPassed] is emitted.
class ScoringFeature extends RunFeature {
  RunContext? _c;
  final _popups = CoinPopup.newPool();
  final _pulses = ShockRing.newPool();

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<HoopPassed>(_onPassed);
  }

  void _onPassed(HoopPassed e) {
    final c = _c;
    if (c == null) return;
    // region WP-3b — ride points are flagged for the versus timeline (§3.13)
    c.addScore(1, flags: e.duringRide ? PointFlags.ride : 0);
    // endregion WP-3b
    final perfect = e.perfect;
    final coins = perfect ? 2 : 1;
    c.earn(coins, perfect ? CoinSource.perfect : CoinSource.hoop);

    // Where: the ring centre that was passed (or the bird for a seam pass).
    final hoop = e.hoop;
    Vector2 at;
    double tilt = 0;
    if (hoop != null) {
      final f = hoop.frame();
      final ring = e.ring.clamp(0, hoop.rings.length - 1);
      at = f.toWorld(Vector2(0, hoop.rings[ring]));
      tilt = f.tilt;
    } else {
      at =
          c.run.birdTrackPosition() ??
          Vector2(c.s.camX + RunConfig.birdX, c.viewHeight / 2);
    }
    // region WP-3b — portal rides: the popup stays with the bird on screen
    // (the ride camera races along the path; §5.12b mock)
    Component fx = c.layers.fx;
    final popup = _popups.obtain();
    if (e.duringRide && c.s.ride?.kind == RideKind.portal) {
      final b = c.game.runBirdPosition;
      if (b != null) at = b;
      fx = c.game.world;
      popup.priority = RunLayer.fx;
    }
    // endregion WP-3b
    fx.add(
      popup..play(
        Offset(at.x, at.y),
        coins,
        doubled: c.s.egg?.stage == EggStage.chick,
      ),
    );
    if (!perfect) {
      c.sfx(Sfx.point);
      if (hoop != null) {
        fx.add(
          _pulses.obtain()..passPulse(
            Offset(at.x, at.y),
            opening: hoop.opening,
            color: hoop.look.colors?.front ?? RingColors.pink.front,
            tilt: tilt,
          ),
        );
      }
    }
    c.game.applyRunStage(c.s.stage);
  }

  @override
  void detach() {
    _c?.events.off<HoopPassed>(_onPassed);
    _c = null;
  }
}
