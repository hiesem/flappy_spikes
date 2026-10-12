import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';
import 'home/menu_primitives.dart';
import 'skins/celebration.dart' show keyframe;
import 'ui/fadable_text.dart';
import 'ui/sprite_button.dart';
import 'ui/text_button.dart';

/// Settings screen (PRD-home-v3 §8), opened from the home gear: SOUND
/// EFFECTS toggle row, MUSIC volume slider row, RUMBLE toggle row, music
/// credit, the DELETE MY DATA row (PRD-2 §3.13), privacy-policy link and
/// RESTORE PURCHASES. The back button sits
/// in the shared top-left spot ([backButton] is the transparent tap target
/// over the game's shared `MenuCornerBox`, as on the Shop / Skins). Tinted labels,
/// natively pink buttons; a full-screen blocker behind the rows consumes
/// stray taps so they cannot start the game while the panel is open.
///
/// Setters are safe to call before [onLoad] has run: values are stored and
/// applied once the children exist.
class SettingsPanel extends PositionComponent
    implements OpacityProvider, Tintable {
  SettingsPanel({
    required this.muted,
    required this.musicVolume,
    required this.onToggleSound,
    required this.onMusicVolume,
    required this.onBack,
    required this.onPrivacyPolicy,
    this.onRestorePurchases,
    this.rumble = true,
    this.onToggleRumble,
    this.onDeleteMyData,
    this.onPrivacyOptions,
  }) : super(priority: 20);

  bool muted;
  double musicVolume;

  /// The RUMBLE switch (PRD-2 §3.33).
  bool rumble;

  /// RUMBLE row tap (the game flips the setting and calls [setRumble]).
  final void Function()? onToggleRumble;
  final void Function() onToggleSound;
  final void Function(double volume) onMusicVolume;
  final void Function() onBack;
  final void Function() onPrivacyPolicy;

  /// "RESTORE PURCHASES" link below the privacy link (PRD-1 §3.7); hidden
  /// when null.
  final void Function()? onRestorePurchases;

  /// The DELETE MY DATA row (PRD-2 §3.13 / Q22): the game shows the confirm
  /// dialog, runs the callable and reports the result. Hidden when null.
  final void Function()? onDeleteMyData;

  /// PRD-2.2 §7.9 the "Privacy options" link under "Privacy Policy": shown
  /// only when the UMP privacy options are required (EEA/UK); hidden when
  /// null (not required, iOS, Linux).
  final void Function()? onPrivacyOptions;

  late final FadableTextComponent _title;
  late final SpriteButton _sfxButton;
  late final FadableTextComponent _sfxLabel;
  late final SpriteComponent _musicIcon;
  late final VolumeSlider _slider;
  late final FadableTextComponent _credit;
  late final RumbleToggle _rumbleButton;
  late final FadableTextComponent _rumbleLabel;
  late final DeleteDataIcon? _deleteIcon;
  late final FadableTextComponent? _deleteLabel;
  late final TextButton _privacyLink;
  TextButton? _privacyOptionsLink;

  /// The "Privacy options" link (tests); null when hidden.
  TextButton? get privacyOptionsLink => _privacyOptionsLink;

  /// The "Privacy Policy" link (tests).
  TextButton get privacyLink => _privacyLink;

  /// The back button's tap target (x 14, y 58, 38 x 38; the pink box and
  /// chevron are the game's shared corner box below the panel).
  late final MenuButton backButton;

  /// The RUMBLE toggle (tests).
  RumbleToggle get rumbleButton => _rumbleButton;
  RestoreLink? _restoreLink;

  /// The restore-purchases link (tests).
  RestoreLink? get restoreLink => _restoreLink;

  /// The DELETE MY DATA row's icon (tests); null when the row is hidden.
  DeleteDataIcon? get deleteIcon => _deleteIcon;

  /// The DELETE MY DATA row's label (tests); null when the row is hidden.
  FadableTextComponent? get deleteLabel => _deleteLabel;
  late Sprite _soundSprite;
  late Sprite _muteSprite;

  double _opacity = 1;
  Color _tint = const Color(0xFF828282);

  // Vertical layout, all derived from the playfield center Y (the mock's
  // rows at 711: Config.settings*Dy). Row composition: 30x30 icon centred
  // at x 85, content from x 130.
  static const double _titleDy = Config.settingsTitleDy;
  static const double _sfxRowDy = Config.settingsSfxRowDy;
  static const double _musicRowDy = Config.settingsMusicRowDy;
  static const double _rumbleRowDy = Config.settingsRumbleRowDy;
  static const double _creditDy = Config.settingsCreditDy;
  static const double _iconX = Config.settingsIconX;
  static const double _contentX = Config.settingsContentX;

  /// The DELETE MY DATA row (PRD-2 §3.13): [deleteRowGap] above the
  /// privacy-policy link, so on a 568 pt screen it sits in the free band
  /// between the music credit and the link and can never collide with the
  /// bottom spike strip (the mock's own band, design/menu_v2/settings_v3.png).
  static Vector2 deleteRowPositionFor(double centerY) =>
      Vector2(_iconX, Config.privacyLinkPositionFor(centerY).y - deleteRowGap);
  static const double deleteRowGap = 60;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final game = findGame()! as FlappySpikesGame;
    final images = game.images;
    final centerY = game.viewHeight / 2;
    _soundSprite = Sprite(await images.load('soundbutton.png'));
    _muteSprite = Sprite(await images.load('mutebutton.png'));

    _title = FadableTextComponent(
      text: 'SETTINGS',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 28),
      position: Vector2(160, centerY + _titleDy),
      anchor: Anchor.center,
    );
    _sfxButton = SpriteButton(
      sprite: muted ? _muteSprite : _soundSprite,
      size: Config.settingsButtonSize,
      position: Vector2(_iconX, centerY + _sfxRowDy),
      anchor: Anchor.center,
      onPressed: onToggleSound,
    );
    _sfxLabel = FadableTextComponent(
      text: 'SOUND EFFECTS',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 18),
      position: Vector2(_contentX, centerY + _sfxRowDy),
      anchor: Anchor.centerLeft,
    );
    _musicIcon = SpriteComponent(
      sprite: Sprite(await images.load('music_note.png')),
      size: Config.settingsButtonSize,
      position: Vector2(_iconX, centerY + _musicRowDy),
      anchor: Anchor.center,
    );
    _slider = VolumeSlider(
      value: musicVolume,
      onChanged: onMusicVolume,
      position: Vector2(
        _contentX,
        centerY + _musicRowDy - VolumeSlider.hitHeight / 2,
      ),
    );
    _credit = FadableTextComponent(
      text: 'Music by ElectroBaptist',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 15),
      position: Vector2(160, centerY + _creditDy),
      anchor: Anchor.center,
    );
    _rumbleButton = RumbleToggle(
      on: rumble,
      position: Vector2(_iconX, centerY + _rumbleRowDy),
      onPressed: () => onToggleRumble?.call(),
    );
    _rumbleLabel = FadableTextComponent(
      text: 'RUMBLE',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 18),
      position: Vector2(_contentX, centerY + _rumbleRowDy),
      anchor: Anchor.centerLeft,
    );
    final deleteRow = onDeleteMyData;
    if (deleteRow != null) {
      final at = deleteRowPositionFor(centerY);
      _deleteIcon = DeleteDataIcon(
        position: at,
        onPressed: deleteRow,
      );
      _deleteLabel = FadableTextComponent(
        text: 'DELETE MY DATA',
        style: const TextStyle(fontFamily: Config.uiFont, fontSize: 18),
        position: Vector2(_contentX, at.y),
        anchor: Anchor.centerLeft,
      );
    }
    final backRect = Config.menuScreenBackRectFor(game.viewHeight);
    backButton = MenuButton(
      position: backRect.topLeft.toVector2(),
      size: backRect.size.toVector2(),
      onPressed: onBack,
      priority: 1,
    );
    _privacyLink = TextButton(
      text: 'Privacy Policy',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 18),
      position:
          Config.privacyLinkPositionFor(centerY) -
          Vector2(
            0,
            onPrivacyOptions != null
                ? Config.settingsPrivacyLinkLiftWithOptions
                : 0,
          ),
      anchor: Anchor.center,
      onPressed: onPrivacyPolicy,
    );
    final options = onPrivacyOptions;
    if (options != null) {
      _privacyOptionsLink = TextButton(
        text: 'Privacy options',
        style: const TextStyle(
          fontFamily: Config.uiFont,
          fontSize: Config.settingsPrivacyOptionsFontSize,
        ),
        position: Config.settingsPrivacyOptionsPositionFor(centerY),
        anchor: Anchor.center,
        padding: Config.settingsPrivacyOptionsPadding,
        onPressed: options,
      );
    }
    // First child = bottom-most: swallows every tap the buttons miss so the
    // tap catcher cannot start the game behind the open panel.
    add(_TapBlocker(size: Vector2(Config.worldWidth, game.viewHeight)));
    addAll([
      _title,
      _sfxButton,
      _sfxLabel,
      _musicIcon,
      _slider,
      _rumbleButton,
      _rumbleLabel,
      _credit,
      backButton,
    ]);
    final deleteIcon = _deleteIcon;
    final deleteLabel = _deleteLabel;
    if (deleteIcon != null && deleteLabel != null) {
      addAll([deleteIcon, deleteLabel]);
    }
    add(_privacyLink);
    final optionsLink = _privacyOptionsLink;
    if (optionsLink != null) add(optionsLink);
    final restore = onRestorePurchases;
    if (restore != null) {
      _restoreLink = RestoreLink(
        center: Config.settingsRestoreLinkPositionFor(centerY),
        onPressed: restore,
      );
      add(_restoreLink!);
    }
    _apply();
  }

  void _apply() {
    _sfxButton.sprite = muted ? _muteSprite : _soundSprite;
    _title.opacity = _opacity;
    _sfxButton.opacity = _opacity;
    _sfxLabel.opacity = _opacity;
    _musicIcon.opacity = _opacity;
    _slider.opacity = _opacity;
    _credit.opacity = _opacity;
    _rumbleButton.opacity = _opacity;
    _rumbleLabel.opacity = _opacity;
    _deleteIcon?.opacity = _opacity;
    _deleteLabel?.opacity = _opacity;
    _privacyLink.opacity = _opacity;
    _privacyOptionsLink?.opacity = _opacity;
    _restoreLink?.opacity = _opacity;
    _title.setColor(_tint);
    _sfxLabel.setColor(_tint);
    _rumbleLabel.setColor(_tint);
    _deleteLabel?.setColor(_tint);
    _credit.setColor(_tint);
    _slider.setColor(_tint);
    _privacyLink.setColor(_tint);
    _privacyOptionsLink?.setColor(_tint);
  }

  void setMuted(bool value) {
    muted = value;
    if (isLoaded) {
      _sfxButton.sprite = value ? _muteSprite : _soundSprite;
    }
  }

  /// The RUMBLE switch changed: the icon follows; switching on buzzes it.
  void setRumble(bool value) {
    rumble = value;
    if (isLoaded) _rumbleButton.setOn(value, buzz: value);
  }

  void setMusicVolume(double value) {
    musicVolume = value;
    if (isLoaded) {
      _slider.setValue(value);
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (isLoaded) {
      _title.setColor(color);
      _sfxLabel.setColor(color);
      _rumbleLabel.setColor(color);
      _deleteLabel?.setColor(color);
      _credit.setColor(color);
      _slider.setColor(color);
      _privacyLink.setColor(color);
      _privacyOptionsLink?.setColor(color);
    }
  }

  @override
  double get opacity => _opacity;

  @override
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    if (isLoaded) {
      _title.opacity = _opacity;
      _sfxButton.opacity = _opacity;
      _sfxLabel.opacity = _opacity;
      _musicIcon.opacity = _opacity;
      _slider.opacity = _opacity;
      _credit.opacity = _opacity;
      _rumbleButton.opacity = _opacity;
      _rumbleLabel.opacity = _opacity;
      _deleteIcon?.opacity = _opacity;
      _deleteLabel?.opacity = _opacity;
      _privacyLink.opacity = _opacity;
      _privacyOptionsLink?.opacity = _opacity;
      _restoreLink?.opacity = _opacity;
    }
  }
}

/// The DELETE MY DATA icon (PRD-2 §3.13): a 30 pt pink square (the rows'
/// icon slot) with a soft trash can — lid handle, lid, bin and three ribs.
/// Fires on tap-down like the SOUND / RUMBLE rows (a menu knock follows).
class DeleteDataIcon extends PositionComponent with TapCallbacks {
  DeleteDataIcon({
    required super.position,
    required this.onPressed,
  }) : super(size: Vector2.all(30), anchor: Anchor.center);

  final void Function() onPressed;

  double _opacity = 1;
  double get opacity => _opacity;
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    withMenuKnock(this, onPressed);
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    final soft = Config.menuSoft.withValues(alpha: _opacity);
    _fill.color = Config.menuPink.withValues(alpha: _opacity);
    _stroke.color = soft;
    canvas.drawRect(size.toRect(), _fill);
    canvas.drawPath(
      Path()
        ..moveTo(12, 11)
        ..lineTo(12, 8)
        ..quadraticBezierTo(12, 6.5, 13.5, 6.5)
        ..lineTo(16.5, 6.5)
        ..quadraticBezierTo(18, 6.5, 18, 8)
        ..lineTo(18, 11),
      _stroke,
    );
    canvas.drawLine(const Offset(6.5, 11), const Offset(23.5, 11), _stroke);
    canvas.drawPath(
      Path()
        ..moveTo(9.2, 13.5)
        ..lineTo(10.2, 23.6)
        ..lineTo(19.8, 23.6)
        ..lineTo(20.8, 13.5),
      _stroke,
    );
    for (final x in const [12.6, 15.0, 17.4]) {
      canvas.drawLine(Offset(x, 17), Offset(x, 21), _stroke);
    }
  }
}

/// The RUMBLE toggle (PRD-home-v3 §8, mock build73 `PHONE`): a 30 pt pink
/// square (like soundbutton.png) with a soft phone outline; on = vibration
/// marks either side, off = a slash. [setOn] with `buzz` shakes the phone
/// and pops the marks in ([Config.settingsRumbleBuzz]). Fires on tap-down
/// like the SOUND toggle (a menu knock follows, PRD-home-v3 §10).
class RumbleToggle extends PositionComponent with TapCallbacks {
  RumbleToggle({
    required bool on,
    required super.position,
    required this.onPressed,
  }) : super(size: Vector2.all(30), anchor: Anchor.center) {
    _on = on;
  }

  final void Function() onPressed;

  late bool _on;
  bool get on => _on;

  double _opacity = 1;
  double get opacity => _opacity;
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  /// Seconds into the buzz (-1 = idle).
  double _buzzT = -1;

  /// Whether the buzz is running (tests).
  bool get buzzing => _buzzT >= 0;

  static const List<(double, double)> _shake = [
    (0, 0),
    (.12, -1.6),
    (.25, 1.6),
    (.37, -1.4),
    (.5, 1.4),
    (.62, -1),
    (.75, 1),
    (.87, -.5),
    (1, 0),
  ];

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _glyph = Paint();

  void setOn(bool value, {bool buzz = false}) {
    _on = value;
    if (buzz) _buzzT = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_buzzT < 0) return;
    _buzzT += dt;
    if (_buzzT >= Config.settingsRumbleBuzz) _buzzT = -1;
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    withMenuKnock(this, onPressed);
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    final soft = Config.menuSoft.withValues(alpha: _opacity);
    _fill.color = Config.menuPink.withValues(alpha: _opacity);
    _stroke.color = soft;
    _glyph.color = soft;
    canvas.drawRect(size.toRect(), _fill);
    final u = _buzzT < 0 ? 1.0 : _buzzT / Config.settingsRumbleBuzz;
    // Phone body (translateX keyframes while buzzing).
    canvas.save();
    canvas.translate(_buzzT < 0 ? 0 : keyframe(_shake, u), 0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10.5, 5.5, 9, 19),
        const Radius.circular(1.5),
      ),
      _stroke..strokeWidth = 2,
    );
    canvas.drawRect(const Rect.fromLTWH(13.5, 21, 3, 1.4), _glyph);
    canvas.restore();
    if (_on) {
      // Vibration marks; while buzzing they pop in about the centre
      // (opacity 0 -> 1, scale .6 -> 1.15 -> 1, ease-out).
      final e = Curves.easeOut.transform(u);
      final k = _buzzT < 0 ? 1.0 : math.min(1.0, e / .4);
      final scale = _buzzT < 0
          ? 1.0
          : keyframe(const [(0, .6), (.4, 1.15), (1, 1)], e);
      canvas.save();
      canvas.translate(15, 15);
      canvas.scale(scale);
      canvas.translate(-15, -15);
      _stroke
        ..strokeWidth = 2
        ..color = Config.menuSoft.withValues(alpha: _opacity * k);
      for (final (x, top, bottom) in const [
        (7.0, 11.0, 19.0),
        (4.0, 13.0, 17.0),
        (23.0, 11.0, 19.0),
        (26.0, 13.0, 17.0),
      ]) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), _stroke);
      }
      canvas.restore();
    } else {
      canvas.drawLine(
        const Offset(6, 25),
        const Offset(24, 5),
        _stroke..strokeWidth = 2.2,
      );
    }
  }
}

/// Minimal volume slider: a thin track with a round knob. A tap anywhere on
/// the component sets the volume from the tap x; a drag scrubs it. Both
/// consume the gesture so it cannot leak to the tap catcher below.
class VolumeSlider extends PositionComponent with TapCallbacks, DragCallbacks {
  VolumeSlider({required double value, required this.onChanged, super.position})
    : _value = value.clamp(0.0, 1.0),
      super(size: Vector2(trackWidth, hitHeight));

  /// Length of the track (and the 0..1 x range), in points.
  static const double trackWidth = 140;

  /// Height of the tap/drag hit area (the track itself is thinner).
  static const double hitHeight = 24;

  static const double _trackHeight = 4;
  static const double _knobRadius = 6;

  final void Function(double volume) onChanged;

  double _value;
  double get value => _value;

  Color _color = const Color(0xFF828282);
  double _opacity = 1;

  late final RectangleComponent _track;
  late final CircleComponent _knob;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _track = RectangleComponent(
      position: Vector2(0, (hitHeight - _trackHeight) / 2),
      size: Vector2(trackWidth, _trackHeight),
    );
    _knob = CircleComponent(
      radius: _knobRadius,
      anchor: Anchor.center,
      position: Vector2(_knobX, hitHeight / 2),
    );
    addAll([_track, _knob]);
    _applyStyle();
  }

  double get _knobX => _value * trackWidth;

  void setValue(double value) {
    _value = value.clamp(0.0, 1.0);
    if (isLoaded) {
      _knob.position.x = _knobX;
    }
  }

  /// Retints track + knob (color-stage system), preserving the fade opacity.
  void setColor(Color color) {
    _color = color;
    if (isLoaded) {
      _applyStyle();
    }
  }

  double get opacity => _opacity;

  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    if (isLoaded) {
      _applyStyle();
    }
  }

  void _applyStyle() {
    final color = _color.withValues(alpha: _opacity);
    _track.paint.color = color;
    _knob.paint.color = color;
  }

  void _setFromLocalX(double x) {
    setValue(x / trackWidth);
    onChanged(_value);
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _setFromLocalX(event.localPosition.x);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    event.handled = true;
    _setFromLocalX(event.localPosition.x);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    // Once the pointer leaves the component the local position is NaN; keep
    // the last in-bounds value instead of scrubbing to garbage.
    final x = event.localEndPosition.x;
    if (!x.isNaN) {
      _setFromLocalX(x);
    }
  }
}

/// Invisible full-screen tap target behind the panel's controls: consumes
/// taps that no button claimed so they cannot reach the [TapCatcher] (which
/// would start the game) while the settings panel is open.
class _TapBlocker extends PositionComponent with TapCallbacks {
  _TapBlocker({super.size});

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }
}

/// "RESTORE PURCHASES" text link (PRD-1 §3.7): fixed menu pink, 11 pt,
/// letter-spacing .1em, like the Shop's; fires on tap-up with the menu
/// buttons' pressed shade. Fades as one layer with the panel.
class RestoreLink extends PositionComponent with GroupOpacity {
  RestoreLink({required Vector2 center, required void Function() onPressed})
    : button = MenuButton(size: linkSize, onPressed: onPressed),
      super(
        position: center - linkSize / 2,
        size: linkSize,
      );

  static final Vector2 linkSize = Vector2(200, 28);

  final MenuButton button;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    button.add(
      MenuText(
        'RESTORE PURCHASES',
        fontSize: 11,
        color: Config.menuPink,
        letterSpacingEm: 0.1,
        position: linkSize / 2,
        anchor: Anchor.center,
      ),
    );
    add(button);
  }
}
