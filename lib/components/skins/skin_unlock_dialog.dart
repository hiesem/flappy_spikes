import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../menu/skin_catalog.dart';
import '../home/menu_primitives.dart';
import '../noads_popup.dart';

/// Confirmation for unlocking a locked skin with coins, in the No-ads
/// popup's visual language (PRD-1 §5.3): the same dim, a centred card with
/// a pink header holding the bird preview, the soft title strip
/// ("UNLOCK GRAPE?"), the gold button ("● 200") and a plain CANCEL link.
///
/// While the balance is short the strip reads "NOT ENOUGH COINS", a line
/// says "You need N more" and the gold button becomes "GET COINS". The
/// state follows the wallet live. The gold button calls [onConfirm] (the
/// game decides: purchase or Shop); CANCEL, a tap on the dim or Esc call
/// [onCancel].
class SkinUnlockDialog extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity, TapCallbacks {
  SkinUnlockDialog({
    required this.skin,
    required this.onConfirm,
    required this.onCancel,
  }) : super(priority: 25);

  final SkinDef skin;
  final void Function() onConfirm;
  final void Function() onCancel;

  /// False once the dialog starts closing (or while a purchase runs):
  /// nothing in it takes taps.
  bool active = true;
  bool _isActive() => active;

  final Paint _dimPaint = Paint()..color = NoAdsPopup.dimColor;
  final Paint _cardPaint = Paint();

  late final Sprite _preview;
  late final Sprite _coin;

  PositionComponent? card;
  late MenuButton confirmButton;
  late MenuButton cancelButton;
  late MenuText titleText;
  late MenuText confirmLabel;
  MenuText? messageText;

  bool? _short;

  /// Whether the balance is short of the price (dialog in its
  /// "NOT ENOUGH COINS" state).
  bool get insufficient => _short ?? false;

  /// Coins still missing (0 when affordable).
  int get missing {
    final gap = skin.price - game.menu.wallet.balance;
    return gap > 0 ? gap : 0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(Config.worldWidth, game.viewHeight);
    final images = await Future.wait([
      game.images.load(skin.preview),
      game.images.load('menu/coin.png'),
    ]);
    _preview = Sprite(images[0]);
    _coin = Sprite(images[1]);
    _sync();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _sync();
  }

  void _sync() {
    _cardPaint.color = game.stageBackground;
    final short = missing > 0;
    if (short != _short) {
      _short = short;
      _build();
    } else if (short) {
      final text = _messageFor(missing);
      if (messageText?.text != text) _build();
    }
  }

  static String _messageFor(int missing) =>
      'You need ${formatCoins(missing)} more';

  void _build() {
    card?.removeFromParent();
    final short = insufficient;
    const headerH = Config.skinDialogHeaderHeight;
    const titleH = Config.noAdsTitleHeight;
    const pad = Config.noAdsPad;
    const messageH =
        Config.skinDialogMessageFontSize * kNormalLineHeight +
        Config.skinDialogMessageGap;
    final cardHeight =
        headerH +
        titleH +
        pad +
        (short ? messageH : 0) +
        Config.noAdsPriceHeight +
        Config.skinDialogCancelHeight;
    final rect = Config.skinDialogRectFor(game.viewHeight, cardHeight);
    final w = rect.width;

    final header = RectangleComponent(
      size: Vector2(w, headerH),
      paint: Paint()..color = Config.menuPink,
      children: [
        // Soft plate: pink skins would vanish on the pink header.
        RectangleComponent(
          size: Vector2.all(Config.skinDialogPlateSize),
          position: Vector2(w / 2, headerH / 2),
          anchor: Anchor.center,
          paint: Paint()..color = Config.menuSoft,
        ),
        MenuIcon(
          _preview,
          size:
              Vector2(Config.skinPreviewWidth, Config.skinPreviewHeight) *
              Config.skinDialogPreviewScale,
          position: Vector2(w / 2, headerH / 2),
          anchor: Anchor.center,
        ),
      ],
    );

    titleText =
        _fitted(
            short ? 'NOT ENOUGH COINS' : 'UNLOCK ${skin.name.toUpperCase()}?',
            maxWidth: w - 2 * pad,
          )
          ..position = Vector2(w / 2, Config.noAdsTitlePad)
          ..anchor = Anchor.topCenter;
    final titleStrip = RectangleComponent(
      position: Vector2(0, headerH),
      size: Vector2(w, titleH),
      paint: Paint()..color = Config.menuSoft,
      children: [titleText],
    );

    var y = headerH + titleH + pad;
    final parts = <Component>[header, titleStrip];
    messageText = null;
    if (short) {
      final message = MenuText(
        _messageFor(missing),
        fontSize: Config.skinDialogMessageFontSize,
        color: Config.menuPlum,
        position: Vector2(w / 2, y),
        anchor: Anchor.topCenter,
      );
      messageText = message;
      parts.add(message);
      y += messageH;
    }

    confirmButton = MenuButton(
      color: Config.menuGold,
      position: Vector2(pad, y),
      size: Vector2(w - 2 * pad, Config.noAdsPriceHeight),
      onPressed: onConfirm,
      isActive: _isActive,
    );
    confirmLabel = MenuText(
      short ? 'GET COINS' : '${skin.price}',
      fontSize: short ? 24 : 28,
      color: Config.menuPlum,
      letterSpacingEm: short ? 0.06 : 0,
    );
    layoutRow(confirmButton, [
      // "● 200": the coin as a plum dot (gold on gold would vanish).
      if (!short)
        MenuIcon(
          _coin,
          size: Vector2.all(Config.skinDialogCoinSize),
          recolor: Config.menuPlum,
        ),
      confirmLabel,
    ], gap: 8);
    parts.add(confirmButton);
    y += Config.noAdsPriceHeight;

    cancelButton = MenuButton(
      position: Vector2(0, y),
      size: Vector2(w, Config.skinDialogCancelHeight),
      onPressed: onCancel,
      isActive: _isActive,
    );
    layoutRow(cancelButton, [
      MenuText(
        'CANCEL',
        fontSize: Config.skinDialogCancelFontSize,
        color: Config.menuPink,
        letterSpacingEm: 0.1,
      ),
    ], gap: 0);
    parts.add(cancelButton);

    final body = _DialogCard(
      position: rect.topLeft.toVector2(),
      size: rect.size.toVector2(),
      fill: _cardPaint,
    )..addAll(parts);
    card = body;
    add(body);
  }

  /// [text] at the popup title size, shrunk until it fits [maxWidth] (long
  /// skin names).
  static MenuText _fitted(String text, {required double maxWidth}) {
    var fontSize = Config.noAdsTitleFontSize;
    while (true) {
      final label = MenuText(
        text,
        fontSize: fontSize,
        color: Config.menuPink,
        letterSpacingEm: 0.06,
      );
      if (label.width <= maxWidth || fontSize <= 14) return label;
      fontSize -= 1;
    }
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _dimPaint);

  @override
  bool containsLocalPoint(Vector2 point) =>
      active && super.containsLocalPoint(point);

  // Taps on the dim cancel; the card swallows its own (see [_DialogCard]).
  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    onCancel();
  }
}

/// The card body: stage-background fill; swallows taps that miss its
/// buttons.
class _DialogCard extends PositionComponent with TapCallbacks {
  _DialogCard({super.position, super.size, required this.fill});

  final Paint fill;

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), fill);

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
  }
}
