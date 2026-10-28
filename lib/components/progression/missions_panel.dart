import 'dart:ui';
import 'package:flame/components.dart';
import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../progression/missions.dart';
import '../../run/config/tuning_values.dart';
import '../../run/effects/coin_icon.dart';
import '../home/menu_primitives.dart';
import '../ui/mystery_box.dart';
import '../ui/p1_popup.dart';

String missionCountdown(DateTime now) {
  final next = DateTime(now.year, now.month, now.day + 1);
  final minutes = next.difference(now).inMinutes;
  return minutes >= 60
      ? 'NEW IN ${minutes ~/ 60} H ${minutes % 60} M'
      : 'NEW IN $minutes M';
}

String missionStripCountdown(DateTime now) {
  final minutes = DateTime(
    now.year,
    now.month,
    now.day + 1,
  ).difference(now).inMinutes;
  return minutes >= 60 ? 'NEW IN ${minutes ~/ 60} H' : 'NEW IN $minutes M';
}

String missionTask(MissionProgress m) {
  final n = m.target;
  return switch (m.template) {
    MissionTemplate.m01 => 'PLAY $n RUNS',
    MissionTemplate.m02 => 'PASS $n HOOPS IN TOTAL',
    MissionTemplate.m03 => '$n PERFECT PASSES',
    MissionTemplate.m04 => 'EARN $n COINS IN RUNS',
    MissionTemplate.m05 => 'CATCH $n POWER-UPS',
    MissionTemplate.m06 =>
      n == 1 ? 'RIDE A COMET OR PORTAL' : 'RIDE $n COMETS OR PORTALS',
    MissionTemplate.m07 =>
      n == 1 ? 'FIND A FEATHER OR PUZZLE PIECE' : 'FIND $n FEATHERS OR PIECES',
    MissionTemplate.m08 => n == 1 ? 'HIT A BULLSEYE' : 'HIT $n BULLSEYES',
    MissionTemplate.m09 => 'OPEN $n SWITCH RINGS',
    MissionTemplate.m10 =>
      n == 1 ? 'WIN A VERSUS MATCH' : 'WIN $n VERSUS MATCHES',
    MissionTemplate.m11 => 'PASS $n HOOPS IN ONE RUN',
    MissionTemplate.m12 => 'GET A ×$n PERFECT STREAK',
    MissionTemplate.m13 => '$n HOOPS IN A ROW, NO RIM HIT',
    MissionTemplate.m14 =>
      n == 1 ? 'SURVIVE A SPIKE SQUEEZE' : 'SURVIVE $n SPIKE SQUEEZES',
    MissionTemplate.m15 =>
      'REACH ${n == 20
          ? 'SKY & HILLS'
          : n == 40
          ? 'CITY SKYLINE'
          : "GIANT'S DESK"} IN ONE RUN',
  };
}

class MissionPips extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  MissionPips(this.missions, {this.side = 12, super.position});
  final List<MissionProgress> missions;
  final double side;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final check = Sprite(await game.images.load('menu/check.png'));
    for (var i = 0; i < missions.length && i < 3; i++) {
      if (missions[i].complete) {
        add(
          MenuIcon(
            check,
            size: Vector2.all(side * .75),
            position: Vector2(i * (side + 5) + side / 2, side / 2),
            anchor: Anchor.center,
          ),
        );
      }
    }
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(i * (side + 5), 0, side, side);
      final p = i < missions.length
          ? (missions[i].progress / missions[i].target).clamp(0.0, 1.0)
          : 0.0;
      canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - side * p, side, side * p),
        Paint()..color = Config.menuPink,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Config.menuPink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }
}

class MissionsPanel extends P1Popup {
  MissionsPanel({
    required this.missions,
    required this.now,
    required super.onDismiss,
    this.weeklyCard,
    this.starRoadCard,
  });
  final Missions missions;
  final DateTime now;
  final PositionComponent? weeklyCard, starRoadCard;
  late MenuText countdown;
  @override
  void update(double dt) {
    super.update(dt);
    countdown.text = missionCountdown(game.storage.now());
  }

  @override
  Future<void> buildCard(PositionComponent card) async {
    var y = 58.0;
    card.add(
      RectangleComponent(
        size: Vector2(280, 46),
        paint: Paint()..color = Config.menuPink,
      ),
    );
    card.add(
      MenuText(
        'MISSIONS',
        fontSize: 21,
        color: Config.menuSoft,
        position: Vector2(16, 10),
      ),
    );
    card.add(
      closeBox(Sprite(await game.images.load('menu/close.png')), onDismiss),
    );
    if (weeklyCard != null) {
      card.add(weeklyCard!..position = Vector2(12, y));
      y += weeklyCard!.height + 14;
    }
    card.add(
      MenuText(
        'TODAY',
        fontSize: 10,
        color: const Color(0xFF8A8A8A),
        position: Vector2(12, y),
      ),
    );
    countdown = MenuText(
      missionCountdown(now),
      fontSize: 10,
      color: Config.menuPink,
      position: Vector2(268, y),
      anchor: Anchor.topRight,
    );
    card.add(countdown);
    final coin = await CoinIcon.sprite(game.images);
    final check = Sprite(await game.images.load('menu/check.png'));
    final rewards = TuningValues.current.ints('mission_rewards');
    y += 18;
    for (final m in missions.missions) {
      final row = PositionComponent(
        position: Vector2(12, y),
        size: Vector2(256, 54),
      );
      row.add(
        RectangleComponent(
          size: row.size.clone(),
          paint: Paint()..color = const Color(0xFFFFFFFF),
        ),
      );
      row.add(
        RectangleComponent(
          size: Vector2(4, 54),
          paint: Paint()
            ..color = switch (m.template.difficulty) {
              MissionDifficulty.easy => const Color(0xFF64CBA2),
              MissionDifficulty.medium => Config.menuPink,
              MissionDifficulty.hard => Config.menuGold,
            },
        ),
      );
      row.add(
        MenuText(
          missionTask(m),
          fontSize: 10,
          color: Config.menuPlum,
          position: Vector2(10, 8),
        ),
      );
      row.add(
        MenuText(
          '${m.progress} / ${m.target}',
          fontSize: 10,
          color: Config.menuPlum,
          position: Vector2(10, 34),
        ),
      );
      row.add(
        MenuText(
          '+${rewards[m.template.difficulty.index]}',
          fontSize: 12,
          color: Config.menuPlum,
          position: Vector2(224, 30),
          anchor: Anchor.topRight,
        ),
      );
      row.add(
        RectangleComponent(
          position: Vector2(10, 27),
          size: Vector2(150, 4),
          paint: Paint()..color = const Color(0xFFE5E5E5),
        ),
      );
      row.add(
        RectangleComponent(
          position: Vector2(10, 27),
          size: Vector2(150 * (m.progress / m.target).clamp(0.0, 1.0), 4),
          paint: Paint()..color = Config.menuPink,
        ),
      );
      row.add(
        MenuIcon(coin, size: Vector2.all(15), position: Vector2(229, 29)),
      );
      if (m.complete) {
        row.add(
          MenuIcon(check, size: Vector2.all(14), position: Vector2(229, 6)),
        );
      }
      card.add(row);
      y += 60;
    }
    card.add(
      RectangleComponent(
        position: Vector2(12, y),
        size: Vector2(256, 56),
        paint: Paint()..color = Config.menuGold,
      ),
    );
    card.add(
      MysteryBoxComponent(
        look: MysteryBoxLook.tier(MysteryBoxTier.gold),
        boxSize: 40,
        position: Vector2(39, y + 28),
      ),
    );
    card.add(
      MenuText(
        'ALL 3 DONE',
        fontSize: 11,
        color: Config.menuPlum,
        position: Vector2(166, y + 28),
        anchor: Anchor.center,
      ),
    );
    y += 70;
    if (starRoadCard != null) {
      card.add(starRoadCard!..position = Vector2(12, y));
      y += starRoadCard!.height + 14;
    }
    cardHeight = y;
  }
}
