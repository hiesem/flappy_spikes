import 'dart:math' as math;
import 'dart:ui';

import '../backdrop/backdrop_math.dart' show kANCH, kPerHoop;
import '../backdrop/backdrop_scene.dart';
import '../backdrop/ride_hook.dart';
import '../backdrop/run_backdrop.dart';
import '../config/handover_config.dart';
import '../config/portal_config.dart';
import '../config/run_config.dart';
import 'portal_ride.dart';
import 'ride_theme.dart' show RidePhase;
import 'ride_reveal.dart';

/// PRD-2.4 §3.5 the run background around one portal ride (WP-R), the
/// background half of `docs/p24/ride_landings.html` (`background()`,
/// `stepGlide`, `REVEAL`). The ride installs it on its [RunBackdrop] at
/// the start, calls [step] every frame and [onLaunch] at the launch, and
/// removes it when it ends.
///
/// * **On the ride** the world follows the run camera: it scrolls with it
///   (the normal 300/310 world rate) and each layer follows the camera's
///   height by its share, capped by `softY`. A themed ride's scene covers
///   it once faded in: the world then holds (unseen) and is not drawn.
/// * **On the exit** the camera stops, so the world holds still.
/// * **Cannon launch**: the world rushes forward with the flight camera and
///   sinks as it rises; on the glide it eases back to rest on the bird's
///   2.5 s `smoother` curve.
/// * **Themed launch**: the scene leaves (the ride clips it, [cover] keeps
///   the world out of what it still covers) and each layer arrives from the
///   ride's direction on its own delay.
/// * **Every ride**: from the glide start the world scrolls
///   `410·e^(−1.35·t)` pt/s faster than the cruise; on `pu_land` a bump runs
///   through the layers. Everything is 0 when the settle ends.
class PortalHandover extends BackdropRideHook {
  PortalHandover(this.ride) : reveal = RideReveal.of(ride.theme.id) {
    _camY0 = ride.c.s.camY;
  }

  /// The ride it belongs to.
  final PortalRide ride;

  /// The themed ride's reveal (null: the cannon).
  final RideReveal? reveal;

  late final double _camY0;

  /// The run camera's height when the ride started (the follow's zero).
  double get camY0 => _camY0;
  final List<Offset> _offsets = List.filled(4, Offset.zero);
  final List<double> _reach = List.filled(4, 0);
  bool _hidden = false;
  double _p = 0;
  double _catchGt = 0;

  /// The world rate (world pt per camera pt) between seams (README "World
  /// distance": 300 per hoop, 310 between planes).
  static const double rate = kPerHoop / RunConfig.spacing;

  /// The time since the launch (s; < 0 before it).
  double get tau => switch (ride.phase) {
    RidePhase.fly => ride.view.ft,
    RidePhase.glide || RidePhase.done =>
      PortalConfig.flyTime - PortalConfig.flyEndEarly + ride.view.gt,
    _ => -1,
  };

  /// How far the themed scene has left (0 before the launch, 1 gone).
  double get progress => _p;

  /// The offset of [band] this frame (tests, debug).
  Offset offsetOf(Band band) => _offsets[_index(band)];

  static int _index(Band b) => b == Band.front ? Band.near.index : b.index;

  /// `softY`: the follow, capped so the scene never runs out.
  static double softY(double y) => y < 0
      ? -HandoverConfig.softUp * _tanh(-y / HandoverConfig.softUp)
      : HandoverConfig.softDown * _tanh(y / HandoverConfig.softDown);

  static double _tanh(double x) {
    final e = math.exp(-2 * x.abs());
    final t = (1 - e) / (1 + e);
    return x < 0 ? -t : t;
  }

  /// The camera height the layers follow now (pt, + = down).
  double get _cy {
    final s = ride.c.s;
    switch (ride.phase) {
      case RidePhase.ride || RidePhase.exit:
        return s.camY - _camY0;
      case RidePhase.fly:
        return reveal == null ? s.camY - _camY0 : 0;
      case RidePhase.glide:
        if (reveal != null) return 0;
        final k = math.min(1.0, ride.view.gt / PortalConfig.glideTime);
        final ke = k * k * k * (k * (k * 6 - 15) + 10);
        return (ride.flyEndCamY - _camY0) * (1 - ke);
      case RidePhase.done:
        return 0;
    }
  }

  /// The landing bump's time curve (× share × amp gives the offset).
  double get _bump {
    if (ride.phase != RidePhase.glide) return 0;
    final w = ride.view.gt - PortalConfig.glideTime;
    if (w < 0 || w >= PortalConfig.settleTime) return 0;
    final taper = 1 -
        math.pow(w / PortalConfig.settleTime, HandoverConfig.bumpTaperPow);
    return math.exp(-HandoverConfig.bumpDecay * w) *
        math.sin(HandoverConfig.bumpFreq * w) *
        taper;
  }

  /// Recomputes this frame's offsets (after the ride's update).
  void step() {
    final rv = reveal;
    final ph = ride.phase;
    final t = tau;
    _p = rv == null ? 0 : RideReveal.progress(t);
    // the scene covers everything: faded in, the exit, the launch frame
    _hidden = rv != null &&
        ((ph == RidePhase.ride && ride.view.envA >= 1) ||
            ph == RidePhase.exit ||
            (ph == RidePhase.fly && _p <= 0));
    final cy = softY(_cy), bump = _bump;
    final revealing = rv != null && t >= 0 && t < RideReveal.arrived;
    for (var b = 0; b < 4; b++) {
      final share = HandoverConfig.share[b];
      var dx = 0.0, dy = -cy * share + HandoverConfig.bumpAmp * share * bump;
      var reach = 0.0;
      if (revealing) {
        final d = rv.distance[b] * RideReveal.remaining(b, t);
        dx += rv.dirX * d;
        dy += rv.dirY * d;
        reach = rv.dirX * rv.distance[b];
      }
      _offsets[b] = dx == 0 && dy == 0 ? Offset.zero : Offset(dx, dy);
      _reach[b] = reach;
    }
  }

  /// The launch: a themed ride's scene still covers the whole screen, so
  /// the world is set (unseen) where it must be for the next hoops: on its
  /// hoop schedule when control returns (WP-R: no hold at a seam, no
  /// creeping after the ride). The cannon's world is visible: no jump.
  void onLaunch() {
    if (reveal == null) return;
    final backdrop = RunBackdrop.of(ride.c.game);
    if (backdrop == null || !identical(backdrop.rideHook, this)) return;
    final s = ride.c.s;
    final cr = RunConfig.cruise(s.hoopIndex);
    const glide = PortalConfig.glideTime + PortalConfig.settleTime;
    // The flight camera's run (`_stepFly`: x = launch + 560·T − 140 at T).
    const fly = PortalConfig.flyTime - PortalConfig.flyEndEarly;
    final dFly = ride.launch.dx + PortalConfig.launchVx * fly - PortalConfig.flyX1;
    // The first hoop after the ride (`_beginGlide` → `resumeAt`) is
    // 2 s of cruise ahead of the screen centre's plane minus birdX when
    // the settle ends; the world must then be 300 · n1 short of it by r.
    final n1 = ride.c.director.hoopIndex;
    final ahead = RunConfig.birdX - kANCH + cr * PortalConfig.firstRingAfterControl;
    final atEnd = kPerHoop * n1 - rate * ahead;
    final catchUp = HandoverConfig.catchUp /
        HandoverConfig.catchUpDecay *
        (1 - math.exp(-HandoverConfig.catchUpDecay * glide));
    final added = rate * (dFly + cr * glide + catchUp);
    backdrop.distance.resync(atEnd - added);
  }

  @override
  bool get hidden => _hidden;

  @override
  Offset bandOffset(Band band) => _offsets[_index(band)];

  @override
  double sideReach(Band band) => _reach[_index(band)];

  @override
  double? scroll(double dc) {
    switch (ride.phase) {
      case RidePhase.ride:
      case RidePhase.exit:
        // unseen under a themed scene: the world holds
        return _hidden ? 0 : rate * dc;
      case RidePhase.fly:
        return rate * dc;
      case RidePhase.glide:
        // the catch-up, integrated over the glide time since the last
        // move (the glide's first frame moved the camera in flight)
        final g0 = _catchGt, g1 = ride.view.gt;
        _catchGt = g1;
        const k = HandoverConfig.catchUpDecay;
        final extra = HandoverConfig.catchUp /
            k *
            (math.exp(-k * g0) - math.exp(-k * g1));
        return rate * (dc + extra);
      case RidePhase.done:
        return null;
    }
  }

  @override
  bool cover(Path covered, double viewHeight) {
    final rv = reveal;
    if (rv == null || ride.phase != RidePhase.fly && ride.phase != RidePhase.glide) {
      return false;
    }
    if (_p >= 1) return false;
    RideReveal.sceneClip(
      covered,
      ride.theme.id,
      _p,
      ride.view.t,
      ride.view.w,
      viewHeight,
      left: ride.view.left, // WP-TAB
    );
    return true;
  }
}
