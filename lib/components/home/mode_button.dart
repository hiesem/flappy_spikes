import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Cubic, Curves;

import '../../game/config.dart';
import '../../menu/home_mode.dart';
import 'menu_primitives.dart';

/// The mock's `cubic-bezier(.3, 1.4, .5, 1)`: the parts' slide overshoot.
const Cubic kModeSwapCurve = Cubic(0.3, 1.4, 0.5, 1);

/// The mock's `cubic-bezier(.3, 1.6, .5, 1)`: the VS tag's pop.
const Cubic kVsTagPopCurve = Cubic(0.3, 1.6, 0.5, 1);

/// PRD-2.2 §2.1 the Home mode button (approved `screen_mode_toggle3.html`):
/// a flat two-part strip — the gold MODE part and the pale mode field
/// ("VERSUS" pink / "FREE FLY" teal). In VERSUS the MODE part is on the
/// left, in FREE FLY on the right; on a switch both parts slide over in
/// 0.22 s with a small overshoot and the field colour cross-fades. Press:
/// 96 % (no shade); hit area: the button plus 6 pt (§2.2). The tap goes
/// to [onPressed] (the game's `toggleHomeMode`).
class ModeButton extends MenuButton {
  ModeButton({
    required Rect rect,
    required HomeMode mode,
    required super.onPressed,
    super.isActive,
  }) : _mode = mode,
       super(
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
         pressedTo: Config.homeModePressedScale,
         pressShade: false,
       ) {
    _fieldText = MenuText(
      _label(mode),
      fontSize: Config.homeModeFieldFontSize,
      color: _textOf(mode),
      letterSpacingEm: Config.homeModeFieldLetterSpacing,
      anchor: Anchor.center,
    );
    _partText = MenuText(
      'MODE',
      fontSize: Config.homeModePartFontSize,
      color: Config.homeModePlum,
      letterSpacingEm: Config.homeModePartLetterSpacing,
      anchor: Anchor.center,
    );
    field = _Fill(
      size: Vector2(fieldWidth, rect.height),
      color: _fieldOf(mode),
      label: _fieldText,
    );
    part = _Fill(
      size: Vector2(Config.homeModePartWidth, rect.height),
      color: Config.menuGold,
      label: _partText,
    );
    _swap = 1;
    _fromMode = mode;
    _place();
  }

  static String _label(HomeMode m) =>
      m == HomeMode.versus ? 'VERSUS' : 'FREE FLY';
  static Color _fieldOf(HomeMode m) => m == HomeMode.versus
      ? Config.homeModeVersusField
      : Config.homeModeFreeFlyField;
  static Color _textOf(HomeMode m) => m == HomeMode.versus
      ? Config.homeModeVersusText
      : Config.homeModeFreeFlyText;

  double get fieldWidth => size.x - Config.homeModePartWidth;

  late final MenuText _fieldText;
  late final MenuText _partText;

  /// The pale mode field and the gold MODE part (tests, screenshots).
  late final PositionComponent field;
  late final PositionComponent part;

  HomeMode _mode;
  HomeMode _fromMode = HomeMode.versus;

  /// 0..1 progress of the current swap (1 = at rest).
  double _swap = 1;

  /// The mode shown.
  HomeMode get mode => _mode;

  /// The field's label ("VERSUS" / "FREE FLY").
  String get label => _fieldText.text;

  /// The field's current colour (cross-fading during a swap).
  Color get fieldColor => (field as _Fill).color;

  /// Whether a swap is animating.
  bool get swapping => _swap < 1;

  /// Shows [m]; [animate] slides the parts over (a tap), else jumps (the
  /// screen's first build, a reset).
  void setMode(HomeMode m, {bool animate = true}) {
    if (m == _mode && !swapping) return;
    _fromMode = animate ? _mode : m;
    _mode = m;
    _swap = animate ? 0 : 1;
    _fieldText.text = _label(m);
    _place();
  }

  /// x of the MODE part / the field in mode [m].
  double _partX(HomeMode m) => m == HomeMode.versus ? 0 : fieldWidth;
  double _fieldX(HomeMode m) =>
      m == HomeMode.versus ? Config.homeModePartWidth : 0;

  void _place() {
    final k = kModeSwapCurve.transform(_swap.clamp(0.0, 1.0));
    double lerp(double a, double b) => a + (b - a) * k;
    part.position.x = lerp(_partX(_fromMode), _partX(_mode));
    field.position.x = lerp(_fieldX(_fromMode), _fieldX(_mode));
    final c = Curves.ease.transform(_swap.clamp(0.0, 1.0));
    (field as _Fill).color = Color.lerp(_fieldOf(_fromMode), _fieldOf(_mode), c)!;
    _fieldText.color = Color.lerp(_textOf(_fromMode), _textOf(_mode), c)!;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_swap < 1) {
      _swap = (_swap + dt / Config.homeModeSwapDuration).clamp(0.0, 1.0);
      _place();
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(ClipComponent.rectangle(size: size.clone(), children: [field, part]));
  }

  /// §2.2: the whole button plus [Config.homeModeHitPadding] all round.
  @override
  bool containsLocalPoint(Vector2 point) {
    if (!tappable || !(isActive?.call() ?? true)) return false;
    const p = Config.homeModeHitPadding;
    return point.x >= -p &&
        point.y >= -p &&
        point.x <= size.x + p &&
        point.y <= size.y + p;
  }
}

/// A flat fill with a centred label (one part of the mode button).
class _Fill extends PositionComponent {
  _Fill({required super.size, required this.color, required this.label});

  Color color;
  final MenuText label;
  final Paint _paint = Paint();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    label.position = size / 2;
    add(label);
  }

  @override
  void render(Canvas canvas) {
    _paint.color = color;
    canvas.drawRect(size.toRect(), _paint);
  }
}

/// PRD-2.2 §2.1 the gold VS tag on START's top-left corner (VERSUS only),
/// styled like the Skins NEW tag: pops in (scale 0.4 -> 1, 0.22 s) when
/// VERSUS is chosen, fades out (0.18 s, shrinking back as in the mock)
/// when FREE FLY is chosen.
class VsTag extends PositionComponent {
  VsTag({required Rect rect, required bool visible})
    : _t = 1,
      _shown = visible,
      super(
        position: rect.center.toVector2(),
        size: rect.size.toVector2(),
        anchor: Anchor.center,
      ) {
    _apply();
  }

  bool _shown;

  /// 0..1 progress of the current transition (1 = at rest).
  double _t;
  double _opacity = 1;
  final Paint _paint = Paint()..color = Config.menuGold;
  late final MenuText _text = MenuText(
    'VS',
    fontSize: Config.homeVsTagFontSize,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: Config.homeVsTagLetterSpacing,
    anchor: Anchor.center,
  );

  /// Whether the tag is (becoming) visible.
  bool get shown => _shown;

  /// Current opacity (0 hidden, 1 shown).
  double get opacity => _opacity;

  void setShown(bool value, {bool animate = true}) {
    if (value == _shown) return;
    _shown = value;
    _t = animate ? 0 : 1;
    _apply();
  }

  void _apply() {
    final t = _t.clamp(0.0, 1.0);
    if (_shown) {
      // Opacity over 0.18 s, the pop over 0.22 s (both from the same start).
      final o = (t * Config.homeVsTagPopDuration / Config.homeVsTagFadeDuration)
          .clamp(0.0, 1.0);
      _opacity = o;
      final k = kVsTagPopCurve.transform(t);
      scale.setAll(Config.homeVsTagFromScale + (1 - Config.homeVsTagFromScale) * k);
    } else {
      final o = (t * Config.homeVsTagPopDuration / Config.homeVsTagFadeDuration)
          .clamp(0.0, 1.0);
      _opacity = 1 - o;
      final k = kVsTagPopCurve.transform(t);
      scale.setAll(1 - (1 - Config.homeVsTagFromScale) * k);
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _text.position = size / 2;
    add(_text);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_t < 1) {
      _t = (_t + dt / Config.homeVsTagPopDuration).clamp(0.0, 1.0);
      _apply();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (_opacity <= 0) return;
    if (_opacity >= 1) {
      super.renderTree(canvas);
      return;
    }
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, _opacity));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}
