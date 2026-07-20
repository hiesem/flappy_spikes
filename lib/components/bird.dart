import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart';

/// The player bird: circle body at (80, 284), 2-frame fly/flap animations,
/// death animation on game over.
class Bird extends BodyComponent<FlappySpikesGame> with ContactCallbacks {
  Bird() : super(priority: 10, renderBody: false);

  late final SpriteAnimationComponent _animationComponent;
  late final SpriteAnimation _idleAnimation;
  late final SpriteAnimation _flapAnimation;
  late final Sprite _deadSprite;

  bool _dead = false;
  double _flapTimer = 0;

  bool get dead => _dead;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final bird = Sprite(await game.images.load('bird.png'));
    final flap = Sprite(await game.images.load('bird_flap.png'));
    _deadSprite = Sprite(await game.images.load('bird_dead.png'));
    _idleAnimation = SpriteAnimation.spriteList(
      [bird, flap],
      stepTime: Config.idleFrameTime,
    );
    _flapAnimation = SpriteAnimation.spriteList(
      [flap, bird],
      stepTime: Config.flapFrameTime,
      loop: false,
    );
    _animationComponent = SpriteAnimationComponent(
      animation: _idleAnimation,
      size: Config.birdSize,
      anchor: Anchor.center,
    );
    add(_animationComponent);
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
    _animationComponent.animation = _flapAnimation;
    _flapTimer = 2 * Config.flapFrameTime;
    game.sound.play(Sfx.flap);
  }

  /// Death animation: dead texture, up-right impulse, restitution 0.1,
  /// spin 5pi rad/s.
  void die() {
    if (_dead) {
      return;
    }
    _dead = true;
    _animationComponent.animation = SpriteAnimation.spriteList(
      [_deadSprite],
      stepTime: 1,
      loop: false,
    );
    body.setFixedRotation(false);
    body.linearVelocity.setZero();
    final impulse = Config.deathVelocity.clone()..scale(body.mass);
    body.applyLinearImpulse(impulse);
    body.angularVelocity = Config.deathSpin;
    for (final fixture in body.fixtures) {
      fixture.restitution = Config.deathRestitution;
    }
  }

  /// Fade the bird sprite out (used on game over).
  void setSpriteOpacity(double value) => _animationComponent.opacity = value;

  @override
  void update(double dt) {
    super.update(dt);
    if (_flapTimer > 0) {
      _flapTimer -= dt;
      if (_flapTimer <= 0 && !_dead) {
        _animationComponent.animation = _idleAnimation;
      }
    }
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
