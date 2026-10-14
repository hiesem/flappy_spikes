import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/sound.dart';
import '../../menu/wallet.dart';
import '../../versus/timeline.dart' show PointFlags;
import '../config/run_config.dart';
import '../config/tuning_values.dart';
import '../director/plans.dart' show HoopKindId, RideKind;
import '../effects/coin_popup.dart';
import '../effects/shock_ring.dart';
import '../hoops/ring_painter.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_layers.dart';
import '../run_state.dart';

/// What a hoop pass is worth (PRD-2 §3.0.1 score, §3.1 rules, §3.2 coins,
/// §5.1 pass feedback; points PRD-2.2 §13):
///
/// - **points** ([pointsFor]): 1 for a non-perfect pass, max(2, streak)
///   for a perfect one, +1 while the chick flies (PRD-2.3 §14.3,
///   [chickBonus]; [RunContext.addScore] → HUD, versus timeline via
///   [ScoreChanged]);
/// - **a coin per hoop** through the one in-run wallet path
///   ([RunContext.earn]: credited at once, kept if the run ends): 1 for a
///   pass with a rim touch ([CoinSource.hoop]), 2 for a perfect pass —
///   PRD-2.3 §14.3: any pass with no rim touch ([CoinSource.perfect]);
///   shown by master #8 ([CoinPopup]) at the hoop;
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

  /// PRD-2.2 §13.1 the points of a pass: 1 for a non-perfect pass
  /// (`point_pass`), max(2, [streak]) for a perfect one
  /// (`point_perfect_min`) — [streak] is the value *after* this pass (the
  /// streak feature runs first). No streak cap (PRD-2.3 §14.3).
  static int pointsFor({required bool perfect, required int streak}) =>
      perfect
      ? math.max(TuningValues.current.i('point_perfect_min'), streak)
      : TuningValues.current.i('point_pass');

  /// PRD-2.3 §14.3 the chick's extra points per hoop passed (`point_chick`,
  /// +1), 0 without a hatched chick.
  static int chickBonus(RunState s) => s.egg?.stage == EggStage.chick
      ? TuningValues.current.i('point_chick')
      : 0;

  /// PRD-2.3 §14.2 the coins of a pass: 1 (`coin_hoop`), 2 for a perfect
  /// pass and every ride hoop (`coin_perfect`).
  static int coinsFor({required bool perfect}) => perfect
      ? TuningValues.current.i('coin_perfect')
      : TuningValues.current.i('coin_hoop');

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<HoopPassed>(_onPassed);
  }

  void _onPassed(HoopPassed e) {
    final c = _c;
    if (c == null) return;
    // region WP-3b / WP-3c — versus timeline flags (§3.13): ride points (3b)
    // and Ring Train points (§3.22, 3c) skip the 0.9 s gap check
    final train = e.hoop?.plan.kind == HoopKindId.train;
    final perfect = e.perfect;
    // PRD-2.3 §14.3 the chick adds +1 point per hoop passed (one score
    // change with the pass, so the versus timeline keeps one entry).
    // PRD-2.3.1 §15.1 a FEVER pass scores with the streak before its boost.
    final streak = c.s.pointStreak ?? c.s.streak;
    c.s.pointStreak = null;
    c.addScore(
      pointsFor(perfect: perfect, streak: streak) + chickBonus(c.s),
      flags: (e.duringRide ? PointFlags.ride : PointFlags.none) |
          (train ? PointFlags.train : PointFlags.none),
    );
    // endregion WP-3b / WP-3c
    final coins = coinsFor(perfect: perfect);
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
      popup..play(Offset(at.x, at.y), coins),
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
