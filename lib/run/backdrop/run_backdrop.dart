import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import '../config/run_config.dart';
import '../hoops/hoop_kind.dart';
import '../run_controller.dart';
import '../run_layers.dart';
import 'backdrop_math.dart';
import 'backdrop_world.dart';
import 'ride_hook.dart';
import 'world_distance.dart';

/// PRD-2.4 §3 the lively run background: one per run, in the world at
/// [RunLayer.runBackdrop] (just over the flat backdrop rectangle, under
/// everything else). It only shows in the run (§3.1): it fades in when the
/// run opens and out when a post-run page (bonus, results) comes up, and
/// it leaves with its run (replay, a new run).
///
/// It moves only with the run camera (`RunState.camX`, mapped to the
/// world distance by [WorldDistance]) and the run clock (`runClock`), so it
/// freezes with them on pause and death and never jumps on revive.
class RunBackdrop extends Component with HasGameReference<FlappySpikesGame> {
  RunBackdrop(this.run) : super(priority: RunLayer.runBackdrop);

  /// The run it belongs to.
  final RunController run;

  /// WP-W1 call: fade-in at run open and fade-out under a post-run page (s).
  static const double fadeTime = .3;

  final BackdropPainter painter = BackdropPainter();
  final WorldDistance distance = WorldDistance();
  late final _RunAnchors _anchors = _RunAnchors(run);

  /// 0..1, eased in at run open, out under the post-run pages.
  double opacity = 0;

  /// PRD-2.4 §3.5 the portal ride's handover hook (WP-R); null = none.
  BackdropRideHook? get rideHook => painter.world.hook;
  set rideHook(BackdropRideHook? h) => painter.world.hook = h;

  /// PRD-2.4 §3.5 the ride phase a hook reads (null = no ride).
  String? get ridePhase => run.state.ride?.phase;

  /// The world distance this frame (prototype `cam`).
  double get worldDistance {
    _sync();
    return distance.w;
  }

  /// Whether this backdrop draws (its run is the game's run, and it is not
  /// faded out).
  bool get showing => identical(game.run, run) && opacity > 0;

  /// The visibility it eases towards: shown in the run, hidden under the
  /// post-run pages (bonus, results).
  double get targetOpacity => game.postRunPageUp ? 0 : 1;

  @override
  void update(double dt) {
    super.update(dt);
    if (!identical(game.run, run)) {
      removeFromParent();
      return;
    }
    final target = targetOpacity;
    final step = dt / fadeTime;
    opacity = opacity < target
        ? clampD(opacity + step, 0, target)
        : clampD(opacity - step, target, 1);
    _sync();
  }

  @override
  void onRemove() {
    // A2-32: the cached strip pictures are GPU-side memory; a backdrop that
    // leaves the world (its run ended or was replaced) drops them with it.
    painter.ctx.clearStrips();
    super.onRemove();
  }

  /// Integrates the world distance up to the camera's current position.
  void _sync() {
    final s = run.state;
    final c = s.camX + kANCH;
    if (!distance.started) {
      final (index, x) = _anchors.first();
      distance.start(c, index, x, _anchors.spacing);
      return;
    }
    final dc = c - distance.c;
    if (dc == 0) return;
    distance.advance(c, _anchors, override: rideHook?.scroll(dc));
  }

  @override
  void render(Canvas canvas) {
    if (!identical(game.run, run) || opacity <= 0) return;
    _sync();
    painter.paint(
      canvas,
      cam: distance.w,
      t: run.state.runClock,
      viewHeight: game.viewHeight,
      bg: game.stageBackground,
      fg: game.foregroundColor,
      opacity: opacity,
    );
  }

  /// The run's backdrop (null on the home screen).
  static RunBackdrop? of(FlappySpikesGame game) =>
      game.world.children.whereType<RunBackdrop>().where((b) => identical(b.run, game.run)).firstOrNull;
}

/// [HoopAnchors] read from the run's director and spawner.
class _RunAnchors implements HoopAnchors {
  _RunAnchors(this.run);

  final RunController run;

  @override
  int get nextIndex => run.director.hoopIndex;

  @override
  double get nextX => run.director.nextTrackX;

  @override
  double get spacing => RunConfig.spacing;

  @override
  double? planeOf(int index) {
    for (final h in run.spawner.hoops) {
      if (h.plan.index == index && h.plan.kind != HoopKindId.rideRing) {
        return h.plan.trackX;
      }
    }
    final ahead = run.spawner.plannedAhead;
    if (ahead != null && ahead.index == index) return ahead.trackX;
    return null;
  }

  /// The run's first known hoop: (index, plane x).
  (int, double) first() {
    var best = -1;
    var x = 0.0;
    for (final h in run.spawner.hoops) {
      if (h.plan.kind == HoopKindId.rideRing) continue;
      if (best < 0 || h.plan.index < best) {
        best = h.plan.index;
        x = h.plan.trackX;
      }
    }
    if (best >= 0) return (best, x);
    return (nextIndex, nextX);
  }
}
