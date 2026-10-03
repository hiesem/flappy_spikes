import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../menu/skin_catalog.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';

/// Images the Skins grid draws (besides the chrome and the previews).
const List<String> kSkinsImages = ['menu/lock.png', 'menu/check.png'];

/// The Skins screen (PRD-1 §5.3, approved design K1): a 3-column grid of
/// every skin in display order on the shared [MenuScreen] chrome. A tile is
/// equipped (pink outline + check badge), owned (plain) or locked (dimmed
/// preview, lock icon, coin price pill); skins that were NEW when the
/// screen opened keep their gold tag for this visit. Taps route to
/// `game.tapSkin`; the screen polls the [SkinStore] every frame.
class SkinsScreen extends MenuScreen {
  SkinsScreen({required super.onBack}) : super(title: 'SKINS');

  late final List<SkinTile> tiles;
  bool _markedSeen = false;

  @override
  List<String> get contentImages => [
    ...kSkinsImages,
    for (final skin in kSkins) ...[skin.preview, skin.previewLocked],
  ];

  /// The tile of [skinId].
  SkinTile tileFor(String skinId) =>
      tiles.firstWhere((tile) => tile.skin.id == skinId);

  @override
  Future<void> buildContent() async {
    final h = game.viewHeight;
    final skins = game.menu.skins;
    tiles = [
      for (final (i, skin) in kSkins.indexed)
        SkinTile(
          skin: skin,
          rect: Config.skinTileRectFor(h, i),
          preview: sprite(skin.preview),
          previewLocked: sprite(skin.previewLocked),
          lock: sprite('menu/lock.png'),
          check: sprite('menu/check.png'),
          coin: sprite('menu/coin.png'),
          // Snapshot: the NEW tags of this visit (markAllSeen runs once the
          // screen is up, so they are gone next time).
          isNew: skins.isNew(skin.id),
          onPressed: () => game.tapSkin(skin.id),
          isActive: isActive,
        ),
    ];
    scroll
      ..contentBottom = Config.skinsContentBottomFor(h, kSkins.length)
      ..content.addAll(tiles);
  }

  @override
  void onMount() {
    super.onMount();
    // After the grid captured this visit's NEW tags: clears them (and the
    // home tile's badge) for next time.
    if (!_markedSeen) {
      _markedSeen = true;
      unawaited(game.menu.skins.markAllSeen());
    }
  }

  /// Scrolls [skinId]'s tile into view (top of the viewport when the grid
  /// scrolls at all).
  void scrollToSkin(String skinId, {bool animate = true}) {
    final rect = tileFor(skinId).toRect();
    final viewport = scroll.viewport;
    final onScreenTop = scroll.screenY(rect.top);
    final onScreenBottom = scroll.screenY(rect.bottom);
    if (onScreenTop >= viewport.top && onScreenBottom <= viewport.bottom) {
      return;
    }
    scroll.scrollTo(rect.top - Config.skinTileGap, animate: animate);
  }

  @override
  void sync({bool force = false}) {
    final skins = game.menu.skins;
    for (final tile in tiles) {
      tile.setState(
        owned: skins.isOwned(tile.skin.id),
        equipped: skins.isEquipped(tile.skin.id),
      );
    }
  }

  @override
  void onTint(Color color) {
    final card = cardColor;
    for (final tile in tiles) {
      tile.color = card;
    }
  }
}

/// One skin tile (mock `.sk`, 92 x 106): card fill and the 48 x 52 preview,
/// plus the state decorations — outline + check badge when equipped; lock
/// icon, dimmed preview (baked into `<id>_preview_locked.png`) and price
/// pill when locked; the gold NEW tag overhanging the top-right corner.
class SkinTile extends MenuButton {
  SkinTile({
    required this.skin,
    required Rect rect,
    required this.preview,
    required this.previewLocked,
    required this.lock,
    required this.check,
    required this.coin,
    required this.isNew,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: const Color(0xFFE1E1E1),
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final SkinDef skin;
  final Sprite preview;
  final Sprite previewLocked;
  final Sprite lock;
  final Sprite check;
  final Sprite coin;

  /// Whether the NEW tag shows (fixed for the visit).
  final bool isNew;

  bool _owned = false;
  bool _equipped = false;
  bool _stateSet = false;

  bool get owned => _owned;
  bool get equipped => _equipped;
  bool get locked => !_owned;

  late final MenuIcon previewIcon;
  late final SkinTileDecoration outline;
  late final SkinTileDecoration checkBadge;
  late final SkinTileDecoration lockIcon;
  late final SkinTileDecoration pricePill;
  MenuTag? newTag;

  /// The price pill's text (tests).
  late final MenuText priceLabel;

  void setState({required bool owned, required bool equipped}) {
    if (_stateSet && owned == _owned && equipped == _equipped) return;
    _stateSet = true;
    _owned = owned;
    _equipped = equipped && owned;
    if (isLoaded) _apply();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    previewIcon = MenuIcon(
      preview,
      size: Vector2(Config.skinPreviewWidth, Config.skinPreviewHeight),
      position: Vector2(width / 2, Config.skinPreviewCenterY),
      anchor: Anchor.center,
    );

    outline = SkinTileDecoration(size: size.clone(), painter: _paintOutline);

    const badge = Config.skinCheckBadgeSize;
    checkBadge = SkinTileDecoration(
      position: Vector2(width - badge, height - badge),
      size: Vector2.all(badge),
      painter: _paintPink,
      children: [
        MenuIcon(
          check,
          size: Vector2.all(Config.skinCheckIconSize),
          position: Vector2.all(badge / 2),
          anchor: Anchor.center,
        ),
      ],
    );

    lockIcon = SkinTileDecoration(
      position: Vector2(Config.skinTileInset, Config.skinLockTop),
      size: Vector2.all(Config.skinLockSize),
      children: [MenuIcon(lock, size: Vector2.all(Config.skinLockSize))],
    );

    // Mock `.price`: 2 / 6 pt padding, 14 pt coin, 4 pt gap, 13 pt text.
    priceLabel = MenuText(
      '${skin.price}',
      fontSize: Config.skinPriceFontSize,
      color: Config.menuSoft,
    );
    final pillSize = Vector2(
      2 * Config.skinPricePadX +
          Config.skinPriceCoinSize +
          Config.skinPriceGap +
          priceLabel.width,
      Config.skinPriceLineHeight + 2 * Config.skinPricePadY,
    );
    pricePill = SkinTileDecoration(
      position: Vector2(
        (width - pillSize.x) / 2,
        height - Config.skinTileInset - pillSize.y,
      ),
      size: pillSize,
      painter: _paintPink,
    );
    layoutRow(pricePill, [
      MenuIcon(coin, size: Vector2.all(Config.skinPriceCoinSize)),
      priceLabel,
    ], gap: Config.skinPriceGap);

    addAll([previewIcon, outline, checkBadge, lockIcon, pricePill]);
    if (isNew) {
      final tag = MenuTag(
        'NEW',
        fontSize: Config.skinTagFontSize,
        letterSpacingEm: Config.skinTagLetterSpacing,
        position: Vector2(
          width + Config.skinTagOverhangX,
          -Config.skinTagOverhangY,
        ),
        anchor: Anchor.topRight,
        priority: 10,
      );
      newTag = tag;
      add(tag);
    }
    _apply();
  }

  void _apply() {
    previewIcon.sprite = _owned ? preview : previewLocked;
    outline.isVisible = _equipped;
    checkBadge.isVisible = _equipped;
    lockIcon.isVisible = !_owned;
    pricePill.isVisible = !_owned;
  }

  static final Paint _pinkPaint = Paint()..color = Config.menuPink;
  static final Paint _outlinePaint = Paint()
    ..color = Config.menuPink
    ..style = PaintingStyle.stroke
    ..strokeWidth = Config.skinOutlineWidth;

  static void _paintPink(Canvas canvas, Vector2 size) =>
      canvas.drawRect(size.toRect(), _pinkPaint);

  // CSS `outline: 3px; outline-offset: -3px`: a 3 pt band inside the edge.
  static void _paintOutline(Canvas canvas, Vector2 size) => canvas.drawRect(
    size.toRect().deflate(Config.skinOutlineWidth / 2),
    _outlinePaint,
  );
}

/// A tile decoration that can be hidden (render only; nothing in it takes
/// taps), optionally painting its own box.
class SkinTileDecoration extends PositionComponent with HasVisibility {
  SkinTileDecoration({
    super.position,
    super.size,
    this.painter,
    super.children,
  });

  final void Function(Canvas canvas, Vector2 size)? painter;

  @override
  void render(Canvas canvas) => painter?.call(canvas, size);
}
