import 'dart:ui' show BlendMode, Color, ColorFilter;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';

/// A scrolling spike strip: tiled ground_spikes texture scrolling at
/// 200 pt/s with seamless wrap, backed by a static full-width physics body.
/// The ceiling strip uses the same texture rotated 180 degrees.
class SpikeStrip extends BodyComponent<FlappySpikesGame> implements Tintable {
  SpikeStrip({required this.isCeiling})
    : super(priority: basePriority, renderBody: false);

  /// Draw order during runs (above pipes, below the bird). The game lifts
  /// the ground strip above open menu screens.
  static const int basePriority = -5;

  final bool isCeiling;

  /// Tiles cover the screen width plus 2 extra tiles for seamless wrap.
  static const int _tileCount = 3;
  static const double _wrapWidth = _tileCount * Config.spikeTileWidth;

  final List<SpriteComponent> _tiles = [];

  double _inset = 0;

  /// Visual-only outward shift of the strip art, in points (0 = the full
  /// 72 pt strip). Menus use [Config.menuSpikeInset] so the strips read as
  /// the mocks' 44 pt; the physics body never moves.
  double get visualInset => _inset;
  set visualInset(double value) {
    _inset = value;
    for (final tile in _tiles) {
      tile.position.y = _tileY;
    }
  }

  // Body-local y of a tile: the ceiling tiles are centre-anchored (rotated),
  // the ground tiles top-left anchored.
  double get _tileY =>
      isCeiling ? -_inset : -Config.spikeHeight / 2 + _inset;

  double get _centerY =>
      isCeiling ? Config.spikeHeight / 2 : game.viewHeight - Config.spikeHeight / 2;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final image = await game.images.load('ground_spikes.png');
    for (var i = 0; i < _tileCount; i++) {
      // Tile left edges in screen space: -384, 0, 384. Body-local x
      // coordinates are relative to the body center (screen x = 160).
      final left = (i - 1) * Config.spikeTileWidth;
      final SpriteComponent tile;
      if (isCeiling) {
        tile = SpriteComponent(
          sprite: Sprite(image),
          size: Vector2(Config.spikeTileWidth, Config.spikeHeight),
          // Rotated 180 degrees around the tile center.
          position: Vector2(
            left + Config.spikeTileWidth / 2 - Config.worldWidth / 2,
            _tileY,
          ),
          anchor: Anchor.center,
          angle: 3.141592653589793,
        );
      } else {
        tile = SpriteComponent(
          sprite: Sprite(image),
          size: Vector2(Config.spikeTileWidth, Config.spikeHeight),
          position: Vector2(left - Config.worldWidth / 2, _tileY),
        );
      }
      _tiles.add(tile);
      add(tile);
    }
    game.registerTintable(this);
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2(Config.worldWidth / 2, _centerY)
      ..userData = this;
    final body = world.createBody(bodyDef);
    final shape = PolygonShape()
      // setAsBoxXY takes HALF extents: half the screen width, half height.
      ..setAsBoxXY(Config.worldWidth / 2, Config.spikeHeight / 2);
    body.createFixture(
      FixtureDef(shape)
        ..friction = 0
        ..filter.categoryBits = Config.categoryWorld
        ..filter.maskBits = Config.categoryBird,
    );
    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!game.isScrolling) {
      return;
    }
    for (final tile in _tiles) {
      tile.position.x -= Config.scrollSpeed * dt;
      // Left edge of the tile in body-local coordinates.
      final tileLeft =
          isCeiling ? tile.position.x - Config.spikeTileWidth / 2 : tile.position.x;
      if (tileLeft + Config.spikeTileWidth <= -Config.worldWidth / 2) {
        tile.position.x += _wrapWidth;
      }
    }
  }

  @override
  void setTint(Color color) {
    for (final tile in _tiles) {
      tile.paint.colorFilter = ColorFilter.mode(color, BlendMode.modulate);
    }
  }

  @override
  void onRemove() {
    game.unregisterTintable(this);
    super.onRemove();
  }
}
