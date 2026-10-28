import 'dart:ui';
import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../progression/star_road.dart';
import '../../skins/look.dart';
import '../../run/effects/coin_icon.dart';
import '../../run/pickups/feather_pickup.dart';
import '../../run/pickups/puzzle_piece_pickup.dart';
import '../../run/config/puzzle_config.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';
import '../ui/mystery_box.dart';
import '../ui/live_effects.dart';
import '../skins/item_tile.dart';
import '../skins/item_art.dart';
import '../../skins/catalog.dart';
import 'star_road_art.dart';
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
    this.itemKeys,
    required super.onBack,
  }) : super(title: 'STAR ROAD');

  final StarRoad road;
  final int daysLeft;
  final Future<bool> Function(int tier) onClaim;
  final Map<int, String> Function()? itemKeys;
  final ItemArtCache _art = ItemArtCache();
  final Set<int> _claimedNow = {};
  bool _claiming = false;
  final Map<int, PositionComponent> rows = {};
  // region P26-G6eB
  MenuTag? _daysChip;
  String _daysText() {
    if (daysLeft != 1) return '$daysLeft DAYS LEFT';
    final now = game.storage.now().toUtc();
    final remaining = DateTime.utc(now.year, now.month, now.day + 1).difference(now);
    return 'ENDS IN ${remaining.inHours} H ${remaining.inMinutes % 60} M';
  }

  @override
  void update(double dt) {
    super.update(dt);
    final labels = _daysChip?.children.whereType<MenuText>();
    if (labels != null && labels.isNotEmpty) labels.first.text = _daysText();
  }
  // endregion

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
    header.add(StarRoadStar(side: 56, position: Vector2(14, 14)));
    header.add(
      MenuText(
        '${road.tier}',
        fontSize: 17,
        color: Config.menuPlum,
        position: Vector2(42, 42),
        anchor: Anchor.center,
      ),
    );
    // region P26-G6eB
    header.add(
      MenuText(
        'SEASON ${road.season}',
        fontSize: 10,
        color: Config.menuPink,
        position: Vector2(84, 6),
      ),
    );
    _daysChip = MenuTag(
      _daysText(), fontSize: 8, fillColor: starRoadDaysChipColor(daysLeft),
      textColor: daysLeft == 1 ? Config.menuPlum : Config.menuSoft, position: Vector2(150, 5),
    );
    header.add(_daysChip!);
    // endregion
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
        'TIER ${road.tier} OF 25 ·',
        fontSize: 10,
        color: Config.menuPlum,
        position: Vector2(84, 45),
      ),
    );
    header.add(StarRoadStar(side: 10, position: Vector2(166, 45)));
    header.add(
      MenuText(
        '${road.xp}',
        fontSize: 10,
        color: Config.menuPlum,
        position: Vector2(179, 45),
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
    header.add(
      MenuText(
        road.tier == 25
            ? 'ROAD COMPLETE'
            : '${8 - road.starsIntoTier} STARS TO TIER ${road.tier + 1}',
        fontSize: 9,
        color: Config.menuPlum,
        position: Vector2(182, 71),
        anchor: Anchor.center,
      ),
    );
    add(header);
    final coin = await CoinIcon.load(game.images);
    final lock = Sprite(await game.images.load('menu/lock.png'));
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
      rows[tier] = row;
      row.add(
        RectangleComponent(
          position: Vector2(19, 0),
          size: Vector2(8, row.height + 6),
          paint: Paint()
            ..color = reached ? Config.menuPink : const Color(0xFFD9D9D9),
        ),
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
      final node = StarRoadTierNode(
        tier: tier,
        state: claimed
            ? StarRoadNodeState.claimed
            : reached
            ? StarRoadNodeState.claimable
            : tier == road.tier + 1
            ? StarRoadNodeState.next
            : StarRoadNodeState.locked,
        position: Vector2(5, row.height / 2 - 18),
      );
      row.add(node);
      if (tier == road.tier + 1) {
        row.add(
          MenuTag(
            'NEXT',
            fontSize: 9,
            fillColor: Config.menuSoft,
            textColor: Config.menuPlum,
            position: Vector2(56, -7),
            priority: 2,
          ),
        );
      }
      final rarity = switch (reward.kind) {
        StarRoadRewardKind.rare => Rarity.rare,
        StarRoadRewardKind.epic => Rarity.epic,
        StarRoadRewardKind.legendary => Rarity.legendary,
        _ => null,
      };
      final dark = switch (rarity) {
        Rarity.rare => const Color(0xFF0E6FA6),
        Rarity.epic => const Color(0xFF6A1A9C),
        Rarity.legendary => const Color(0xFFC98A00),
        _ => Config.menuPlum,
      };
      if (rarity == null) {
        row.add(
          RectangleComponent(
            position: Vector2(56, 6),
            size: Vector2.all(item ? 56 : 50),
            paint: Paint()..color = const Color(0xFFFFF8E6),
          ),
        );
        row.add(
          _RoadRewardArt(
            reward.kind,
            coin,
            position: Vector2(item ? 84 : 81, row.height / 2),
          ),
        );
      }
      final rewardVisual = PositionComponent();
      row.add(rewardVisual);
      void showReward() {
        rewardVisual.removeAll(rewardVisual.children);
        final key = claimed || _claimedNow.contains(tier)
            ? itemKeys?.call()[tier]
            : null;
        final won = allItems.where((i) => i.key == key).firstOrNull;
        if (rarity != null && won == null) {
          rewardVisual.add(
            MysteryBoxComponent(
              look: MysteryBoxLook.colours(rarity.color, dark, label: null),
              boxSize: 56,
              position: Vector2(84, row.height / 2),
            ),
          );
          rewardVisual.add(
            MenuText(
              'MYSTERY',
              fontSize: 8,
              color: const Color(0xFFFFFFFF),
              position: Vector2(84, row.height / 2 + 7),
              anchor: Anchor.center,
            ),
          );
        } else if (won != null) {
          rewardVisual.add(
            ItemTile(
              item: won,
              rect: Rect.fromLTWH(56, 9, 56, 56),
              state: () => const ItemTileState(
                owned: true,
                equipped: false,
                tryingOn: false,
                isNew: false,
              ),
              onPressed: () {},
              art: _art,
              cardColor: () => game.stageBackground,
              tint: () => Config.uiAccent,
              reduceMotion: () => game.reduceMotion,
              rewardTile: true,
            ),
          );
        }
        rewardVisual.add(
          MenuText(
            won?.name.toUpperCase() ?? starRoadRewardLabel(reward),
            fontSize: 11,
            // region P26-G6eB
            color: reached ? dark : const Color(0xFF999999),
            // endregion
            position: Vector2(item ? 122 : 114, 14),
          ),
        );
        // region P26-G6eB
        if (reward.kind == StarRoadRewardKind.feather ||
            reward.kind == StarRoadRewardKind.piece) {
          rewardVisual.add(
            MenuTag(
              reward.kind == StarRoadRewardKind.feather ? 'GOLDEN' : '1 OF 4',
              fontSize: 8,
              fillColor: Config.menuGold,
              textColor: Config.menuPlum,
              position: Vector2(122, 52),
            ),
          );
        }
        // endregion
        rewardVisual.add(
          StarRoadStar(side: 10, position: Vector2(item ? 122 : 114, 34)),
        );
        rewardVisual.add(
          MenuText(
            '${tier * 8}${won == null ? '' : ' · ${won.layer.key.toUpperCase()}'}',
            fontSize: 10,
            color: Config.menuPlum,
            position: Vector2(item ? 135 : 127, 34),
          ),
        );
      }

      showReward();
      if (reached && !claimed) {
        row.add(
          _ClaimButton(
            reduceMotion: () => game.reduceMotion,
            position: Vector2(216, row.height / 2 - 16),
            size: Vector2(70, 32),
            color: Config.menuPink,
            onPressed: () async {
              if (_claiming) return;
              _claiming = true;
              try {
                if (await onClaim(tier)) {
                  _claimedNow.add(tier);
                  node.removeFromParent();
                  row.add(
                    StarRoadTierNode(
                      tier: tier,
                      state: StarRoadNodeState.claimed,
                      position: Vector2(5, row.height / 2 - 18),
                    ),
                  );
                  showReward();
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
                position: Vector2(35, 16),
                anchor: Anchor.center,
              ),
            ],
          ),
        );
      } else if (!reached) {
        if (tier == road.tier + 1) {
          final bar = PositionComponent(
            position: Vector2(202, row.height / 2 - 7),
            size: Vector2(84, 14),
          );
          bar.add(
            RectangleComponent(
              size: bar.size.clone(),
              paint: Paint()..color = const Color(0xFFFCD9EE),
            ),
          );
          bar.add(
            RectangleComponent(
              size: Vector2(84 * road.starsIntoTier / 8, 14),
              paint: Paint()..color = Config.menuPink,
            ),
          );
          bar.add(
            MenuText(
              '${road.starsIntoTier} / 8',
              fontSize: 9,
              color: Config.menuPlum,
              position: Vector2(42, 7),
              anchor: Anchor.center,
            ),
          );
          row.add(bar);
        } else {
          row.add(
            MenuIcon(
              lock,
              size: Vector2.all(14),
              position: Vector2(250, row.height / 2),
              anchor: Anchor.center,
            ),
          );
        }
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
    scroll.content.add(
      MenuText(
        'SEASON ${road.season + 1} STARTS WHEN THIS ONE ENDS',
        fontSize: 9,
        color: Config.menuPlum,
        position: Vector2(160, StarRoadLayout.rowTop(25) + 96),
        anchor: Anchor.topCenter,
      ),
    );
    add(
      MenuText(
        // region P26-G6eB
        'STARS COME FROM DAILY MISSIONS · UP TO 11 A DAY',
        // endregion
        fontSize: 9,
        color: Config.menuPlum,
        position: Vector2(160, 230),
        anchor: Anchor.topCenter,
      ),
    );
    scroll.contentBottom = StarRoadLayout.rowTop(25) + 118;
    final first = road.claimable.isNotEmpty
        ? road.claimable.first
        : (road.tier + 1).clamp(1, 25);
    scroll.scrollTo(StarRoadLayout.rowTop(first) - 70, animate: false);
  }
}

/// Uses the existing run pickup and coin masters for the track tiles.
class _RoadRewardArt extends PositionComponent {
  _RoadRewardArt(this.kind, this.coin, {super.position});
  final StarRoadRewardKind kind;
  final Image coin;
  @override
  void render(Canvas canvas) {
    switch (kind) {
      case StarRoadRewardKind.coins:
        CoinIcon.paint(canvas, coin, Offset.zero, 32);
      case StarRoadRewardKind.feather:
        FeatherArt.paintAt(canvas, Offset.zero, .85, 0);
      case StarRoadRewardKind.piece:
        canvas.save();
        canvas.scale(.85);
        PuzzleArt.paintPieceCentred(canvas, 0, PuzzleConfig.themes.first);
        canvas.restore();
      default:
        break;
    }
  }
}

/// The shared pulse and shine decorate the claim button; the gold outline
/// follows the design's 1.4-second claim ring.
class _ClaimButton extends MenuButton {
  _ClaimButton({
    required this.reduceMotion,
    required super.position,
    required super.size,
    required super.color,
    required super.onPressed,
    required super.isActive,
    required super.children,
  }) {
    pulse = PulseEffect(
      this,
      amount: .02,
      glowColor: const Color(0x99FFB529),
      glowBlur: 4,
    );
    streak = LightStreak(this);
    decorator
      ..addLast(pulse)
      ..addLast(streak);
  }
  final bool Function() reduceMotion;
  late final PulseEffect pulse;
  late final LightStreak streak;
  double _time = 0;
  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    pulse.k = reduceMotion()
        ? 0
        : (1 - math.cos(_time * math.pi * 2 / 1.4)) / 2;
    if (reduceMotion()) {
      streak.progress = null;
    } else {
      streak.at(_time);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final alpha = reduceMotion()
        ? 1.0
        : (1 - math.cos(_time * math.pi * 2 / 1.4)) / 2;
    canvas.drawRect(
      size.toRect().inflate(4),
      Paint()
        ..color = const Color(0xFFFFB529).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
