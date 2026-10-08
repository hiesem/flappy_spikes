import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/sound.dart';
import '../run/run_layers.dart';
import '../skins/look.dart';
import 'look_component.dart';

/// The player bird: circle body at (70, viewHeight / 2), drawn with the
/// equipped 2.0 look (bird + gear + hat, [LookComponent]) whose art body
/// centre sits on the physics body centre — the 1.0 bird box, so the hitbox
/// and physics are independent of the look (PRD-menu-v2 §3.1/§3.8).
///
/// The look follows `menu.items` while any bird is on screen; the run bird
/// blends 35 % toward the stage foreground from stage 5 ([LookComponent.blend],
/// `Config.skinStageBlend`). Death keeps the look and switches to the frozen
/// dead pose, so hat and gear tumble with the body.
///
/// PRD-2 (WP-1a): Forge2D only integrates the vertical motion (gravity, a
/// flap sets vy −370, max fall 650); every contact — rim ends, pass plane,
/// spikes — is plain math in `lib/run/physics/` (no fixtures collide). On
/// death the body turns kinematic and the run drives it from the §3.0.5
/// tumble ([placeTumble]).
class Bird extends BodyComponent<FlappySpikesGame> {
  Bird() : super(priority: RunLayer.bird, renderBody: false);

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
        // Plain-math contacts only (PRD-2 §7): nothing collides in Forge2D.
        ..filter.maskBits = 0,
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
    // WP-3b: input is ignored while a portal ride drives the bird (§3.12).
    if (_ride) return;
    body.linearVelocity.setZero();
    final impulse = Vector2(0, -Config.flapVelocity * body.mass);
    body.applyLinearImpulse(impulse);
    _look.playFlap();
    game.sound.play(Sfx.flap);
  }

  /// §3.0.5 death: the dead pose (white X eyes; hat and gear stay
  /// attached); the body turns kinematic and is drawn behind the tooth tips
  /// ([RunLayer.deadBird]). The run's `DeathTumble` moves it through
  /// [placeTumble].
  void die() {
    if (_dead) {
      return;
    }
    _dead = true;
    _spinVelocity = 0;
    if (isLoaded) {
      _look.showDead();
      body
        ..setType(BodyType.kinematic)
        ..linearVelocity.setZero()
        ..angularVelocity = 0;
    }
    priority = RunLayer.deadBird;
  }

  /// §3.0.5 tumble frame: the bird's screen centre and angle.
  void placeTumble(Vector2 screen, double angle) {
    if (!isLoaded) return;
    body.setTransform(screen, angle);
  }

  // region WP-1a — rim knock (PRD-2 §3.0.4 2–3)
  double _spinVelocity = 0;
  double _spin = 0;

  /// Sets the flight state after a rim push-out / save bounce.
  void setFlight({required double y, required double vy}) {
    if (!isLoaded || _dead) return;
    body
      ..setTransform(Vector2(body.position.x, y), body.angle)
      ..linearVelocity.setValues(0, vy);
  }

  /// §3.0.4 3 a rim hit: one full turn at [omega] rad/s (0.35 s).
  void startRimSpin(double omega) {
    if (_dead) return;
    _spinVelocity = omega;
    _spin = 0;
  }

  /// True while the rim-hit turn plays.
  bool get spinning => _spinVelocity != 0;

  void _stepSpin(double dt) {
    if (_spinVelocity == 0 || _dead || !isLoaded) return;
    _spin += _spinVelocity * dt;
    if (_spin.abs() >= 2 * math.pi) {
      _spin = 0;
      _spinVelocity = 0;
    }
    body.setTransform(body.position, _spin);
  }
  // endregion WP-1a

  // region WP-2d — phoenix rise (PRD-2 §3.14, §5.9)
  /// §5.9 the burst: the X eyes open (alive pose) while the phoenix still
  /// drives the kinematic body.
  void phoenixAlive() {
    _dead = false;
    _spinVelocity = 0;
    if (isLoaded) _look.showAlive();
  }

  /// §5.9 a wing beat while hovering after the burst.
  void phoenixFlap() {
    if (isLoaded) _look.playFlap();
  }

  /// §3.14 straight back in: a dynamic flying bird at ([Config.birdX], [y]),
  /// upright, at rest (the caller flaps it), drawn at its normal layer.
  void reviveFlight(double y) {
    _dead = false;
    _spinVelocity = 0;
    _spin = 0;
    priority = RunLayer.bird;
    if (!isLoaded) return;
    _look.showAlive();
    body
      ..setType(BodyType.dynamic)
      ..setTransform(Vector2(Config.birdX, y), 0)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
    body.gravityScale = Vector2.all(1);
  }
  // endregion WP-2d

  // region WP-3b — portal rides (PRD-2 §3.12, §5.12b)
  bool _ride = false;

  /// A portal ride drives the bird (kinematic; flaps ignored).
  bool get inRide => _ride;

  /// §3.12 the ride takes the bird over at its current position.
  void beginRide() {
    _ride = true;
    _spinVelocity = 0;
    _spin = 0;
    if (!isLoaded) return;
    body
      ..setType(BodyType.kinematic)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
  }

  /// One ride frame: screen centre, angle, scale (squash / storm depth);
  /// [hidden] in the cannon barrel, the volcano or the rocket.
  void placeRide(
    Vector2 screen,
    double angle, {
    double scale = 1,
    bool hidden = false,
  }) {
    if (!isLoaded) return;
    body.setTransform(screen, angle);
    _look
      ..scale.setValues(scale, scale)
      ..opacity = hidden ? 0 : _spriteOpacity;
  }

  /// §3.12 home: a dynamic flying bird at ([Config.birdX], [y]), upright,
  /// at rest, at its normal layer.
  void endRide(double y) {
    _ride = false;
    priority = RunLayer.bird;
    if (!isLoaded) return;
    _look
      ..scale.setValues(1, 1)
      ..opacity = _spriteOpacity;
    body
      ..setType(BodyType.dynamic)
      ..setTransform(Vector2(Config.birdX, y), 0)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
    body.gravityScale = Vector2.all(1);
  }
  // endregion WP-3b

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
      // Forge2D never moves the bird sideways: the world scrolls at its
      // forward speed instead (PRD-2 §7).
      if (body.linearVelocity.x != 0) body.linearVelocity.x = 0;
    }
    _stepSpin(dt);
  }
}
