import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../game/sound.dart';
import '../../leaderboard/gift_apply.dart';
import '../../leaderboard/lb_models.dart';
import '../../run/screens/level_reveal_sheet.dart';
import '../../run/screens/results_screen.dart';
import '../../skins/catalog.dart';
import '../home/menu_primitives.dart';
import '../ui/confetti.dart';
import '../ui/mystery_box.dart';
import '../ui/p1_popup.dart';
import 'board_row.dart';
import 'podium.dart';

MenuText _text(
  String value,
  double y, {
  double font = 12,
  Color color = Config.menuPink,
}) => MenuText(
  value,
  fontSize: font,
  color: color,
  position: Vector2(Config.p1PopupWidth / 2, y),
  anchor: Anchor.topCenter,
);

MenuButton _button(
  String text,
  double y,
  void Function() pressed,
  bool Function() active, {
  double x = 40,
  double width = 200,
}) => MenuButton(
  position: Vector2(x, y),
  size: Vector2(width, 38),
  color: Config.menuPink,
  onPressed: pressed,
  isActive: active,
  children: [
    MenuText(
      text,
      fontSize: 14,
      color: const Color(0xffffffff),
      position: Vector2(width / 2, 19),
      anchor: Anchor.center,
    ),
  ],
);

/// The settled podium and the invitation to collect one box.
class GiftPopup extends P1Popup {
  GiftPopup({
    required this.gift,
    required this.onCollect,
    required super.onDismiss,
  });
  final LbGift gift;
  final void Function() onCollect;

  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 450;
    card.add(_text('BOARD ENDED', 10, font: 19));
    final hours = gift.createdAt == null
        ? 0
        : DateTime.now().difference(gift.createdAt!).inHours.clamp(0, 9999);
    card.add(
      _text(
        gift.playerCount > 0
            ? 'TODAY · ${gift.playerCount} PLAYERS     ENDED $hours H AGO'
            : 'TODAY     ENDED $hours H AGO',
        38,
        font: 9,
      ),
    );
    final rows = [
      for (final row in gift.finalBoard)
        if (row.rank == gift.boardRank)
          LbBoardRow(
            rid: row.rid,
            rank: row.rank,
            name: game.myVersusName,
            look: game.menu.items.look,
            points: row.points,
            lastAt: row.lastAt,
          )
        else
          row,
    ];
    if (!rows.any((row) => row.rank == gift.boardRank)) {
      rows.add(
        LbBoardRow(
          rid: 'own',
          rank: gift.boardRank,
          name: game.myVersusName,
          look: game.menu.items.look,
          points: 0,
        ),
      );
    }
    final own = rows.firstWhere((row) => row.rank == gift.boardRank);
    card.add(
      BoardPodium(rows, today: true, ownId: own.rid)
        ..position = Vector2(6, 54)
        ..scale.setAll(.83),
    );
    for (final row in gift.finalBoard.where(
      (row) => row.rank == 4 || row.rank == 5,
    )) {
      card.add(
        BoardRow(
          row,
          own: false,
          position: Vector2(18, 208 + (row.rank - 4) * 39),
        )..scale.setAll(.83),
      );
    }
    card.add(
      RectangleComponent(
        position: Vector2(14, 300),
        size: Vector2(Config.p1PopupWidth - 28, 62),
        paint: Paint()..color = const Color(0xffffd9ee),
      ),
    );
    final ordinal = ['1st', '2nd', '3rd'][gift.boardRank - 1];
    card.add(
      _text(
        gift.playerCount > 0
            ? 'You finished $ordinal of ${gift.playerCount}!'
            : 'You finished $ordinal!',
        310,
        font: 14,
      ),
    );
    card.add(_text('Your ${gift.tier} box is waiting.', 335, font: 12));
    card.add(_button('GO TO COLLECT', 386, onCollect, isActive));
    final close = Sprite(await game.images.load('menu/close.png'));
    card.add(closeBox(close, onDismiss));
  }
}

/// Opens only after a durable claim. Its owner keeps the modal until completion.
class GiftOpeningPopup extends P1Popup {
  GiftOpeningPopup({
    required this.gift,
    required this.claim,
    required this.finish,
  }) : super(onDismiss: () {});
  final LbGift gift;
  final Future<AppliedLbGift?> Function() claim;
  final void Function(AppliedLbGift, Rect) finish;
  late final MysteryBoxComponent box;
  late final PositionComponent content;
  bool busy = false, revealed = false, lidStarted = false;
  AppliedLbGift? prize;
  double elapsed = 0, tickAt = 0, arrival = 0, rise = 0;
  Rect get claimRect => Rect.fromLTWH(
    card.absolutePosition.x + 40,
    card.absolutePosition.y + 275,
    200,
    38,
  );

  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 340;
    final tier = MysteryBoxTier.values.firstWhere(
      (v) => v.name == gift.tier,
      orElse: () => MysteryBoxTier.gold,
    );
    card.add(
      _text(
        '${gift.tier.toUpperCase()} BOX · ${['1ST', '2ND', '3RD'][gift.boardRank - 1]} PLACE',
        15,
        font: 14,
      ),
    );
    card.add(_GiftRays(() => !game.reduceMotion));
    box = MysteryBoxComponent(
      look: MysteryBoxLook.colours(
        tier.main,
        tier.dark,
        label: null,
        ribbon: Config.menuPink,
      ),
      boxSize: 100,
      position: Vector2(Config.p1PopupWidth / 2, 55),
    );
    card.add(box);
    content = PositionComponent();
    card.add(content);
    content.add(
      _button('TAP TO OPEN', 275, () => unawaited(open()), () => !busy),
    );
  }

  Future<void> open() async {
    if (busy) return;
    busy = true;
    final result = await claim();
    if (!isMounted || !active) return;
    if (result == null) {
      busy = false;
      return;
    }
    prize = result;
    game.sound.play(Sfx.skTick);
  }

  @override
  void update(double dt) {
    super.update(dt);
    arrival = (arrival + dt / .4).clamp(0.0, 1.0);
    box.y = 55 + 95 * (1 - (1 - arrival) * (1 - arrival));
    if (revealed) {
      rise = (rise + dt / .35).clamp(0.0, 1.0);
      content.y = 24 * (1 - rise);
      return;
    }
    if (prize == null) return;
    elapsed += dt;
    if (elapsed < .75) {
      box.lid = MysteryBoxLid.shake(
        (elapsed / .75).clamp(0, 1),
        revealTime: elapsed,
      );
      if (elapsed >= tickAt + .2) {
        tickAt = elapsed;
        game.sound.play(Sfx.skTick);
      }
      return;
    }
    if (!lidStarted) {
      lidStarted = true;
      game.sound.play(Sfx.pairBoxOpen);
      game.sound.play(switch (gift.tier) {
        'gold' => Sfx.bnPrizeBig,
        'silver' => Sfx.bnPrizeM,
        _ => Sfx.bnPrizeS,
      });
    }
    box.lid = MysteryBoxLid.off(((elapsed - .75) / .5).clamp(0, 1));
    if (elapsed < 1.25) return;
    revealed = true;
    content.y = 24;
    if (!game.reduceMotion) {
      card.add(
        ConfettiBurst.burst(
          origin: const Offset(140, 150),
          count: 20,
          stars: true,
        ),
      );
    }
    content.removeAll(content.children.toList());
    final result = prize!;
    if (result.kind == 'item') {
      finish(result, claimRect);
      return;
    }
    final title = switch (result.kind) {
      'feather' => 'Golden feather',
      'piece' => 'Puzzle piece',
      _ => '+${result.coins} / COINS',
    };
    final sub = switch (result.kind) {
      'feather' => 'ADDED TO YOUR FEATHERS',
      'piece' => 'ADDED TO YOUR PUZZLE ALBUM',
      _ => switch (gift.tier) {
        'silver' => 'SILVER BOX · 50–200 COINS',
        'bronze' => 'BRONZE BOX · 25–100 COINS',
        _ => 'GOLD BOX · 100–300 COINS',
      },
    };
    content.add(_text(title, 205, font: 18));
    content.add(_text(sub, 232, font: 10, color: Config.menuPlum));
    content.add(
      _button('COLLECT', 275, () {
        game.sound.play(Sfx.col4Coins);
        finish(result, claimRect);
      }, isActive),
    );
  }
}

class _GiftRays extends PositionComponent {
  _GiftRays(this.motion) : super(size: Vector2(Config.p1PopupWidth, 240));
  final bool Function() motion;
  double time = 0;
  @override
  void update(double dt) {
    super.update(dt);
    if (motion()) time += dt;
  }

  @override
  void render(Canvas canvas) => ResultsScreen.paintCardStickerRays(
    canvas,
    const Offset(140, 150),
    120,
    time,
  );
}

/// The J4 sheet owns the item art and animation; this payout was already
/// journalled by GiftApply, so it must not pay an unrelated level reward.
class GiftItemReveal extends LevelRevealSheet {
  GiftItemReveal({required SkinItem super.item, required super.onFinished});
  @override
  Future<void> choose(bool equip) async {
    if (!revealed || choosing) return;
    choosing = true;
    if (equip && item != null) {
      await game.menu.items.equip(item!.layer, item!.id);
    }
    onFinished(equip);
    removeFromParent();
  }
}
