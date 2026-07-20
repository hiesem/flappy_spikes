import 'dart:ui' show BlendMode, Color, ColorFilter;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';

/// A pair of pipes (bottom + top) with a score-dependent gap (145 pt at the
/// start ramping down to 105 pt — see [Config.gapForScore]), a full-height
/// score sensor 111 pt to the right of the pipe center, moving left at
/// 200 pt/s.
///
/// The body origin sits at screen vertical center (y = 284) so the sensor
/// fixture can be centered on it.
class PipePair extends BodyComponent<FlappySpikesGame> implements Tintable {
  PipePair({required this.gapBottomY, this.gap = Config.pipeGap})
      : super(priority: -10, renderBody: false);

  /// Y of the top edge of the bottom pipe (= bottom edge of the gap).
  final double gapBottomY;

  /// Vertical size of the opening between the two pipes.
  final double gap;

  bool scored = false;

  final List<SpriteComponent> _sprites = [];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final pipeSize = Vector2(Config.pipeWidth, Config.pipeHeight);
    final bottom = SpriteComponent(
      sprite: Sprite(await game.images.load('pipe_bottom.png')),
      size: pipeSize,
      position: Vector2(
        -Config.pipeWidth / 2,
        gapBottomY - game.viewHeight / 2,
      ),
    );
    final top = SpriteComponent(
      sprite: Sprite(await game.images.load('pipe_top.png')),
      size: pipeSize,
      anchor: Anchor.bottomLeft,
      position: Vector2(
        -Config.pipeWidth / 2,
        gapBottomY - gap - game.viewHeight / 2,
      ),
    );
    _sprites.addAll([bottom, top]);
    addAll([bottom, top]);
    game.registerTintable(this);
  }

  @override
  Body createBody() {
    const halfW = Config.pipeWidth / 2;
    const halfH = Config.pipeHeight / 2;
    final bodyDef = BodyDef()
      ..type = BodyType.kinematic
      ..position = Vector2(Config.pipeSpawnX, game.viewHeight / 2)
      ..userData = this;
    final body = world.createBody(bodyDef);

    FixtureDef pipeFixture(PolygonShape shape) {
      return FixtureDef(shape)
        ..friction = 0
        ..filter.categoryBits = Config.categoryPipe
        ..filter.maskBits = Config.categoryBird;
    }

    final bottomShape = PolygonShape()
      ..setAsBox(
        halfW,
        halfH,
        Vector2(0, gapBottomY + halfH - game.viewHeight / 2),
        0,
      );
    body.createFixture(pipeFixture(bottomShape));

    final topShape = PolygonShape()
      ..setAsBox(
        halfW,
        halfH,
        Vector2(0, gapBottomY - gap - halfH - game.viewHeight / 2),
        0,
      );
    body.createFixture(pipeFixture(topShape));

    // Full-height score sensor, 111 pt right of the pipe center.
    final sensorShape = PolygonShape()
      ..setAsBox(5, game.viewHeight / 2, Vector2(Config.sensorOffsetX, 0), 0);
    body.createFixture(
      FixtureDef(sensorShape)
        ..isSensor = true
        ..filter.categoryBits = Config.categoryScore
        ..filter.maskBits = Config.categoryBird,
    );
    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);
    body.linearVelocity.setValues(
      game.isScrolling ? -Config.scrollSpeed : 0,
      0,
    );
    if (body.position.x < -Config.pipeWidth) {
      removeFromParent();
    }
  }

  @override
  void setTint(Color color) {
    for (final sprite in _sprites) {
      sprite.paint.colorFilter = ColorFilter.mode(color, BlendMode.modulate);
    }
  }

  @override
  void onRemove() {
    game.unregisterTintable(this);
    super.onRemove();
  }
}
