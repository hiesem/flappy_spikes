import 'package:flame_forge2d/flame_forge2d.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../skins/look.dart';
import 'look_component.dart';

/// The player bird: circle body at (80, viewHeight / 2), drawn with the
/// equipped 2.0 look (bird + gear + hat, [LookComponent]) whose art body
/// centre sits on the physics body centre — the 1.0 bird box, so the hitbox
/// and physics are independent of the look (PRD-menu-v2 §3.1/§3.8).
///
/// The look follows `menu.items` while any bird is on screen; the run bird
/// blends 35 % toward the stage foreground from stage 5 ([LookComponent.blend],
/// `Config.skinStageBlend`). Death keeps the look and switches to the frozen
/// dead pose, so hat and gear tumble with the body.
class Bird extends BodyComponent<FlappySpikesGame> with ContactCallbacks {
  Bird() : super(priority: 10, renderBody: false);

  late final LookComponent _look;

  bool _dead = false;
  double _spriteOpacity = 1;

  bool get dead => _dead;

  /// The look currently drawn (follows `menu.items`).
  Look get look => _look.look;

  /// Exposed for tests.
  LookComponent get lookComponent => _look;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _look = LookComponent(
      look: game.menu.items.look,
      artScale: Config.lookScale,
      opacity: _spriteOpacity,
    );
    add(_look);
    game.menu.items.addListener(_onItemsChanged);
  }

  @override
  void onRemove() {
    game.menu.items.removeListener(_onItemsChanged);
    super.onRemove();
  }

  /// Equipping an item (skin shop) swaps the look in place.
  void _onItemsChanged() {
    _look.look = game.menu.items.look;
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
    _look.playFlap();
    game.sound.play(Sfx.flap);
  }

  /// Death animation: dead pose (hat and gear stay attached), up-right
  /// impulse, restitution 0.1, spin 5pi rad/s.
  void die() {
    if (_dead) {
      return;
    }
    _dead = true;
    _look.showDead();
    body.setFixedRotation(false);
    body.linearVelocity.setZero();
    final impulse = Config.deathVelocity.clone()..scale(body.mass);
    body.applyLinearImpulse(impulse);
    body.angularVelocity = Config.deathSpin;
    for (final fixture in body.fixtures) {
      fixture.restitution = Config.deathRestitution;
    }
  }

  /// Fade the bird art (game over; hidden while on the home screen, which
  /// draws its own bird). Safe before [onLoad].
  void setSpriteOpacity(double value) {
    _spriteOpacity = value;
    if (isLoaded) {
      _look.opacity = value;
    }
  }

  double get spriteOpacity => _spriteOpacity;

  @override
  void update(double dt) {
    super.update(dt);
    // Identity colours in menus / stages 0-4, blended toward the stage
    // foreground from stage 5 (follows the colour crossfade).
    _look
      ..blend = game.skinBlend
      ..blendColor = game.foregroundColor;
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
