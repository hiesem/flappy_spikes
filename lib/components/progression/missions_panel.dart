import 'dart:ui';
import 'dart:math' as math;
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

/// Three inset pips, optionally animating each changed mission in order.
class MissionPips extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  MissionPips(
    this.missions, {
    this.before,
    this.side = 12,
    this.color = Config.menuPink,
    super.position,
  });
  final List<MissionProgress> missions;
  final List<int>? before;
  final double side;
  Color color;
  double elapsed = 0;
  late Sprite check;
  List<int> get moved => [
    for (var i = 0; i < missions.length && i < 3; i++)
      if (before != null && before![i] < missions[i].progress) i,
  ];
  double get duration => moved.isEmpty ? 0 : .5 + (moved.length - 1) * 1.6 + .9;
  double fractionAt(int i) {
    final m = missions[i];
    final from = before == null ? m.progress : before![i];
    final order = moved.indexOf(i);
    if (order < 0) return from / m.target;
    final u = ((elapsed - .5 - order * 1.6) / .65).clamp(0.0, 1.0);
    final eased = 1 - math.pow(1 - u, 3).toDouble();
    return (from + (m.progress - from) * eased) / m.target;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    check = Sprite(await game.images.load('menu/check.png'));
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(i * (side + 5), 0, side, side);
      final p = i < missions.length ? fractionAt(i).clamp(0.0, 1.0) : 0.0;
      canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - side * p, side, side * p),
        Paint()..color = color,
      );
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (p >= 1 && i < missions.length) {
        final order = moved.indexOf(i);
        final popTime = order < 0 ? 1.0 : elapsed - (.5 + order * 1.6 + .65);
        final pop = popTime >= 0 && popTime < .25
            ? 1 + .35 * math.sin(math.pi * popTime / .25)
            : 1.0;
        final size = side * .75 * pop;
        check.render(
          canvas,
          position: Vector2(
            rect.center.dx - size / 2,
            rect.center.dy - size / 2,
          ),
          size: Vector2.all(size),
        );
      }
    }
  }
}

/// Home entry; countdown follows local midnight while the screen remains open.
class MissionsHomeStrip extends MenuButton
    with HasGameReference<FlappySpikesGame> {
  MissionsHomeStrip({
    required this.missions,
    required Rect rect,
    required super.onPressed,
    required super.isActive,
  }) : super(
         position: Vector2(rect.left, rect.top),
         size: Vector2(rect.width, rect.height),
         color: missions.allDone ? Config.menuGold : Config.menuSoft,
       );
  final Missions missions;
  MenuText? countdown;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      MenuText(
        missions.allDone ? 'ALL DONE' : 'MISSIONS',
        fontSize: 10,
        color: Config.menuPlum,
        position: Vector2(10, 5),
      ),
    );
    add(
      MissionPips(
        missions.missions,
        side: missions.allDone ? 10 : 12,
        color: missions.allDone ? Config.menuPlum : Config.menuPink,
        position: Vector2(missions.allDone ? 85 : 144, 5),
      ),
    );
    if (missions.allDone) {
      countdown = MenuText(
        missionStripCountdown(game.storage.now()),
        fontSize: 8,
        color: Config.menuPlum,
        position: Vector2(209, 6),
        anchor: Anchor.topRight,
      );
      add(countdown!);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    countdown?.text = missionStripCountdown(game.storage.now());
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!missions.allDone) {
      final path = Path()
        ..moveTo(201, 6)
        ..lineTo(207, 11)
        ..lineTo(201, 16);
      canvas.drawPath(
        path,
        Paint()
          ..color = Config.menuPink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
    }
  }
}

/// Results pips fill in order; the chest message appears after the last fill.
class MissionResultsStrip extends PositionComponent {
  MissionResultsStrip({required this.missions, required this.before})
    : super(position: Vector2(14, 565), size: Vector2(292, 22));
  final List<MissionProgress> missions;
  final List<int> before;
  late MissionPips pips;
  late MenuText label;
  bool get newlyAllDone =>
      missions.every((m) => m.complete) &&
      List.generate(
        missions.length,
        (i) => before[i] >= missions[i].target,
      ).contains(false);
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    label = MenuText(
      'MISSIONS',
      fontSize: 10,
      color: Config.menuPlum,
      position: Vector2(10, 5),
    );
    pips = MissionPips(
      missions,
      before: before,
      side: 16,
      position: Vector2(231, 3),
    );
    addAll([label, pips]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (newlyAllDone && pips.elapsed >= pips.duration) {
      label.text = 'ALL DONE · CHEST ON HOME';
      pips.color = Config.menuPlum;
    }
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(
    size.toRect(),
    Paint()
      ..color = newlyAllDone && pips.elapsed >= pips.duration
          ? Config.menuGold
          : Config.menuSoft,
  );
}

class _ChestRow extends PositionComponent {
  _ChestRow(double y) : super(position: Vector2(12, y), size: Vector2(256, 56));
  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFFFFF8E8));
    canvas.save();
    canvas.clipRect(size.toRect());
    for (var x = -56.0; x < width + 56; x += 32) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + 16, 0)
        ..lineTo(x - 40, 56)
        ..lineTo(x - 56, 56)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFFFF3D6));
    }
    canvas.restore();
    canvas.drawRect(
      size.toRect().deflate(1),
      Paint()
        ..color = Config.menuGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
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
              MissionDifficulty.easy => Config.menuSoft,
              MissionDifficulty.medium => Config.menuPink,
              MissionDifficulty.hard => Config.menuPlum,
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
    card.add(_ChestRow(y));
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
    y += 66;
    if (missions.allDone) {
      card.add(
        RectangleComponent(
          position: Vector2(12, y),
          size: Vector2(256, 26),
          paint: Paint()..color = Config.menuPlum,
        ),
      );
      card.add(
        MenuText(
          'ALL DONE · NEW MISSIONS TOMORROW',
          fontSize: 9,
          color: Config.menuSoft,
          position: Vector2(140, y + 13),
          anchor: Anchor.center,
        ),
      );
      y += 36;
    }
    y += 4;
    if (starRoadCard != null) {
      card.add(starRoadCard!..position = Vector2(12, y));
      y += starRoadCard!.height + 14;
    }
    cardHeight = y;
  }
}
