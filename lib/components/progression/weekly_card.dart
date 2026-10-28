import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../progression/weekly_course.dart';
import '../home/menu_primitives.dart';

/// Weekly course entry in the missions panel (PRD G5).
class WeeklyCard extends PositionComponent {
  WeeklyCard({required this.course, required this.now, required this.onPressed})
    : super(size: Vector2(256, 66));

  final WeeklyCourse course;
  final DateTime now;
  final void Function() onPressed;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final week = WeeklyWeek.at(now);
    addAll([
      MenuText(
        'WEEKLY COURSE',
        fontSize: 12,
        color: Config.menuPink,
        position: Vector2(54, 10),
      ),
      MenuText(
        week.countdown(now),
        fontSize: 8.5,
        color: Config.menuPlum,
        position: Vector2(248, 7),
        anchor: Anchor.topRight,
      ),
      MenuText(
        'BEST HOOP ${course.bestHoops}',
        fontSize: 9.5,
        color: Config.menuPlum,
        position: Vector2(54, 27),
      ),
      MenuText(
        [15, 30, 60, 120]
            .map(
              (tier) =>
                  '$tier${course.weeklyRewards.contains(tier) ? ' ✓' : ''}',
            )
            .join('  '),
        fontSize: 9.5,
        color: Config.menuPlum,
        position: Vector2(54, 45),
      ),
      MenuButton(
        position: Vector2(182, 22),
        size: Vector2(66, 34),
        color: Config.menuPink,
        onPressed: onPressed,
        children: [
          MenuText(
            '▶ PLAY',
            fontSize: 12,
            color: Config.menuSoft,
            position: Vector2(33, 17),
            anchor: Anchor.center,
          ),
        ],
      ),
    ]);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xffffffff));
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 44, 66),
      Paint()..color = Config.menuGold,
    );
    canvas.drawRect(
      size.toRect().deflate(1),
      Paint()
        ..color = Config.menuGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final flag = Path()
      ..moveTo(15, 20)
      ..lineTo(15, 47)
      ..moveTo(15, 20)
      ..lineTo(32, 20)
      ..lineTo(28, 26)
      ..lineTo(32, 32)
      ..lineTo(15, 32);
    canvas.drawPath(
      flag,
      Paint()
        ..color = Config.menuPlum
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
