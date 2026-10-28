import 'dart:ui';
import 'package:flame/components.dart';
import '../../../game/config.dart';
import '../../../progression/puzzle_album.dart';
import '../../../run/config/puzzle_config.dart';
import '../../../run/pickups/puzzle_piece_pickup.dart';
import '../../home/menu_primitives.dart';
import '../../ui/mystery_box.dart';
import '../../skins/item_art.dart';
import '../../skins/item_tile.dart';
import '../../../skins/catalog.dart';
import '../levels_screen.dart';
import 'levels_tabs.dart';

class AlbumTab {
  static void install(LevelsScreen screen) {
    final album = PuzzleAlbum(screen.game.storage);
    screen.installTabContent(
      LevelsTab.album,
      header: AlbumHeader(album, screen),
      rows: [for (var i = 0; i < 8; i++) _AlbumCard(album, i)],
      contentBottom: 264 + 4 * 150.0 + 12,
    );
  }
}

class AlbumHeader extends PositionComponent {
  AlbumHeader(this.album, this.screen);
  final PuzzleAlbum album;
  final LevelsScreen screen;
  @override
  Future<void> onLoad() async {
    final won = allItems
        .where((i) => i.key == album.storage.albumRewardItem)
        .firstOrNull;
    if (album.storage.albumRewardClaimed && won != null) {
      add(
        ItemTile(
          item: won,
          rect: const Rect.fromLTWH(5, 2, 74, 78),
          state: () => const ItemTileState(
            owned: true,
            equipped: false,
            tryingOn: false,
            isNew: false,
          ),
          onPressed: () {},
          art: ItemArtCache(),
          cardColor: () => const Color(0xFFE8E8E8),
          tint: () => Config.menuPink,
          reduceMotion: () => true,
          rewardTile: true,
        ),
      );
    }
    if (album.storage.albumRewardClaimed && won == null) {
      add(
        MenuIcon(
          screen.sprite('menu/coin.png'),
          size: Vector2.all(48),
          position: Vector2(18, 18),
        ),
      );
    }
    addAll([
      MenuText(
        album.completed == 8 ? 'ALBUM COMPLETE' : 'ALL 8 PICTURES',
        fontSize: 16,
        color: const Color(0xFF828282),
        position: Vector2(94, 10),
      ),
      MenuText(
        album.storage.albumRewardClaimed
            ? (won == null
                  ? 'WON: COINS'
                  : 'WON: ${won.name.toUpperCase()} · ${won.rarity!.label} ${won.layer.key.toUpperCase()}')
            : 'REWARD · 1 RANDOM EPIC ITEM',
        fontSize: 8,
        color: album.storage.albumRewardClaimed
            ? (won?.rarity?.color ?? Config.menuGold)
            : const Color(0xFF828282),
        position: Vector2(94, 36),
      ),
      MenuText(
        '${album.completed} / 8 PICTURES${album.completed == 8 ? ' ✓' : ''}',
        fontSize: 8,
        color: Config.menuPlum,
        anchor: Anchor.center,
        position: Vector2(188, 65),
      ),
    ]);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFFE8E8E8));
    canvas.drawRect(
      const Rect.fromLTWH(94, 57, 188, 16),
      Paint()..color = Config.menuSoft,
    );
    canvas.drawRect(
      Rect.fromLTWH(94, 57, 188 * album.completed / 8, 16),
      Paint()..color = album.completed == 8 ? Config.menuGold : Config.menuPink,
    );
    if (album.storage.albumRewardClaimed) {
      return;
    }
    canvas.save();
    canvas.translate(42, 38);
    MysteryBox.paint(
      canvas,
      MysteryBoxLook.colours(const Color(0xFF9B30D9), const Color(0xFF6F219B)),
      size: 48,
    );
    canvas.restore();
  }
}

class _AlbumCard extends PositionComponent {
  _AlbumCard(this.album, this.index)
    : super(
        position: Vector2(14 + (index % 2) * 150.0, 264 + (index ~/ 2) * 150.0),
        size: Vector2(142, 140),
      );
  final PuzzleAlbum album;
  final int index;
  @override
  Future<void> onLoad() async {
    final count = album.storage.albumCounts[index];
    final now = index == album.current;
    addAll([
      MenuText(
        '${index + 1} · ${PuzzleConfig.themes[index].name.toUpperCase()}',
        fontSize: 11,
        color: const Color(0xFF828282),
        anchor: Anchor.topCenter,
        position: Vector2(71, 100),
      ),
      MenuText(
        now
            ? '${count > 0 ? '✓ AGAIN ' : ''}${album.held} / 4'
            : count > 0
            ? '✓ COMPLETE'
            : '0 / 4',
        fontSize: 9,
        color: Config.menuPlum,
        anchor: Anchor.topCenter,
        position: Vector2(71, 119),
      ),
      if (now) MenuTag('NOW', fontSize: 8, position: Vector2(5, 3)),
      if (count > 1)
        MenuText(
          '×$count',
          fontSize: 12,
          color: Config.menuPlum,
          position: Vector2(112, 4),
        ),
    ]);
  }

  @override
  void render(Canvas canvas) {
    final count = album.storage.albumCounts[index];
    final now = index == album.current;
    canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFFE8E8E8));
    canvas.save();
    canvas.translate(71, 52);
    canvas.scale(1.35);
    for (var k = 0; k < 4; k++) {
      final have =
          count > 0 || (now && album.storage.puzzlePieces & (1 << k) != 0);
      PuzzleArt.paintPiece(
        canvas,
        k,
        PuzzleConfig.themes[index],
        ghost: have ? null : const Color(0xFFBDBDBD),
        seam: const Color(0xFF999999),
      );
    }
    if (count > 0) {
      canvas.drawRect(
        const Rect.fromLTWH(-25, -25, 50, 50),
        Paint()
          ..color = Config.menuGold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }
}
