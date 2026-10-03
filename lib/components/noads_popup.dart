import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/purchases.dart';
import '../services/iap_service.dart';
import 'home/menu_primitives.dart';

/// Images the No-ads popup draws (under `assets/images/`).
const List<String> kNoAdsPopupImages = [
  'menu/noads.png',
  'menu/close.png',
  'menu/coin.png',
];

/// The No-ads upsell (PRD-1 §5.1, approved design P1 "Centre card"): a 60 %
/// dim over whatever screen is below and a centred card — pink header with
/// the crossed-AD icon and a darker close ×, the soft "GO AD-FREE" strip,
/// two benefit rows and the gold store-price button.
///
/// A tap on the dim or the ×, or Esc, calls [onDismiss]; the price button
/// [onBuy]. Taps on the card itself are swallowed. The game owns the
/// open/close bookkeeping (back stack, analytics, policy).
class NoAdsPopup extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity, TapCallbacks {
  NoAdsPopup({
    required this.trigger,
    required this.onDismiss,
    required this.onBuy,
  }) : super(priority: 25);

  /// launch / home_tile / shop_banner.
  final String trigger;
  final void Function() onDismiss;
  final void Function() onBuy;

  static const Color dimColor = Color(0x9914141E); // rgba(20,20,30,.6)
  static const double benefitTitleSize = 16;
  static const double benefitSubSize = 13;

  /// False once the popup starts closing: nothing in it takes taps.
  bool active = true;
  bool _isActive() => active;

  late final PositionComponent card;
  late final MenuButton closeButton;
  late final MenuButton priceButton;
  late final MenuText priceLabel;

  final Paint _dimPaint = Paint()..color = dimColor;
  final Paint _cardPaint = Paint();

  String? _price;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    final loaded = await Future.wait(kNoAdsPopupImages.map(game.images.load));
    final sprites = [for (final image in loaded) Sprite(image)];
    final noAds = sprites[0];
    final close = sprites[1];
    final coin = sprites[2];

    final rect = Config.noAdsCardRectFor(h);
    final w = rect.width;
    card = _Card(
      position: rect.topLeft.toVector2(),
      size: rect.size.toVector2(),
      fill: _cardPaint,
    );

    // Header: pink, crossed-AD icon centred, close × top-right.
    final header = RectangleComponent(
      size: Vector2(w, Config.noAdsHeaderHeight),
      paint: Paint()..color = Config.menuPink,
      children: [
        MenuIcon(
          noAds,
          size: Vector2.all(84),
          position: Vector2(w / 2, Config.noAdsHeaderHeight / 2),
          anchor: Anchor.center,
        ),
      ],
    );
    closeButton = MenuButton(
      color: Config.menuPinkDark,
      position: Vector2(w - Config.noAdsCloseSize, 0),
      size: Vector2.all(Config.noAdsCloseSize),
      onPressed: onDismiss,
      isActive: _isActive,
      children: [
        MenuIcon(
          close,
          size: Vector2.all(18),
          position: Vector2.all(Config.noAdsCloseSize / 2),
          anchor: Anchor.center,
        ),
      ],
    );

    // Title strip.
    const titleTop = Config.noAdsHeaderHeight;
    final titleStrip = RectangleComponent(
      position: Vector2(0, titleTop),
      size: Vector2(w, Config.noAdsTitleHeight),
      paint: Paint()..color = Config.menuSoft,
      children: [
        MenuText(
          'GO AD-FREE',
          fontSize: Config.noAdsTitleFontSize,
          color: Config.menuPink,
          letterSpacingEm: 0.06,
          position: Vector2(w / 2, Config.noAdsTitlePad),
          anchor: Anchor.topCenter,
        ),
      ],
    );

    // Benefit rows.
    const rowsTop = titleTop + Config.noAdsTitleHeight + Config.noAdsPad;
    PositionComponent benefit(int i, Sprite icon, String title, String sub) {
      final top =
          rowsTop + i * (Config.noAdsBenefitSize + Config.noAdsBenefitGap);
      const textX =
          Config.noAdsPad + Config.noAdsBenefitSize + Config.noAdsBenefitGap;
      // Two CSS line boxes (16 pt line-height normal) centred on the 44 pt
      // square; the 13 pt subtitle sits on the second line's baseline.
      const line = benefitTitleSize * kNormalLineHeight;
      const blockTop = (Config.noAdsBenefitSize - 2 * line) / 2;
      const baseline = (line - benefitTitleSize * 1.256) / 2 +
          benefitTitleSize * 0.992;
      const subBaseline =
          (benefitSubSize * kNormalLineHeight - benefitSubSize * 1.256) / 2 +
          benefitSubSize * 0.992;
      return PositionComponent(
        position: Vector2(0, top),
        size: Vector2(w, Config.noAdsBenefitSize),
        children: [
          RectangleComponent(
            position: Vector2(Config.noAdsPad, 0),
            size: Vector2.all(Config.noAdsBenefitSize),
            paint: Paint()..color = Config.menuPink,
            children: [
              MenuIcon(
                icon,
                size: Vector2.all(28),
                position: Vector2.all(Config.noAdsBenefitSize / 2),
                anchor: Anchor.center,
              ),
            ],
          ),
          MenuText(
            title,
            fontSize: benefitTitleSize,
            color: Config.menuPlum,
            position: Vector2(textX, blockTop + 0.5),
          ),
          MenuText(
            sub,
            fontSize: benefitSubSize,
            color: Config.menuPlum.withValues(alpha: 0.75),
            position: Vector2(
              textX,
              blockTop + line + baseline - subBaseline - 0.5,
            ),
          ),
        ],
      );
    }

    // Price button.
    const priceTop =
        rowsTop +
        2 * Config.noAdsBenefitSize +
        Config.noAdsBenefitGap +
        Config.noAdsPriceGap;
    priceLabel = MenuText(
      _priceText,
      fontSize: 28,
      color: Config.menuPlum,
    );
    priceButton = MenuButton(
      color: Config.menuGold,
      position: Vector2(Config.noAdsPad, priceTop),
      size: Vector2(w - 2 * Config.noAdsPad, Config.noAdsPriceHeight),
      onPressed: onBuy,
      isActive: _isActive,
    );
    priceButton.add(priceLabel);
    _layoutPrice();

    card.addAll([
      header,
      closeButton,
      titleStrip,
      benefit(0, noAds, 'NO FORCED ADS', 'or banners, ever'),
      benefit(
        1,
        coin,
        '${formatAmount(kNoAdsBonusCoins)} BONUS COINS',
        'added instantly',
      ),
      priceButton,
    ]);
    add(card);
    _sync();
  }

  String get _priceText =>
      _price ?? game.monetization.iap.priceOf(IapProduct.noAds);

  void _layoutPrice() {
    priceLabel
      ..text = _priceText
      ..position = Vector2(
        (priceButton.width - priceLabel.width) / 2,
        (priceButton.height - priceLabel.height) / 2,
      );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _sync();
  }

  void _sync() {
    _cardPaint.color = game.stageBackground;
    final price = game.monetization.iap.priceOf(IapProduct.noAds);
    if (price != _price) {
      _price = price;
      _layoutPrice();
    }
    final pending = game.purchases.isPending(IapProduct.noAds);
    priceButton
      ..tappable = !pending
      ..dimmed = pending;
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _dimPaint);

  @override
  bool containsLocalPoint(Vector2 point) =>
      active && super.containsLocalPoint(point);

  // Taps on the dim dismiss; the card swallows its own (see [_Card]).
  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    onDismiss();
  }
}

/// The card body: stage-background fill; swallows taps that miss its
/// buttons (so they do not reach the dim and dismiss).
class _Card extends PositionComponent with TapCallbacks {
  _Card({super.position, super.size, required this.fill});

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
