import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart'
    show TextAlign, TextPainter, TextSpan, TextDirection;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../home/menu_primitives.dart';
import 'live_effects.dart' show WiggleEffect;

/// The P1 popup frame shared by the purchase popups (PRD-home-v3 §6 / §7;
/// the No-ads upsell's "Centre card" style): a full-screen dim over
/// whatever is below and a [Config.p1PopupWidth] card centred on the
/// screen, filled with the stage background. The card swallows its own
/// taps; a tap on the dim calls [onDismiss] (as the ✕ does).
///
/// Subclasses build the card's content in [buildCard] (local card
/// coordinates) and set [cardHeight] there; the card's pose ([cardPose],
/// scale / rotation about its centre) is theirs to animate. The whole
/// popup fades as one layer ([GroupOpacity]); [active] false stops every
/// tap (closing).
abstract class P1Popup extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity, TapCallbacks {
  P1Popup({required this.onDismiss, super.priority = 26});

  /// ✕, dim tap, Esc.
  final void Function() onDismiss;

  /// False once the popup starts closing: nothing in it takes taps.
  bool active = true;
  bool isActive() => active;

  late final PositionComponent card;

  /// Scale / rotation of the card about its centre.
  late final WiggleEffect cardPose;

  /// Set by [buildCard].
  double cardHeight = 0;

  final Paint _dimPaint = Paint()..color = Config.p1PopupDim;
  final Paint _cardPaint = Paint();

  /// Adds the content to [card] and sets [cardHeight].
  Future<void> buildCard(PositionComponent card);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    card = _P1Card(size: Vector2(Config.p1PopupWidth, 0), fill: _cardPaint);
    cardPose = WiggleEffect(card);
    card.decorator.addLast(cardPose);
    await buildCard(card);
    card
      ..size = Vector2(Config.p1PopupWidth, cardHeight)
      ..position = Vector2(
        (Config.worldWidth - Config.p1PopupWidth) / 2,
        ((h - cardHeight) / 2).roundToDouble(),
      );
    add(card);
  }

  /// The ✕ close box: [Config.menuPinkDark], 38 pt, top-right of the card,
  /// with the soft 18 pt cross.
  MenuButton closeBox(Sprite close, void Function() onPressed) => MenuButton(
    color: Config.menuPinkDark,
    position: Vector2(Config.p1PopupWidth - Config.p1PopupCloseSize, 0),
    size: Vector2.all(Config.p1PopupCloseSize),
    onPressed: onPressed,
    isActive: isActive,
    priority: 10,
    children: [
      MenuIcon(
        close,
        size: Vector2.all(18),
        position: Vector2.all(Config.p1PopupCloseSize / 2),
        anchor: Anchor.center,
      ),
    ],
  );

  @override
  void update(double dt) {
    super.update(dt);
    _cardPaint.color = game.stageBackground;
  }

  @override
  void render(Canvas canvas) =>
      canvas.drawRect(bleedRectFor(this, size.y), _dimPaint); // WP-TAB

  @override
  bool containsLocalPoint(Vector2 point) =>
      active && super.containsLocalPoint(point);

  // Taps on the dim dismiss; the card swallows its own (see [_P1Card]).
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
class _P1Card extends PositionComponent with TapCallbacks {
  _P1Card({super.size, required this.fill});

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

/// Centred, wrapping text (the popups' message lines): [text] laid out in
/// [maxWidth] with the mocks' CSS line height; the component's height is
/// the laid-out block.
class MenuParagraph extends PositionComponent {
  MenuParagraph(
    this.text, {
    required double fontSize,
    required Color color,
    required double maxWidth,
    double letterSpacingEm = 0,
    double lineHeight = kNormalLineHeight,
    super.position,
  }) : _painter = TextPainter(
         text: TextSpan(
           text: text,
           style: menuTextStyle(
             fontSize: fontSize,
             color: color,
             letterSpacingEm: letterSpacingEm,
             lineHeight: lineHeight,
           ),
         ),
         textAlign: TextAlign.center,
         textDirection: TextDirection.ltr,
       )..layout(minWidth: maxWidth, maxWidth: maxWidth),
       _shift = letterSpacingEm * fontSize / 2 {
    size = Vector2(maxWidth, _painter.height);
  }

  final String text;
  final TextPainter _painter;
  final double _shift;

  /// Laid-out line count (tests).
  int get lineCount => _painter.computeLineMetrics().length;

  @override
  void render(Canvas canvas) => _painter.paint(canvas, Offset(-_shift, 0));
}
