import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';
import 'ui/fadable_text.dart';
import 'ui/sprite_button.dart';
import 'ui/text_button.dart';

/// Settings screen, opened from the start scene's gear button: SOUND EFFECTS
/// toggle row, MUSIC volume slider row, music credit, privacy-policy link and
/// a back button. Same visual language as the start panel (tinted labels,
/// natively pink buttons); a full-screen blocker behind the rows consumes
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
  }) : super(priority: 20);

  bool muted;
  double musicVolume;
  final void Function() onToggleSound;
  final void Function(double volume) onMusicVolume;
  final void Function() onBack;
  final void Function() onPrivacyPolicy;

  late final FadableTextComponent _title;
  late final SpriteButton _sfxButton;
  late final FadableTextComponent _sfxLabel;
  late final SpriteComponent _musicIcon;
  late final VolumeSlider _slider;
  late final FadableTextComponent _credit;
  late final SpriteButton _backButton;
  late final TextButton _privacyLink;
  late Sprite _soundSprite;
  late Sprite _muteSprite;

  double _opacity = 1;
  Color _tint = const Color(0xFF828282);

  // Vertical layout, all derived from the playfield center Y (values at the
  // 568 design height in parentheses). Everything stays within the safe band
  // between the spike strips (72 .. viewHeight - 72).
  static const double _titleDy = -140; // (144)
  static const double _sfxRowDy = -45; // (239)
  static const double _musicRowDy = 15; // (299)
  static const double _creditDy = 60; // (344)
  static const double _backDy = 115; // (399)
  // Row composition: 30x30 icon centered at x=85, content from x=115.
  static const double _iconX = 85;
  static const double _contentX = 115;

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
    _backButton = SpriteButton(
      sprite: Sprite(await images.load('back_arrow.png')),
      size: Config.settingsButtonSize,
      position: Vector2(160, centerY + _backDy),
      anchor: Anchor.center,
      onPressed: onBack,
    );
    _privacyLink = TextButton(
      text: 'Privacy Policy',
      style: const TextStyle(fontFamily: Config.uiFont, fontSize: 18),
      position: Config.privacyLinkPositionFor(centerY),
      anchor: Anchor.center,
      onPressed: onPrivacyPolicy,
    );
    // First child = bottom-most: swallows every tap the buttons miss so the
    // tap catcher cannot start the game behind the open panel.
    add(_TapBlocker(size: Vector2(Config.worldWidth, game.viewHeight)));
    addAll([
      _title,
      _sfxButton,
      _sfxLabel,
      _musicIcon,
      _slider,
      _credit,
      _backButton,
    ]);
    add(_privacyLink);
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
    _backButton.opacity = _opacity;
    _privacyLink.opacity = _opacity;
    _title.setColor(_tint);
    _sfxLabel.setColor(_tint);
    _credit.setColor(_tint);
    _slider.setColor(_tint);
    _privacyLink.setColor(_tint);
  }

  void setMuted(bool value) {
    muted = value;
    if (isLoaded) {
      _sfxButton.sprite = value ? _muteSprite : _soundSprite;
    }
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
      _credit.setColor(color);
      _slider.setColor(color);
      _privacyLink.setColor(color);
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
      _backButton.opacity = _opacity;
      _privacyLink.opacity = _opacity;
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
