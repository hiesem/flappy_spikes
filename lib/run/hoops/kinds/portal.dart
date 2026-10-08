import 'dart:math' as math;
import 'dart:ui';

import '../../config/portal_config.dart';
import '../../run_context.dart';
import '../../run_state.dart';
import '../hoop.dart';
import '../hoop_kind.dart';
import '../ring_painter.dart';
import 'normal.dart';

/// The portal ring (PRD-2 §3.12, §5.12b): a normal-sized ring in purple
/// `#7C4DFF` / deep violet `#4B2BB8` with a cyan `#22E6FF` inner rim and a
/// 13 % cyan fill; a short beam of light (66 pt, as tall as the opening,
/// cyan → violet → transparent, pulsing 75–100 %) streams out of its front
/// toward the bird. It is ring #0 of the ride chain: the bird flies through
/// it like any ring (rims bounce, the pass counts as usual) and the pass
/// starts the ride (`PortalRideFeature`). No tier look (ARCH §2.5).
class PortalHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.portal;

  @override
  bool get usesTierLook => false;

  @override
  void buildVisual(Hoop h, RunContext c) {
    h.paintBack = (canvas) => paintBack(canvas, h.opening, c.s.runClock, h.look.opacity);
    h.front.paintFront = (canvas) => paintFront(canvas, h.opening, h.look.opacity);
  }

  /// The portal ellipse's half height (the normal ring's, §5.12b).
  static double ry(double opening) => RingPainter.ryFor(opening);

  /// The beam pulse (0.75 … 1) at [t] (s).
  static double beamAlpha(double t) =>
      .75 + .25 * math.sin(t * PortalConfig.beamPulse);

  /// Back half (behind the bird): beam, cyan fill, deep violet back stroke.
  static void paintBack(Canvas c, double opening, double t, double opacity) {
    if (opacity <= 0) return;
    final r = ry(opening);
    final beam = beamAlpha(t) * opacity;
    const len = PortalConfig.portalBeam;
    final p = Paint()
      ..shader = Gradient.linear(
        const Offset(2, 0),
        const Offset(2 - len, 0),
        [
          Color.fromRGBO(34, 230, 255, .73 * beam),
          Color.fromRGBO(124, 77, 255, .27 * beam),
          const Color(0x007C4DFF),
        ],
        const [0, .6, 1],
      );
    c.drawPath(
      Path()
        ..moveTo(2, -r - 1)
        ..lineTo(2, r + 1)
        ..lineTo(2 - len, .8 * (r + 1))
        ..lineTo(2 - len, -.8 * (r + 1))
        ..close(),
      p,
    );
    final oval = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * PortalConfig.portalRx,
      height: 2 * r,
    );
    c
      ..drawOval(oval, Paint()..color = Color.fromRGBO(34, 230, 255, .13 * opacity))
      ..drawArc(
        oval,
        -math.pi / 2,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = PortalConfig.portalStroke
          ..color = PortalConfig.portalBack.withValues(alpha: opacity),
      );
  }

  /// Front half (over the bird): purple stroke and the cyan inner rim.
  static void paintFront(Canvas c, double opening, double opacity) {
    if (opacity <= 0) return;
    final r = ry(opening);
    c
      ..drawArc(
        Rect.fromCenter(
          center: Offset.zero,
          width: 2 * PortalConfig.portalRx,
          height: 2 * r,
        ),
        math.pi / 2,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = PortalConfig.portalStroke
          ..color = PortalConfig.portalFront.withValues(alpha: opacity),
      )
      ..drawArc(
        Rect.fromCenter(
          center: Offset.zero,
          width: 2 * PortalConfig.portalInnerRx,
          height: 2 * (r - PortalConfig.portalInnerInset),
        ),
        math.pi / 2,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = PortalConfig.portalInnerStroke
          ..color = PortalConfig.portalCyan.withValues(alpha: .9 * opacity),
      );
  }
}

/// A ride ring (PRD-2 §3.12, §5.12b): the standard ring (master #3, the
/// equipped hoop skin, tier tints and sparkles) rotated to face the path.
/// Owned by the portal ride, never by the spawner's physics: the ride
/// passes it by arc length; rims are ignored in rides.
class RideRingKind extends NormalHoopKind {
  @override
  HoopKindId get id => HoopKindId.rideRing;

  @override
  RimMode rimMode(Hoop h, RunState s) => RimMode.ignored;
}
