import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../config/portal_config.dart';
import '../../director/plans.dart';
import '../../effects/particle_pool.dart';
import '../ride_path.dart';
import '../ride_theme.dart';

/// The cannon ride (PRD-2 §3.12, §5.12b `portal_1…6.png`; mock
/// `screen_portal.html`): curve up (r 180), climb 1 600 pt, loop over the
/// top (r 220), dive 2 000 pt; rings every 380 pt from 190; purple / cyan
/// tint and vertical speed lines; the ground rises into view with the
/// blocky spiked cannon; the bird drops into the muzzle, the barrel tilts
/// 38° right with a shake and fires (flash, smoke, confetti); the cannon
/// recoils and stays behind in the world.
class CannonTheme extends RideTheme {
  @override
  RideId get id => RideId.cannon;

  @override
  RidePath buildPath() => RidePath.segments(const [
    RideSeg.arc(180, -90),
    RideSeg.line(1600),
    RideSeg.arc(220, -180),
    RideSeg.line(2000),
  ]);

  @override
  List<double> ringStations(RidePath p) => RidePath.everyStep(
    PortalConfig.rideRings,
    first: PortalConfig.firstRing,
    step: PortalConfig.cannonRingStep,
  );

  /// PRD-2.2 §18.1 the score circle in this scene.
  @override
  Color get circleColor => const Color(0xFF7C4DFF);

  @override
  Color get circleDigits => const Color(0xFF3B2A8A);

  @override
  (Color, Color) get washTint =>
      (PortalConfig.cannonTintTop, PortalConfig.cannonTintBottom);

  @override
  Map<RideCue, Sfx> get sounds => const {
    RideCue.cannonAim: Sfx.puCannonAim,
    RideCue.cannonShot: Sfx.puCannonShot,
  };

  /// §3.12 cannon entry 0.22 s + aiming ≈ 1 s (the shot at 1.2 s).
  @override
  double get exitDuration => 1.2;

  @override
  double get worldFadeIn => PortalConfig.cannonTintIn;

  /// The path end on screen during the exit (the ride camera stopped).
  Offset _end(RideView v) {
    final e = v.path.end;
    return Offset(e.x - v.camEnd.x, e.y - v.camEnd.y);
  }

  double _tiltAt(double et) {
    if (et < PortalConfig.cannonEntry) return 0;
    final k = (et - PortalConfig.cannonEntry) / PortalConfig.cannonAim;
    return (PortalConfig.cannonTilt * sm(k) + math.sin(et * 40) * 2) *
        math.pi /
        180;
  }

  @override
  Offset launchPoint(RideView v) {
    final e = _end(v);
    const a = PortalConfig.cannonTilt * math.pi / 180;
    // The muzzle centre (svg y 16) rotated about the pivot (svg 60, 112).
    return Offset(e.dx + 96 * math.sin(a), e.dy + 112 - 96 * math.cos(a));
  }

  @override
  void paintBackdrop(Canvas c, RideView v, Vector2 cam) {
    vGradient(
      c,
      Rect.fromLTWH(0, 0, v.w, v.h),
      PortalConfig.cannonTintTop,
      PortalConfig.cannonTintBottom,
    );
  }

  @override
  void paintWorld(Canvas c, RideView v, Vector2 cam) {
    final near = _near(v);
    if (near <= 0) return;
    final e = v.path.end;
    _ground(c, Offset(e.x - cam.x, e.y - cam.y), near);
  }

  double _near(RideView v) =>
      v.phase == RidePhase.ride ? sm((v.s - (v.path.length - 800)) / 600) : 1;

  @override
  void paintWorldFront(Canvas c, RideView v) {
    final near = _near(v);
    if (near <= 0) return;
    final e = v.path.end;
    _cannon(c, Offset(e.x - v.cam.x, e.y - v.cam.y), 0, 0, near);
  }

  @override
  void paintExit(Canvas c, RideView v, double et, Offset off) {
    final e = _end(v) - off;
    _ground(c, e, 1);
  }

  @override
  void paintExitFront(Canvas c, RideView v, double et, Offset off) {
    final e = _end(v) - off;
    if (et < exitDuration) {
      final shakeY = et >= PortalConfig.cannonEntry ? math.sin(et * 40) * 2 : 0;
      _cannon(c, e.translate(0, shakeY.toDouble()), _tiltAt(et), 0, 1);
    } else {
      final ft = et - exitDuration;
      final recoil = -10 * math.max(0, 1 - ft * 5);
      final tilt =
          PortalConfig.cannonTilt *
          (1 - sm(math.min(1, ft * 2.5))) *
          math.pi /
          180;
      _cannon(c, e.translate(recoil.toDouble(), 0), tilt, 0, 1);
    }
  }

  @override
  BirdPose exitPose(RideView v, double et) {
    if (et >= PortalConfig.cannonEntry - 1e-9) {
      if (v.once('aim')) v.cue(RideCue.cannonAim);
      return BirdPose(v.lastBird, hidden: true);
    }
    // §3.12 straight on into the muzzle (full size, visible above the rim,
    // then hidden by the barrel drawn in front of it).
    final dy = math.min(PortalConfig.rideSpeed * et, 112.0);
    return BirdPose(v.lastBird.translate(0, dy), rot: math.pi / 2);
  }

  @override
  void onLaunch(RideView v) {
    v.cue(RideCue.cannonShot);
    v.data['flash'] = v.t;
    final m = launchPoint(v);
    for (var i = 0; i < 20; i++) {
      final life = v.rand(.6, 1.2);
      v.scenePool.spawn(
        shape: ParticleShape.circle,
        x: m.dx - 8,
        y: m.dy,
        vx: v.rand(-40, 90) / life,
        vy: -v.rand(20, 150) / life,
        w: v.rand(10, 20),
        color: const Color(0xFF8D8D99),
        life: life,
        alpha0: .8,
        scale0: .4,
        scale1: v.rand(1, 2.4),
      );
    }
    const confetti = [
      Color(0xFFEC008C),
      Color(0xFFFFB529),
      Color(0xFF22E6FF),
      Color(0xFF7EE400),
    ];
    for (var i = 0; i < 22; i++) {
      final life = v.rand(.9, 1.5);
      v.scenePool.spawn(
        x: m.dx - 4,
        y: m.dy,
        vx: v.rand(-60, 140) / life,
        vy: -v.rand(80, 240) / life,
        w: v.rand(6, 12),
        h: v.rand(10, 20),
        color: confetti[i % 4],
        life: life,
        spin: v.rand(-500, 500) * math.pi / 180 / life,
      );
    }
  }

  @override
  void paintExtra(Canvas c, RideView v) {
    final at = v.data['flash'] as double?;
    if (at == null) return;
    final k = (v.t - at) / .35;
    if (k >= 1) return;
    c.drawRect(
      Rect.fromLTWH(0, 0, v.w, v.h),
      fillOf(const Color(0xFFFFFFFF), .7 * (1 - k)),
    );
  }

  // ------------------------------------------------------------------ art

  /// §5.12b violet ground block with a cyan top line, 150 pt under the path
  /// end ([e]).
  static void _ground(Canvas c, Offset e, double alpha) {
    final r = Rect.fromLTWH(e.dx - 310, e.dy + 150, 620, 260);
    c
      ..drawRect(r, fillOf(PortalConfig.ground, alpha))
      ..drawRect(
        Rect.fromLTWH(r.left, r.top, 620, 6),
        fillOf(PortalConfig.portalCyan, alpha),
      );
  }

  /// §5.12b the cannon (svg 120 × 150, top-left at [e] − (60, 0)); the
  /// barrel group turns by [tilt] about (60, 112).
  static void _cannon(Canvas c, Offset e, double tilt, double recoil, double a) {
    c
      ..save()
      ..translate(e.dx - 60 + recoil, e.dy);
    c
      ..save()
      ..translate(60, 112)
      ..rotate(tilt)
      ..translate(-60, -112);
    c
      ..drawRect(const Rect.fromLTWH(34, 20, 52, 92), fillOf(PortalConfig.pink, a))
      ..drawRect(
        const Rect.fromLTWH(34, 20, 14, 92),
        fillOf(PortalConfig.pinkLight, a),
      )
      ..drawRect(const Rect.fromLTWH(24, 8, 72, 16), fillOf(PortalConfig.gold, a))
      ..drawRect(
        const Rect.fromLTWH(24, 8, 72, 4),
        fillOf(PortalConfig.goldLight, a),
      );
    for (final s in const [
      [34.0, 58.0, 20.0, 68.0, 34.0, 78.0],
      [86.0, 58.0, 100.0, 68.0, 86.0, 78.0],
      [34.0, 86.0, 20.0, 96.0, 34.0, 106.0],
      [86.0, 86.0, 100.0, 96.0, 86.0, 106.0],
    ]) {
      c.drawPath(poly(s), fillOf(PortalConfig.gold, a));
    }
    c
      ..drawRect(const Rect.fromLTWH(34, 30, 52, 8), fillOf(PortalConfig.band, a))
      ..drawRect(
        const Rect.fromLTWH(34, 118, 52, 10),
        fillOf(PortalConfig.band, a),
      )
      ..restore();
    c
      ..drawRect(const Rect.fromLTWH(20, 112, 80, 20), fillOf(PortalConfig.plum, a))
      ..drawRect(const Rect.fromLTWH(26, 126, 26, 26), fillOf(PortalConfig.plum, a))
      ..drawRect(const Rect.fromLTWH(32, 132, 14, 14), fillOf(PortalConfig.gold, a))
      ..drawRect(const Rect.fromLTWH(68, 126, 26, 26), fillOf(PortalConfig.plum, a))
      ..drawRect(const Rect.fromLTWH(74, 132, 14, 14), fillOf(PortalConfig.gold, a))
      ..restore();
  }
}
