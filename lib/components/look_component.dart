import 'dart:ui';

import 'package:flame/components.dart';

import '../game/config.dart';
import '../skins/art/look_painter.dart';
import '../skins/look.dart';

/// Which frame sequence a [LookComponent] plays.
enum LookPose { idle, flap, dead }

/// Draws one equipped [Look] (bird + gear + hat) with [LookPainter] — the
/// vector replacement for the PRD-1 `SkinSpriteComponent` sprite sheets.
///
/// Units: the art box is the original 44 x 36 bird box in *art units* (see
/// [LookPainter]) and [artScale] is points per art unit. The component's size
/// is the art box at that scale and it anchors on the art body centre
/// (21, 18), so a parent puts the component at the bird's body centre — the
/// 1.0 hitbox centre — and the whole look (hats, gear, wind-up key) rotates
/// and tumbles with the body.
///
/// Frame timing mirrors the 1.0 bird: idle alternates idle/flap every
/// [Config.idleFrameTime]; [playFlap] shows flap then idle for
/// [Config.flapFrameTime] each and returns to idle; [showDead] switches to the
/// dead pose and freezes both clocks (wing up, X eye — [LookPainter.paint]).
///
/// Two clocks are kept apart: the *pose* clock ([poseTime]) only times the
/// 1.0 wing frames and restarts on every flap, while the *art* clock ([time])
/// is continuous and is handed to [LookPainter.paint] as its `t`. A flap (or
/// the return to idle) therefore never resets the clockwork item animations
/// (the wind-up key, PRD §5.2 "idle-only, no gameplay reactions"); only
/// [showDead] / [paused] freeze them.
///
/// [blend] (0..1) with [blendColor] is the run stage tint, applied at draw
/// time: `c * (1 - blend) + blendColor * blend` on RGB with alpha kept — the
/// `Config.skinStageBlend` rule (SPEC "Skin tint rule"). At 0 the look draws
/// its true colours with no extra layer (menus and stages 0–4).
class LookComponent extends PositionComponent {
  LookComponent({
    required this.look,
    double artScale = 1,
    double opacity = 1,
    double blend = 0,
    this.blendColor = const Color(0xFF000000),
    Anchor? anchor,
    super.position,
    super.priority,
  })  : _opacity = opacity.clamp(0.0, 1.0),
        _blend = blend.clamp(0.0, 1.0) {
    this.anchor = anchor ?? bodyAnchor;
    this.artScale = artScale;
  }

  /// Default anchor: the art body centre (21, 18) of the 44 x 36 art box.
  static const Anchor bodyAnchor = Anchor(21 / 44, 18 / 36);

  /// The look drawn; swapped in place when the player equips another item.
  Look look;

  double _opacity;
  double _blend;

  /// The stage foreground the [blend] factor mixes in.
  Color blendColor;

  LookPose _pose = LookPose.idle;

  /// Wing/frame clock: alternates the idle wing and times the two flap
  /// frames. Restarted by [playFlap] and when the flap pose returns to idle.
  double _poseTime = 0;

  /// Continuous art clock, passed to [LookPainter.paint] as `t`; it drives
  /// the animated gear/hat art and is never reset by a flap.
  double _artTime = 0;

  /// Drives the wing from outside (the live home / Shop idle bird) instead
  /// of the pose clock; null = the 1.0 frame timing below.
  bool? flapOverride;

  /// Freezes both clocks (the wing frames and the gear / hat art) while true.
  /// The live home bird sets it from the screen's idle-clock pause (§8.4) so
  /// an animated item (e.g. the wind-up key) stops turning under a popup, ad
  /// or the debug panel, exactly like the rest of the idle motion.
  bool paused = false;

  /// Draws the eye closed (idle blink, [LookPainter.paint]'s `blink`).
  bool blink = false;

  /// Streak tier 2+ gold bird (PRD-2 §3.0.9 #5): the classic bird turns
  /// gold, other skins get a gold glow outline ([LookPainter.paint]'s
  /// `gold`). Set by the run's streak feature.
  bool goldTier = false;

  final Paint _layerPaint = Paint();

  /// Points per art unit; setting it resizes the component's art box.
  double get artScale => size.x / LookPainter.boxWidth;
  set artScale(double value) {
    size = Vector2(LookPainter.boxWidth * value, LookPainter.boxHeight * value);
  }

  /// 0..1; draws through an alpha layer while < 1 (the bird fade in/out).
  double get opacity => _opacity;
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  /// Stage tint factor; 0 keeps the identity colours.
  double get blend => _blend;
  set blend(double value) => _blend = value.clamp(0.0, 1.0);

  LookPose get pose => _pose;

  /// The continuous art clock in seconds — the `t` handed to
  /// [LookPainter.paint]; frozen only in the [LookPose.dead] pose / [paused].
  double get time => _artTime;

  /// The wing/frame clock in seconds (see the class docs); restarted by
  /// [playFlap], so it differs from [time] during and right after a flap.
  double get poseTime => _poseTime;

  /// Whether the wing is drawn in the flap (down) position right now.
  bool get flapping =>
      _pose != LookPose.dead && (flapOverride ?? _poseFlapping);

  bool get _poseFlapping => switch (_pose) {
        LookPose.dead => false,
        LookPose.flap => _poseTime < Config.flapFrameTime,
        LookPose.idle => (_poseTime ~/ Config.idleFrameTime).isOdd,
      };

  void playFlap() {
    _pose = LookPose.flap;
    _poseTime = 0; // The art clock keeps running through the wing change.
  }

  /// Dead pose (hat and gear stay attached and tumble with the body).
  void showDead() {
    _pose = LookPose.dead;
  }

  /// Back from the dead pose (WP-2d phoenix, PRD-2 §5.9): idle wings.
  void showAlive() {
    if (_pose != LookPose.dead) return;
    _pose = LookPose.idle;
    _poseTime = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_pose == LookPose.dead || paused) {
      return; // Frozen: the dead pose / idle art under an overlay.
    }
    _artTime += dt;
    _poseTime += dt;
    if (_pose == LookPose.flap && _poseTime >= 2 * Config.flapFrameTime) {
      _pose = LookPose.idle;
      _poseTime = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    final needsLayer = _opacity < 1 || _blend > 0;
    if (needsLayer) {
      _layerPaint
        ..color = Color.fromRGBO(255, 255, 255, _opacity)
        ..colorFilter = _blend > 0
            ? ColorFilter.matrix(blendMatrix(_blend, blendColor))
            : null;
      canvas.saveLayer(null, _layerPaint);
    }
    canvas.save();
    // LookPainter draws with the art-box centre at the canvas origin; put it
    // at the art-box centre inside the component's box so local coordinates
    // are art units * artScale (the body centre lands on the anchor).
    canvas.translate(
      LookPainter.boxWidth / 2 * artScale,
      LookPainter.boxHeight / 2 * artScale,
    );
    canvas.scale(artScale);
    LookPainter.paint(
      canvas,
      look,
      t: _artTime,
      flap: flapping,
      dead: _pose == LookPose.dead,
      blink: blink,
      gold: goldTier,
    );
    canvas.restore();
    if (needsLayer) canvas.restore();
  }

  /// The 4x5 [ColorFilter.matrix] of the stage blend: every RGB channel
  /// becomes `c * (1 - blend) + tint * blend`, alpha is kept.
  static List<double> blendMatrix(double blend, Color tint) {
    final keep = 1 - blend;
    return [
      keep, 0, 0, 0, tint.r * 255 * blend, //
      0, keep, 0, 0, tint.g * 255 * blend, //
      0, 0, keep, 0, tint.b * 255 * blend, //
      0, 0, 0, 1, 0, //
    ];
  }
}
