
import 'package:flame/components.dart';

// region P26-G6eA
import '../../game/flappy_game.dart';
import 'star_road_art.dart';
// endregion
import '../../game/config.dart';
import '../../game/sound.dart';
import '../../progression/star_road.dart';
import '../home/menu_primitives.dart';

/// Presentation shared by the road and its missions-panel entry.
String starRoadRewardLabel(StarRoadReward reward) => switch (reward.kind) {
  StarRoadRewardKind.coins => '${reward.coins} COINS',
  StarRoadRewardKind.feather => 'FEATHER',
  StarRoadRewardKind.piece => 'PUZZLE PIECE',
  StarRoadRewardKind.rare ||
  StarRoadRewardKind.epic ||
  StarRoadRewardKind.legendary => 'MYSTERY',
};

Sfx starRoadClaimSound(StarRoadReward reward) => switch (reward.kind) {
  StarRoadRewardKind.legendary => Sfx.lvUpBig,
  StarRoadRewardKind.rare || StarRoadRewardKind.epic => Sfx.lvClaim,
  _ => Sfx.bnCoin,
};

/// The missions-panel entry. The caller measures the entire panel and selects
/// [compact] when its expanded content would overflow the available height.
class StarRoadCard extends MenuButton {
  StarRoadCard({
    required this.road,
    required this.daysLeft,
    required this.compact,
    required super.onPressed,
    super.isActive,
  }) : super(size: Vector2(256, compact ? 44 : 88), color: Config.menuSoft);

  // region P26-G6eA
  /// The panel host removes itself in [leavePanel] and restores on back.
  factory StarRoadCard.open({
    required FlappySpikesGame game,
    required StarRoad road,
    required int daysLeft,
    required bool compact,
    required void Function() leavePanel,
    required void Function() returnToPanel,
    bool Function()? isActive,
  }) => StarRoadCard(
    road: road,
    daysLeft: daysLeft,
    compact: compact,
    isActive: isActive,
    onPressed: () {
      if (game.openStarRoad(daysLeft: daysLeft, onBack: returnToPanel)) {
        leavePanel();
      }
    },
  );
  // endregion

  final StarRoad road;
  final int daysLeft;
  final bool compact;

  String get progressLabel => road.tier == starRoadTierCount
      ? 'ALL TIERS REACHED'
      : '${road.starsIntoTier} / 8 STARS TO TIER ${road.tier + 1}';
  String get compactLabel => road.claimable.isNotEmpty
      ? 'TIER ${road.tier} · ${road.claimable.length} TO CLAIM'
      : 'TIER ${road.tier} · ${road.starsIntoTier} / 8';

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // region P26-G6eA
    add(StarRoadStar(side: 12, position: Vector2(10, compact ? 15 : 8)));
    add(MenuText('STAR ROAD', fontSize: 11, color: Config.menuPlum,
      position: Vector2(25, compact ? 15 : 8)));
    // endregion
    add(
      MenuText(
        compact ? compactLabel : '$daysLeft DAYS LEFT',
        fontSize: compact ? 9 : 10,
        color: Config.menuPlum,
        position: Vector2(compact ? 110 : 10, compact ? 16 : 31),
      ),
    );
    if (!compact) {
      add(
        MenuText(
          progressLabel,
          fontSize: 10,
          color: Config.menuPlum,
          position: Vector2(10, 63),
        ),
      );
    }
    add(
      MenuText(
        '›',
        fontSize: 20,
        color: Config.menuPink,
        position: Vector2(242, compact ? 11 : 30),
      ),
    );
  }
}

/// The available panel height is measured before deciding which card to use.
bool starRoadCardShouldFold({
  required double otherContentHeight,
  required double availableHeight,
  double expandedHeight = 88,
}) => otherContentHeight + expandedHeight > availableHeight;
