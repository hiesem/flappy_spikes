import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../progression/weekly_course.dart';
import '../home/menu_primitives.dart';

/// Weekly course entry in the missions panel (PRD G5).
class WeeklyCard extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  WeeklyCard({required this.course, required this.now, required this.onPressed})
    : super(size: Vector2(256, 66));

  final WeeklyCourse course;
  final DateTime now;
  final void Function() onPressed;
  late final MenuText countdown, best;
  final List<MenuText> tierLabels = [];
  final List<RectangleComponent> tierBoxes = [];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    countdown = MenuText(
      WeeklyWeek.at(now).countdown(now),
      fontSize: 8.5,
      color: Config.menuPlum,
      position: Vector2(248, 7),
      anchor: Anchor.topRight,
    );
    best = MenuText(
      'BEST HOOP ${course.bestHoops}',
      fontSize: 9.5,
      color: Config.menuPlum,
      position: Vector2(54, 27),
    );
    final button = MenuButton(
      position: Vector2(182, 22),
      size: Vector2(66, 34),
      color: Config.menuPink,
      onPressed: onPressed,
    );
    layoutRow(button, [
      MenuIcon(
        Sprite(await game.images.load('menu/play.png')),
        size: Vector2.all(12),
      ),
      MenuText('PLAY', fontSize: 14, color: Config.menuSoft),
    ], gap: 4);
    addAll([
      MenuText(
        'WEEKLY COURSE',
        fontSize: 12,
        color: Config.menuPink,
        position: Vector2(54, 10),
      ),
      countdown,
      best,
      button,
    ]);
    var x = 54.0;
    for (final tier in [15, 30, 60, 120]) {
      final got = course.weeklyRewards.contains(tier);
      final box = RectangleComponent(
        position: Vector2(x, 45),
        size: Vector2(tier == 120 ? 33 : 29, 15),
        paint: Paint()..color = got ? Config.menuSoft : const Color(0xfff4f4f4),
      );
      final label = MenuText(
        '$tier${got ? ' ✓' : ''}',
        fontSize: 9,
        color: got ? Config.menuPink : Config.menuPlum,
        position: Vector2(x + box.width / 2, 52),
        anchor: Anchor.center,
      );
      tierBoxes.add(box);
      tierLabels.add(label);
      addAll([box, label]);
      x += box.width + 4;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final current = game.storage.now();
    final currentCourse = WeeklyCourse(
      weeklyBest: game.storage.weeklyBest,
      weeklyRewards: game.storage.weeklyRewards,
    ).refresh(current);
    countdown.text = WeeklyWeek.at(current).countdown(current);
    best.text = 'BEST HOOP ${currentCourse.bestHoops}';
    const tiers = [15, 30, 60, 120];
    for (var i = 0; i < tiers.length; i++) {
      final got = currentCourse.weeklyRewards.contains(tiers[i]);
      tierLabels[i].text = '${tiers[i]}${got ? ' ✓' : ''}';
      tierLabels[i].color = got ? Config.menuPink : Config.menuPlum;
      tierBoxes[i].paint.color = got
          ? Config.menuSoft
          : const Color(0xfff4f4f4);
    }
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
