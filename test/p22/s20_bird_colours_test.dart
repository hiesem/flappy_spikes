import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;

/// PRD-2.2 §20.3: the run bird keeps its own colours at every colour stage.
/// The old stage blend (35 % toward the stage foreground from stage 5) is
/// gone; only the themed death tints still blend the look.
///
/// Stage indices 0, 1, 5 and 10 are reached with forced hoop counts (10 per
/// stage). At each one the bird is pinned, drawn on and off, and its solid
/// pixels are compared with the stage-0 pixels of the same pinned bird.
const double _scale = 2; // device px per point

/// Hoop counts for stage indices 0, 1, 5 and 10 (`stageForHoops`).
const List<int> _stageHoops = [0, 10, 50, 100];

/// The accessory look (robin + wind-up key + cowboy) owned and equipped.
const Map<String, Object> _accessoryPrefs = {
  'ownedItems': ['bird:robin', 'gear:windup', 'hat:cowboy'],
};

Future<void> _equipAccessoryLook(FlappySpikesGame game) async {
  await game.menu.items.equip(SkinLayer.bird, 'robin');
  await game.menu.items.equip(SkinLayer.gear, 'windup');
  await game.menu.items.equip(SkinLayer.hat, 'cowboy');
}

/// The frame as straight RGBA at [_scale] (the render path of the shots).
Future<Uint8List> _frame(FlappySpikesGame game) async {
  final size = Vector2(
    Config.worldWidth * _scale,
    (game.viewHeight * _scale).roundToDouble(),
  );
  // Resize right before rendering: the harness reverts earlier resizes.
  game.onGameResize(size);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await rec.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final raw = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return raw!.buffer.asUint8List();
}

/// Fixes the run bird at its spawn point, upright, in the flap frame and
/// fully opaque (the same pinning as look_visual_test).
void _pinBird(FlappySpikesGame game, {bool visible = true}) {
  final bird = game.world.children.query<Bird>().single;
  bird.body
    ..gravityScale = Vector2.zero()
    ..linearVelocity.setZero()
    ..angularVelocity = 0
    ..setTransform(Vector2(Config.birdX, game.viewHeight / 2), 0);
  bird.lookComponent.playFlap(); // t = 0: the same wing frame every time
  game.update(0);
  bird.setSpriteOpacity(visible ? 1 : 0);
}

/// The pinned bird drawn on and off in the current frame.
Future<({Uint8List on, Uint8List off})> _onAndOff(FlappySpikesGame game) async {
  _pinBird(game);
  final on = await _frame(game);
  _pinBird(game, visible: false);
  final off = await _frame(game);
  _pinBird(game);
  return (on: on, off: off);
}

/// Byte offsets of the bird's solid pixels in a frame: the bird is painted
/// there (on and off differ strongly) and so is every pixel within two
/// pixels of it. Anti-aliased edges mix in the background, so they are left
/// out and the comparison only sees the bird's own colours.
List<int> _solidBirdPixels(Uint8List on, Uint8List off, double birdY) {
  final w = (Config.worldWidth * _scale).round();
  final h = on.length ~/ (w * 4);
  bool paintsBird(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    final i = (y * w + x) * 4;
    var diff = 0;
    for (var k = 0; k < 3; k++) {
      final d = (on[i + k] - off[i + k]).abs();
      if (d > diff) diff = d;
    }
    return diff > 60;
  }

  // The bird's box around its pinned body centre (art box 44 x 36 pt).
  final cx = (Config.birdX * _scale).round();
  final cy = (birdY * _scale).round();
  final solid = <int>[];
  for (var y = cy - 40 * _scale.toInt(); y < cy + 40 * _scale.toInt(); y++) {
    for (var x = cx - 40 * _scale.toInt(); x < cx + 40 * _scale.toInt(); x++) {
      var interior = true;
      for (var dy = -2; dy <= 2 && interior; dy++) {
        for (var dx = -2; dx <= 2 && interior; dx++) {
          interior = paintsBird(x + dx, y + dy);
        }
      }
      if (interior) solid.add((y * w + x) * 4);
    }
  }
  return solid;
}

/// Compares the bird's solid pixels in [later] with [reference] (stage 0).
void _expectSameColours(
  Uint8List reference,
  Uint8List later,
  List<int> solid, {
  required String label,
}) {
  expect(solid.length, greaterThan(400), reason: '$label: bird mask');
  var exact = 0, worst = 0;
  for (final i in solid) {
    var d = 0;
    for (var k = 0; k < 3; k++) {
      final c = (reference[i + k] - later[i + k]).abs();
      if (c > d) d = c;
    }
    if (d <= 2) exact++;
    if (d > worst) worst = d;
  }
  expect(
    exact / solid.length,
    greaterThanOrEqualTo(0.98),
    reason: '$label: bird pixels match stage 0 (worst channel diff $worst)',
  );
}

/// Drives the run to each stage in [_stageHoops] and checks the bird there.
Future<void> _sweepStages(FlappySpikesGame game) async {
  final run = game.run!;
  final stage0 = await _onAndOff(game);
  final solid = _solidBirdPixels(stage0.on, stage0.off, game.viewHeight / 2);
  expect(
    game.world.children.query<Bird>().single.lookComponent.blend,
    0,
    reason: 'stage 0 has no blend',
  );

  var hoops = 0;
  for (final target in _stageHoops.skip(1)) {
    while (hoops < target) {
      run.debugPass();
      hoops++;
    }
    stepGame(game, 0.6); // past the colour crossfade (0.5 s)
    final bird = game.world.children.query<Bird>().single;
    expect(run.state.hoopsPassed, target);
    expect(game.stageKey, stageForHoops(target));
    expect(bird.lookComponent.blend, 0, reason: 'hoops $target');
    final shot = await _onAndOff(game);
    _expectSameColours(
      stage0.on,
      shot.on,
      solid,
      label: 'stage ${target ~/ 10} (hoops $target)',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'classic skin: the same pixels at stages 0, 1, 5 and 10',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await loadFonts();
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await tester.runAsync(() async {
        await startRun(game);
        await _sweepStages(game);
      });
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: _accessoryPrefs),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'robin + wind-up key + cowboy: the same pixels at stages 0, 1, 5 and 10',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await loadFonts();
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await tester.runAsync(() async {
        await _equipAccessoryLook(game);
        await flushAndMount(game);
        await startRun(game);
        expect(game.runBird!.look.bird, 'robin');
        await _sweepStages(game);
      });
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'the gold streak bird and a themed death tint still apply, no stage blend',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await loadFonts();
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(game);
        final bird = game.world.children.query<Bird>().single;

        // Stage 10 (hoop 100): no blend at all.
        for (var i = 0; i < 100; i++) {
          run.debugPass();
        }
        stepGame(game, 0.6);
        expect(bird.lookComponent.blend, 0);

        // Gold bird at streak tier 2 (PRD-2 §3.5): the colours change by
        // the gold flag, never by a stage blend.
        run.debugPass(perfect: true);
        run.debugPass(perfect: true);
        game.update(1 / 60);
        expect(run.state.tier, greaterThanOrEqualTo(2));
        expect(bird.lookComponent.goldTier, isTrue);
        expect(bird.lookComponent.blend, 0);

        // A themed death (PRD-2 §5.17) still tints the look toward its colour.
        const frozen = Color(0xFF8FD8FF);
        bird
          ..deathTint = frozen
          ..deathTintAmount = .8;
        game.update(0);
        expect(bird.lookComponent.blend, closeTo(.8, 1e-9));
        expect(bird.lookComponent.blendColor, frozen);

        bird
          ..deathTint = null
          ..deathTintAmount = 0;
        game.update(0);
        expect(bird.lookComponent.blend, 0);
      });
    },
  );
}
