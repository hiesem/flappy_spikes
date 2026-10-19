import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../game/config.dart';
import '../game/purchases.dart' show PurchaseProblem;
import 'home/menu_primitives.dart';
import 'skins/celebration.dart' show keyframe;
import 'ui/p1_popup.dart';

/// "PURCHASE CANCELLED" / "PURCHASE FAILED" (PRD-home-v3 §6, mock
/// build73 `showFail`) in the P1 popup style: pink 120 pt header with the
/// soft card icon and a gold ✕ badge that spins in, the ✕ close box, the
/// soft title band, the plum message, the grey small line and a
/// full-width gold OK. The card pops in (.82 -> 1.04 -> 1, 0.24 s); ✕, OK
/// and the dim all call [onDismiss] (the game plays `sk_close` and fades
/// it out). Reduce motion: no pop, the badge simply shows.
class PurchaseResultPopup extends P1Popup {
  PurchaseResultPopup({required this.problem, required super.onDismiss});

  final PurchaseProblem problem;

  late final MenuButton closeButton;
  late final MenuButton okButton;
  late final MenuText titleText;
  late final MenuParagraph messageText;
  late final MenuParagraph smallText;
  late final _CardIcon _icon;

  /// The gold ✕ badge's scale right now (tests).
  double get badgeScale => _icon.badgeScale;

  double _t = 0;

  @override
  Future<void> buildCard(PositionComponent card) async {
    final close = Sprite(await game.images.load('menu/close.png'));
    const w = Config.p1PopupWidth;
    const pad = Config.p1PopupPad;
    const headerH = Config.purchasePopupHeaderHeight;
    const titleH = Config.purchasePopupTitleHeight;
    _icon = _CardIcon(
      position: Vector2(w / 2, headerH / 2),
      animate: !game.reduceMotion,
    );
    final header = RectangleComponent(
      size: Vector2(w, headerH),
      paint: Paint()..color = Config.menuPink,
      children: [_icon],
    );
    closeButton = closeBox(close, onDismiss);
    titleText = MenuText(
      problem.title,
      fontSize: Config.purchasePopupTitleFontSize,
      color: Config.menuPink,
      letterSpacingEm: 0.08,
      anchor: Anchor.center,
      position: Vector2(w / 2, titleH / 2),
    );
    final titleBand = RectangleComponent(
      position: Vector2(0, headerH),
      size: Vector2(w, titleH),
      paint: Paint()..color = Config.menuSoft,
      children: [titleText],
    );
    var y = headerH + titleH + Config.purchasePopupBodyTop;
    messageText = MenuParagraph(
      problem.message,
      fontSize: Config.purchasePopupMessageFontSize,
      color: Config.menuPlum,
      letterSpacingEm: 0.02,
      lineHeight: 1.3,
      maxWidth: w - 2 * pad,
      position: Vector2(pad, y),
    );
    y += messageText.height + Config.purchasePopupSmallGap;
    smallText = MenuParagraph(
      problem.smallLine,
      fontSize: Config.purchasePopupSmallFontSize,
      color: Config.p1PopupSmallText,
      letterSpacingEm: 0.03,
      maxWidth: w - 2 * pad,
      position: Vector2(pad, y),
    );
    y += smallText.height + Config.purchasePopupOkGap;
    final okLabel = MenuText(
      'OK',
      fontSize: Config.purchasePopupOkFontSize,
      color: Config.menuPlum,
      letterSpacingEm: 0.12,
      anchor: Anchor.center,
      position: Vector2((w - 2 * pad) / 2, Config.purchasePopupOkHeight / 2),
    );
    okButton = MenuButton(
      color: Config.menuGold,
      position: Vector2(pad, y),
      size: Vector2(w - 2 * pad, Config.purchasePopupOkHeight),
      onPressed: onDismiss,
      isActive: isActive,
      children: [okLabel],
    );
    y += Config.purchasePopupOkHeight + pad;
    cardHeight = y;
    card.addAll([
      header,
      closeButton,
      titleBand,
      messageText,
      smallText,
      okButton,
    ]);
    _pose();
  }

  void _pose() {
    if (game.reduceMotion) return;
    final u = Curves.easeOut.transform(
      (_t / Config.purchasePopupPopDuration).clamp(0.0, 1.0),
    );
    cardPose.scale = keyframe(const [(0, .82), (.7, 1.04), (1, 1)], u);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (isLoaded) _pose();
  }
}

/// The header art (mock `CARD_ICO`, 78 x 66 centred on [position]): a soft
/// credit card (5 pt outline, stripe, chip) and a gold ✕ badge (r 15, plum
/// cross) on its lower right that spins in (scale 0 / -90° -> 1.25 / 10°
/// at 70 % -> 1 / 0°, ease-out, 0.38 s after 0.12 s).
class _CardIcon extends PositionComponent {
  _CardIcon({required Vector2 position, required this.animate})
    : super(position: position, size: Vector2(78, 66), anchor: Anchor.center);

  final bool animate;
  double _t = 0;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = Config.menuSoft;
  final Paint _fill = Paint()..color = Config.menuSoft;
  final Paint _gold = Paint()..color = Config.menuGold;
  final Paint _cross = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..color = Config.menuPlum;

  /// The badge's current scale (tests).
  double get badgeScale => _badge().$1;

  (double, double) _badge() {
    if (!animate) return (1, 0);
    final local = _t - Config.purchasePopupBadgeDelay;
    if (local <= 0) return (0, -90);
    final u = Curves.easeOut.transform(
      (local / Config.purchasePopupBadgeDuration).clamp(0.0, 1.0),
    );
    return (
      keyframe(const [(0, 0), (.7, 1.25), (1, 1)], u),
      keyframe(const [(0, -90), (.7, 10), (1, 0)], u),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(4, 10, 58, 40), _stroke);
    canvas.drawRect(const Rect.fromLTWH(4, 20, 58, 8), _fill);
    canvas.drawRect(const Rect.fromLTWH(12, 37, 16, 5), _fill);
    final (scale, degrees) = _badge();
    if (scale <= 0) return;
    canvas.save();
    canvas.translate(56, 46);
    canvas.rotate(degrees * math.pi / 180);
    canvas.scale(scale);
    canvas.drawCircle(Offset.zero, 15, _gold);
    canvas.drawLine(const Offset(-6, -6), const Offset(6, 6), _cross);
    canvas.drawLine(const Offset(6, -6), const Offset(-6, 6), _cross);
    canvas.restore();
  }
}
