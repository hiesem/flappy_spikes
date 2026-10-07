import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../home/menu_primitives.dart' show withMenuKnock;
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import 'item_art.dart';
import 'shop_glyphs.dart';

/// What a tile shows right now (read from the shop every frame).
class ItemTileState {
  const ItemTileState({
    required this.owned,
    required this.equipped,
    required this.tryingOn,
    required this.isNew,
  });

  final bool owned;

  /// Equipped and not covered by a try-on on its layer.
  final bool equipped;
  final bool tryingOn;
  final bool isNew;
}

/// One 92 x 92 grid tile of the skin shop (PRD-menu-v2 §3.3 / §4.1, mock
/// `.tile`): the item art in an 84 x 68 box on the card fill plus its state
/// decorations — equipped (3 pt pink inner outline + check badge, the bird
/// flaps), locked (art at 42 %, lock top-left, coin price pill), trying on
/// (outline pulsing pink <-> soft, art solid, no pill), NEW (gold tag
/// overhanging the top-right corner, wobbling) and the rarity markers
/// (rare / epic / legendary bottom bar, epic / legendary 1 pt inner
/// outline, a moving shine on the legendary bar). Presses scale it to 93 %;
/// a tab switch fades / raises it in after [enterDelay].
///
/// Static art is a cached [Picture]; animated items (and flapping birds)
/// redraw every frame, only while the tile is inside the grid viewport.
class ItemTile extends PositionComponent with TapCallbacks {
  ItemTile({
    required this.item,
    required Rect rect,
    required this.state,
    required this.onPressed,
    required this.art,
    required this.cardColor,
    required this.tint,
    required this.reduceMotion,
    this.isActive,
    this.isOnScreen,
    double? enterDelay,
  }) : _age = enterDelay == null ? double.infinity : -enterDelay,
       _price = PriceChip(
         item.price,
         background: Config.menuPink,
         textColor: Config.menuSoft,
       ),
       super(
         position: rect.center.toVector2(),
         size: rect.size.toVector2(),
         anchor: Anchor.center,
       ) {
    // A random phase so neighbouring animated tiles do not move in step
    // (mock `t: Math.random() * 5`), deterministic per item.
    _t = (item.key.hashCode % 500) / 100;
  }

  final SkinItem item;
  final ItemTileState Function() state;
  final void Function() onPressed;
  final ItemArtCache art;
  final Color Function() cardColor;
  final Color Function() tint;
  final bool Function() reduceMotion;
  final bool Function()? isActive;

  /// Whether the tile is inside the grid viewport (animated art only runs
  /// then; null = always).
  final bool Function()? isOnScreen;

  final PriceChip _price;
  late final ShopText _newLabel = ShopText(
    'NEW',
    fontSize: Config.skinShopTagFontSize,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: 0.06,
  );

  double _t = 0;
  double _clock = 0;
  double _age;
  bool _pressed = false;
  double _scale = 1;
  ItemTileState _state = const ItemTileState(
    owned: false,
    equipped: false,
    tryingOn: false,
    isNew: false,
  );

  ItemTileState get current => _state;
  bool get pressed => _pressed;

  /// Entrance progress 0..1 (1 = settled).
  double get enterProgress =>
      (_age / Config.skinShopEnterDuration).clamp(0.0, 1.0);

  /// Whether the art is redrawn every frame (vs. the cached picture).
  bool get animatesArt =>
      ItemArt.isAnimated(item) ||
      (item.layer == SkinLayer.bird && (_state.equipped || _state.tryingOn));

  bool get _visible => isOnScreen?.call() ?? true;

  @override
  bool containsLocalPoint(Vector2 point) =>
      (isActive?.call() ?? true) && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _pressed = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    _pressed = false;
    withMenuKnock(this, onPressed);
  }

  @override
  void onTapCancel(TapCancelEvent event) => _pressed = false;

  @override
  void update(double dt) {
    super.update(dt);
    _state = state();
    _clock += dt;
    if (_age < Config.skinShopEnterDuration) _age += dt;
    // CSS `transition: transform .12s`.
    final target = _pressed ? Config.skinShopPressScale : 1.0;
    final step = dt / 0.12 * (1 - Config.skinShopPressScale);
    _scale = _scale < target
        ? math.min(target, _scale + step)
        : math.max(target, _scale - step);
    scale.setAll(_scale);
    if (_visible && animatesArt) {
      _t += dt;
      if (item.layer == SkinLayer.trail) {
        ItemArt.advanceTrail(art.emitterFor(item), _t, dt);
      }
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (!_visible) return;
    final e = enterProgress;
    if (e >= 1) {
      super.renderTree(canvas);
      return;
    }
    if (e <= 0) return;
    final eased = Curves.easeOut.transform(e);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, eased));
    if (!reduceMotion()) {
      canvas.translate(0, Config.skinShopEnterRise * (1 - eased));
    }
    super.renderTree(canvas);
    canvas.restore();
  }

  static final Paint _paint = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  static final Paint _alpha = Paint();

  @override
  void render(Canvas canvas) {
    final s = _state;
    final rect = size.toRect();
    canvas.drawRect(rect, _paint..color = cardColor());

    // Art (42 % while locked, solid while being tried on). Static art is a
    // cached picture with that alpha already baked in, so a settled locked
    // tile never composites a per-frame layer; only the animated art (whose
    // picture changes every frame) is dimmed through one.
    final dim = !s.owned && !s.tryingOn;
    canvas.save();
    canvas.translate(
      (width - Config.skinShopArtWidth) / 2,
      (height - Config.skinShopArtHeight) / 2,
    );
    // The mock's thumbnail is an 84 x 68 canvas: art never leaves it.
    canvas.clipRect(
      const Rect.fromLTWH(
        0,
        0,
        Config.skinShopArtWidth,
        Config.skinShopArtHeight,
      ),
    );
    if (animatesArt) {
      if (dim) {
        canvas.saveLayer(
          const Rect.fromLTWH(
            0,
            0,
            Config.skinShopArtWidth,
            Config.skinShopArtHeight,
          ),
          _alpha
            ..color = const Color.fromRGBO(
              0,
              0,
              0,
              Config.skinShopLockedOpacity,
            ),
        );
      }
      final flap = item.layer == SkinLayer.bird && (s.equipped || s.tryingOn);
      ItemArt.paint(
        canvas,
        item,
        t: _t,
        flap: flap,
        emitter: item.layer == SkinLayer.trail ? art.emitterFor(item) : null,
      );
      if (dim) canvas.restore();
    } else {
      canvas.drawPicture(
        dim ? art.lockedPictureFor(item) : art.pictureFor(item),
      );
    }
    canvas.restore();

    // Inner outlines: equipped / trying on win over the rarity outline.
    final rarity = item.isNone ? null : item.rarity;
    const ow = Config.skinShopOutline;
    if (s.equipped || s.tryingOn) {
      var color = Config.menuPink;
      if (s.tryingOn && !reduceMotion()) {
        // `.9s ease-in-out infinite alternate` pink -> soft.
        final u =
            (_clock % (2 * Config.skinShopTryPulse)) / Config.skinShopTryPulse;
        final k = Curves.easeInOut.transform(u > 1 ? 2 - u : u);
        color = Color.lerp(Config.menuPink, Config.menuSoft, k)!;
      }
      canvas.drawRect(
        rect.deflate(ow / 2),
        _stroke
          ..color = color
          ..strokeWidth = ow,
      );
    } else if (rarity == Rarity.epic || rarity == Rarity.legendary) {
      canvas.drawRect(
        rect.deflate(.5),
        _stroke
          ..color = rarity!.color.withValues(
            alpha: rarity == Rarity.epic ? .35 : .6,
          )
          ..strokeWidth = 1,
      );
    }

    // Lock + price pill.
    if (!s.owned) {
      canvas.save();
      canvas.translate(Config.skinShopLockLeft, Config.skinShopLockTop);
      ShopGlyphs.lock(
        canvas,
        Config.skinShopLockSize,
        tint().withValues(alpha: .75),
      );
      canvas.restore();
      if (!s.tryingOn) {
        _price.paint(
          canvas,
          Offset(
            (width - _price.width) / 2,
            height - Config.skinShopPriceBottom - _price.height,
          ),
        );
      }
    }

    // Check badge.
    if (s.equipped) {
      const b = Config.skinShopCheckBadge;
      canvas.drawRect(
        Rect.fromLTWH(width - b, height - b, b, b),
        _paint..color = Config.menuPink,
      );
      canvas.save();
      canvas.translate(width - b + 4, height - b + 4);
      ShopGlyphs.check(canvas, 14, const Color(0xFFFFFFFF));
      canvas.restore();
    }

    // Rarity bar (above the badge, as the mock's ::after).
    if (rarity != null && rarity != Rarity.common) {
      final bar = Rect.fromLTWH(
        0,
        height - Config.skinShopRarityBar,
        width,
        Config.skinShopRarityBar,
      );
      if (rarity == Rarity.legendary) {
        // 200 %-wide gold / light / gold gradient sliding right, 1.6 s.
        final period = 2 * width;
        final shift = reduceMotion()
            ? 0.0
            : (_clock % Config.skinShopShineLoop) /
                  Config.skinShopShineLoop *
                  period;
        _paint.shader = Gradient.linear(
          Offset(shift, 0),
          Offset(shift + period, 0),
          const [Color(0xFFFFB529), Color(0xFFFFF6D6), Color(0xFFFFB529)],
          const [0, .5, 1],
          TileMode.repeated,
        );
        canvas.drawRect(bar, _paint);
        _paint.shader = null;
      } else {
        canvas.drawRect(bar, _paint..color = rarity.color);
      }
    }

    if (s.isNew) _paintNewTag(canvas);
  }

  void _paintNewTag(Canvas canvas) {
    const padX = 5.0, padY = 2.0;
    final tw = _newLabel.width + 2 * padX;
    final th = _newLabel.height + 2 * padY;
    final right = width + Config.skinShopTagOverhangX;
    final top = -Config.skinShopTagOverhangY;
    canvas.save();
    canvas.translate(right - tw / 2, top + th / 2);
    if (!reduceMotion()) {
      // `nwb 1.2s ease-in-out infinite`: 50 % = scale 1.12, rotate 4°.
      final u = (_clock % Config.skinShopNewWobble) / Config.skinShopNewWobble;
      final k = Curves.easeInOut.transform(u < .5 ? u * 2 : 2 - u * 2);
      canvas.rotate(4 * math.pi / 180 * k);
      canvas.scale(1 + .12 * k);
    }
    canvas.drawRect(
      Rect.fromLTWH(-tw / 2, -th / 2, tw, th),
      _paint..color = Config.menuGold,
    );
    _newLabel.paint(canvas, Offset(-tw / 2 + padX, -th / 2 + padY));
    canvas.restore();
  }
}
