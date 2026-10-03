import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../menu/skin_catalog.dart';
import 'skin_sprite.dart';

/// The player bird: circle body at (80, viewHeight / 2), drawn with the
/// equipped skin (tinted layer + overlay, see [SkinSpriteComponent]),
/// 2-frame fly/flap animation, death animation on game over.
///
/// The skin canvas is anchored on the body centre (manifest anchor), so the
/// sprite sits exactly where the 1.0 bird did; hitbox and physics are
/// independent of the skin.
class Bird extends BodyComponent<FlappySpikesGame> with ContactCallbacks {
  Bird() : super(priority: 10, renderBody: false);

  late final SkinSpriteComponent _sprite;

  bool _dead = false;
  double _spriteOpacity = 1;

  bool get dead => _dead;

  /// The skin currently drawn (follows `menu.skins` while on the home
  /// screen).
  SkinDef get skin => _sprite.sprites.skin;

  /// Exposed for tests.
  SkinSpriteComponent get skinSprite => _sprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final skin = game.menu.skins.equippedSkin;
    _sprite = SkinSpriteComponent(
      sprites: await SkinSprites.load(game.images, skin),
      initialTint: game.skinTintFor(skin),
      size: Vector2(SkinDef.spriteWidth, SkinDef.spriteHeight),
      anchor: const Anchor(SkinDef.anchorX, SkinDef.anchorY),
    );
    _sprite.opacity = _spriteOpacity;
    add(_sprite);
    game.menu.skins.addListener(_onSkinsChanged);
  }

  @override
  void onRemove() {
    game.menu.skins.removeListener(_onSkinsChanged);
    super.onRemove();
  }

  /// Equipping a skin (Skins screen) swaps the sprites in place.
  Future<void> _onSkinsChanged() async {
    final skin = game.menu.skins.equippedSkin;
    if (skin.id == this.skin.id) return;
    final sprites = await SkinSprites.load(game.images, skin);
    if (isMounted) {
      _sprite.sprites = sprites;
    }
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(Config.birdX, game.viewHeight / 2)
      ..fixedRotation = true
      ..gravityScale = Vector2.zero() // frozen until the game starts
      ..userData = this;
    final body = world.createBody(bodyDef);
    final shape = CircleShape()..radius = Config.birdRadius;
    body.createFixture(
      FixtureDef(shape)
        ..density = 1
        ..friction = 0
        ..restitution = 0
        ..filter.categoryBits = Config.categoryBird
        ..filter.maskBits =
            Config.categoryWorld | Config.categoryPipe | Config.categoryScore,
    );
    return body;
  }

  /// Enables gravity (called when the start scene transitions to playing).
  void enableGravity() {
    body.gravityScale = Vector2.all(1);
  }

  /// Zero the velocity, then apply an upward impulse giving ~370 pt/s delta-v.
  void flap() {
    if (_dead || game.state != GameState.playing) {
      return;
    }
    body.linearVelocity.setZero();
    final impulse = Vector2(0, -Config.flapVelocity * body.mass);
    body.applyLinearImpulse(impulse);
    _sprite.playFlap();
    game.sound.play(Sfx.flap);
  }

  /// Death animation: dead texture, up-right impulse, restitution 0.1,
  /// spin 5pi rad/s.
  void die() {
    if (_dead) {
      return;
    }
    _dead = true;
    _sprite.showDead();
    body.setFixedRotation(false);
    body.linearVelocity.setZero();
    final impulse = Config.deathVelocity.clone()..scale(body.mass);
    body.applyLinearImpulse(impulse);
    body.angularVelocity = Config.deathSpin;
    for (final fixture in body.fixtures) {
      fixture.restitution = Config.deathRestitution;
    }
  }

  /// Fade the bird sprite (game over; hidden while on the home screen,
  /// which draws its own bird). Safe before [onLoad].
  void setSpriteOpacity(double value) {
    _spriteOpacity = value;
    if (isLoaded) {
      _sprite.opacity = value;
    }
  }

  double get spriteOpacity => _spriteOpacity;

  @override
  void update(double dt) {
    super.update(dt);
    // Identity colour in menus / stage 0, blended toward the stage tint in
    // later run stages (follows the colour crossfade).
    _sprite.tint = game.skinTintFor(skin);
    // Terminal velocity (Flappy Bird feel): cap the fall speed so dives stay
    // recoverable. The death toss is exempt — it should tumble freely.
    if (!_dead && game.state == GameState.playing) {
      final vy = body.linearVelocity.y;
      if (vy > Config.maxFallSpeed) {
        body.linearVelocity.y = Config.maxFallSpeed;
      }
    }
  }

  @override
  void beginContact(Object other, Contact contact) {
    super.beginContact(other, contact);
    if (_dead) {
      return;
    }
    final fixture =
        contact.fixtureA.body == body ? contact.fixtureB : contact.fixtureA;
    if (fixture.isSensor) {
      game.onScoreSensor(other);
    } else {
      game.onBirdHit();
    }
  }
}
