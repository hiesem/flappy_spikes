import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../progression/day_streak.dart';
import '../../run/effects/coin_icon.dart';
import '../../run/effects/life_icons.dart';
import '../../run/hoops/ring_painter.dart';
import '../../run/pickups/feather_pickup.dart';
import '../../run/pickups/puzzle_piece_pickup.dart';
import '../../run/config/puzzle_config.dart';
import '../home/menu_primitives.dart';
import '../ui/p1_popup.dart';

/// The single drawn flame master, shared by the chip and streak cards.
class StreakFlame extends PositionComponent {
  StreakFlame({
    this.lit = true,
    this.still = false,
    double side = 14,
    super.position,
  }) : super(size: Vector2(side, side * 1.25));

  bool lit;
  bool still;
  double time = 0;
  static const periods = [1.2, .9, .6];
  static final _paths = [
    Path()
      ..moveTo(0, -15)
      ..cubicTo(3, -9, 10, -6, 10, 3)
      ..cubicTo(10, 9, 6, 13, 0, 13)
      ..cubicTo(-6, 13, -10, 9, -10, 3)
      ..cubicTo(-10, -3, -5, -5, -4, -10)
      ..cubicTo(-1, -7, -1, -4, 0, -2)
      ..cubicTo(1, -6, 0, -10, 0, -15)
      ..close(),
    Path()
      ..moveTo(0, -3)
      ..cubicTo(2, 0, 6, 2, 6, 6)
      ..cubicTo(6, 10, 3, 12, 0, 12)
      ..cubicTo(-3, 12, -6, 10, -6, 6)
      ..cubicTo(-6, 3, -3, 1, -2, -2)
      ..cubicTo(-1, 0, -.5, 1, 0, 2)
      ..cubicTo(.5, 0, 0, -1, 0, -3)
      ..close(),
    Path()
      ..moveTo(0, 5)
      ..cubicTo(1.5, 6.5, 3, 7.5, 3, 9.5)
      ..cubicTo(3, 11, 1.6, 12, 0, 12)
      ..cubicTo(-1.6, 12, -3, 11, -3, 9.5)
      ..cubicTo(-3, 8, -1.5, 7, 0, 5)
      ..close(),
  ];
  final _paint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    if (lit && !still) time += dt;
  }

  @override
  void render(Canvas canvas) {
    final t = lit && !still ? time : 0.0;
    final colors = lit
        ? const [Color(0xFFFF7A1A), Config.menuGold, Color(0xFFFFF3C4)]
        : const [Color(0xFFBDBDBD), Color(0xFFD6D6D6), Color(0xFFEDEDED)];
    canvas.save();
    canvas.translate(width / 2, height * 16 / 30);
    canvas.scale(width / 24);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      // Each tip sways by at most 0.7 pt at chip size.
      canvas.translate(
        t == 0 ? 0 : math.sin(t * 2 * math.pi / periods[i]) * .7,
        0,
      );
      canvas.drawPath(_paths[i], _paint..color = colors[i]);
      canvas.restore();
    }
    if (lit && !still) {
      for (var i = 0; i < 2; i++) {
        final phase = (t / 1.9 + i * .5) % 1;
        canvas.drawRect(
          Rect.fromLTWH(
            i == 0 ? 3 : -5,
            -12 - math.sin(phase * math.pi),
            1.6,
            1.6,
          ),
          _paint
            ..color = colors[i].withValues(alpha: math.sin(phase * math.pi)),
        );
      }
    }
    canvas.restore();
  }
}

/// Home's right-aligned 26 pt chip. Its state always comes from G2a.
class StreakStrip extends MenuButton with HasGameReference<FlappySpikesGame> {
  StreakStrip({required super.isActive})
    : super(size: Vector2(52, 26), onPressed: () {});
  late final StreakFlame flame;
  late final MenuText count;
  bool pending = false;
  bool visible = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    onPressed = game.openStreakCard;
    flame = StreakFlame(position: Vector2(7, 4));
    count = MenuText(
      '0',
      fontSize: 17,
      color: Config.menuPlum,
      position: Vector2(26, 3),
    );
    addAll([flame, count]);
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      visible && super.containsLocalPoint(point);

  @override
  void update(double dt) {
    final state = game.dayStreak;
    visible =
        DayStreak.unlocked(game.storage.gamesPlayed + 1) &&
        (state.streakLastDay >= 0 || state.streakLostDays > 0);
    final lit = state.flewToday(game.storage.today);
    flame
      ..lit = lit
      ..still = game.reduceMotion || game.liveMotionPaused;
    count
      ..text = '${state.streakDays}'
      ..color = lit ? Config.menuPlum : const Color(0xFF9A9A9A);
    size.x = math.max(52, count.width + 35);
    position = Vector2(
      Config.worldWidth - 14 - width,
      Config.homeGearRectFor(game.viewHeight).bottom + 8,
    );
    pending = state.rewardPending(
      today: game.storage.today,
      runNumber: game.storage.gamesPlayed + 1,
    );
    color = lit ? const Color(0xFFFFFFFF) : const Color(0xB3FFFFFF);
    super.update(dt);
    // The chip's update runs after its Home parent's state sync. Keep the
    // free-start presentation here so Home owns only this component's mount.
    final home = game.homeScreen;
    if (home != null && home.built) {
      game.syncStreakSlot(home.slotButton);
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (visible) super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (pending) {
      canvas.drawCircle(
        Offset(width - 1, 1),
        4,
        Paint()..color = Config.menuGold,
      );
    }
  }
}

/// P1 frame for both the automatic reward and the explicitly opened card.
class StreakCard extends P1Popup {
  StreakCard({
    required this.state,
    required this.today,
    required this.reward,
    required super.onDismiss,
    required this.onCollect,
  });
  final DayStreak state;
  final int today;
  final bool reward;
  final void Function(Rect from) onCollect;
  MenuButton? collectButton;

  void label(
    PositionComponent parent,
    String text,
    double y,
    double font, {
    Color color = Config.menuPlum,
  }) {
    parent.add(
      MenuText(
        text,
        fontSize: font,
        color: color,
        position: Vector2(Config.p1PopupWidth / 2, y),
        anchor: Anchor.topCenter,
      ),
    );
  }

  @override
  Future<void> buildCard(PositionComponent card) async {
    final w = Config.p1PopupWidth;
    cardHeight = reward ? 370 : 282;
    card.add(
      RectangleComponent(
        size: Vector2(w, 118),
        paint: Paint()..color = Config.menuPink,
      ),
    );
    card.add(
      StreakFlame(
        side: 40,
        position: Vector2(w / 2 - 46, 22),
        lit: reward || state.flewToday(today),
        still: game.reduceMotion,
      ),
    );
    card.add(
      MenuText(
        '${state.streakDays}',
        fontSize: 54,
        color: Config.menuSoft,
        position: Vector2(w / 2 + 6, 20),
      ),
    );
    label(card, 'DAY STREAK', 86, 12, color: Config.menuSoft);
    card.add(
      closeBox(Sprite(await game.images.load('menu/close.png')), onDismiss),
    );
    final track = state.trackDay;
    final image = await CoinIcon.load(game.images);
    for (var i = 1; i <= 7; i++) {
      final x = 16.0 + (i - 1) * 36;
      final current = i == track;
      final tile = RectangleComponent(
        position: Vector2(x, 132),
        size: Vector2(32, 54),
        paint: Paint()
          ..color = current
              ? const Color(0xFFFFFFFF)
              : i < track
              ? Config.menuSoft
              : const Color(0xFFE4E4E4),
      );
      card.add(tile);
      if (current) {
        tile.add(
          RectangleComponent(
            size: tile.size.clone(),
            paint: Paint()
              ..color = Config.menuPink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          ),
        );
      }
      tile.add(
        MenuText(
          '$i',
          fontSize: 10,
          color: current ? Config.menuPink : Config.menuPlum,
          position: Vector2(16, 4),
          anchor: Anchor.topCenter,
        ),
      );
      final r = DayStreak.rewardForDay(
        i,
        canReceiveFeather: true,
        canReceivePiece: true,
      );
      tile.add(_RewardIcon(r, image, side: 19, position: Vector2(16, 28)));
      final value =
          r.item == StreakRewardItem.bigHoops ||
              r.item == StreakRewardItem.shield
          ? 'FREE'
          : r.item == StreakRewardItem.feather
          ? '+60'
          : '${r.coins}';
      tile.add(
        MenuText(
          value,
          fontSize: 9,
          color: Config.menuPlum,
          position: Vector2(16, 41),
          anchor: Anchor.topCenter,
        ),
      );
      if (i < track || current && state.streakPaidDay == today) {
        tile.add(
          MenuIcon(
            Sprite(await game.images.load('menu/check.png')),
            size: Vector2.all(10),
            position: Vector2(24, -3),
          ),
        );
      }
    }
    if (reward) {
      label(card, 'DAY $track REWARD', 200, 10, color: const Color(0xFF8A8A8A));
      final r = game.previewStreakReward;
      final text = switch (r.item) {
        StreakRewardItem.bigHoops => 'FREE BIG HOOPS',
        StreakRewardItem.shield => 'FREE SHIELD',
        StreakRewardItem.feather => '+${r.coins}',
        StreakRewardItem.piece => '+${r.coins}',
        null => '+${r.coins}',
      };
      final rewardRow = PositionComponent(
        position: Vector2(0, 220),
        size: Vector2(w, 48),
      );
      final iconBox = PositionComponent(
        size: Vector2(32, 40),
        children: [_RewardIcon(r, image, side: 28, position: Vector2(16, 20))],
      );
      final words = MenuText(
        text,
        fontSize: r.item == null ? 30 : 20,
        color: Config.menuPlum,
      );
      card.add(rewardRow);
      layoutRow(rewardRow, [
        iconBox,
        words,
        if (r.item == StreakRewardItem.feather ||
            r.item == StreakRewardItem.piece)
          PositionComponent(
            size: Vector2(24, 40),
            children: [
              _RewardIcon(
                const StreakReward(),
                image,
                side: 24,
                position: Vector2(12, 20),
              ),
            ],
          ),
      ], gap: 8);
      label(
        card,
        'One run a day keeps the flame going.',
        278,
        11,
        color: const Color(0xFF9A4D78),
      );
      collectButton = MenuButton(
        color: Config.menuGold,
        position: Vector2(16, 304),
        size: Vector2(w - 32, 50),
        isActive: isActive,
        onPressed: () =>
            onCollect(Rect.fromLTWH(card.x + 16, card.y + 304, w - 32, 50)),
        children: [
          MenuText(
            'COLLECT',
            fontSize: 24,
            color: Config.menuPlum,
            position: Vector2((w - 32) / 2, 25),
            anchor: Anchor.center,
          ),
        ],
      );
      card.add(collectButton!);
    } else {
      label(
        card,
        state.flewToday(today)
            ? 'Today is done. See you tomorrow!'
            : 'Fly 1 run today to reach day ${state.streakDays + 1}.',
        206,
        12,
      );
      label(
        card,
        state.flewToday(today) ? 'NEXT REWARD TOMORROW' : 'ENDS AT MIDNIGHT',
        246,
        10,
        color: const Color(0xFF8A8A8A),
      );
    }
  }
}

/// Shared reward art is also used for the free-start fetch flight.
void paintStreakPowerup(Canvas canvas, StreakRewardItem item, double side) {
  if (item == StreakRewardItem.shield) {
    LifeIcons.paintShield(canvas, Offset.zero, side);
  } else {
    canvas.save();
    canvas.scale(side / 48);
    RingPainter.paintBoth(
      canvas,
      centre: Offset.zero,
      opening: 30,
      colors: RingColors.gold,
    );
    canvas.restore();
  }
}

class _RewardIcon extends PositionComponent {
  _RewardIcon(this.reward, this.coin, {required this.side, super.position});
  final StreakReward reward;
  final Image coin;
  final double side;
  @override
  void render(Canvas canvas) {
    final item = reward.item;
    if (item == null) {
      CoinIcon.paint(canvas, coin, Offset.zero, side);
    } else if (item == StreakRewardItem.piece) {
      canvas.save();
      canvas.scale(side / 40);
      PuzzleArt.paintPieceCentred(canvas, 0, PuzzleConfig.themeFor(0));
      canvas.restore();
    } else if (item == StreakRewardItem.feather) {
      FeatherArt.paintAt(canvas, Offset.zero, side / 40, 0);
    } else {
      paintStreakPowerup(canvas, item, side);
    }
  }
}

/// A short white landing flash over the existing slot button.
class StreakSlotLanding extends PositionComponent {
  StreakSlotLanding() : super(priority: 30);
  double _time = 0;
  final _paint = Paint();
  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_time >= .18) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final slot = parent;
    if (slot is! PositionComponent) return;
    canvas.drawRect(
      slot.size.toRect(),
      _paint
        ..color = Color.fromRGBO(
          255,
          255,
          255,
          .65 * (1 - _time / .18).clamp(0, 1),
        ),
    );
  }
}
