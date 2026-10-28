import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../progression/star_road.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';
import '../ui/mystery_box.dart';
import 'star_road_card.dart';

/// Track geometry uses the same coordinates at both supported phone heights.
class StarRoadLayout {
  static const header = Rect.fromLTWH(14, 140, 292, 84);
  static const listTop = 252.0;
  static double rowTop(int tier) {
    var y = listTop + 10;
    for (var i = 1; i < tier; i++) {
      y += starRoadReward(i).kind == StarRoadRewardKind.coins ? 68 : 84;
    }
    return y;
  }

  static Rect viewport(double height) => Rect.fromLTRB(0, listTop, 320, height);
}

/// The road is driven by persisted state; the owner of the screen supplies the
/// durable claim operation and replaces it when the state changes.
class StarRoadScreen extends MenuScreen {
  StarRoadScreen({
    required this.road,
    required this.daysLeft,
    required this.onClaim,
    required super.onBack,
  }) : super(title: 'STAR ROAD');

  final StarRoad road;
  final int daysLeft;
  final Future<bool> Function(int tier) onClaim;
  final Set<int> _claimedNow = {};
  bool _claiming = false;

  @override
  Rect scrollViewportFor(double viewHeight) =>
      StarRoadLayout.viewport(viewHeight);

  @override
  Future<void> buildContent() async {
    final header = PositionComponent(
      position: Vector2(14, 140),
      size: Vector2(292, 84),
    );
    header.add(
      RectangleComponent(
        size: header.size.clone(),
        paint: Paint()..color = Config.menuSoft,
      ),
    );
    header.add(
      MenuText(
        '★ ${road.tier}',
        fontSize: 23,
        color: Config.menuPink,
        position: Vector2(12, 27),
      ),
    );
    header.add(
      MenuText(
        'SEASON ${road.season} · $daysLeft DAYS LEFT',
        fontSize: 10,
        color: Config.menuPink,
        position: Vector2(84, 6),
      ),
    );
    header.add(
      MenuText(
        starRoadSeasonName(road.season < 1 ? 1 : road.season),
        fontSize: 16,
        color: Config.menuPlum,
        position: Vector2(84, 22),
      ),
    );
    header.add(
      MenuText(
        road.tier == 25
            ? 'ALL TIERS REACHED'
            : '${road.starsIntoTier} / 8 STARS TO TIER ${road.tier + 1}',
        fontSize: 10,
        color: Config.menuPlum,
        position: Vector2(84, 49),
      ),
    );
    header.add(
      RectangleComponent(
        position: Vector2(84, 66),
        size: Vector2(196, 10),
        paint: Paint()..color = const Color(0xFFE5E5E5),
      ),
    );
    header.add(
      RectangleComponent(
        position: Vector2(84, 66),
        size: Vector2(196 * (road.tier == 25 ? 1 : road.starsIntoTier / 8), 10),
        paint: Paint()..color = Config.menuPink,
      ),
    );
    add(header);
    for (var tier = 1; tier <= starRoadTierCount; tier++) {
      final reward = starRoadReward(tier);
      final item = reward.kind != StarRoadRewardKind.coins;
      final y = StarRoadLayout.rowTop(tier);
      final reached = tier <= road.tier;
      final claimed = road.claimed.contains(tier) || _claimedNow.contains(tier);
      final row = PositionComponent(
        position: Vector2(14, y),
        size: Vector2(292, item ? 78 : 62),
      );
      row.add(
        RectangleComponent(
          position: Vector2(50, 0),
          size: Vector2(242, row.height),
          paint: Paint()
            ..color = reached && !claimed
                ? const Color(0xFFFFF3D6)
                : Config.menuSoft,
        ),
      );
      row.add(
        MenuText(
          '$tier',
          fontSize: 15,
          color: reached ? Config.menuPink : Config.menuPlum,
          position: Vector2(20, row.height / 2),
          anchor: Anchor.center,
        ),
      );
      final rarity = switch (reward.kind) {
        StarRoadRewardKind.rare => Rarity.rare,
        StarRoadRewardKind.epic => Rarity.epic,
        StarRoadRewardKind.legendary => Rarity.legendary,
        _ => null,
      };
      if (rarity != null) {
        row.add(
          MysteryBoxComponent(
            look: MysteryBoxLook.colours(
              rarity.color,
              Color.lerp(rarity.color, const Color(0xFF000000), .3)!,
              label: null,
            ),
            boxSize: 56,
            position: Vector2(84, row.height / 2),
          ),
        );
        row.add(
          MenuText(
            'MYSTERY',
            fontSize: 6,
            color: const Color(0xFFFFFFFF),
            position: Vector2(84, row.height / 2 + 7),
            anchor: Anchor.center,
          ),
        );
      }
      row.add(
        MenuText(
          starRoadRewardLabel(reward),
          fontSize: 11,
          color: Config.menuPlum,
          position: Vector2(item ? 122 : 114, 14),
        ),
      );
      row.add(
        MenuText(
          '★ ${tier * 8}',
          fontSize: 10,
          color: Config.menuPlum,
          position: Vector2(item ? 122 : 114, 34),
        ),
      );
      if (reached && !claimed) {
        row.add(
          MenuButton(
            position: Vector2(226, row.height / 2 - 14),
            size: Vector2(60, 28),
            color: Config.menuPink,
            onPressed: () async {
              if (_claiming) return;
              _claiming = true;
              try {
                if (await onClaim(tier)) {
                  _claimedNow.add(tier);
                  for (final button
                      in row.children.whereType<MenuButton>().toList()) {
                    button.removeFromParent();
                  }
                  row.add(
                    MenuText(
                      'CLAIMED',
                      fontSize: 9,
                      color: Config.menuPlum,
                      position: Vector2(225, row.height / 2),
                      anchor: Anchor.centerLeft,
                    ),
                  );
                }
              } finally {
                _claiming = false;
              }
            },
            isActive: () => isActive() && !_claiming,
            children: [
              MenuText(
                'CLAIM',
                fontSize: 10,
                color: const Color(0xFFFFFFFF),
                position: Vector2(30, 14),
                anchor: Anchor.center,
              ),
            ],
          ),
        );
      } else if (claimed) {
        row.add(
          MenuText(
            'CLAIMED',
            fontSize: 9,
            color: Config.menuPlum,
            position: Vector2(225, row.height / 2),
            anchor: Anchor.centerLeft,
          ),
        );
      }
      scroll.content.add(row);
    }
    scroll.contentBottom = StarRoadLayout.rowTop(25) + 118;
    final first = road.claimable.isNotEmpty
        ? road.claimable.first
        : (road.tier + 1).clamp(1, 25);
    scroll.scrollTo(StarRoadLayout.rowTop(first) - 70, animate: false);
  }
}
