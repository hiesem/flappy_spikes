import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../game/config.dart';
import '../menu/skin_catalog.dart';

/// The six sprites of one skin: tinted layer + overlay for the idle, flap
/// and dead frames.
class SkinSprites {
  SkinSprites._(this.skin, this.tinted, this.overlay);

  final SkinDef skin;
  final List<Sprite> tinted;
  final List<Sprite> overlay;

  static Future<SkinSprites> load(Images images, SkinDef skin) async {
    final loaded = await Future.wait(skin.images.map(images.load));
    final sprites = loaded.map(Sprite.new).toList();
    return SkinSprites._(skin, sprites.sublist(0, 3), sprites.sublist(3));
  }
}

/// Which frame sequence a [SkinSpriteComponent] plays.
enum SkinPose { idle, flap, dead }

/// Draws a bird skin the way the game does: the tinted layer through a
/// modulate ColorFilter of [tint], then the overlay untinted on top. Used by
/// the physics [Bird] and the home-screen bird, so both always match.
///
/// Frame timing mirrors the 1.0 bird: idle alternates idle/flap every
/// [Config.idleFrameTime]; a flap shows flap then idle for
/// [Config.flapFrameTime] each and returns to idle; dead is a still frame.
/// `filterQuality` stays at the Paint default for the in-run bird; the home
/// screen passes the smoother menu sampling.
class SkinSpriteComponent extends PositionComponent {
  SkinSpriteComponent({
    required this.sprites,
    required Color initialTint,
    FilterQuality filterQuality = FilterQuality.none,
    super.position,
    super.size,
    super.anchor,
    super.priority,
  }) : _tint = initialTint {
    _tintPaint.filterQuality = filterQuality;
    _overlayPaint.filterQuality = filterQuality;
    _updateTintPaint();
  }

  /// Swappable (equipping a skin replaces the sprites in place).
  SkinSprites sprites;
  Color _tint;
  double _opacity = 1;
  SkinPose _pose = SkinPose.idle;
  double _time = 0;

  final Paint _tintPaint = Paint();
  final Paint _overlayPaint = Paint();

  Color get tint => _tint;
  set tint(Color value) {
    if (value == _tint) return;
    _tint = value;
    _updateTintPaint();
  }

  double get opacity => _opacity;
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    _updateTintPaint();
  }

  SkinPose get pose => _pose;

  /// Index of the frame currently drawn: 0 idle, 1 flap, 2 dead.
  int get frame => switch (_pose) {
    SkinPose.dead => 2,
    SkinPose.flap => _time < Config.flapFrameTime ? 1 : 0,
    SkinPose.idle => (_time ~/ Config.idleFrameTime).isEven ? 0 : 1,
  };

  void playFlap() {
    _pose = SkinPose.flap;
    _time = 0;
  }

  void showDead() {
    _pose = SkinPose.dead;
    _time = 0;
  }

  void _updateTintPaint() {
    final alpha = Color.fromRGBO(255, 255, 255, _opacity);
    _tintPaint
      ..color = alpha
      ..colorFilter = ColorFilter.mode(_tint, BlendMode.modulate);
    _overlayPaint.color = alpha;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_pose == SkinPose.flap && _time >= 2 * Config.flapFrameTime) {
      _pose = SkinPose.idle;
      _time = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    final i = frame;
    sprites.tinted[i].render(canvas, size: size, overridePaint: _tintPaint);
    sprites.overlay[i].render(canvas, size: size, overridePaint: _overlayPaint);
  }
}
