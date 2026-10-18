import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../game/config.dart';
import 'home/menu_primitives.dart';
import 'skins/celebration.dart' show keyframe;
import 'ui/p1_popup.dart';

/// Images the popup draws.
const List<String> kDeleteDataPopupImages = ['menu/close.png'];

/// Which face of the "Delete my data" dialog is up (PRD-2 §3.13 / Q22).
enum DeleteDataStep {
  /// "DELETE MY ACCOUNT & DATA" — CANCEL / DELETE.
  confirm,

  /// The callable confirmed: "DATA DELETED", nothing left online.
  done,

  /// Offline / refused: nothing was deleted, the local state is kept.
  failed,
}

/// "Delete my data" (PRD-2 §3.13, owner answer Q22): a confirm dialog in
/// the P1 popup style — pink header with the soft trash glyph, the ✕ close
/// box, the soft title band, the plum message, the grey small line and the
/// buttons — then the result face ("DATA DELETED" / "COULDN'T DELETE") with
/// the same card and a gold OK.
///
/// The confirm face's DELETE calls [onConfirm] (the game runs the callable
/// and swaps the face); CANCEL, the ✕ and the dim call [onDismiss].
class DeleteDataPopup extends P1Popup {
  DeleteDataPopup({
    required this.step,
    required this.onConfirm,
    required super.onDismiss,
  });

  final DeleteDataStep step;

  /// The confirm face's DELETE tap.
  final void Function() onConfirm;

  static const String confirmTitle = 'DELETE MY ACCOUNT & DATA';
  static const String confirmMessage =
      'Your online versus data is deleted: your uploaded runs, your player '
      'profile and your account.';
  static const String confirmSmall =
      // WP-L (owner 2026-10-17): the stored level resets with the data.
      "This can't be undone. Coins and skins stay; your level resets.";
  static const String doneTitle = 'DATA DELETED';
  static const String doneMessage =
      'Your runs, your profile and your account are gone. Coins and skins '
      'on this phone are kept.';
  static const String doneSmall = 'A fresh player profile starts from here.';
  /// PRD-2.3 §20.2: the confirm face names the website's request page.
  static final String confirmWeb =
      'You can also request this at '
      '${Config.deleteDataUrl.replaceFirst('https://', '')}.';
  static const String failedTitle = "COULDN'T DELETE";
  static const String failedMessage =
      "You're offline, so nothing was deleted. Your online data is still "
      'there.';
  static const String failedSmall = 'Check your connection and try again.';

  /// Cancel / ✕ / dim on the confirm, OK / ✕ / dim on the result faces.
  late final MenuButton closeButton;
  late final MenuButton? cancelButton;
  late final MenuButton confirmButton;
  late final MenuText titleText;
  late final MenuParagraph messageText;
  late final MenuParagraph smallText;

  /// PRD-2.3 §20.2 the confirm face's website line (null on the results).
  MenuParagraph? webText;

  late final TrashGlyph _icon;

  /// While the callable runs: the buttons stop taking taps.
  bool _busy = false;

  /// The header glyph (tests).
  TrashGlyph get icon => _icon;

  /// Whether the callable is running (tests).
  bool get busy => _busy;

  double _t = 0;

  @override
  Future<void> buildCard(PositionComponent card) async {
    final close = Sprite(await game.images.load('menu/close.png'));
    const w = Config.p1PopupWidth;
    const pad = Config.p1PopupPad;
    const headerH = Config.purchasePopupHeaderHeight;
    const titleH = Config.purchasePopupTitleHeight;
    final result = step != DeleteDataStep.confirm;
    _icon = TrashGlyph(
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
      switch (step) {
        DeleteDataStep.confirm => confirmTitle,
        DeleteDataStep.done => doneTitle,
        DeleteDataStep.failed => failedTitle,
      },
      fontSize: Config.purchasePopupTitleFontSize,
      color: Config.menuPink,
      letterSpacingEm: 0.08,
      anchor: Anchor.center,
      position: Vector2(w / 2, titleH / 2),
    );
    // WP-N2 "DELETE MY ACCOUNT & DATA" is wider than the card at 20 pt:
    // the same title, scaled down to fit between the card's paddings.
    const room = w - 2 * pad;
    if (titleText.width > room) {
      titleText.fontSize = (titleText.fontSize * room / titleText.width)
          .floorToDouble();
    }
    final titleBand = RectangleComponent(
      position: Vector2(0, headerH),
      size: Vector2(w, titleH),
      paint: Paint()..color = Config.menuSoft,
      children: [titleText],
    );
    var y = headerH + titleH + Config.purchasePopupBodyTop;
    messageText = MenuParagraph(
      switch (step) {
        DeleteDataStep.confirm => confirmMessage,
        DeleteDataStep.done => doneMessage,
        DeleteDataStep.failed => failedMessage,
      },
      fontSize: Config.purchasePopupMessageFontSize,
      color: Config.menuPlum,
      letterSpacingEm: 0.02,
      lineHeight: 1.3,
      maxWidth: w - 2 * pad,
      position: Vector2(pad, y),
    );
    y += messageText.height + Config.purchasePopupSmallGap;
    smallText = MenuParagraph(
      switch (step) {
        DeleteDataStep.confirm => confirmSmall,
        DeleteDataStep.done => doneSmall,
        DeleteDataStep.failed => failedSmall,
      },
      fontSize: Config.purchasePopupSmallFontSize,
      color: Config.p1PopupSmallText,
      letterSpacingEm: 0.03,
      maxWidth: w - 2 * pad,
      position: Vector2(pad, y),
    );
    y += smallText.height;
    final web = step == DeleteDataStep.confirm
        ? MenuParagraph(
            confirmWeb,
            fontSize: Config.purchasePopupSmallFontSize,
            color: Config.p1PopupSmallText,
            letterSpacingEm: 0.03,
            maxWidth: w - 2 * pad,
            position: Vector2(pad, y + Config.purchasePopupSmallGap),
          )
        : null;
    webText = web;
    if (web != null) y += Config.purchasePopupSmallGap + web.height;
    y += Config.purchasePopupOkGap;
    if (result) {
      confirmButton = MenuButton(
        color: Config.menuGold,
        position: Vector2(pad, y),
        size: Vector2(w - 2 * pad, Config.purchasePopupOkHeight),
        onPressed: onDismiss,
        isActive: isActive,
        children: [
          MenuText(
            'OK',
            fontSize: Config.purchasePopupOkFontSize,
            color: Config.menuPlum,
            letterSpacingEm: 0.12,
            anchor: Anchor.center,
            position: Vector2(
              (w - 2 * pad) / 2,
              Config.purchasePopupOkHeight / 2,
            ),
          ),
        ],
      );
      cancelButton = null;
    } else {
      const gap = 10.0;
      const buttonW = (w - 2 * pad - gap) / 2;
      cancelButton = _button(
        'CANCEL',
        color: Config.menuSoft,
        textColor: Config.menuPlum,
        position: Vector2(pad, y),
        size: Vector2(buttonW, Config.purchasePopupOkHeight),
        onPressed: onDismiss,
      );
      confirmButton = _button(
        'DELETE',
        color: Config.menuPink,
        textColor: Config.menuSoft,
        position: Vector2(pad + buttonW + gap, y),
        size: Vector2(buttonW, Config.purchasePopupOkHeight),
        onPressed: onConfirm,
      );
    }
    y += Config.purchasePopupOkHeight + pad;
    cardHeight = y;
    card.addAll([
      header,
      closeButton,
      titleBand,
      messageText,
      smallText,
      ?web,
      ?cancelButton,
      confirmButton,
    ]);
    _pose();
  }

  MenuButton _button(
    String label, {
    required Color color,
    required Color textColor,
    required Vector2 position,
    required Vector2 size,
    required void Function() onPressed,
  }) {
    final button = MenuButton(
      color: color,
      position: position,
      size: size,
      onPressed: () {
        if (!_busy) onPressed();
      },
      isActive: isActive,
    );
    button.add(
      MenuText(
        label,
        fontSize: 20,
        color: textColor,
        letterSpacingEm: 0.1,
        anchor: Anchor.center,
        position: size / 2,
      ),
    );
    return button;
  }

  /// The callable is running: DELETE stops taking taps and dims.
  void setBusy(bool value) {
    _busy = value;
    if (isLoaded) confirmButton.dimmed = value;
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

/// The header art: a soft trash can (lid handle, lid, tapered bin, three
/// ribs) that pops in (0.86 -> 1.06 -> 1, 0.3 s) unless reduce motion is on.
class TrashGlyph extends PositionComponent {
  TrashGlyph({required Vector2 position, required this.animate})
    : super(position: position, size: Vector2(52, 60), anchor: Anchor.center);

  final bool animate;

  static const double popDuration = 0.3;

  double _t = 0;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..color = Config.menuSoft;
  final Paint _fill = Paint()..color = Config.menuSoft;

  /// The current pop scale (tests).
  double get popScale {
    if (!animate) return 1;
    final u = Curves.easeOut.transform(
      (_t / popDuration).clamp(0.0, 1.0),
    );
    return keyframe(const [(0, .86), (.7, 1.06), (1, 1)], u);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(26, 30);
    canvas.scale(popScale);
    canvas.translate(-26, -30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(19, 7, 14, 6),
        const Radius.circular(2),
      ),
      _stroke,
    );
    canvas.drawLine(const Offset(11, 17), const Offset(41, 17), _stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 21, 22, 30),
        const Radius.circular(4),
      ),
      _stroke,
    );
    for (final x in const [21.0, 26.0, 31.0]) {
      canvas.drawRect(Rect.fromLTWH(x - 1, 27, 2, 18), _fill);
    }
    canvas.restore();
  }
}
