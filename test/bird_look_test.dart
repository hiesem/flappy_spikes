import 'package:flame/components.dart' show Anchor;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/look_component.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// WP-D: the equipped 2.0 look (bird + gear + hat) on the run bird and the
/// home bird, and the unchanged 1.0 body/hitbox it is drawn on.
void main() {
  const prefs = {
    'ownedItems': ['bird:robin', 'gear:windup', 'hat:cowboy'],
    'equippedItem.gear': 'windup',
    'equippedItem.hat': 'cowboy',
  };

  final withGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(prefs),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  withGame.testGameWidget(
    'the art body centre sits on the physics body centre; hitbox unchanged',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final bird = game.world.children.query<Bird>().single;
      game.update(0);
      final look = bird.lookComponent;
      expect(look.look.bird, 'classic');
      expect(look.look.gear, 'windup');
      expect(look.look.hat, 'cowboy');

      // The 30 art-unit body square is the 1.0 bird height (29.5 pt).
      expect(look.artScale, closeTo(Config.lookScale, 1e-3));
      expect(look.artScale * 30, closeTo(2 * Config.birdRadius, 1e-6));

      // The look hangs at the body component's origin; Forge2D draws the
      // bird's children through the body transform, so the art body centre
      // lands exactly on the physics body centre (spawn point unchanged).
      expect(look.position.x, closeTo(0, 1e-3));
      expect(look.position.y, closeTo(0, 1e-3));
      expect(
        look.positionOfAnchor(LookComponent.bodyAnchor).x,
        closeTo(0, 1e-3),
      );
      expect(bird.position, bird.body.position);
      expect(bird.body.position.x, Config.birdX);
      expect(bird.body.position.y, game.viewHeight / 2);

      // Hitbox / fixture: still the 1.0 circle, independent of the art.
      final fixtures = bird.body.fixtures.toList();
      expect(fixtures, hasLength(1));
      expect((fixtures.single.shape as CircleShape).radius, Config.birdRadius);
    },
  );

  withGame.testGameWidget(
    'equipping mid-run swaps the look in place',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final bird = game.world.children.query<Bird>().single;
      game.onScreenTap(); // START -> playing
      await flushAndMount(game);
      expect(game.state, GameState.playing);
      expect(bird.look.bird, 'classic');
      await game.menu.items.equip(SkinLayer.bird, 'robin');
      expect(bird.look.bird, 'robin');
      expect(bird.lookComponent.look.bird, 'robin');
      stepGame(game, 0.5, flapBelow: 320);
      expect(game.state, GameState.playing, reason: 'physics unaffected');
      expect(bird.look.bird, 'robin');
    },
  );

  withGame.testGameWidget(
    'death keeps bird + gear + hat and freezes the look clock',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.onScreenTap();
      await flushAndMount(game);
      final bird = game.world.children.query<Bird>().single;
      stepGame(game, 0.3, flapBelow: 200);
      final t = bird.lookComponent.time;
      game.onBirdHit();
      expect(bird.dead, isTrue);
      expect(bird.lookComponent.pose, LookPose.dead);
      // Hat and gear stay attached (the whole look tumbles with the body).
      expect(bird.look.bird, 'classic');
      expect(bird.look.gear, 'windup');
      expect(bird.look.hat, 'cowboy');
      stepGame(game, 0.5);
      expect(bird.lookComponent.time, t);
      expect(bird.lookComponent.pose, LookPose.dead);
    },
  );

  withGame.testGameWidget(
    'the home bird stands on the emblem plate centre at scale 1.32, stage 0',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final plate = Config.homePlateCentreFor(game.viewHeight);
      final home = game.homeScreen!.bird;
      game.update(0);
      expect(home.look.bird, 'classic');
      // PRD-home-v3 §3.1: bird scale 1.32 (1.1 on the shortest screens),
      // its art-box centre on the plate centre.
      expect(
        home.lookComponent.artScale,
        closeTo(Config.homeBirdScaleFor(game.viewHeight), 1e-6),
      );
      final centre = home.lookComponent.absolutePositionOfAnchor(
        Anchor.center,
      );
      // At rest the idle bob moves it at most a few points.
      expect(centre.x, closeTo(plate.dx, 8));
      expect(centre.y, closeTo(plate.dy, 4));
      // Menus always render at colour stage 0: identity colours.
      expect(home.lookComponent.blend, 0);

      // It follows equipment live.
      await game.menu.items.equip(SkinLayer.bird, 'robin');
      expect(home.look.bird, 'robin');
    },
  );
}
