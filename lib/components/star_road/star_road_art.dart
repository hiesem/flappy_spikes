import 'dart:math' as math;
import 'dart:ui';
import 'package:flame/components.dart';
import '../../game/config.dart';
import '../home/menu_primitives.dart';

/// The approved Star Road five-point star, shared by its card and road.
class StarRoadStar extends PositionComponent {
  StarRoadStar({double side = 14, super.position, super.anchor})
    : super(size: Vector2.all(side));
  static void paint(Canvas canvas, double side) {
    Path star(double dy) {
      final p = Path();
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5;
        final r = side * (i.isEven ? .46 : .19);
        final x = side / 2 + math.cos(angle) * r;
        final y = side / 2 + math.sin(angle) * r + dy;
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      return p..close();
    }

    canvas.drawPath(star(side * .04), Paint()..color = const Color(0xFFC98A00));
    canvas.drawPath(star(0), Paint()..color = const Color(0xFFFFB529));
  }

  @override
  void render(Canvas canvas) => paint(canvas, size.x);
}

enum StarRoadNodeState { claimed, claimable, next, locked }

/// Tier plate used by the track, mini road and reward popup.
class StarRoadTierNode extends PositionComponent {
  StarRoadTierNode({
    required this.tier,
    required this.state,
    double side = 36,
    super.position,
  }) : super(size: Vector2.all(side));
  final int tier;
  final StarRoadNodeState state;
  Color get ink => switch (state) {
    StarRoadNodeState.claimed => const Color(0xFFFFFFFF),
    StarRoadNodeState.claimable => const Color(0xFF7A0044),
    StarRoadNodeState.next => Config.menuPink,
    StarRoadNodeState.locked => const Color(0xFFA6A6A6),
  };
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      MenuText(
        '$tier',
        fontSize: size.x * (tier > 9 ? 15 : 16) / 36,
        color: ink,
        position: size / 2,
        anchor: Anchor.center,
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final fill = switch (state) {
      StarRoadNodeState.claimed => Config.menuPink,
      StarRoadNodeState.claimable => const Color(0xFFFFB529),
      StarRoadNodeState.next => const Color(0xFFFFFFFF),
      StarRoadNodeState.locked => const Color(0xFFE2E2E2),
    };
    final edge = switch (state) {
      StarRoadNodeState.claimed => const Color(0xFFB4006B),
      StarRoadNodeState.claimable => const Color(0xFFC98A00),
      StarRoadNodeState.next => Config.menuPink,
      StarRoadNodeState.locked => const Color(0xFFC4C4C4),
    };
    final s = size.x;
    Path oct(double dy) => Path()
      ..moveTo(s * .25, dy)
      ..lineTo(s * .75, dy)
      ..lineTo(s, dy + s * .25)
      ..lineTo(s, dy + s * .75)
      ..lineTo(s * .75, dy + s)
      ..lineTo(s * .25, dy + s)
      ..lineTo(0, dy + s * .75)
      ..lineTo(0, dy + s * .25)
      ..close();
    canvas.drawPath(oct(s * .055), Paint()..color = edge);
    canvas.drawPath(oct(0), Paint()..color = fill);
    if (state == StarRoadNodeState.next) {
      canvas.drawPath(
        oct(0),
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }
}
