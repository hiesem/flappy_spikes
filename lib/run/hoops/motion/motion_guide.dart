import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../config/layout_config.dart';
import '../../director/plans.dart';
import '../../effects/dashed_path.dart';
import '../ring_painter.dart';
import 'hoop_motion.dart';

/// §5.12 The guide of a moving ring: dashed stage-fg lines (2.5 pt, 6 / 6,
/// 75 %) with 13 × 12 arrowheads and 16 pt end caps, drawn around the ring's
/// **home** position (guide-local (0, 0)) so it scrolls with the world.
/// Uses the shared `DashedPathPainter` (ARCH §3). Pure painting; the
/// component is [MotionGuide].
///
/// - rail / horizontal / diagonal: the slide line with end caps and an
///   arrowhead past each end;
/// - swing: the rope (solid, from the pivot above the top spikes to the
///   ring) and the dashed arc of the ring's path with an arrowhead at each
///   end;
/// - orbit: the dashed ellipse with an arrowhead on each side (clockwise);
/// - rock: a curved arrow above the ring (arrowheads both ends) and a dotted
///   centre line.
abstract final class MotionGuidePainter {
  static final Paint _fill = Paint()..style = PaintingStyle.fill;
  static final Paint _solid = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  /// Paints the guide of [spec] for a ring with [opening] in guide-local
  /// coordinates. [ring] = the ring's current offset from home (the swing's
  /// rope end); [opacity] fades the whole guide (portal clear-ahead).
  static void paint(
    Canvas canvas,
    MotionSpec spec, {
    required double opening,
    required Color color,
    Offset ring = Offset.zero,
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final line = color.withValues(alpha: LayoutConfig.guideOpacity * opacity);
    final head = color.withValues(alpha: LayoutConfig.arrowOpacity * opacity);
    switch (spec.type) {
      case MotionType.rail:
      case MotionType.horizontal:
      case MotionType.diagonal:
        final a = spec.axisDeg * math.pi / 180;
        final d = Offset(math.sin(a), math.cos(a));
        final h = spec.halfTravel;
        DashedPathPainter.line(canvas, -d * h, d * h, color: line);
        final n = Offset(-d.dy, d.dx) * (LayoutConfig.capLength / 2);
        for (final s in const [-1.0, 1.0]) {
          final end = d * (h * s);
          _segment(canvas, end - n, end + n, line, LayoutConfig.guideWidth);
          arrowhead(canvas, d * (s * (h + LayoutConfig.arrowGap)), d * s, head);
        }
      case MotionType.swing:
        final l = spec.rope;
        final amp = spec.amplitudeDeg * math.pi / 180;
        final pivot = Offset(0, -l);
        _segment(
          canvas,
          pivot,
          ring,
          color.withValues(alpha: LayoutConfig.ropeOpacity * opacity),
          LayoutConfig.ropeWidth,
        );
        // Path of the ring centre: angle measured from straight down.
        final rect = Rect.fromCircle(center: pivot, radius: l);
        DashedPathPainter.stroke(
          canvas,
          Path()..addArc(rect, math.pi / 2 - amp, 2 * amp),
          color: line,
        );
        for (final s in const [-1.0, 1.0]) {
          final th = s * amp;
          final p = pivot + Offset(math.sin(th), math.cos(th)) * l;
          // Tangent pointing outward (away from the bottom of the arc).
          final t = Offset(math.cos(th), -math.sin(th)) * s;
          arrowhead(canvas, p + t * LayoutConfig.arrowGap, t, head);
        }
      case MotionType.orbit:
        DashedPathPainter.stroke(
          canvas,
          Path()..addOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: 2 * spec.rx,
              height: 2 * spec.ry,
            ),
          ),
          color: line,
        );
        // Clockwise on screen: down on the right, up on the left.
        arrowhead(canvas, Offset(spec.rx, 0), const Offset(0, 1), head);
        arrowhead(canvas, Offset(-spec.rx, 0), const Offset(0, -1), head);
      case MotionType.rock:
        final r = RingPainter.ryFor(opening) + LayoutConfig.rockArcGap;
        final half = LayoutConfig.rockArcHalfDeg * math.pi / 180;
        DashedPathPainter.stroke(
          canvas,
          Path()..addArc(
            Rect.fromCircle(center: Offset.zero, radius: r),
            -math.pi / 2 - half,
            2 * half,
          ),
          color: line,
        );
        for (final s in const [-1.0, 1.0]) {
          final a = -math.pi / 2 + s * half;
          final p = Offset(math.cos(a), math.sin(a)) * r;
          final t = Offset(-math.sin(a), math.cos(a)) * s;
          arrowhead(canvas, p + t * LayoutConfig.arrowGap, t, head);
        }
        final e = RingPainter.ryFor(opening) - 10;
        DashedPathPainter.line(
          canvas,
          Offset(0, -e),
          Offset(0, e),
          color: color.withValues(
            alpha: LayoutConfig.rockAxisOpacity * opacity,
          ),
          width: LayoutConfig.rockAxisWidth,
          dashes: LayoutConfig.rockAxisDash,
        );
    }
  }

  /// A 13 × 12 arrowhead whose tip points along [dir] (unit), centred like
  /// the mock's `0,-7 6,5 -6,5` triangle at [at].
  static void arrowhead(Canvas canvas, Offset at, Offset dir, Color color) {
    final n = Offset(-dir.dy, dir.dx);
    const tip = LayoutConfig.arrowLength * 7 / 12;
    const back = LayoutConfig.arrowLength - tip;
    const w = LayoutConfig.arrowWidth / 2;
    final path = Path()
      ..moveTo(at.dx + dir.dx * tip, at.dy + dir.dy * tip)
      ..lineTo(
        at.dx - dir.dx * back + n.dx * w,
        at.dy - dir.dy * back + n.dy * w,
      )
      ..lineTo(
        at.dx - dir.dx * back - n.dx * w,
        at.dy - dir.dy * back - n.dy * w,
      )
      ..close();
    canvas.drawPath(path, _fill..color = color);
  }

  static void _segment(Canvas c, Offset a, Offset b, Color color, double w) {
    _solid
      ..color = color
      ..strokeWidth = w;
    c.drawLine(a, b, _solid);
  }
}

/// §3.11 / §5.12 The guide component of one moving ring: sits at the ring's
/// home position in the hoop-back track layer, under the ring (z 3 in the
/// mock), and spawns with the ring at the screen edge so the motion can be
/// read before the ring is reachable.
class MotionGuide extends PositionComponent {
  MotionGuide({
    required this.motion,
    required this.opening,
    required Vector2 home,
    required this.color,
  }) : super(position: home.clone(), priority: -1);

  final HoopMotion motion;
  final double opening;

  /// The current stage foreground (§5.12 "fg").
  final Color Function() color;

  /// Guide opacity (1 = the §5.12 look).
  double opacity = 1;

  @override
  void render(Canvas canvas) {
    MotionGuidePainter.paint(
      canvas,
      motion.spec,
      opening: opening,
      color: color(),
      ring: Offset(motion.offset.x, motion.offset.y),
      opacity: opacity,
    );
  }
}
