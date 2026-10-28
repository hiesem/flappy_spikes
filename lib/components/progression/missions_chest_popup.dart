import 'dart:math' as math;
import 'dart:ui';
import 'package:flame/components.dart';
import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../progression/missions.dart';
import '../../run/config/puzzle_config.dart';
import '../../run/effects/twinkle.dart';
import '../../run/pickups/feather_pickup.dart';
import '../../run/pickups/puzzle_piece_pickup.dart';
import '../home/menu_primitives.dart';
import '../noads_celebration.dart';
import '../shop/pack_art.dart';
import '../ui/confetti.dart';
import '../ui/mystery_box.dart';
import '../ui/p1_popup.dart';

/// The Home-only mission chest. The game owns and persists its prize.
class MissionsChestPopup extends P1Popup {
  MissionsChestPopup({
    required this.reward,
    required this.piece,
    required super.onDismiss,
  });
  final MissionChestReward reward;
  final int piece;
  double elapsed = 0;
  bool _opened = false;
  late final MysteryBoxComponent box;
  late final _RayLayer _rays;
  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 346;
    _rays = _RayLayer();
    _rays.opacity = 0;
    card.add(_rays);
    box = MysteryBoxComponent(
      look: MysteryBoxLook.tier(MysteryBoxTier.gold),
      boxSize: 120,
      position: Vector2(140, 92),
    );
    card.add(box);
    card.add(
      _PrizeArt(
        reward: reward,
        piece: piece,
        popup: this,
        position: Vector2(140, 61),
      ),
    );
    card.add(
      MenuText(
        'ALL MISSIONS DONE!',
        fontSize: 20,
        color: Config.menuPink,
        position: Vector2(140, 163),
        anchor: Anchor.topCenter,
      ),
    );
    card.add(
      MenuText(
        'BONUS CHEST',
        fontSize: 10,
        color: const Color(0xFF8A8A8A),
        position: Vector2(140, 204),
        anchor: Anchor.topCenter,
      ),
    );
    card.add(
      MenuText(
        switch (reward.kind) {
          MissionChestKind.feather => 'GOLDEN FEATHER',
          MissionChestKind.piece => 'PUZZLE PIECE',
          MissionChestKind.coins => '+40 COINS',
        },
        fontSize: 19,
        color: Config.menuPlum,
        position: Vector2(140, 224),
        anchor: Anchor.topCenter,
      ),
    );
    card.add(
      MenuButton(
        position: Vector2(16, 280),
        size: Vector2(248, 50),
        color: Config.menuPink,
        onPressed: onDismiss,
        isActive: () => active && elapsed >= 1.5,
        children: [
          MenuText(
            'NICE!',
            fontSize: 24,
            color: Config.menuSoft,
            position: Vector2(124, 25),
            anchor: Anchor.center,
          ),
        ],
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    if (!isLoaded) return;
    box.lid = elapsed < 1.35
        ? (elapsed < .75
              ? const MysteryBoxLid.closed()
              : MysteryBoxLid.shake(
                  ((elapsed - .75) / .6).clamp(0, 1),
                  revealTime: elapsed,
                ))
        : MysteryBoxLid.off(((elapsed - 1.35) / .5).clamp(0, 1));
    _rays.opacity = ((elapsed - 1.35) / .4).clamp(0, 1);
    if (!_opened && elapsed >= 1.35) {
      _opened = true;
      game.sound.play(Sfx.pairBoxOpen);
      game.sound.play(Sfx.bnPrizeM);
      if (!game.reduceMotion) {
        card.add(
          ConfettiBurst.burst(
            origin: const Offset(140, 85),
            count: 30,
            speed: 120,
            stars: true,
          ),
        );
      }
    }
  }
}

class _PrizeArt extends PositionComponent {
  _PrizeArt({
    required this.reward,
    required this.piece,
    required this.popup,
    super.position,
  });
  final MissionChestReward reward;
  final int piece;
  final MissionsChestPopup popup;
  @override
  void render(Canvas canvas) {
    if (popup.elapsed < 1.5) return;
    final u = ((popup.elapsed - 1.5) / .45).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(0, 30 * (1 - u));
    canvas.scale(u);
    switch (reward.kind) {
      case MissionChestKind.feather:
        canvas.scale(1.4);
        FeatherArt.paint(canvas);
      case MissionChestKind.piece:
        canvas.scale(1.2);
        PuzzleArt.paintPieceCentred(
          canvas,
          piece,
          PuzzleConfig.themeFor(popup.game.storage.puzzleRound),
        );
      case MissionChestKind.coins:
        canvas.translate(-42, -24);
        canvas.scale(.7);
        PackArtPainter.paint(
          canvas,
          0,
          popup.elapsed,
          still: popup.game.reduceMotion,
        );
    }
    canvas.restore();
    if (!popup.game.reduceMotion && popup.elapsed < 2.2) {
      final (scale, rotation, alpha) = Twinkle.curve(
        ((popup.elapsed - 1.5) / .7).clamp(0, 1),
      );
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        Twinkle.paint(
          canvas,
          Offset(math.cos(a) * 43, math.sin(a) * 43),
          12 * scale,
          const Color(0xFFFFE082).withValues(alpha: alpha),
          rotation: rotation,
        );
      }
    }
  }
}

class _RayLayer extends PositionComponent
    with GroupOpacity, HasGameReference<FlappySpikesGame> {
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      NoAdsCelebrationRays(
        rayCenter: const Offset(140, 76),
        motion: () => !game.reduceMotion,
        size: Vector2(280, 156),
      ),
    );
  }
}
