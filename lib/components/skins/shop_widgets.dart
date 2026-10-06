import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import 'shop_glyphs.dart';
import 'skin_tab_bar.dart' show kSkinShopOvershoot;

/// Collection progress bar (PRD-menu-v2 §3.7, mock `.prog`): soft-pink
/// track, pink fill of owned / 88, plum "n / 88" centred. A rise animates
/// the fill (0.6 s overshoot after 0.4 s) and pops the bar to 112 % after
/// 0.5 s ([popEnabled] false under reduce motion).
class CollectionBar extends PositionComponent {
  CollectionBar({
    required Rect rect,
    required this.owned,
    required this.total,
    required this.popEnabled,
  }) : super(
         position: rect.center.toVector2(),
         size: rect.size.toVector2(),
         anchor: Anchor.center,
       );

  final int Function() owned;
  final int total;
  final bool Function() popEnabled;

  late final ShopText _label = ShopText(
    '',
    fontSize: Config.skinShopBarFontSize,
    color: Config.menuPlum,
    letterSpacingEm: Config.skinShopBarLetterSpacing,
  );

  int? _count;
  double _fillFrom = 0;
  double _fillTo = 0;
  double _fillT = 1e9; // seconds since the last rise
  double _popT = 1e9;

  /// The number shown (tests).
  int get count => _count ?? 0;

  /// The label text (tests).
  String get labelText => _label.text;

  /// Current fill share 0..1 (animated).
  double get fill {
    final u =
        ((_fillT - Config.skinShopBarFillDelay) /
                Config.skinShopBarFillDuration)
            .clamp(0.0, 1.0);
    return _fillFrom + (_fillTo - _fillFrom) * kSkinShopOvershoot.transform(u);
  }

  /// Current pop scale (1 at rest).
  double get popScale {
    final u =
        (_popT - Config.skinShopBarPopDelay) / Config.skinShopBarPopDuration;
    if (u <= 0 || u >= 1) return 1;
    final k = u < .5 ? u * 2 : 2 - u * 2;
    return 1 + (Config.skinShopBarPopScale - 1) * k;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _fillT += dt;
    _popT += dt;
    final n = owned();
    if (n != _count) {
      final first = _count == null;
      if (!first && n > _count! && popEnabled()) _popT = 0;
      _fillFrom = first ? n / total : fill;
      _fillTo = n / total;
      _fillT = first ? 1e9 : 0;
      _count = n;
      _label.text = '$n / $total';
    }
    scale.setAll(popScale);
  }

  static final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _paint..color = Config.menuSoft);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width * fill.clamp(0.0, 1.0), height),
      _paint..color = Config.menuPink,
    );
    _label.paint(
      canvas,
      Offset((width - _label.width) / 2, (height - _label.height) / 2),
    );
  }
}

/// Name row inside the preview (mock `.nmrow`): the active tab's item name
/// (14 pt, stage foreground) and its rarity chip (9 pt, white on the rarity
/// colour); "none" has no chip.
class SkinNameRow extends PositionComponent {
  SkinNameRow({
    required super.position,
    required this.item,
    required this.tint,
  });

  final SkinItem Function() item;
  final Color Function() tint;

  late final ShopText _name = ShopText(
    '',
    fontSize: Config.skinShopNameFontSize,
    color: const Color(0xFF828282),
  );
  late final ShopText _chip = ShopText(
    '',
    fontSize: Config.skinShopChipFontSize,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: 0.12,
  );
  Rarity? _rarity;

  /// Visible texts (tests).
  String get nameText => _name.text;
  String? get chipText => _rarity == null ? null : _chip.text;

  @override
  void update(double dt) {
    super.update(dt);
    final current = item();
    _name.text = current.name;
    _rarity = current.isNone ? null : current.rarity;
    if (_rarity != null) _chip.text = _rarity!.label;
  }

  static final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    _name.color = tint();
    _name.paint(canvas, Offset.zero);
    final rarity = _rarity;
    if (rarity == null) return;
    // Chip padding 2 / 4 / 1 / 4, centred on the name's line box, 6 pt gap.
    final cw = _chip.width + 8;
    final ch = _chip.height + 3;
    final left = _name.width + 6;
    final top = (_name.height - ch) / 2;
    canvas.drawRect(
      Rect.fromLTWH(left, top, cw, ch),
      _paint..color = rarity.color,
    );
    _chip.paint(canvas, Offset(left + 4, top + 2));
  }
}

/// What the preview's action button says.
enum ShopActionKind { equipped, nothingOn, buy }

/// The action button at the preview's bottom-right (PRD-menu-v2 §3.4–3.5,
/// mock `.act`): "✓ EQUIPPED" / "✓ NOTHING ON" (flat, stage foreground,
/// pink check) or "[lock] BUY [coin price]" (pink, soft text, pulsing to
/// 106 % every 1 s; grey #A0A0A0 and still when unaffordable, but still
/// tappable). Anchored at its bottom-right corner.
class ShopActionButton extends PositionComponent with TapCallbacks {
  ShopActionButton({
    required Vector2 bottomRight,
    required this.kind,
    required this.price,
    required this.affordable,
    required this.tint,
    required this.reduceMotion,
    required this.onPressed,
    this.isActive,
  }) : super(
         position: bottomRight,
         anchor: Anchor.bottomRight,
         size: Vector2(0, Config.skinShopActionHeight),
       );

  final ShopActionKind Function() kind;

  /// Price of the tried-on item (BUY only).
  final int Function() price;
  final bool Function() affordable;
  final Color Function() tint;
  final bool Function() reduceMotion;
  final void Function() onPressed;
  final bool Function()? isActive;

  static const double fontSize = Config.skinShopActionFontSize;
  static const double padX = 10, gap = 6, glyph = 14, lockGlyph = 13;

  final ShopText _text = ShopText(
    '',
    fontSize: fontSize,
    color: const Color(0xFF828282),
    letterSpacingEm: 0.08,
  );
  PriceChip? _chip;
  int? _chipPrice;
  ShopActionKind? _kind;
  double _t = 0;

  ShopActionKind get shownKind => _kind ?? kind();
  String get label => _text.text;
  bool get poor => shownKind == ShopActionKind.buy && !affordable();

  /// Current pulse scale (1 when still).
  double get pulseScale {
    if (shownKind != ShopActionKind.buy || poor || reduceMotion()) return 1;
    // `buyp 1s ease-in-out infinite`: 50 % = scale 1.06.
    final u = _t % 1;
    final k = Curves.easeInOut.transform(u < .5 ? u * 2 : 2 - u * 2);
    return 1 + (Config.skinShopActionPulse - 1) * k;
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      (isActive?.call() ?? true) && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) => event.handled = true;

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    onPressed();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final k = kind();
    final p = price();
    if (k != _kind || (k == ShopActionKind.buy && p != _chipPrice)) {
      _kind = k;
      _text.text = switch (k) {
        ShopActionKind.equipped => 'EQUIPPED',
        ShopActionKind.nothingOn => 'NOTHING ON',
        ShopActionKind.buy => 'BUY',
      };
      if (k == ShopActionKind.buy) {
        _chipPrice = p;
        _chip = PriceChip(
          p,
          background: Config.menuSoft,
          textColor: Config.menuPink,
        );
        size.x =
            padX + lockGlyph + gap + _text.width + gap + _chip!.width + padX;
      } else {
        _chip = null;
        _chipPrice = null;
        size.x = glyph + gap + _text.width;
      }
    }
    // Scale about the centre while the anchor stays bottom-right.
    final s = pulseScale;
    scale.setAll(s);
  }

  static final Paint _paint = Paint();

  @override
  void renderTree(Canvas canvas) {
    final s = scale.x;
    if (s == 1) {
      super.renderTree(canvas);
      return;
    }
    // Re-centre the pulse on the button (CSS transform-origin: center).
    canvas.save();
    canvas.translate(width * (s - 1) / 2, height * (s - 1) / 2);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    final k = shownKind;
    if (k != ShopActionKind.buy) {
      final color = tint();
      _text.color = color;
      canvas.save();
      canvas.translate(0, (height - glyph) / 2);
      ShopGlyphs.check(canvas, glyph, Config.menuPink);
      canvas.restore();
      _text.paint(canvas, Offset(glyph + gap, (height - _text.height) / 2));
      return;
    }
    final isPoor = poor;
    canvas.drawRect(
      size.toRect(),
      _paint..color = isPoor ? Config.skinShopPoorGrey : Config.menuPink,
    );
    canvas.save();
    canvas.translate(padX, (height - lockGlyph) / 2);
    ShopGlyphs.lock(canvas, lockGlyph, Config.menuSoft);
    canvas.restore();
    _text.color = Config.menuSoft;
    final textX = padX + lockGlyph + gap;
    _text.paint(canvas, Offset(textX, (height - _text.height) / 2));
    final chip = _chip!;
    chip.label.color = isPoor ? const Color(0xFF888888) : Config.menuPink;
    chip.paint(
      canvas,
      Offset(textX + _text.width + gap, (height - chip.height) / 2),
    );
  }
}
