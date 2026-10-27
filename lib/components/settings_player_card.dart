import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart' show Sfx;
import '../levels/level_track.dart';
import '../run/config/hud_config.dart';
import '../run/hud/fit_name.dart';
import '../versus/custom_name.dart';
import 'home/menu_primitives.dart';
import 'settings_panel.dart' show paintSettingsSpinner;
import 'levels/emblem_view.dart';
import 'look_component.dart';

/// WP-NAME the PLAYER card at the top of Settings (design A "Player card
/// at the top, edit in place", `design/username_settings/username.html`):
/// a white card with the player's sticker (52 pt), a small NAME label and
/// the name in plum Fredoka ("You" until the player chooses one), with a
/// pink pencil box on the right.
///
/// A tap on the card or the pencil turns the name into a text field right
/// there: the NAME label turns pink, the name gets a pink underline, a
/// blinking caret and an `n/14` counter, and the pencil becomes a pink ✓
/// over a grey ✕. The system keyboard comes from a hidden [EditableText]
/// in a GameWidget overlay ([kPlayerNameOverlay]); this card draws what is
/// typed. ✓ / Enter saves, ✕ / back cancels. Under the card a hint (or the
/// inline error in red) says the rule: 3–14 letters A–Z or digits.
///
/// 2.4.0 (38) while a ✓ waits for the server ([saving]) the ✓ / ✕ make
/// way for the Settings spinner ([paintSettingsSpinner]), the field is
/// read-only (the keyboard goes down) and taps / back do nothing; a
/// refusal brings the buttons and the keyboard back with the reason.
class SettingsPlayerCard extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  SettingsPlayerCard({
    super.position,
    this.onLayout,
    CustomNameReason? initialError,
  }) : _error = initialError,
       super(size: Vector2(Config.settingsBodyWidth, cardHeight));

  /// The card's height at rest and while editing (the ✓ / ✕ column).
  static const double cardHeight = 68;
  static const double editHeight = 80;
  static const double padX = 10, padY = 8;
  static const double sticker = 52;
  static const double gap = 10;
  static const double button = 30;
  static const double buttonGap = 4;

  /// The hint under the card: 6 pt below it, two lines of 14 pt.
  static const double hintGap = 6;
  static const double hintLine = 14;
  static const double hintFontSize = 9.5;

  /// The name: Fredoka SemiBold 22 pt (editing: 20 pt), plum.
  static const double nameSize = 22;
  static const double fieldSize = 20;
  static const Color plum = HudConfig.plum;
  static const Color grey = Color(0xFFBDBDBD);
  static const Color hintInk = Config.settingsCaption;

  /// Called when the card's block height changes (editing, an error).
  final void Function()? onLayout;

  bool _editing = false;
  bool get editing => _editing;

  /// The text being typed (editing).
  String _draft = '';
  String get draft => _draft;

  /// The inline error under the card (null = the hint, or nothing at rest).
  CustomNameReason? _error;
  CustomNameReason? get error => _error;

  /// A ✓ is waiting for the server.
  bool _saving = false;
  bool get saving => _saving;
  set _savingNow(bool value) {
    _saving = value;
    _readOnly.value = value;
    if (value) _spin = 0;
  }

  /// The hidden field is read-only while [saving].
  final ValueNotifier<bool> _readOnly = ValueNotifier(false);

  /// Seconds the save spinner has been turning (tests).
  double _spin = 0;
  double get spin => _spin;

  double _blink = 0;

  late final MenuText _label;
  late final MenuText _name;
  // region P26-J7
  late final MenuText _rank;
  late final EmblemView _emblem;
  late final LookComponent _emblemBird;
  // endregion
  late final MenuText _field;
  late final MenuText _counter;
  late final MenuText _hint1;
  late final MenuText _hint2;
  late final MenuButton tapTarget;

  /// WP-N2 while editing: a tap on the card's text area asks for the
  /// keyboard again (the system can hide it, e.g. Android's hide arrow).
  late final MenuButton fieldTarget;
  late final MenuButton pencil;
  late final MenuButton confirm;
  late final MenuButton cancel;

  /// The name shown at rest: the custom name, or "You".
  String get shownName {
    final n = validCustomName(game.storage.versusCustomName);
    return n.isNotEmpty ? n : kDefaultOwnName;
  }

  /// Height of the card plus its hint lines (what pushes the rows down).
  double get blockHeight {
    final card = _editing ? editHeight : cardHeight;
    final hint = _editing || _error != null ? hintGap + 2 * hintLine : 0.0;
    return card + hint;
  }

  double get _textLeft => padX + sticker + gap;
  double get _textRight => width - padX - button - 8;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (_error != null) {
      // A name saved offline was refused later ([initialError]): said
      // once, here.
      unawaited(game.storage.saveVersusCustomNameError(''));
    }
    tapTarget = MenuButton(
      size: Vector2(width, cardHeight),
      pressedTo: 1,
      pressShade: false,
      onPressed: startEditing,
    );
    fieldTarget = MenuButton(
      size: Vector2(_textRight, editHeight),
      pressedTo: 1,
      pressShade: false,
      onPressed: showKeyboard,
    );
    pencil = MenuButton(
      color: Config.menuPink,
      position: Vector2(width - padX - button, (cardHeight - button) / 2),
      size: Vector2.all(button),
      onPressed: startEditing,
      children: [_Glyph(_GlyphKind.pencil)],
    );
    confirm = MenuButton(
      color: Config.menuPink,
      position: Vector2(width - padX - button, padY),
      size: Vector2.all(button),
      onPressed: () => unawaited(commit()),
      children: [_Glyph(_GlyphKind.check)],
    );
    cancel = MenuButton(
      color: grey,
      position: Vector2(width - padX - button, padY + button + buttonGap),
      size: Vector2.all(button),
      onPressed: cancelEditing,
      children: [_Glyph(_GlyphKind.cross)],
    );
    _label = MenuText(
      'NAME',
      fontSize: 9,
      color: Config.settingsCaption,
      letterSpacingEm: 0.2,
    );
    _name = MenuText(
      '',
      fontSize: nameSize,
      color: plum,
      fontFamily: HudConfig.nameFont,
      fontWeight: FontWeight.w600,
      lineHeight: 1,
    );
    // region P26-J7
    _rank = MenuText('', fontSize: 9.5, color: plum, lineHeight: 1);
    _emblem = EmblemView(level: game.storage.lvlIndex, artScale: .23);
    _emblemBird = LookComponent(
      look: game.menu.items.look,
      artScale: .23 * 1.4,
      anchor: Anchor.center,
    )..paused = true;
    addAll([_emblem, _emblemBird]);
    // endregion
    _field = MenuText(
      '',
      fontSize: fieldSize,
      color: plum,
      fontFamily: HudConfig.nameFont,
      fontWeight: FontWeight.w600,
      lineHeight: 1,
    );
    _counter = MenuText(
      '',
      fontSize: 10,
      color: Config.settingsCaption,
      letterSpacingEm: 0.1,
      anchor: Anchor.centerRight,
    );
    _hint1 = MenuText('', fontSize: hintFontSize, color: hintInk);
    _hint2 = MenuText('', fontSize: hintFontSize, color: hintInk);
    add(tapTarget);
    _built = true;
    _sync();
  }

  bool _built = false;

  static final NameMeasure _measureName = measureName(
    fontFamily: HudConfig.nameFont,
    fontWeight: FontWeight.w600,
  );

  void _sync() {
    if (!_built) return;
    final h = _editing ? editHeight : cardHeight;
    size.y = h;
    // region P26-J7
    _emblem
      ..level = game.storage.lvlIndex
      ..position = Vector2(padX + sticker / 2, h / 2)
      ..reduceMotion = game.reduceMotion;
    _emblemBird.position = _emblem.position.clone();
    // endregion
    // Children for the current state.
    void show(Component c, bool on) {
      if (on && c.parent == null) add(c);
      if (!on && c.parent != null) c.removeFromParent();
    }

    show(tapTarget, !_editing);
    show(fieldTarget, _editing);
    show(pencil, !_editing);
    show(confirm, _editing && !_saving);
    show(cancel, _editing && !_saving);
    show(_name, !_editing);
    // region P26-J7
    show(_rank, !_editing);
    // endregion
    show(_field, _editing);
    show(_counter, _editing);
    show(_label, true);
    final hint = _editing || _error != null;
    show(_hint1, hint);
    show(_hint2, hint);

    _label.color = _editing ? Config.menuPink : Config.settingsCaption;
    final room = _textRight - _textLeft;
    if (_editing) {
      // NAME over the field; the field's baseline area: 22 pt + underline.
      const labelH = 13.0;
      const fieldH = 30.0;
      final top = (h - labelH - fieldH) / 2;
      _label.position = Vector2(_textLeft, top);
      _counter
        ..text = '${_draft.length}/$kCustomNameMax'
        ..color = _draft.length > kCustomNameMax
            ? Config.settingsRed
            : Config.settingsCaption
        ..position = Vector2(_textRight, top + labelH + fieldH / 2);
      final textRoom = room - _counter.width - 10;
      final f = fitName(
        _draft,
        textRoom,
        fieldSize,
        _measureName,
        minScale: .5,
      );
      _field
        ..text = f.text
        ..fontSize = f.size
        ..position = Vector2(
          _textLeft + 2,
          top + labelH + (fieldH - f.size) / 2,
        );
    } else {
      const labelH = 13.0;
      final f = fitName(shownName, room, nameSize, _measureName);
      _name
        ..text = f.text
        ..fontSize = f.size;
      // region P26-J7
      const rankH = 14.0;
      final top = (h - labelH - nameSize - rankH) / 2;
      final level = game.storage.lvlIndex;
      final rank = fitRankName(
        trackLevelDef(level)?.name ?? 'UNRANKED',
        level,
        room,
        9.5,
        measureName(fontFamily: 'Opificio Neue'),
      );
      _rank
        ..text = rank.text
        ..fontSize = rank.size
        ..position = Vector2(_textLeft, top + labelH + nameSize + 3);
      // endregion
      _label.position = Vector2(_textLeft, top);
      _name.position = Vector2(
        _textLeft,
        top + labelH + (nameSize - f.size) / 2,
      );
    }
    if (hint) {
      final e = _error;
      final first = _saving
          ? 'SAVING…'
          : e != null
          ? e.message
          : '3–14 letters A–Z or numbers 0–9.';
      _hint1
        ..text = first
        ..color = e != null && !_saving ? Config.settingsRed : hintInk
        ..position = Vector2(0, h + hintGap);
      _hint2
        ..text = 'Other players see this name in Versus.'
        ..position = Vector2(0, h + hintGap + hintLine);
    }
    onLayout?.call();
  }

  /// Opens the field with the current custom name (empty for "You").
  void startEditing() {
    if (_editing) return;
    _click();
    _editing = true;
    _savingNow = false;
    _error = null;
    _draft = validCustomName(game.storage.versusCustomName);
    _blink = 0;
    game.pushBack(_back);
    _openKeyboard();
    _sync();
  }

  /// ✕ / back: leaves the name as it was.
  void cancelEditing() {
    if (!_editing || _saving) return;
    _click();
    _close();
  }

  void _close() {
    _editing = false;
    _savingNow = false;
    _error = null;
    game.popBack(_back);
    _closeKeyboard();
    _sync();
  }

  bool _back() {
    cancelEditing();
    return true;
  }

  /// The typed text changed (the keyboard overlay, tests).
  void setDraft(String value) {
    if (!_editing || _saving) return;
    _draft = value;
    _blink = 0;
    // Wrong characters show at once; the length is checked on ✓.
    final f = checkCustomNameFormat(value);
    _error = f == CustomNameReason.chars ? f : null;
    _sync();
  }

  /// ✓ / Enter: an empty field clears the name ("You"); otherwise the
  /// format rule here, then the server (word filter). Offline the name is
  /// kept on the phone and sent later.
  Future<void> commit() async {
    if (!_editing || _saving) return;
    final name = _draft.trim();
    if (name.isNotEmpty) {
      final f = checkCustomNameLocal(name);
      if (f != null) {
        _error = f;
        _sync();
        return;
      }
    }
    _click();
    _savingNow = true;
    _error = null;
    _sync();
    final r = await game.saveCustomName(name);
    if (!isMounted || !_editing) return;
    _savingNow = false;
    if (r is CustomNameRefused) {
      _error = r.reason;
      _sync();
      return;
    }
    _close();
  }

  void _click() {
    if (game.soundReady) game.sound.play(Sfx.click);
  }

  /// The hidden field's state while it is mounted.
  final GlobalKey<PlayerNameInputState> _input = GlobalKey(
    debugLabel: 'playerNameInput',
  );

  /// WP-N2 asks for focus and the system keyboard again (editing only).
  void showKeyboard() {
    if (!_editing || _saving) return;
    _input.currentState?.requestKeyboard();
  }

  void _openKeyboard() {
    game.overlays.addEntry(
      kPlayerNameOverlay,
      (context, _) => PlayerNameInput(
        key: _input,
        initial: _draft,
        readOnly: _readOnly,
        onChanged: setDraft,
        onSubmitted: () => unawaited(commit()),
      ),
    );
    game.overlays.add(kPlayerNameOverlay);
  }

  void _closeKeyboard() {
    game.overlays.remove(kPlayerNameOverlay);
  }

  @override
  void onRemove() {
    if (_editing) {
      _editing = false;
      game.popBack(_back);
      _closeKeyboard();
    }
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // region P26-J7
    if (_built) {
      _emblem.reduceMotion = game.reduceMotion;
      if (!game.reduceMotion) _emblem.t += dt;
    }
    // endregion
    if (_editing) _blink = (_blink + dt) % 1;
    if (_saving) _spin += dt;
  }

  final Paint _white = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _pink = Paint()..color = Config.menuPink;
  final Paint _ring = Paint();

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _white);
    // region P26-J7
    // EmblemView + LookComponent children keep the PNG/fallback route and
    // the equipped bird's plate centre identical to the other rank cards.
    // endregion
    if (_editing) {
      // The field's underline (2 pt pink) and the caret.
      final y = _field.y + _field.fontSize + (30 - _field.fontSize) / 2 + 2;
      canvas.drawRect(
        Rect.fromLTWH(_textLeft, y, _textRight - _textLeft, 2),
        _pink,
      );
      if (_blink < .5 && !_saving) {
        final x = _field.x + _textWidth(_field) + 1;
        const caretH = 22.0;
        final cy = _field.y + _field.fontSize / 2;
        canvas.drawRect(Rect.fromLTWH(x, cy - caretH / 2, 2, caretH), _pink);
      }
    }
    // Saving: the spinner where the ✓ / ✕ column was.
    if (_saving) {
      paintSettingsSpinner(canvas, spinnerCenter, _spin, _ring);
    }
  }

  /// The save spinner's centre: the middle of the ✓ / ✕ column.
  Offset get spinnerCenter => Offset(width - padX - button / 2, height / 2);

  double _textWidth(MenuText t) => t.text.isEmpty ? 0 : t.width;
}

/// The overlay name of the hidden keyboard field ([PlayerNameInput]).
const String kPlayerNameOverlay = 'playerName';

/// WP-NAME the system keyboard for [SettingsPlayerCard]: an invisible
/// [EditableText] that takes the typing (no autocorrect, no suggestions,
/// at most 14 characters, Enter = done). The card draws the text; this
/// widget only reports it.
class PlayerNameInput extends StatefulWidget {
  const PlayerNameInput({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onSubmitted,
    this.readOnly,
  });

  final String initial;

  /// True while the card saves: no typing, the keyboard goes down (and
  /// comes back when it turns false with the focus still here).
  final ValueListenable<bool>? readOnly;
  final void Function(String text) onChanged;
  final void Function() onSubmitted;

  @override
  State<PlayerNameInput> createState() => PlayerNameInputState();
}

class PlayerNameInputState extends State<PlayerNameInput> {
  static final ValueListenable<bool> _never = ValueNotifier(false);

  late final TextEditingController controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode focus = FocusNode(debugLabel: 'playerName');
  final GlobalKey<EditableTextState> _field = GlobalKey();

  @override
  void initState() {
    super.initState();
    // WP-N2 (no keyboard on the Pixel 8): `autofocus` alone never worked
    // here. GameWidget puts the overlays inside its own FocusScope whose
    // focused child is the game's Focus node, and autofocus only applies
    // in a scope WITHOUT a focused child — so the field never got focus,
    // never attached to the text input and never showed the keyboard.
    // It asks for both explicitly once it is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => requestKeyboard());
  }

  /// Takes the focus (which attaches the field to the platform text input
  /// and shows the keyboard) or, when it already has it, shows the
  /// keyboard again.
  void requestKeyboard() {
    if (!mounted) return;
    final field = _field.currentState;
    if (field != null) {
      field.requestKeyboard();
    } else {
      focus.requestFocus();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      width: 220,
      height: 40,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0,
          // The app has no WidgetsApp: the editing shortcuts (hardware
          // backspace, arrows on desktop) come from here.
          child: DefaultTextEditingShortcuts(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.readOnly ?? _never,
              builder: (context, readOnly, _) => EditableText(
                key: _field,
                readOnly: readOnly,
                controller: controller,
                focusNode: focus,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kCustomNameMax),
                ],
                style: const TextStyle(fontSize: 20, color: Color(0xFF000000)),
                cursorColor: const Color(0xFF000000),
                backgroundCursorColor: const Color(0xFF000000),
                onChanged: (t) {
                  // The card draws the caret at the end: keep it there.
                  final end = TextSelection.collapsed(offset: t.length);
                  if (controller.selection != end) controller.selection = end;
                  widget.onChanged(t);
                },
                onSubmitted: (_) => widget.onSubmitted(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _GlyphKind { pencil, check, cross }

/// The white glyph on a 30 pt button: ✎, ✓ or ✕.
class _Glyph extends PositionComponent {
  _Glyph(this.kind) : super(size: Vector2.all(SettingsPlayerCard.button));

  final _GlyphKind kind;
  final Paint _p = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _fill = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void render(Canvas canvas) {
    const c = SettingsPlayerCard.button / 2;
    switch (kind) {
      case _GlyphKind.pencil:
        // A pencil at 45°, tip bottom-left (the design's ✎).
        canvas.save();
        canvas.translate(c, c);
        canvas.rotate(-math.pi / 4);
        canvas.drawRect(const Rect.fromLTWH(-3.5, -9, 7, 12), _fill);
        canvas.drawRect(const Rect.fromLTWH(-3.5, -11.5, 7, 1.6), _fill);
        canvas.drawPath(
          Path()
            ..moveTo(-3.5, 4)
            ..lineTo(3.5, 4)
            ..lineTo(0, 9.5)
            ..close(),
          _fill,
        );
        canvas.restore();
      case _GlyphKind.check:
        _p.strokeWidth = 2.6;
        canvas.drawPath(
          Path()
            ..moveTo(c - 6.5, c + .5)
            ..lineTo(c - 2, c + 5)
            ..lineTo(c + 7, c - 5),
          _p,
        );
      case _GlyphKind.cross:
        _p.strokeWidth = 2.4;
        canvas.drawLine(
          const Offset(c - 5.5, c - 5.5),
          const Offset(c + 5.5, c + 5.5),
          _p,
        );
        canvas.drawLine(
          const Offset(c + 5.5, c - 5.5),
          const Offset(c - 5.5, c + 5.5),
          _p,
        );
    }
  }
}
